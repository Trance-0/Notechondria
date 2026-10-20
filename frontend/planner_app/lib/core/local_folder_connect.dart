part of '../main.dart';

/// Local folder mode in the planner (design `docs/development/local_folder_mode.md`
/// 2.7; `local_folder_mode/modes_and_migration.md` 2.9, 2.10, 7.1).
/// `_NotechondriaAppState` owns the controller; this file holds the
/// `Planner.Startup/local_folder` step, the folder session, the settings
/// widgets, and the reconnect view that replaces the shell while the folder
/// is pending. The connect-time push of browser data (7.1) is in
/// `core/local_folder_push.dart`.
///
/// The planner keeps its cloud session in memory only, so no saved session
/// can win over a connected folder at startup (2.10 rule 2): a cold start
/// with a connected folder is always in folder mode. A tab that signed in
/// to the cloud before another tab connected a folder keeps its session
/// and shows the 2.10 rule 5 banner.

/// The mounted shell's folder controller, for the code outside the shell's
/// state: the controller's log lines go to the shell's debug log, and the
/// image call sites read `nc-folder:` URLs through it (3.6).
class _PlannerFolder {
  static LocalFolderController? current;
  static void Function(LocalFolderLogLevel level, String message)? logTarget;

  static void log(LocalFolderLogLevel level, String message) =>
      logTarget?.call(level, message);
}

/// Per-shell folder bookkeeping (extensions cannot declare fields).
class _FolderSessionState {
  /// A folder session start is running.
  bool starting = false;
}

/// 2.10 rule 3: the folder this app already pushed its browser data into.
const String _kFolderPushedKey = 'notechondria.planner.folder_pushed';

final RegExp _folderLogSource =
    RegExp(r'Shared\.LocalFolder(?:\.\w+)?/[\w.]+');

extension _AppShellLocalFolderX on _AppShellState {
  LocalFolderController? get _folder => widget.localFolder;

  /// Folder mode with the folder waiting for Reconnect or Choose again
  /// (2.9 step 4, 6.3): the reconnect view replaces the shell.
  bool get _folderPending {
    final folder = _folder;
    if (folder == null || folder.storageMode != StorageMode.folder) {
      return false;
    }
    return const {
      LocalFolderState.needsPick,
      LocalFolderState.needsPermission,
      LocalFolderState.error,
    }.contains(folder.state);
  }

  void _attachLocalFolder() {
    final folder = _folder;
    if (folder == null) return;
    _PlannerFolder.current = folder;
    _PlannerFolder.logTarget = (level, message) {
      if (!mounted) return;
      log(
        level: switch (level) {
          LocalFolderLogLevel.info => DebugLogLevel.info,
          LocalFolderLogLevel.warning => DebugLogLevel.warning,
          LocalFolderLogLevel.error => DebugLogLevel.error,
        },
        source: _folderLogSource.firstMatch(message)?.group(0) ??
            'Shared.LocalFolder',
        message: message,
      );
    };
    folder.addListener(_onLocalFolderChanged);
  }

  void _detachLocalFolder() {
    _folder?.removeListener(_onLocalFolderChanged);
    if (identical(_PlannerFolder.current, _folder)) {
      _PlannerFolder.current = null;
      _PlannerFolder.logTarget = null;
    }
  }

  void _onLocalFolderChanged() {
    if (mounted) refreshState();
  }

  // --- startup (2.9) ---

