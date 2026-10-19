import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'change_channel.dart';
import 'folder_fs.dart';
import 'folder_index.dart';
import 'folder_journal.dart';
import 'folder_layout.dart';
import 'folder_lock.dart';
import 'folder_messages.dart';
import 'folder_pick_flow.dart';
import 'folder_scanner.dart';
import 'local_folder_boot.dart';
import 'local_folder_platform.dart';
import 'storage_mode_client.dart';
import 'transport.dart';

/// Folder state (main 2.5). It never changes routing (2.8).
enum LocalFolderState {
  opening,
  needsPick,
  needsPermission,
  scanning,
  active,
  error,
  disconnected,
}

/// Why the state is `disconnected` (2.8 rule 4, 2.10 rules 4 and 5).
enum DisconnectReason { thisTab, otherTab, switchedElsewhere }

/// The error that set the `error` state: [message] for the reconnect view,
/// [process] and [cause] for the 503 detail (2.8 rule 4).
class LocalFolderFailure {
  const LocalFolderFailure(this.process, this.cause, this.message);
  final String process;
  final String cause;
  final String message;
}

String _causeOf(String message) {
  final i = message.indexOf(' — ');
  final cause = i < 0 ? message : message.substring(i + 3);
  return cause.endsWith('.') ? cause.substring(0, cause.length - 1) : cause;
}

const String _kAppVersion =
    String.fromEnvironment('APP_VERSION', defaultValue: 'dev');

/// One per app instance, owned by `_NotechondriaAppState` (main 2.5, 2.7).
/// It captures `Zone.current` when created, during the root widget's first
/// build inside `runGuardedApp`'s zone; void listeners are bound to it.
class LocalFolderController extends ChangeNotifier {
  LocalFolderController._({
    required this.app,
    required this.platform,
    required LocalFolderBootSnapshot? boot,
    this.log = discardLocalFolderLog,
    this.appVersion = _kAppVersion,
    DateTime Function()? now,
  })  : zone = Zone.current,
        _now = now ?? DateTime.now {
    final decision =
        decideStorageMode(app: app, isWeb: platform.isWeb, snapshot: boot);
    _mode = decision.mode;
    _record = decision.record;
    cloudSessionWins = decision.cloudSessionWins;
    _state = _mode == StorageMode.folder
        ? LocalFolderState.opening
        : LocalFolderState.disconnected;
    if (platform.isWeb) {
      _channel = platform.openChangeChannel(zone);
      _subscription = _channel.messages.listen(_onMessage);
    } else {
      _channel = NoopFolderChangeChannel();
    }
  }

  /// The production controller: the browser platform and the snapshot of
  /// `LocalFolderBoot.preload`. Without a snapshot (today's widget tests)
  /// or on a native build, the mode is `browserOrCloud`.
  factory LocalFolderController.forApp(String app,
          {LocalFolderLogSink log = discardLocalFolderLog}) =>
      LocalFolderController._(
          app: app,
          platform: browserLocalFolderPlatform(),
          boot: LocalFolderBoot.snapshot,
          log: log);

  /// Test seam (8.2): `MemoryFolderPlatform` and a seeded snapshot.
  factory LocalFolderController.forTest({
    required String app,
    required LocalFolderPlatform platform,
    LocalFolderBootSnapshot? boot,
    LocalFolderLogSink log = discardLocalFolderLog,
    String appVersion = 'test',
    DateTime Function()? now,
  }) =>
      LocalFolderController._(
          app: app,
          platform: platform,
          boot: boot,
          log: log,
          appVersion: appVersion,
          now: now);

  final String app;
  final LocalFolderPlatform platform;
  final Zone zone;
  final LocalFolderLogSink log;
  final String appVersion;
  final DateTime Function() _now;
  late final FolderChangeChannel _channel;
  StreamSubscription<Map<String, Object?>>? _subscription;

  late StorageMode _mode;
  late LocalFolderState _state;
  StorageModeRecord? _record;
  FolderFs? _folder;
  FolderJournal? _journal;
  FolderIndex? _index;
  ScanProgress? _progress;
  LocalFolderFailure? _failure;
  DisconnectReason? _disconnectReason;
  String? _switchedTo;
  bool _missingRecord = false;
  ({FolderFs folder, String folderId})? _pendingSwitch;
  FolderFs? _pendingPicked;
  FolderFs? _pendingOther;

  /// 2.10 rule 2: a folder is connected, but this app's cloud session wins.
  late final bool cloudSessionWins;

