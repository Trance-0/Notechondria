import 'dart:collection';

import 'folder_fs.dart';
import 'folder_identity.dart';
import 'folder_index.dart';
import 'folder_journal.dart';
import 'folder_layout.dart';
import 'folder_lock.dart';
import 'folder_messages.dart';

// Paged folder scan (3.8, 6.2 R4): listing pages of at most [pageSize]
// entries per shared hold, each preceded by the R3 journal check; a final
// re-check of every UUID seen at two paths; counters raised above the
// largest ids seen; one journaled fix per duplicate identity (3.7); then the
// derived index, written under the exclusive lock (R1).

/// R4: entries per shared hold.
const int kScanPageSize = 500;

/// Directories a scan walks (3.8), plus `history/` for the version counter
/// and `profile/` for the folder counts.
const List<String> kScanDirectories = [
  kNotesDir,
  'trash',
  kCoursesDir,
  kPlannerDir,
  kAssetsDir,
  kHistoryDir,
  kProfileDir,
];

const List<String> kScanRootFiles = [kManifestPath, kReadmePath, kRecycleBinPath];

/// Whether a scan indexes [path]: a root file of [kScanRootFiles] or a file
/// under one of [kScanDirectories].
bool isIndexedPath(String path) =>
    kScanRootFiles.contains(path) ||
    kScanDirectories.any((dir) => path.startsWith('$dir/'));

class ScanProgress {
  const ScanProgress(this.done, this.total);
  final int done;
  final int total;
}

class ScanResult {
  const ScanResult({
    required this.index,
    required this.fixes,
    required this.dropped,
    required this.countersRaised,
  });

  final FolderIndex index;

  /// Identity fixes applied (3.7), in order.
  final List<IdentityFix> fixes;

  /// Note paths of the previous index that no longer exist.
  final List<String> dropped;
  final bool countersRaised;
}

