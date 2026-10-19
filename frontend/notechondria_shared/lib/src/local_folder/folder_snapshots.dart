import 'folder_fs.dart';
import 'folder_layout.dart';
import 'note_codec.dart';

// History snapshots for the folder-only reasons and the two-pool prune
// (storage rules 3.8). Moved into Phase 1 because the journal replay writes
// `external_edit` snapshots (3.4.1, design review 3 T7(d)).

/// Versions kept per pool, as `prune_recent_versions` keeps 12
/// (`backend/notes/services.py:339-344`).
const int kSnapshotPoolCap = 12;

/// Reasons that only the folder backend records; they form their own pool.
const Set<String> kFolderOnlySnapshotReasons = {
  'external_edit',
  'concurrent_edit',
};

/// One `history/<hex>/index.json` entry. The snapshot text, the note file as
/// it was on disk, is `history/<hex>/<id>.md`.
class HistoryEntry {
  const HistoryEntry({
    required this.id,
    required this.reason,
    required this.label,
    required this.createdAt,
    this.title,
    this.opId,
    this.extra = const {},
  });

  /// A wrong-typed field reads as absent (the file may be hand-edited, 3.8).
  /// The caller checks that `id` is an int.
  factory HistoryEntry.fromJson(Map<String, Object?> json) => HistoryEntry(
        id: json['id'] as int,
        reason: jsonString(json['reason']) ?? 'manual',
        label: jsonString(json['label']) ?? '',
        createdAt: jsonString(json['created_at']) ?? '',
        title: jsonString(json['title']),
        opId: jsonString(json['op_id']),
        extra: {
          for (final e in json.entries)
            if (!const {'id', 'reason', 'label', 'created_at', 'title', 'op_id'}
                .contains(e.key))
              e.key: e.value,
        },
      );

  final int id;
  final String reason;
  final String label;
  final String createdAt;
  final String? title;

  /// The journal record whose replay saved this snapshot (3.4.1).
  final String? opId;
  final Map<String, Object?> extra;

  bool get isFolderOnly => kFolderOnlySnapshotReasons.contains(reason);

  Map<String, Object?> toJson() => {
        ...extra,
        'id': id,
        'reason': reason,
        'label': label,
        'created_at': createdAt,
        if (title != null) 'title': title,
        if (opId != null) 'op_id': opId,
      };
}

/// `history/<hex>/index.json`.
class HistoryIndex {
  const HistoryIndex({required this.noteUuid, required this.versions});

  factory HistoryIndex.fromJson(Map<String, Object?> json) => HistoryIndex(
        noteUuid: jsonString(json['note_uuid']) ?? '',
        versions: [
          for (final v in jsonList(json['versions']))
            if (v is Map && v['id'] is int)
              HistoryEntry.fromJson(Map<String, Object?>.from(v)),
        ],
      );

  final String noteUuid;
  final List<HistoryEntry> versions;

  String encode() => encodeFolderJson({
        'schema_version': kFolderSchemaVersion,
        'note_uuid': noteUuid,
        'versions': [for (final v in versions) v.toJson()],
      });
}

HistoryIndex? decodeHistoryIndex(String text) {
  final json = decodeJsonObject(text);
  return json == null ? null : HistoryIndex.fromJson(json);
}

int _newestFirst(HistoryEntry a, HistoryEntry b) {
  final byTime = b.createdAt.compareTo(a.createdAt);
  return byTime != 0 ? byTime : b.id.compareTo(a.id);
}

/// Keeps the [cap] newest versions in each pool (3.8): the folder-only
/// reasons in one, every other reason in the other. Pruning in one pool
/// never removes a version of the other. [kept] is newest first.
({List<HistoryEntry> kept, List<HistoryEntry> pruned}) pruneHistory(
    List<HistoryEntry> versions,
    {int cap = kSnapshotPoolCap}) {
  final sorted = [...versions]..sort(_newestFirst);
  final kept = <HistoryEntry>[];
  final pruned = <HistoryEntry>[];
  var folderOnly = 0;
  var backend = 0;
  for (final v in sorted) {
    final count = v.isFolderOnly ? ++folderOnly : ++backend;
    (count <= cap ? kept : pruned).add(v);
  }
  return (kept: kept, pruned: pruned);
}

/// The backend's `version_label` (`backend/notes/services.py:356-363`).
String historyVersionLabel(String reason, DateTime createdAt) {
  switch (reason.toLowerCase()) {
    case 'autosave_1m':
      return 'AutoSave-1m';
    case 'autosave_10m':
      return 'AutoSave-10m';
    case 'autosave_1h':
      return 'AutoSave-1h';
  }
  final t = createdAt.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
}