  /// 2.10 rule 5: another tab connected this folder name while this tab is
  /// in browser-local mode.
  String? connectedElsewhere;

  StorageMode get storageMode => _mode;
  LocalFolderState get state => _state;
  StorageModeRecord? get record => _record;
  FolderFs? get folder => _folder;
  FolderJournal? get journal => _journal;
  FolderIndex? get index => _index;
  ScanProgress? get progress => _progress;
  LocalFolderFailure? get failure => _failure;
  DisconnectReason? get disconnectReason => _disconnectReason;
  FolderLocks get locks => platform.locks;
  String get folderName => _record?.folderName ?? _folder?.name ?? '';
  String get lockName => folderLockName(_record?.folderId ?? '');
  DateTime now() => _now();

  LocalFolderTransport? _transport;
  StorageModeClient? _httpClient;
  String? _busy;
  bool _enterFolderOnActive = false;

  /// The in-page `/api/v1` backend (main 2.5).
  LocalFolderTransport get transport =>
      _transport ??= LocalFolderTransport(this);

  /// The app's `http.Client` (`StorageModeClient`), created on first use
  /// over `http.Client()`, so in tests its inner client is the zone's
  /// (8.5).
  http.Client get httpClient => _httpClient ??=
      StorageModeClient(mode: () => _mode, local: transport);

  /// "Folder busy: ..." while a chunked operation runs (6.2 R4).
  String? get busyLine => _busy;

  void setBusy(String? line) {
    if (_busy == line) return;
    _busy = line;
    notifyListeners();
  }

  void _setState(LocalFolderState next) {
    _state = next;
    if (next == LocalFolderState.active && _enterFolderOnActive) {
      _enterFolderOnActive = false;
      _mode = StorageMode.folder;
      _disconnectReason = null;
    }
    notifyListeners();
  }

  void _fail(String process, String message) {
    _failure = LocalFolderFailure(process, _causeOf(message), message);
    _setState(LocalFolderState.error);
  }

  /// The 503 detail for the current state (2.8 rule 4, T3, T7(i)), or null
  /// in `active` and `opening` (the transport holds requests then). Folder
  /// names and causes are interpolated, so the detail is scrubbed of the
  /// session-rejection sentinels (2.5).
  String? unavailableDetail({required bool isRead}) {
    final detail = _unavailableDetail(isRead: isRead);
    return detail == null ? null : scrubSessionSentinels(detail);
  }

  String? _unavailableDetail({required bool isRead}) {
    final name = folderName;
    switch (_state) {
      case LocalFolderState.active:
      case LocalFolderState.opening:
        return null;
      case LocalFolderState.needsPick:
        return _missingRecord
            ? LocalFolderMessages.needsPickMissingRecord(name)
            : LocalFolderMessages.needsPickSessionOnly(name);
      case LocalFolderState.needsPermission:
        return LocalFolderMessages.needsPermission(name);
      case LocalFolderState.scanning:
        return LocalFolderMessages.scanning(
            name, _progress?.done ?? 0, _progress?.total ?? 0);
      case LocalFolderState.error:
        final f = _failure;
        return LocalFolderMessages.unavailable(
            f?.process ?? 'scan', f?.cause ?? 'the folder could not be read');
      case LocalFolderState.disconnected:
        return switch (_disconnectReason) {
          DisconnectReason.otherTab =>
            LocalFolderMessages.disconnectedElsewhere(name),
          DisconnectReason.switchedElsewhere =>
            LocalFolderMessages.switchedElsewhere(name, _switchedTo ?? ''),
          _ => isRead
              ? LocalFolderMessages.disconnectedHereRead(name)
              : LocalFolderMessages.disconnectedHereWrite(name),
        };
    }
  }

  /// Completes when the state leaves `opening`, or after [timeLeft]; true
  /// when it left (the transport's `opening` hold, 2.8 rule 4).
  Future<bool> waitWhileOpening(Duration timeLeft) async {
    if (_state != LocalFolderState.opening) return true;
    final left = Completer<bool>();
    void listener() {
      if (_state != LocalFolderState.opening && !left.isCompleted) {
        left.complete(true);
      }
    }

    addListener(listener);
    final timer = Timer(timeLeft, () {
      if (!left.isCompleted) left.complete(false);
    });
    try {
      return await left.future;
    } finally {
      timer.cancel();
      removeListener(listener);
    }
  }

