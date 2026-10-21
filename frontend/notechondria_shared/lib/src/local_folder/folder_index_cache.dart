import 'dart:async';

import 'folder_fs.dart';
import 'folder_index.dart';
import 'folder_journal.dart';
import 'folder_layout.dart';
import 'folder_lock.dart';
import 'folder_messages.dart';
import 'folder_scanner.dart';
import 'local_folder_boot.dart';

/// L2A-1: how long after this tab's last write the in-memory index is
/// written to `index.json`, so that a burst of saves costs one write.
const Duration kIndexFlushDelay = Duration(seconds: 1);

bool _isNoteEntry(IndexedFile f) =>
    f.kind == IndexedKind.note ||
    f.kind == IndexedKind.trashNote ||
    f.kind == IndexedKind.sidecar;

/// The in-memory index cache (L2A2-5): the `index.json` fast path, the
/// unverified set (3.8, L2A-1), the coalesced flush (L2A-1), and the scan
/// that keeps this tab's changes made while it runs (L2A-2). Split out of
/// `LocalFolderController` so the controller stays under the 1.6 line cap
/// and Phase 4's change handling has a home (design next_phase.md A).
///
/// It is controller-free like [FolderIndex]: it holds the index state and
/// reads the controller's live folder, record, lock name, and `active`
/// flag through the accessors it is built with (those change over the
/// controller's lifetime), mirroring how [FolderScanner] takes its
/// collaborators as fields.
class FolderIndexCache {
  FolderIndexCache({
    required FolderFs? Function() folder,
    required StorageModeRecord? Function() record,
    required bool Function() isActive,
    required this.locks,
    required String Function() lockName,
    required this.zone,
    required this.indexFlushDelay,
    required DateTime Function() now,
    required this.log,
    required void Function() onProgress,
    required void Function() onIndexChanged,
  })  : _folder = folder,
        _record = record,
        _isActive = isActive,
        _lockName = lockName,
        _now = now,
        _onProgress = onProgress,
        _onIndexChanged = onIndexChanged;

  final FolderFs? Function() _folder;
  final StorageModeRecord? Function() _record;
  final bool Function() _isActive;
  final FolderLocks locks;
  final String Function() _lockName;
  final Zone zone;

  /// [kIndexFlushDelay]; tests that time routes set it longer.
  final Duration indexFlushDelay;
  final DateTime Function() _now;
  final LocalFolderLogSink log;
  final void Function() _onProgress;
  final void Function() _onIndexChanged;

  FolderIndex? _index;

  /// Note body and sidecar entries loaded from `index.json` and not yet
  /// compared with the disk in this page (3.8, L2A-1).
  Set<String> _unverified = <String>{};

  /// This tab's index changes while a scan runs (L2A-2).
  IndexChangeLog? _scanLog;
  Timer? _flushTimer;
  bool _indexDirty = false;
  ScanProgress? _progress;

  FolderIndex? get index => _index;
  ScanProgress? get progress => _progress;

  /// Replaces the in-memory index. Entries of a [fromFile] index start
  /// unverified; a scanned index is verified. Drops a pending flush.
  void setIndex(FolderIndex? index, {bool fromFile = false}) {
    _flushTimer?.cancel();
    _flushTimer = null;
    _indexDirty = false;
    _index = index;
    _unverified = {
      if (fromFile && index != null)
        for (final f in index.files.values)
          if (_isNoteEntry(f)) f.path,
    };
  }

  /// Sets the initial scan progress shown while `scanning` (2.9 step 3).
  void startProgress() {
    _progress = const ScanProgress(0, 0);
  }

  /// A scan from [previous]; index changes this tab makes while it runs are
  /// applied to its result, in its final hold for `index.json` and again
  /// for those made after that hold (L2A-2).
  Future<ScanResult> scan(FolderJournal journal,
      {FolderIndex? previous, Set<String> changedPaths = const {}}) async {
    final during = _scanLog = IndexChangeLog();
    var applied = 0;
    try {
      final result = await _scanner(journal).scan(
          previous: previous,
          changedPaths: changedPaths,
          beforeWrite: (files) {
            during.applyTo(files);
            applied = during.length;
          });
      final files = Map<String, IndexedFile>.of(result.index.files);
      during.applyTo(files, from: applied);
      setIndex(FolderIndex(
          folderId: result.index.folderId,
          generatedAt: result.index.generatedAt,
          files: files,
          layoutVersion: result.index.layoutVersion));
      if (during.length > applied) _scheduleFlush();
      return ScanResult(
          index: _index!,
          fixes: result.fixes,
          dropped: result.dropped,
          countersRaised: result.countersRaised);
    } finally {
      if (identical(_scanLog, during)) _scanLog = null;
    }
  }

  FolderScanner _scanner(FolderJournal journal) => FolderScanner(
        fs: _folder()!,
        locks: locks,
        lockName: _lockName(),
        journal: journal,
        folderId: _record()!.folderId,
        now: _now,
        onProgress: (p) {
          _progress = p;
          _onProgress();
        },
      );

  /// Whether [path]'s entry came from `index.json` and has not been
  /// compared with the disk in this page (3.8, L2A-1).
  bool isUnverified(String path) => _unverified.contains(path);

  /// Applies changes to the in-memory index: this tab's own writes
  /// ([written]), and files a handler re-read (6.2 R2, P1B-1). Every changed
  /// path, and each of [verified], now matches the disk. [written] changes
  /// reach `index.json` through a coalesced [flushIndex]; a scan running
  /// meanwhile applies them to its result (L2A-2).
  void updateIndex(Map<String, IndexedFile?> changes,
      {Iterable<String> removedDirs = const [],
      Iterable<String> verified = const [],
      bool written = false}) {
    _unverified
      ..removeAll(changes.keys)
      ..removeAll(verified);
    if (changes.isEmpty && removedDirs.isEmpty) return;
    final base = _index ??
        FolderIndex(
            folderId: _record()?.folderId ?? '',
            generatedAt: '',
            files: const {});
    _index = base.withChanges(changes, removedDirs: removedDirs);
    _scanLog?.add(changes, removedDirs);
    if (written) _scheduleFlush();
    _onIndexChanged();
  }

  void _scheduleFlush() {
    _indexDirty = true;
    _flushTimer ??= zone.run(() => Timer(indexFlushDelay, () {
          _flushTimer = null;
          unawaited(flushIndex());
        }));
  }

  /// Writes the in-memory index to `index.json` under the exclusive lock
  /// (R1) when this tab's writes changed it since the last write of the
  /// file (L2A-1), so a reload starts from them and purged notes leave the
  /// file. A failure is logged and retried after the next write.
  Future<void> flushIndex() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    final folder = _folder();
    if (!_indexDirty || folder == null || !_isActive()) {
      return;
    }
    _indexDirty = false;
    try {
      await locks.run(_lockName(), FolderLockMode.exclusive, () async {
        final index = _index;
        if (index != null && identical(folder, _folder())) {
          await folder.writeText(kIndexPath, index.encode());
        }
      });
    } catch (error) {
      _indexDirty = true;
      log(LocalFolderLogLevel.warning,
          scrubSessionSentinels(LocalFolderMessages.indexNotSaved('$error')));
    }
  }

  /// Cancels any pending flush timer (controller `dispose`).
  void cancelFlush() {
    _flushTimer?.cancel();
    _flushTimer = null;
  }
}
