import 'dart:convert';

import 'folder_fs.dart';
import 'folder_journal_record.dart';
import 'folder_layout.dart';
import 'folder_lock.dart';
import 'folder_messages.dart';
import 'folder_snapshots.dart';
import 'note_codec.dart';

export 'folder_journal_record.dart';

// Write-ahead journal for multi-file operations (storage rules 3.4.1): the
// apply order, roll-forward, and the R3 read path. The record format is in
// `folder_journal_record.dart`.

/// Thrown when step 4 finds a write target missing or of the wrong length.
class FolderJournalException implements Exception {
  const FolderJournalException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// A record whose `schema_version` is newer than this build's. It is left in
/// place and reported as a failed roll-forward, so readers skip the paths it
/// names (6.2 R3) until a newer build finishes it.
class FolderJournalTooNew implements Exception {
  const FolderJournalTooNew(this.opId, this.schemaVersion, this.touchedPaths);
  final String opId;
  final int schemaVersion;

  /// Every `path` the record's writes and removals name.
  final Set<String> touchedPaths;

  @override
  String toString() =>
      LocalFolderMessages.journalTooNewCause(schemaVersion, kFolderSchemaVersion);
}

Set<String> _namedPaths(Map<String, Object?> json) => {
      for (final key in const ['writes', 'removals'])
        for (final item in jsonList(json[key]))
          if (item is Map && item['path'] is String) item['path'] as String,
    };

class RollForwardResult {
  const RollForwardResult({
    this.replayed = const [],
    this.snapshots = 0,
    this.failure,
    this.failedOpId,
  });

  final List<String> replayed;
  final int snapshots;
  final Object? failure;
  final String? failedOpId;

  bool get failed => failure != null;
}

const Set<String> _sharedIndexNames = {'attachments.json', 'index.json'};

/// Step 3 order: note bodies, sidecars, other files, shared index files,
/// then `manifest.json`.
int _writeRank(String path) {
  if (path == kManifestPath) return 4;
  if (isNoteBodyPath(path)) return 0;
  if (isSidecarPath(path)) return 1;
  final parent = folderPathParent(path);
  final name = folderPathBasename(path);
  final sharedIndex = path == kRecycleBinPath ||
      (parent == kPlannerDir && name.endsWith('.json')) ||
      (path.startsWith('$kAssetsDir/notes/') && name == 'attachments.json') ||
      (path.startsWith('$kHistoryDir/') && _sharedIndexNames.contains(name));
  return sharedIndex ? 3 : 2;
}

bool _isHistoryIndex(String path) =>
    path.startsWith('$kHistoryDir/') && path.endsWith('/index.json');

/// Applies and replays journal records. Every method expects the caller to
/// hold the exclusive folder lock (6.2 R1); [rollForwardUnderLock] takes it.
class FolderJournal {
  FolderJournal(
    this.fs, {
    required this.app,
    JournalOpIds? opIds,
    DateTime Function()? now,
    this.log = discardLocalFolderLog,
  })  : _opIds = opIds ?? JournalOpIds(),
        _now = now ?? DateTime.now;

  final FolderFs fs;
  final String app;
  final JournalOpIds _opIds;
  final DateTime Function() _now;
  final LocalFolderLogSink log;

  JournalRecord newRecord(List<JournalWrite> writes,
          [List<JournalRemoval> removals = const []]) =>
      JournalRecord(
        opId: _opIds.next(_now()),
        app: app,
        createdAt: _now().toUtc().toIso8601String(),
        writes: writes,
        removals: removals,
      );

  /// Steps 2 to 5 of 3.4.1. The caller did step 1 (re-read every file it
  /// rewrites, under the same exclusive hold).
  Future<void> commit(JournalRecord record) async {
    await fs.writeText(record.path, encodeFolderJson(record.toJson()));
    await _apply(record, replay: false);
  }