  /// Maps a folder failure to a state (6.3): `NotAllowedError` is a routine
  /// revocation (`needsPermission`), `NotFoundError` on the root means the
  /// folder moved; anything else is `error`.
  void reportFolderError(Object error, {String process = 'read'}) {
    if (error is FolderFsException && error.kind == FolderErrorKind.notAllowed) {
      _setState(LocalFolderState.needsPermission);
    } else if (error is FolderFsException &&
        error.kind == FolderErrorKind.notFound &&
        error.path.isEmpty) {
      _fail('restore_handle', LocalFolderMessages.folderNotFound(folderName));
    } else if (error is FolderLayoutException) {
      _fail('scan', error.message);
    } else {
      _fail(process, LocalFolderMessages.unavailable(process, '$error'));
    }
  }

  // --- startup (2.9) ---

  /// The `local_folder` startup step, steps 2 to 5. Makes no network call.
  Future<void> open() async {
    final record = _record;
    if (_mode != StorageMode.folder || record == null) return;
    _setState(LocalFolderState.opening);
    var handle = _folder;
    if (handle == null && record.remember) {
      try {
        handle = await platform.handleStore.load(record.folderId);
      } catch (_) {
        handle = null;
      }
    }
    if (handle == null) {
      _missingRecord = record.remember;
      _setState(LocalFolderState.needsPick);
      return;
    }
    _folder = handle;
    try {
      switch (await handle.queryPermission()) {
        case FolderPermission.granted:
          await _openGranted();
        case FolderPermission.prompt:
          _setState(LocalFolderState.needsPermission);
        case FolderPermission.denied:
          _fail('permission', LocalFolderMessages.permissionDenied(folderName));
      }
    } catch (error) {
      reportFolderError(error, process: 'restore_handle');
    }
  }

  /// Step 3: manifest, roll-forward, then the index fast path or a scan.
  Future<void> _openGranted() async {
    final folder = _folder!;
    final record = _record!;
    try {
      // A moved or deleted root throws NotFoundError here (6.3), before a
      // missing manifest.json could be mistaken for it.
      await folder.list('');
      final manifest = await readFolderManifest(folder);
      if (manifest == null) {
        final importPending = await folder.stat(kImportProgressPath) != null;
        _fail(
            'scan',
            LocalFolderMessages.manifestMissing(folderName,
                importPending: importPending));
        return;
      }
      if (manifest.folderId != record.folderId) {
        _fail(
            'restore_handle',
            LocalFolderMessages.folderIdChanged(
                folderName, manifest.folderId, record.folderId));
        return;
      }
      final journal = _journal = FolderJournal(folder, app: app, log: log);
      try {
        final rolled = await rollForwardUnderLock(
            locks: locks, lockName: lockName, journal: journal);
        final failure = rolled.failure;
        if (failure is FolderFsException &&
            failure.kind == FolderErrorKind.notAllowed) {
          _setState(LocalFolderState.needsPermission);
          return;
        }
      } on FolderLockTimeout {
        // Another tab holds the lock; readers roll forward later (6.2 R3),
        // so startup does not wait past the 5 s cap (2.9 "Bounds").
      }
      final index = await readFolderIndex(folder, folderId: record.folderId);
      if (index != null) {
        _index = index;
        _setState(LocalFolderState.active);
        return;
      }
      _progress = const ScanProgress(0, 0);
      _setState(LocalFolderState.scanning);
      _index = (await _scanner(journal).scan()).index;
      _setState(LocalFolderState.active);
    } catch (error) {
      reportFolderError(error, process: 'scan');
    }
  }

  FolderScanner _scanner(FolderJournal journal) => FolderScanner(
        fs: _folder!,
        locks: locks,
        lockName: lockName,
        journal: journal,
        folderId: _record!.folderId,
        now: _now,
        onProgress: (p) {
          _progress = p;
          notifyListeners();
        },
      );

  /// Applies changes to the in-memory index: this tab's own writes, and
  /// files a handler re-read (6.2 R2, P1B-1). `index.json` on disk is
  /// rewritten only by scans; a rescan replaces the whole index.
  void updateIndex(Map<String, IndexedFile?> changes,
      {Iterable<String> removedDirs = const []}) {
    if (changes.isEmpty && removedDirs.isEmpty) return;
    final base = _index ??
        FolderIndex(
            folderId: _record?.folderId ?? '', generatedAt: '', files: const {});
    _index = base.withChanges(changes, removedDirs: removedDirs);
    notifyListeners();
  }