  /// The `Planner.Startup/local_folder` step, after `local_state` and
  /// before `config`. Makes no network request.
  Future<void> _runLocalFolderStep() async {
    final bootFailure = LocalFolderBoot.preloadFailureMessage('planner');
    if (bootFailure != null) {
      log(
        level: DebugLogLevel.warning,
        source: 'Planner.Startup/local_folder',
        message: bootFailure,
      );
    }
    final folder = _folder;
    if (folder == null || folder.storageMode != StorageMode.folder) return;
    await startupStep<void>(
      'Planner.Startup/local_folder',
      () => _openFolderAtStartup(folder),
      status: _splashStatus,
      label: "Opening folder '${folder.folderName}'",
      failureConsequence: 'Folder not opened',
      outcome: (_) => folder.state == LocalFolderState.active
          ? (
              level: DebugLogLevel.info,
              message: 'Folder opened: Planner.Startup/local_folder \u2014 '
                  "'${folder.folderName}' is open; every request is answered "
                  'in this page.',
            )
          : (
              level: DebugLogLevel.warning,
              message: 'Folder not open yet: Planner.Startup/local_folder '
                  '\u2014 the folder is ${folder.state.name}, so startup '
                  'shows the reconnect view and loads no data until '
                  'Reconnect or Choose again.',
            ),
    );
  }

  /// Steps 2 to 5 through the controller; the splash shows scan progress
  /// and each report re-arms its timer. Step 3 ends with the session.
  Future<void> _openFolderAtStartup(LocalFolderController folder) async {
    void progress() {
      final p = folder.progress;
      if (folder.state != LocalFolderState.scanning || p == null) return;
      _splashStatus.value =
          LocalFolderMessages.scanProgress(folder.folderName, p.done, p.total);
      _armSplashTimer();
    }

    folder.addListener(progress);
    try {
      await folder.open();
    } finally {
      folder.removeListener(progress);
    }
    if (folder.state == LocalFolderState.active) {
      await _startFolderSession(restore: true);
    }
  }

  /// 2.9 step 3: after the startup pass, outside its budget, a verification
  /// rescan compares the stored index with the disk; the data reloads when
  /// the rescan changed it.
  Future<void> _verifyFolderAfterStartup() async {
    final folder = _folder;
    if (folder == null ||
        !inFolderMode ||
        folder.state != LocalFolderState.active) {
      return;
    }
    String fingerprint() {
      final files = folder.index?.files;
      if (files == null) return '';
      return [
        for (final f in files.values) '${f.path}:${f.size}:${f.lastModified}',
      ].join('|');
    }

    final before = fingerprint();
    final result = await folder.rescan();
    if (result == null || !mounted || fingerprint() == before) return;
    await _loadInitialData();
  }

  /// The pass ends with the folder pending: no session, no data load; the
  /// splash closes and the reconnect view shows (2.9 step 4).
  void _finishStartupWithFolderPending() {
    _isLoading = false;
    _showSplash = false;
    refreshState();
    log(
      level: DebugLogLevel.info,
      source: 'Planner.Startup/initial_data',
      message: 'Folder data not loaded yet: Planner.Startup/initial_data '
          '\u2014 the folder is waiting for Reconnect or Choose again; '
          'oauth_callback and initial_data were skipped.',
    );
  }

  /// In folder mode oauth_callback is skipped (2.9); the planner has no
  /// saved session to restore in either mode.
  void _logFolderSkipsSignIn() {
    if (!Uri.base.queryParameters.containsKey('code')) return;
    log(
      level: DebugLogLevel.warning,
      source: 'Planner.Startup/oauth_callback',
      message: 'Sign-in not completed: Planner.Startup/oauth_callback '
          '\u2014 this app is in folder mode; disconnect the folder to sign '
          'in to the cloud.',
    );
  }

  // --- the folder session (2.9 step 3, 7.1) ---

