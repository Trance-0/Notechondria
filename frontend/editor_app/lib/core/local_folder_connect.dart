part of '../main.dart';

/// Local folder mode in the editor (design `docs/development/local_folder_mode.md`
/// 2.7; `local_folder_mode/modes_and_migration.md` 2.9, 2.10, 7.1; design
/// review 3 T2). `_NotechondriaAppState` owns the controller; this file
/// holds the `Editor.Startup/local_folder` step, the folder session with
/// the connect-time push, the settings widgets, and the reconnect view that
/// replaces the shell while the folder is pending.

/// The mounted shell's folder controller, for the code outside the shell's
/// state: the controller's log lines go to the shell's debug log (the
/// controller exists before any shell, 2.7), and the image call sites read
/// `nc-folder:` URLs through it (3.6).
class _EditorFolder {
  static LocalFolderController? current;
  static void Function(LocalFolderLogLevel level, String message)? logTarget;

  static void log(LocalFolderLogLevel level, String message) =>
      logTarget?.call(level, message);
}

/// Per-shell folder bookkeeping (extensions cannot declare fields).
class _FolderSessionState {
  /// A cold `#/notes/<uuid>` that arrived while the folder was pending; it
  /// opens once the folder is active (T2).
  String? pendingDeepLink;

  /// The 2.10 rule 2 notice was shown in this start.
  bool precedenceShown = false;

  /// A folder session start is running.
  bool starting = false;
}