  /// Rescan (6.4) and the verification rescan after startup (2.9). Keeps
  /// the state `active`; a failure moves it as [reportFolderError] does.
  Future<ScanResult?> rescan({Set<String> changedPaths = const {}}) async {
    final journal = _journal;
    if (_state != LocalFolderState.active || journal == null) return null;
    try {
      final result = await _scanner(journal)
          .scan(previous: _index, changedPaths: changedPaths);
      _index = result.index;
      notifyListeners();
      return result;
    } catch (error) {
      reportFolderError(error, process: 'rescan');
      return null;
    }
  }

  // --- reconnect and choose again (2.9, 6.3) ---

  /// "Reconnect '<name>'": `requestPermission` is the first call.
  Future<void> reconnect() async {
    final handle = _folder;
    if (handle == null) return;
    final Future<FolderPermission> pending;
    try {
      pending = handle.requestPermission();
    } catch (error) {
      reportFolderError(error, process: 'permission');
      return;
    }
    try {
      switch (await pending) {
        case FolderPermission.granted:
          _setState(LocalFolderState.opening);
          await _openGranted();
        case FolderPermission.prompt:
          _setState(LocalFolderState.needsPermission);
        case FolderPermission.denied:
          _fail('permission', LocalFolderMessages.permissionDenied(folderName));
      }
    } catch (error) {
      reportFolderError(error, process: 'permission');
    }
  }

  /// "Choose '<name>' again": the picker is the first call; only after it
  /// returns is the picked folder's manifest.json read and its folder_id
  /// checked (2.9), followed by the copy check (3.7).
  Future<PickOutcome> chooseAgain() async {
    final Future<FolderFs> picking = platform.picker.pickDirectory();
    final record = _record;
    final FolderFs picked;
    try {
      picked = await picking;
    } on FolderFsException catch (e) {
      if (e.kind == FolderErrorKind.abort) {
        log(LocalFolderLogLevel.info, LocalFolderMessages.pickCancelled);
        return const PickCancelled();
      }
      return PickFailed(LocalFolderMessages.pickFailed('$e'));
    }
    if (record == null) return const PickCancelled();
    final refusal = await refusalForPicked(picked,
        expectedFolderId: record.folderId, name: folderName);
    if (refusal != null) {
      if (refusal.canSwitch) {
        final id = (await readFolderManifest(picked))!.folderId;
        _pendingSwitch = (folder: picked, folderId: id);
      }
      return refusal;
    }
    FolderFs? other = _folder;
    if (other == null && record.remember) {
      try {
        other = await platform.handleStore.load(record.folderId);
      } catch (_) {
        other = null;
      }
    }
    final check =
        await checkPickedAgainst(picked, other, folderId: record.folderId);
    _pendingPicked = picked;
    _pendingOther = other;
    return switch (check) {
      CopyCheck.same || CopyCheck.moved => await _accept(picked),
      CopyCheck.looksLikeCopy => PickLooksLikeCopy(
          LocalFolderMessages.looksLikeCopy(picked.name, other!.name)),
      CopyCheck.needsAccess => PickMayBeCopy(
          LocalFolderMessages.mayBeCopy(picked.name, other!.name)),
    };
  }

  Future<PickOutcome> _accept(FolderFs picked) async {
    _pendingPicked = null;
    _pendingOther = null;
    _folder = picked;
    final record = _record!;
    if (record.remember) {
      await platform.handleStore.save(record.folderId, picked);
    }
    _setState(LocalFolderState.opening);
    await _openGranted();
    return const PickOpened();
  }

  /// "Check '<other>'": `requestPermission({mode: 'read'})` on the
  /// remembered folder is the first call, then the 3.7 read.
  Future<PickOutcome> checkRememberedCopy() async {
    final other = _pendingOther;
    final picked = _pendingPicked;
    if (other == null || picked == null) return const PickCancelled();
    final pending = other.requestPermission(write: false);
    if (await pending != FolderPermission.granted) {
      return PickMayBeCopy(LocalFolderMessages.mayBeCopy(picked.name, other.name));
    }
    final check =
        await readOtherForCopyCheck(other, folderId: _record!.folderId);
    if (check == CopyCheck.looksLikeCopy) {
      return PickLooksLikeCopy(
          LocalFolderMessages.looksLikeCopy(picked.name, other.name));
    }
    return _accept(picked);
  }

  /// "It is the same folder, moved": continue with the picked folder and
  /// replace the remembered record.
  Future<PickOutcome> treatPickedAsMoved() async {
    final picked = _pendingPicked;
    if (picked == null) return const PickCancelled();
    return _accept(picked);
  }