/// T7(j): which snapshot, if any, to take before overwriting a note body.
/// The external-edit check (3.8) compares the file with the sidecar's
/// `md_size`/`md_last_modified`; the concurrent-edit check compares it with
/// the `lastModified` this tab last served. When both trip, the file was
/// changed by something other than the app, so the reason is
/// `external_edit`, and only one snapshot is taken.
String? overwriteSnapshotReason({
  required FolderStat? disk,
  int? sidecarSize,
  int? sidecarLastModified,
  int? servedLastModified,
}) {
  if (disk == null) return null;
  final external = sidecarSize != null &&
      sidecarLastModified != null &&
      !disk.sameAs(sidecarSize, sidecarLastModified);
  if (external) return 'external_edit';
  if (servedLastModified != null && disk.lastModified != servedLastModified) {
    return 'concurrent_edit';
  }
  return null;
}

/// The files one snapshot changes. Journaled callers add [writes] to their
/// record and [prunedBodies] to its removals; [FolderSnapshotWriter.write]
/// applies them directly.
class SnapshotPlan {
  const SnapshotPlan({
    required this.entry,
    required this.manifestText,
    required this.bodyPath,
    required this.bodyText,
    required this.indexPath,
    required this.indexText,
    required this.prunedBodies,
  });

  final HistoryEntry entry;
  final String manifestText;
  final String bodyPath;
  final String bodyText;
  final String indexPath;
  final String indexText;
  final List<String> prunedBodies;
}

/// Writes folder-only snapshots. Callers hold the exclusive folder lock.
class FolderSnapshotWriter {
  FolderSnapshotWriter(this.fs, {DateTime Function()? now})
      : _now = now ?? DateTime.now;

  final FolderFs fs;
  final DateTime Function() _now;

  Future<HistoryIndex?> readIndex(String uuidHex) async {
    final text = await readTextOrNull(fs, historyIndexPath(uuidHex));
    return text == null ? null : decodeHistoryIndex(text);
  }

  Future<bool> hasEntryForOp(String uuidHex, String opId) async {
    final index = await readIndex(uuidHex);
    return index?.versions.any((v) => v.opId == opId) ?? false;
  }

  /// Plans a snapshot from the current disk state (manifest and history
  /// index re-read from disk, 6.2 R2). Counters are first raised to
  /// [counterFloor], so a journal replay can issue an id above the ones
  /// its record journaled but has not written yet (3.4.1).
  Future<SnapshotPlan> plan({
    required String noteUuid,
    required String reason,
    required String text,
    required String notePath,
    String? opId,
    Map<String, int> counterFloor = const {},
  }) async {
    final manifest = await readFolderManifest(fs);
    if (manifest == null) {
      throw const FolderLayoutException(
          'Snapshot not saved: Shared.LocalFolder/journal — manifest.json is '
          'missing, so no version id can be issued.');
    }
    final (updated, id) =
        (manifest.raisedTo(counterFloor) ?? manifest).allocate('version');
    final hex = uuidHex(noteUuid);
    final now = _now();
    final entry = HistoryEntry(
      id: id,
      reason: reason,
      label: historyVersionLabel(reason, now),
      createdAt: now.toUtc().toIso8601String(),
      title: decodeNoteFile(text, path: notePath).frontmatter.title,
      opId: opId,
    );
    final existing = await readIndex(hex);
    final result = pruneHistory([...?existing?.versions, entry]);
    return SnapshotPlan(
      entry: entry,
      manifestText: updated.encode(),
      bodyPath: historyBodyPath(hex, id),
      bodyText: text,
      indexPath: historyIndexPath(hex),
      indexText: HistoryIndex(noteUuid: noteUuid, versions: result.kept)
          .encode(),
      prunedBodies: [for (final p in result.pruned) historyBodyPath(hex, p.id)],
    );
  }

  /// Writes a snapshot outside a journal record, in the order that keeps
  /// every interruption harmless: the manifest counter first (an ID may be
  /// burned, never reused), then the body (an orphan body is ignored), then
  /// the index entry, then the pruned bodies.
  Future<HistoryEntry> write({
    required String noteUuid,
    required String reason,
    required String text,
    required String notePath,
    String? opId,
    Map<String, int> counterFloor = const {},
  }) async {
    final p = await plan(
        noteUuid: noteUuid,
        reason: reason,
        text: text,
        notePath: notePath,
        opId: opId,
        counterFloor: counterFloor);
    await fs.writeText(kManifestPath, p.manifestText);
    await fs.writeText(p.bodyPath, p.bodyText);
    await fs.writeText(p.indexPath, p.indexText);
    for (final path in p.prunedBodies) {
      await removeIfPresent(fs, path);
    }
    return p.entry;
  }
}