/// 2.10 rule 3: the folder this app already pushed its browser data into.
const String _kFolderPushedKey = 'notechondria.editor.folder_pushed';

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
    _EditorFolder.current = folder;
    _EditorFolder.logTarget = (level, message) {
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
    if (identical(_EditorFolder.current, _folder)) {
      _EditorFolder.current = null;
      _EditorFolder.logTarget = null;
    }
  }

  void _onLocalFolderChanged() {
    if (mounted) refreshState();
  }

  // --- startup (2.9) ---

  /// The `Editor.Startup/local_folder` step, after `local_state` and before
  /// `config`. Makes no network request.
  Future<void> _runLocalFolderStep() async {
    final bootFailure = LocalFolderBoot.preloadFailureMessage('editor');
    if (bootFailure != null) {
      log(
        level: DebugLogLevel.warning,
        source: 'Editor.Startup/local_folder',
        message: bootFailure,
      );
    }
    final folder = _folder;
    if (folder == null || folder.storageMode != StorageMode.folder) return;
    await startupStep<void>(
      'Editor.Startup/local_folder',
      () => _openFolderAtStartup(folder),
      status: _splashStatus,
      label: "Opening folder '${folder.folderName}'",
      failureConsequence: 'Folder not opened',
      outcome: (_) => folder.state == LocalFolderState.active
          ? (
              level: DebugLogLevel.info,
              message: 'Folder opened: Editor.Startup/local_folder \u2014 '
                  "'${folder.folderName}' is open; every request is answered "
                  'in this page.',
            )
          : (
              level: DebugLogLevel.warning,
              message: 'Folder not open yet: Editor.Startup/local_folder '
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
      source: 'Editor.Startup/initial_data',
      message: 'Folder data not loaded yet: Editor.Startup/initial_data '
          '\u2014 the folder is waiting for Reconnect or Choose again; '
          'session_restore, oauth_callback, and initial_data were skipped.',
    );
  }

  /// In folder mode session_restore and oauth_callback are skipped (2.9).
  void _logFolderSkipsSignIn() {
    if (!Uri.base.queryParameters.containsKey('code')) return;
    log(
      level: DebugLogLevel.warning,
      source: 'Editor.Startup/oauth_callback',
      message: 'Sign-in not completed: Editor.Startup/oauth_callback \u2014 '
          'this app is in folder mode; disconnect the folder to sign in to '
          'the cloud.',
    );
  }

  /// 2.10 rule 2: a saved cloud session won over the connected folder.
  /// Shown once per start; the status card repeats it.
  void _noteCloudSessionPrecedence() {
    final folder = _folder;
    final token = _token;
    if (folder == null ||
        !folder.cloudSessionWins ||
        _folderSession.precedenceShown ||
        token == null ||
        token.isEmpty) {
      return;
    }
    _folderSession.precedenceShown = true;
    final message = LocalFolderMessages.cloudSessionWins(
        'Editor', _cloudUserLabel, folder.folderName);
    log(
      level: DebugLogLevel.info,
      source: 'Editor.Startup/local_folder',
      message: message,
    );
    showMessage(message);
  }

  String get _cloudUserLabel =>
      currentUsername ?? _profile?['email']?.toString() ?? 'user';

  // --- the folder session (2.9 step 3, 7.1) ---

  /// `applyAuthPayload` with the folder payload, and on this app's first
  /// start in a folder the 7.1 push: the in-memory token is set before the
  /// course push (`_syncLocalCourse` needs one), the drafts follow inside
  /// `applyAuthPayload`. Then a deep link that waited for the folder opens.
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
      if (firstStart) {
        _token = kLocalFolderToken;
        await _syncAllLocalCourses();
      }
      final session = await widget.client.checkSession(kLocalFolderToken);
      await applyAuthPayload({
        ...session,
        'token': kLocalFolderToken,
        'folder_session': restore && !firstStart ? 'restore' : 'pick',
      });
      if (firstStart) {
        await prefs.setString(_kFolderPushedKey, record.folderId);
        _logBrowserDataMoved(record.folderName,
            drafts - _localDrafts.length, courses - _localCourses.length);
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
      return;
    } finally {
      _folderSession.starting = false;
    }
    final uuid = _folderSession.pendingDeepLink;
    _folderSession.pendingDeepLink = null;
    if (uuid != null && mounted) await _openNoteByUuid(uuid);
  }

  void _logBrowserDataMoved(String name, int drafts, int courses) {
    final message = 'Browser data moved: Shared.LocalFolder/connect \u2014 '
        '$drafts drafts and $courses categories from this browser are now '
        "in '$name'; this browser keeps recoverable copies for 30 days "
        '(local recycle bin).';
    log(
      level: DebugLogLevel.info,
      source: 'Shared.LocalFolder/connect',
      message: message,
    );
    if (drafts + courses > 0) showMessage(message);
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

  /// The status card: in folder mode it replaces the account rows; with a
  /// cloud session that took precedence it repeats the 2.10 rule 2 line.
  Widget? _folderStatusCard() {
    final folder = _folder;
    if (folder == null || (!inFolderMode && !folder.cloudSessionWins)) {
      return null;
    }
    return LocalFolderStatusCard(
      controller: folder,
      onDisconnect: inFolderMode ? disconnectFolder : null,
      cloudApiBaseUrl: _localSettings['api_base_url']?.toString() ??
          _defaultApiBaseUrl(),
      cloudUser: folder.cloudSessionWins ? _cloudUserLabel : null,
    );
  }

  /// `ping` through the app's `StorageModeClient` (2.7): the folder answers
  /// it in folder mode, the network otherwise.
  Future<PingResult> _pingThroughFolderClient() => pingBackend(
        _localSettings['api_base_url']?.toString() ?? _httpClient?.baseUrl,
        client: _folder?.httpClient,
      );

  String get _folderPullNotNeeded =>
      'Cloud notes not pulled: Editor.Sync.Notes/pull \u2014 this app uses '
      "the folder '${_folder?.folderName ?? ''}', which has no cloud copy; "
      'disconnect the folder and sign in to pull cloud notes.';

  /// `clearAppSpecificSessionFields`: a Disconnect (still in folder mode
  /// while the session is cleared, 2.10 rule 4) drops every folder row
  /// from memory and puts this browser's own cached rows back, so the
  /// signed-out reload that follows cannot write a folder row to
  /// `local_cache` (2.7, 202-N9). A cloud logout keeps its old behavior.
  void _clearFolderSessionFields() {
    if (!inFolderMode) return;
    _frontPage = Map<String, dynamic>.from(
        _localCache['front_page'] as Map? ?? const {});
    _courses = (_localCache['courses'] as List<dynamic>? ?? const [])
        .map((item) =>
            decorateRemoteCourse(Map<String, dynamic>.from(item as Map)))
        .toList(growable: false);
    _courseNotes = const [];
    _learnerNotes = const [];
    _selectedNote = null;
    _selectedCourse = null;
  }
}