  /// `applyAuthPayload` with the folder payload, and on this app's first
  /// start in a folder the 7.1 push: the in-memory token is set before the
  /// course push (`_syncLocalCourse` throws without one), then events and
  /// imported calendars follow with the course-id map; the drafts follow
  /// inside `applyAuthPayload`.
  Future<void> _startFolderSession({required bool restore}) async {
    final folder = _folder;
    final record = folder?.record;
    if (folder == null ||
        record == null ||
        folder.state != LocalFolderState.active ||
        _folderSession.starting) {
      return;
    }
    _folderSession.starting = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final firstStart = prefs.getString(_kFolderPushedKey) != record.folderId;
      final drafts = _localDrafts.length;
      final courses = _localCourses.length;
      var items = 0;
      if (firstStart) {
        _token = kLocalFolderToken;
        items = await _pushBrowserPlannerData(record);
      }
      final session = await widget.client.checkSession(kLocalFolderToken);
      await applyAuthPayload({
        ...session,
        'token': kLocalFolderToken,
        'folder_session': restore && !firstStart ? 'restore' : 'pick',
      });
      if (firstStart) {
        await prefs.setString(_kFolderPushedKey, record.folderId);
        _logBrowserDataMoved(record.folderName, drafts - _localDrafts.length,
            courses - _localCourses.length, items);
      }
    } catch (error) {
      if (_profile == null) _token = null;
      log(
        level: DebugLogLevel.warning,
        source: 'Shared.LocalFolder/connect',
        message: 'Folder session not started: Shared.LocalFolder/connect '
            "\u2014 '${folder.folderName}' answered "
            '${describeRequestFailure(error)}.',
      );
      refreshState();
    } finally {
      _folderSession.starting = false;
    }
  }

  void _logBrowserDataMoved(String name, int drafts, int courses, int items) {
    final message = 'Browser data moved: Shared.LocalFolder/connect \u2014 '
        '$drafts drafts, $courses courses, and $items planner items from '
        "this browser are now in '$name'; this browser keeps recoverable "
        'copies for 30 days (local recycle bin, and the planner items in '
        '$_kPushedToFolderKey).';
    log(
      level: DebugLogLevel.info,
      source: 'Shared.LocalFolder/connect',
      message: message,
    );
    if (drafts + courses + items > 0) showMessage(message);
  }

  // --- widgets ---

  /// The reconnect view in place of the shell while the folder is pending.
  Widget? _folderGateView() {
    final folder = _folder;
    if (folder == null || !_folderPending) return null;
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: LocalFolderReconnectView(
            controller: folder,
            onUseBrowserLocal: disconnectFolder,
            onOpened: () => _startFolderSession(restore: true),
          ),
        ),
      ),
    );
  }

  /// The 2.10 rule 5 banners (other tabs) above the shell, web builds only.
  Widget _withFolderBanner(Widget child) {
    final folder = _folder;
    if (folder == null || !folder.platform.isWeb) return child;
    return Column(
      children: [
        Material(child: LocalFolderChangeBanner(controller: folder)),
        Expanded(child: child),
      ],
    );
  }

  /// "Use a local folder (no account)" in the signed-out AuthHub (1.3), on
  /// web builds only.
  Widget? _folderSignInOption() {
    final folder = _folder;
    if (folder == null || !folder.platform.isWeb) return null;
    return LocalFolderSignInOption(
      controller: folder,
      onConnected: () => _startFolderSession(restore: false),
    );
  }

  /// The status card; in folder mode it replaces the account rows.
  Widget? _folderStatusCard() {
    final folder = _folder;
    if (folder == null || !inFolderMode) return null;
    return LocalFolderStatusCard(
      controller: folder,
      onDisconnect: disconnectFolder,
      cloudApiBaseUrl: _localSettings['api_base_url']?.toString() ??
          _defaultApiBaseUrl(),
    );
  }

  /// `ping` through the app's `StorageModeClient` (2.7): the folder answers
  /// it in folder mode, the network otherwise.
  Future<PingResult> _pingThroughFolderClient() => pingBackend(
        _localSettings['api_base_url']?.toString() ?? _httpClient?.baseUrl,
        client: _folder?.httpClient,
      );

  String get _folderPullNotNeeded =>
      'Cloud notes not pulled: Planner.Sync.Notes/pull \u2014 this app uses '
      "the folder '${_folder?.folderName ?? ''}', which has no cloud copy; "
      'disconnect the folder and sign in to pull cloud notes.';
}