  /// Op ids of the records in `.notechondria/journal/`, in op-id order.
  Future<List<String>> listPending() async {
    final entries = await listOrEmpty(fs, kJournalDir);
    final ids = [
      for (final e in entries)
        if (e.isFile && e.name.endsWith('.json'))
          e.name.substring(0, e.name.length - 5),
    ]..sort();
    return ids;
  }

  /// Every path a pending record names; readers skip them when roll-forward
  /// failed (6.2 R3). An unreadable record names none.
  Future<Set<String>> pendingPaths() async {
    final out = <String>{};
    for (final id in await listPending()) {
      try {
        final record = await _readRecord(id);
        if (record != null) out.addAll(record.touchedPaths);
      } on FolderJournalTooNew catch (e) {
        out.addAll(e.touchedPaths);
      } on FolderJournalException {
        // The next roll-forward discards it.
      }
    }
    return out;
  }

  Future<JournalRecord?> _readRecord(String opId) async {
    final text = await readTextOrNull(fs, '$kJournalDir/$opId.json');
    if (text == null) return null;
    final json = decodeJsonObject(text);
    final version = json?['schema_version'];
    if (json != null && version is int && version > kFolderSchemaVersion) {
      throw FolderJournalTooNew(opId, version, _namedPaths(json));
    }
    try {
      if (json != null && json['op_id'] == opId) {
        return JournalRecord.fromJson(json);
      }
    } on TypeError {
      // Falls through to the unreadable-record path.
    }
    throw FolderJournalException(LocalFolderMessages.journalUnreadable(
        opId, 'it is not a journal record'));
  }

  /// Replays every leftover record, one at a time in op-id order. The list
  /// is read here, inside the caller's exclusive hold, so a record another
  /// tab already finished is skipped (3.4.1 "re-lists"). A record that
  /// cannot be parsed is deleted and logged; a newer build's record throws
  /// [FolderJournalTooNew] and stays.
  Future<RollForwardResult> rollForward() async {
    final replayed = <String>[];
    var snapshots = 0;
    for (final opId in await listPending()) {
      JournalRecord? record;
      try {
        record = await _readRecord(opId);
      } on FolderJournalException catch (e) {
        log(LocalFolderLogLevel.warning, e.message);
        await removeIfPresent(fs, '$kJournalDir/$opId.json');
        continue;
      }
      if (record == null) continue;
      snapshots += await _apply(record, replay: true);
      replayed.add(opId);
    }
    return RollForwardResult(replayed: replayed, snapshots: snapshots);
  }

  /// Steps 3 to 5; returns the number of `external_edit` snapshots taken.
  Future<int> _apply(JournalRecord record, {required bool replay}) async {
    // Stable: within one rank, the record's own order.
    final ranked = [
      for (var i = 0; i < record.writes.length; i++) (i, record.writes[i]),
    ]..sort((a, b) {
        final r = _writeRank(a.$2.path).compareTo(_writeRank(b.$2.path));
        return r != 0 ? r : a.$1.compareTo(b.$1);
      });
    final ordered = [for (final (_, w) in ranked) w];
    final written = <String, int>{};
    final prunedBodies = <String>[];
    final floor = replay ? _journaledCounters(record) : const <String, int>{};
    var snapshots = 0;
    for (final w in ordered) {
      var text = w.text;
      if (replay) {
        if (w.expect != null && isNoteBodyPath(w.path)) {
          snapshots += await _keepExternalEdit(
              record, w.path, w.expect!, w.text, floor);
        }
        text = await _replayText(record, w.path, text, prunedBodies);
        final current = await readTextOrNull(fs, w.path);
        if (current != text) await fs.writeText(w.path, text);
      } else {
        await fs.writeText(w.path, text);
      }
      written[w.path] = utf8.encode(text).length;
    }
    for (final entry in written.entries) {
      final stat = await fs.stat(entry.key);
      if (stat == null || stat.size != entry.value) {
        throw FolderJournalException(LocalFolderMessages.journalIncomplete(
            record.opId,
            record.app,
            "'${entry.key}' is ${stat == null ? 'missing' : '${stat.size} bytes, not ${entry.value}'} after the writes"));
      }
    }
    for (final path in prunedBodies) {
      await removeIfPresent(fs, path);
    }
    final removals = [
      ...record.removals.where((r) => !r.directory),
      ...record.removals.where((r) => r.directory),
    ];
    for (final r in removals) {
      if (replay && r.expect != null && isNoteBodyPath(r.path)) {
        snapshots +=
            await _keepExternalEdit(record, r.path, r.expect!, null, floor);
      }
      await removeIfPresent(fs, r.path, recursive: r.directory);
    }
    await removeIfPresent(fs, record.path);
    return snapshots;
  }