class FolderScanner {
  FolderScanner({
    required this.fs,
    required this.locks,
    required this.lockName,
    required this.journal,
    required this.folderId,
    this.onProgress,
    this.pageSize = kScanPageSize,
    this.progressInterval = const Duration(seconds: 1),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final FolderFs fs;
  final FolderLocks locks;
  final String lockName;
  final FolderJournal journal;
  final String folderId;

  /// Called after every page and at least every [progressInterval] within
  /// one (the splash re-arms on each report, 2.9).
  final void Function(ScanProgress progress)? onProgress;
  final int pageSize;
  final Duration progressInterval;
  final DateTime Function() _now;

  LocalFolderLogSink get _log => journal.log;

  Future<IndexedFile?> _indexOne(String path, IndexedFile? previous) async {
    final stat = await fs.stat(path);
    if (stat == null) return null;
    if (previous != null && stat.sameAs(previous.size, previous.lastModified)) {
      return previous;
    }
    final text = indexReadsContent(path) ? await readTextOrNull(fs, path) : null;
    return indexFile(path, stat, text);
  }

  Future<T> _read<T>(Future<T> Function(Set<String> skip) read) =>
      readWithJournalCheck(
          locks: locks, lockName: lockName, journal: journal, read: read);

  /// Runs [operation] under the exclusive lock, after the roll-forward that
  /// precedes every write (3.4.1). If that roll-forward fails, [operation]
  /// gets the paths of the pending records and skips any change that
  /// touches one (6.2 R3), so the scan still finishes and the folder opens.
  Future<T> _exclusive<T>(Future<T> Function(Set<String> skip) operation) =>
      locks.run(lockName, FolderLockMode.exclusive, () async {
        final rolled = await rollForwardHeld(journal);
        return operation(
            rolled.failed ? await journal.pendingPaths() : const <String>{});
      });

  /// Scans the folder; unchanged files ([previous] has the same size and
  /// `lastModified`) are not read again. [changedPaths] are re-checked at
  /// the end like duplicate UUIDs (change messages, Phase 4). [beforeWrite]
  /// runs in the final exclusive hold, before `index.json` is written, and
  /// may change the scanned entries: the controller applies there the index
  /// changes this tab made between pages (L2A-2).
  Future<ScanResult> scan({
    FolderIndex? previous,
    Set<String> changedPaths = const {},
    void Function(Map<String, IndexedFile> files)? beforeWrite,
  }) async {
    final before = previous?.files ?? const <String, IndexedFile>{};
    final files = <String, IndexedFile>{};
    final queue = Queue<(String, bool)>()
      ..addAll([for (final d in kScanDirectories) (d, true)])
      ..addAll([for (final f in kScanRootFiles) (f, false)]);
    var done = 0;
    var total = queue.length;
    var lastReport = _now();
    void report({bool force = false}) {
      final now = _now();
      if (!force && now.difference(lastReport) < progressInterval) return;
      lastReport = now;
      onProgress?.call(ScanProgress(done, total));
    }

    while (queue.isNotEmpty) {
      await _read<void>((skip) async {
        var budget = pageSize;
        while (budget-- > 0 && queue.isNotEmpty) {
          final (path, isDirectory) = queue.removeFirst();
          done++;
          if (isDirectory) {
            for (final entry in await listOrEmpty(fs, path)) {
              queue.add((joinFolderPath(path, entry.name), entry.isDirectory));
              total++;
            }
          } else if (!skip.contains(path)) {
            final entry = await _indexOne(path, before[path]);
            if (entry != null) files[path] = entry;
          }
          report();
        }
      });
      report(force: true);
    }

    await _recheck(files, changedPaths);

    final dropped = [
      for (final f in before.values)
        if ((f.kind == IndexedKind.note || f.kind == IndexedKind.trashNote) &&
            !files.containsKey(f.path))
          f.path,
    ]..sort();
    for (final path in dropped) {
      _log(LocalFolderLogLevel.info, LocalFolderMessages.noteDropped(path));
    }

    final raised = await _raiseCounters(
        FolderIndex(folderId: folderId, generatedAt: '', files: files).maxIds);

    final fixes = planIdentityFixes(files);
    final touched = <String>{};
    final applied = <IdentityFix>[];
    for (final fix in fixes) {
      final changed = await _exclusive((skip) async {
        if (identityFixPaths(fix).any(skip.contains)) return const <String>{};
        return applyIdentityFix(fs, journal, fix);
      });
      if (changed.isNotEmpty) applied.add(fix);
      touched.addAll(changed);
    }
    if (touched.isNotEmpty) {
      await _read<void>((skip) async {
        for (final path in touched) {
          final entry = skip.contains(path) ? null : await _indexOne(path, null);
          if (entry == null) {
            files.remove(path);
          } else {
            files[path] = entry;
          }
        }
      });
    }

    final generatedAt = _now().toUtc().toIso8601String();
    final index = await locks.run(lockName, FolderLockMode.exclusive, () async {
      beforeWrite?.call(files);
      final index =
          FolderIndex(folderId: folderId, generatedAt: generatedAt, files: files);
      await fs.writeText(kIndexPath, index.encode());
      return index;
    });
    return ScanResult(
        index: index, fixes: applied, dropped: dropped, countersRaised: raised);
  }

  /// R4: under one more shared hold, re-reads every note whose UUID was
  /// seen at two paths (and [changedPaths]), and drops entries whose file
  /// is gone, so a scan during a trash move never reports a note twice.
  Future<void> _recheck(
      Map<String, IndexedFile> files, Set<String> changedPaths) async {
    final byUuid = <String, List<String>>{};
    for (final f in files.values) {
      if (f.kind != IndexedKind.note && f.kind != IndexedKind.trashNote) {
        continue;
      }
      final uuid = files[sidecarPathForBody(f.path)]?.uuid ?? f.uuid;
      if (uuid != null) (byUuid[uuid] ??= []).add(f.path);
    }
    final paths = <String>{...changedPaths};
    for (final group in byUuid.values) {
      if (group.length < 2) continue;
      for (final path in group) {
        paths
          ..add(path)
          ..add(sidecarPathForBody(path));
      }
    }
    if (paths.isEmpty) return;
    await _read<void>((skip) async {
      for (final path in paths) {
        final entry = skip.contains(path) ? null : await _indexOne(path, null);
        if (entry == null) {
          files.remove(path);
        } else {
          files[path] = entry;
        }
      }
    });
  }

  /// 3.7: raises each counter to the largest id seen, in one journaled
  /// write; skipped while a pending record still has to write the manifest.
  Future<bool> _raiseCounters(Map<String, int> maxIds) {
    return _exclusive((skip) async {
      if (skip.contains(kManifestPath)) return false;
      final manifest = await readFolderManifest(fs);
      final raised = manifest?.raisedTo(maxIds);
      if (manifest == null || raised == null) return false;
      await journal.commit(
          journal.newRecord([JournalWrite(kManifestPath, raised.encode())]));
      final kinds = [
        for (final kind in kIdKinds)
          if (raised.counter(kind) != manifest.counter(kind))
            '$kind ${manifest.counter(kind)} -> ${raised.counter(kind)}',
      ].join(', ');
      _log(LocalFolderLogLevel.info, LocalFolderMessages.countersRaised(kinds));
      return true;
    });
  }
}