  /// "Give it its own identity": a new folder_id in the picked copy's
  /// manifest, journaled under the shared folder_id's lock. The copy is then
  /// a different folder, so the result is the "Switch to this folder"
  /// refusal.
  Future<PickOutcome> giveCopyOwnIdentity() async {
    final picked = _pendingPicked;
    if (picked == null) return const PickCancelled();
    final journal = FolderJournal(picked, app: app, log: log);
    final fresh = newUuidV4();
    await locks.run(lockName, FolderLockMode.exclusive, () async {
      await journal.rollForward();
      final manifest = await readFolderManifest(picked);
      if (manifest == null) return;
      await journal.commit(journal.newRecord([
        JournalWrite(kManifestPath, manifest.withFolderId(fresh).encode()),
      ]));
    });
    _pendingSwitch = (folder: picked, folderId: fresh);
    return PickRefused(
        LocalFolderMessages.pickDifferentFolder(
            picked.name, fresh, folderName, _record!.folderId),
        canSwitch: true);
  }

  /// "Switch to this folder" (2.9), in its four steps.
  Future<void> switchToPicked() async {
    final pending = _pendingSwitch;
    final old = _record;
    if (pending == null || old == null) return;
    _pendingSwitch = null;
    final record = StorageModeRecord(
      folderId: pending.folderId,
      folderName: pending.folder.name,
      connectedBy: app,
      connectedAt: _now().toUtc().toIso8601String(),
      remember: old.remember,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kSharedStorageModeKey, record.encode());
    await _forgetHandle(old.folderId);
    if (record.remember) {
      await platform.handleStore.save(record.folderId, pending.folder);
    }
    _channel.post({
      'op': kChangeOpSwitch,
      'folder_id': record.folderId,
      'folder_name': record.folderName,
    });
    _record = record;
    _folder = pending.folder;
    _index = null;
    _setState(LocalFolderState.opening);
    await _openGranted();
  }

  // --- the connected folder from browser-local mode (1.3, T3) ---

  /// Loads the remembered handle into page memory, without asking the
  /// browser anything, so "Use the connected folder" can call
  /// `requestPermission` as its first call.
  Future<void> preloadRememberedHandle() async {
    final record = _record;
    if (_folder != null || record == null || !record.remember) return;
    try {
      _folder = await platform.handleStore.load(record.folderId);
    } catch (_) {
      _folder = null;
    }
    notifyListeners();
  }

  /// "Use the connected folder '<name>'": the Reconnect path when a
  /// remembered handle is in memory ([preloadRememberedHandle]), else
  /// "Choose again" with its folder_id checks. The mode becomes `folder`
  /// when the folder reaches `active`.
  Future<PickOutcome> useConnectedFolder() async {
    final handle = _folder;
    if (handle == null) {
      _enterFolderOnActive = true;
      final outcome = await chooseAgain();
      // "Switch to this folder" and the copy questions wait for the next
      // click, which reaches `active` through the same flag.
      final waits = outcome is PickLooksLikeCopy ||
          outcome is PickMayBeCopy ||
          (outcome is PickRefused && outcome.canSwitch);
      if (!waits) _enterFolderOnActive = false;
      return outcome;
    }
    final Future<FolderPermission> pending = handle.requestPermission();
    _enterFolderOnActive = true;
    try {
      if (await pending == FolderPermission.granted) {
        _setState(LocalFolderState.opening);
        await _openGranted();
      }
    } catch (error) {
      reportFolderError(error, process: 'permission');
    }
    if (_state == LocalFolderState.active) return const PickOpened();
    _enterFolderOnActive = false;
    return PickFailed(_failure?.message ??
        scrubSessionSentinels(LocalFolderMessages.needsPermission(folderName)));
  }

  /// T3: the "Remember this folder on this browser" choice, from the pick
  /// flow or the status card.
  Future<void> setRemember(bool remember) async {
    final record = _record;
    if (record == null || record.remember == remember) return;
    final next = StorageModeRecord(
      folderId: record.folderId,
      folderName: record.folderName,
      connectedBy: record.connectedBy,
      connectedAt: record.connectedAt,
      remember: remember,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kSharedStorageModeKey, next.encode());
    final folder = _folder;
    if (remember && folder != null) {
      await platform.handleStore.save(record.folderId, folder);
    } else if (!remember) {
      await _forgetHandle(record.folderId);
    }
    _record = next;
    notifyListeners();
  }