  /// The counters the record issued itself: those of its `manifest.json`
  /// write and the version ids in its history index writes. The replay's
  /// `external_edit` snapshot is numbered above them, because the record's
  /// manifest is written last, so the disk counter can still be below a
  /// version the record allocated (a `concurrent_edit` snapshot journaled
  /// with a PATCH, a `before_restore` restore).
  Map<String, int> _journaledCounters(JournalRecord record) {
    final floor = <String, int>{};
    void see(String kind, int id) {
      if (id > (floor[kind] ?? 0)) floor[kind] = id;
    }

    for (final w in record.writes) {
      if (w.path == kManifestPath) {
        try {
          decodeFolderManifest(w.text).idCounters.forEach(see);
        } on FolderLayoutException {
          // A record never journals an invalid manifest; nothing to raise.
        }
      } else if (_isHistoryIndex(w.path)) {
        for (final v in decodeHistoryIndex(w.text)?.versions ??
            const <HistoryEntry>[]) {
          see('version', v.id);
        }
      }
    }
    return floor;
  }

  /// N15: before a replay rewrites or removes a note body, a body that
  /// matches neither `expect` nor the journaled text was edited after the
  /// crash; its text is saved as one `external_edit` snapshot, with a
  /// version id above [floor].
  Future<int> _keepExternalEdit(JournalRecord record, String path,
      JournalExpect expect, String? journaledText,
      Map<String, int> floor) async {
    final stat = await fs.stat(path);
    if (stat == null || stat.sameAs(expect.size, expect.lastModified)) {
      return 0;
    }
    final current = await fs.readText(path);
    if (journaledText != null && current == journaledText) return 0;
    final uuid = await _noteUuidFor(path, current, journaledText);
    final writer = FolderSnapshotWriter(fs, now: _now);
    if (await writer.hasEntryForOp(uuidHex(uuid), record.opId)) return 0;
    final entry = await writer.write(
        noteUuid: uuid,
        reason: 'external_edit',
        text: current,
        notePath: path,
        opId: record.opId,
        counterFloor: floor);
    log(LocalFolderLogLevel.info,
        LocalFolderMessages.externalEditSaved(path, entry.id));
    return 1;
  }

  Future<String> _noteUuidFor(
      String path, String current, String? journaledText) async {
    final fromText = (journaledText == null
            ? null
            : frontmatterUuidOf(journaledText)) ??
        frontmatterUuidOf(current);
    if (fromText != null) return fromText;
    final sidecar = await readTextOrNull(fs, sidecarPathForBody(path));
    final fromSidecar = sidecar == null ? null : decodeSidecar(sidecar)?.uuid;
    // A note the app never adopted has no UUID; its text still gets a
    // history directory of its own so nothing is discarded.
    return fromSidecar ?? uuidFromHex(noteStemOf(path)) ?? newUuidV4();
  }

  /// Replay-only merges for files the replay itself may have changed:
  /// counters never go below disk, and a history index keeps the entries
  /// this record's own replay saved.
  Future<String> _replayText(JournalRecord record, String path, String text,
      List<String> prunedBodies) async {
    if (path != kManifestPath && !_isHistoryIndex(path)) return text;
    final disk = await readTextOrNull(fs, path);
    if (disk == null) return text;
    if (path == kManifestPath) {
      try {
        final journaled = decodeFolderManifest(text);
        final onDisk = decodeFolderManifest(disk);
        return journaled.raisedTo(onDisk.idCounters)?.encode() ?? text;
      } on FolderLayoutException {
        return text;
      }
    }
    final journaled = decodeHistoryIndex(text);
    final onDisk = decodeHistoryIndex(disk);
    if (journaled == null || onDisk == null) return text;
    final ids = {for (final v in journaled.versions) v.id};
    final own = onDisk.versions
        .where((v) => v.opId == record.opId && !ids.contains(v.id))
        .toList();
    if (own.isEmpty) return text;
    final result = pruneHistory([...journaled.versions, ...own]);
    final hex = folderPathBasename(folderPathParent(path));
    prunedBodies.addAll(result.pruned.map((v) => historyBodyPath(hex, v.id)));
    return HistoryIndex(
            noteUuid: journaled.noteUuid.isEmpty
                ? onDisk.noteUuid
                : journaled.noteUuid,
            versions: result.kept)
        .encode();
  }
}

/// Roll-forward under the exclusive lock (3.4.1). A failure other than a
/// lock timeout is returned, logged, and leaves the record in place.
Future<RollForwardResult> rollForwardUnderLock({
  required FolderLocks locks,
  required String lockName,
  required FolderJournal journal,
  Duration? timeLeft,
}) {
  return locks.run(lockName, FolderLockMode.exclusive,
      () => rollForwardHeld(journal),
      timeLeft: timeLeft);
}

/// [rollForwardUnderLock] for a caller that already holds the exclusive
/// lock, such as a scan step about to write (3.4.1 "before any write").
Future<RollForwardResult> rollForwardHeld(FolderJournal journal) async {
  try {
    return await journal.rollForward();
  } on FolderLockTimeout {
    rethrow;
  } catch (error) {
    final pending = await _firstPendingOrNull(journal);
    journal.log(
        LocalFolderLogLevel.warning,
        LocalFolderMessages.journalIncomplete(
            pending ?? 'a record', journal.app, '$error'));
    return RollForwardResult(failure: error, failedOpId: pending);
  }
}

Future<String?> _firstPendingOrNull(FolderJournal journal) async {
  try {
    final ids = await journal.listPending();
    return ids.isEmpty ? null : ids.first;
  } catch (_) {
    return null;
  }
}

/// 6.2 R3: runs [read] under the shared lock. A non-empty journal makes the
/// reader release, roll forward under the exclusive lock, and take the
/// shared lock again. If roll-forward fails, [read] gets the paths of the
/// pending records, which it must skip. [timeLeft] is asked before every
/// wait, so all waits count against one request deadline (2.9).
Future<T> readWithJournalCheck<T>({
  required FolderLocks locks,
  required String lockName,
  required FolderJournal journal,
  required Future<T> Function(Set<String> skipPaths) read,
  Duration? Function()? timeLeft,
}) async {
  final first = await locks.run<(bool, T?)>(lockName, FolderLockMode.shared,
      () async {
    if ((await journal.listPending()).isNotEmpty) return (true, null);
    return (false, await read(const <String>{}));
  }, timeLeft: timeLeft?.call());
  if (!first.$1) return first.$2 as T;
  final rolled = await rollForwardUnderLock(
      locks: locks,
      lockName: lockName,
      journal: journal,
      timeLeft: timeLeft?.call());
  return locks.run(lockName, FolderLockMode.shared, () async {
    final skip = rolled.failed ? await journal.pendingPaths() : <String>{};
    return read(skip);
  }, timeLeft: timeLeft?.call());
}