  // --- connect and disconnect (1.3, 2.10) ---

  /// First connect: the picker is the first call; the picked folder is only
  /// inspected, nothing is written.
  Future<ConnectPick?> pickForConnect() async {
    final Future<FolderFs> picking = platform.picker.pickDirectory();
    try {
      return await inspectConnectPick(await picking);
    } on FolderFsException catch (e) {
      if (e.kind != FolderErrorKind.abort) rethrow;
      log(LocalFolderLogLevel.info, LocalFolderMessages.pickCancelled);
      return null;
    }
  }

  /// Connects [pick]. A folder without a manifest is initialized
  /// (README.md, then manifest.json last); a non-empty one only with
  /// [confirmedEntryCount] (6.1 mitigation 3).
  Future<void> connectPicked(ConnectPick pick,
      {required bool remember, bool confirmedEntryCount = false}) async {
    if (pick.refusal != null) throw StateError(pick.refusal!);
    if (pick.manifest == null && pick.entryCount > 0 && !confirmedEntryCount) {
      throw StateError('Folder not connected: Shared.LocalFolder/connect — '
          "'${pick.folder.name}' has ${pick.entryCount} entries and no "
          'manifest.json; confirm the count first.');
    }
    final folder = pick.folder;
    var folderId = pick.manifest?.folderId;
    if (folderId == null) {
      folderId = newUuidV4();
      for (final file in initialFolderFiles(
          folderId: folderId, appVersion: appVersion, now: _now())) {
        if (file.path == kReadmePath && await folder.stat(kReadmePath) != null) {
          continue;
        }
        await folder.writeText(file.path, file.text);
      }
    }
    final record = StorageModeRecord(
      folderId: folderId,
      folderName: folder.name,
      connectedBy: app,
      connectedAt: _now().toUtc().toIso8601String(),
      remember: remember,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kSharedStorageModeKey, record.encode());
    if (remember) {
      await platform.handleStore.save(folderId, folder);
    } else {
      await _forgetHandle(folderId);
    }
    _channel.post({
      'op': kChangeOpConnect,
      'folder_id': folderId,
      'folder_name': folder.name,
    });
    _record = record;
    _folder = folder;
    _mode = StorageMode.folder;
    _disconnectReason = null;
    connectedElsewhere = null;
    _setState(LocalFolderState.opening);
    await _openGranted();
  }

  Future<void> _forgetHandle(String folderId) async {
    try {
      await platform.handleStore.delete(folderId);
    } catch (_) {
      // A record that cannot be deleted is overwritten by the next save.
    }
  }

  /// Disconnect (2.10 rule 4), in this order so that no request carrying
  /// `Token local-folder` can reach the network: (1) the state becomes
  /// `disconnected`, so queued requests get 503; (2) [clearSession] clears
  /// the app's in-memory folder token and profile; (3) the shared key and
  /// the remembered record are cleared and `{op: "disconnect"}` is posted;
  /// (4) only then does the mode switch to `browserOrCloud`.
  Future<void> disconnect({Future<void> Function()? clearSession}) async {
    final record = _record;
    _disconnectReason = DisconnectReason.thisTab;
    _setState(LocalFolderState.disconnected);
    if (clearSession != null) await clearSession();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(kSharedStorageModeKey);
    if (record != null) await _forgetHandle(record.folderId);
    _channel.post({'op': kChangeOpDisconnect, 'folder_id': record?.folderId});
    _mode = StorageMode.browserOrCloud;
    _folder = null;
    _journal = null;
    _index = null;
    notifyListeners();
  }

  void _onMessage(Map<String, Object?> message) {
    final op = message['op'];
    if (_mode == StorageMode.folder) {
      if (op == kChangeOpDisconnect &&
          message['folder_id'] == _record?.folderId) {
        _disconnectReason = DisconnectReason.otherTab;
        _setState(LocalFolderState.disconnected);
      } else if (op == kChangeOpSwitch &&
          message['folder_id'] != _record?.folderId) {
        _disconnectReason = DisconnectReason.switchedElsewhere;
        _switchedTo = '${message['folder_name'] ?? ''}';
        _setState(LocalFolderState.disconnected);
      }
    } else if (op == kChangeOpConnect && !cloudSessionWins) {
      connectedElsewhere = '${message['folder_name'] ?? ''}';
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _channel.close();
    _httpClient?.close();
    super.dispose();
  }
}
