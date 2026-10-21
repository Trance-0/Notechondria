part of '../main.dart';

/// Local folder mode in the portal (design `docs/development/local_folder_mode.md`
/// 2.7 "Portal note route"; `local_folder_mode/modes_and_migration.md` 2.9,
/// 2.10, 7.1; design review 3 T1). `_NotechondriaAppState` owns the
/// controller and passes it to every shell and to `_NoteRoutePage`; this
/// file holds the `Portal.Startup/local_folder` step, the folder session
/// with the connect-time push, the settings widgets, and the reconnect view
/// that replaces the shell while the folder is pending.

/// The app's folder controller, for the code outside a shell's state: the
/// image call sites read `nc-folder:` URLs through it (3.6), and the
/// controller's log lines go to the debug log of the shell that attached
/// last (the controller exists before any shell, 2.7).
class _PortalFolder {
  static LocalFolderController? current;
  static Object? logOwner;
  static void Function(LocalFolderLogLevel level, String message)? logTarget;

  /// The controller whose `open()` a shell already started: the portal
  /// builds one shell per route, and only the first one opens the folder.
  static LocalFolderController? opened;

  static void log(LocalFolderLogLevel level, String message) =>
      logTarget?.call(level, message);
}

/// Per-shell folder bookkeeping (extensions cannot declare fields).
class _FolderSessionState {
  /// The `local_folder` step of this shell finished; from then on the shell
  /// starts the folder session itself when the folder becomes active (T1).
  bool stepDone = false;

  /// This shell saw the folder pending (Reconnect or Choose again).
  bool sawPending = false;

  /// A cold `#/courses/<slug>` that arrived while the folder was pending.
  bool pendingCourseLink = false;

  /// The 2.10 rule 2 notice was shown in this start.
  bool precedenceShown = false;

  /// A folder session start is running.
  bool starting = false;
}

/// 2.10 rule 3: the folder this app already pushed its browser data into.
const String _kFolderPushedKey = 'notechondria.portal.folder_pushed';

/// 7.1 step 3: browser-local planner events the folder accepted, kept for
/// 30 days (`{folder_id, pushed_at, events, feeds}`).
const String _kPushedToFolderKey = 'notechondria.portal.pushed_to_folder';

final RegExp _folderLogSource = RegExp(r'Shared\.LocalFolder(?:\.\w+)?/[\w.]+');

const Set<LocalFolderState> _kFolderPendingStates = {
  LocalFolderState.needsPick,
  LocalFolderState.needsPermission,
  LocalFolderState.error,
};

extension _AppShellLocalFolderX on _AppShellState {
  LocalFolderController? get _folder => widget.localFolder;

  /// Folder mode with the folder waiting for Reconnect or Choose again
  /// (2.9 step 4, 6.3): the reconnect view replaces the shell.
  bool get _folderPending {
    final folder = _folder;
    return folder != null &&
        folder.storageMode == StorageMode.folder &&
        _kFolderPendingStates.contains(folder.state);
  }

  bool get _hasFolderSession => _profile?['is_local_folder'] == true;

  void _attachLocalFolder() {
    final folder = _folder;
    if (folder == null) return;
    _PortalFolder.current = folder;
    _PortalFolder.logOwner = this;
    _PortalFolder.logTarget = (level, message) {
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
    if (identical(_PortalFolder.logOwner, this)) {
      _PortalFolder.logOwner = null;
      _PortalFolder.logTarget = null;
    }
  }

  /// T1: the shell owns step 3. A shell in folder mode without a folder
  /// session starts it once the folder becomes active, wherever the click
  /// happened (this shell's reconnect view, `_NoteRoutePage`'s, or the
  /// status card).
  void _onLocalFolderChanged() {
    if (!mounted) return;
    final folder = _folder!;
    if (inFolderMode && _kFolderPendingStates.contains(folder.state)) {
      _folderSession.sawPending = true;
    }
    if (inFolderMode &&
        folder.state == LocalFolderState.active &&
        _folderSession.stepDone &&
        !_hasFolderSession &&
        !_folderSession.starting) {
      unawaited(_startFolderSession(restore: _folderSession.sawPending));
    }
    refreshState();
  }

  // --- startup (2.9) ---

  /// The `Portal.Startup/local_folder` step, after `local_state` and before
  /// `config`. Makes no network request.
  Future<void> _runLocalFolderStep() async {
    final bootFailure = LocalFolderBoot.preloadFailureMessage('portal');
    if (bootFailure != null) {
      log(
        level: DebugLogLevel.warning,
        source: 'Portal.Startup/local_folder',
        message: bootFailure,
      );
    }
    final folder = _folder;
    if (folder == null || folder.storageMode != StorageMode.folder) {
      _folderSession.stepDone = true;
      return;
    }
    try {
      await startupStep<void>(
        'Portal.Startup/local_folder',
        () => _openFolderAtStartup(folder),
        status: _splashStatus,
        label: "Opening folder '${folder.folderName}'",
        failureConsequence: 'Folder not opened',
        outcome: (_) => folder.state == LocalFolderState.active
            ? (
                level: DebugLogLevel.info,
                message: 'Folder opened: Portal.Startup/local_folder \u2014 '
                    "'${folder.folderName}' is open; every request is "
                    'answered in this page.',
              )
            : (
                level: DebugLogLevel.warning,
                message: 'Folder not open yet: Portal.Startup/local_folder '
                    '\u2014 the folder is ${folder.state.name}, so startup '
                    'shows the reconnect view and loads no data until '
                    'Reconnect or Choose again.',
              ),
      );
    } finally {
      _folderSession.stepDone = true;
    }
  }

  /// Steps 2 to 5 through the controller; the splash shows scan progress
  /// and each report re-arms its timer. Step 3 ends with the session. A
  /// later shell (another route) finds the folder already opening or open:
  /// it waits for that and only applies the payload (T1).
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
      if (!identical(_PortalFolder.opened, folder)) {
        _PortalFolder.opened = folder;
        await folder.open();
      } else {
        await folder.waitWhileOpening(const Duration(seconds: 30));
      }
    } finally {
      folder.removeListener(progress);
    }
    if (folder.state == LocalFolderState.active) {
      await _startFolderSession(restore: true);
    } else if (_kFolderPendingStates.contains(folder.state)) {
      _folderSession.sawPending = true;
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
      source: 'Portal.Startup/initial_data',
      message: 'Folder data not loaded yet: Portal.Startup/initial_data '
          '\u2014 the folder is waiting for Reconnect or Choose again; '
          'session_restore, oauth_callback, and initial_data were skipped.',
    );
  }

  /// In folder mode session_restore and oauth_callback are skipped (2.9).
  void _logFolderSkipsSignIn() {
    if (!Uri.base.queryParameters.containsKey('code')) return;
    log(
      level: DebugLogLevel.warning,
      source: 'Portal.Startup/oauth_callback',
      message: 'Sign-in not completed: Portal.Startup/oauth_callback \u2014 '
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
        'Portal', _cloudUserLabel, folder.folderName);
    log(
      level: DebugLogLevel.info,
      source: 'Portal.Startup/local_folder',
      message: message,
    );
    showMessage(message);
  }

  String get _cloudUserLabel =>
      currentUsername ?? _profile?['email']?.toString() ?? 'user';

  // --- the folder session (2.9 step 3, 7.1) ---

  /// `applyAuthPayload` with the folder payload. On this app's first start
  /// in a folder the 7.1 push runs first: the in-memory token is set (the
  /// course push needs one), courses go in, then the local planner events
  /// with `client_local_id`; the drafts follow inside `applyAuthPayload`.
  /// A connect whose session the listener already started is not repeated;
  /// a Reconnect re-applies the payload, which also pushes the drafts that
  /// failed while the folder was away.
  Future<void> _startFolderSession({required bool restore}) async {
    final folder = _folder;
    final record = folder?.record;
    if (folder == null ||
        record == null ||
        folder.state != LocalFolderState.active ||
        _folderSession.starting ||
        (!restore && _hasFolderSession)) {
      return;
    }
    _folderSession.starting = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final firstStart = prefs.getString(_kFolderPushedKey) != record.folderId;
      final drafts = _localDrafts.length;
      final courses = _localCourses.length;
      var events = (pushed: 0, failed: 0);
      if (firstStart) {
        _token = kLocalFolderToken;
        final courseIds = await _pushLocalCoursesToFolder();
        events = await _pushLocalEventsToFolder(record, courseIds);
      }
      final session = await widget.client.checkSession(kLocalFolderToken);
      await applyAuthPayload({
        ...session,
        'token': kLocalFolderToken,
        'folder_session': restore && !firstStart ? 'restore' : 'pick',
      });
      if (firstStart) {
        // A failed event push runs again at the next start; the folder
        // upserts on client_local_id, so a repeat never duplicates.
        if (events.failed == 0) {
          await prefs.setString(_kFolderPushedKey, record.folderId);
        }
        _logBrowserDataMoved(record.folderName, drafts - _localDrafts.length,
            courses - _localCourses.length, events.pushed);
      }
    } catch (error) {
      if (!_hasFolderSession) _token = null;
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
    if (_folderSession.pendingCourseLink && mounted) {
      _folderSession.pendingCourseLink = false;
      await _openInitialCourseDeepLink();
    }
  }

  /// 7.1 step 2: each browser-local course through `_syncLocalCourse`
  /// (upsert on `client_course_id`; drafts are remapped, the local copy goes
  /// to the local recycle bin). Returns local id -> folder id for step 3.
  Future<Map<int, int>> _pushLocalCoursesToFolder() async {
    final ids = <int, int>{};
    for (final course in List<Map<String, dynamic>>.from(_localCourses)) {
      final localId = (course['id'] as num?)?.toInt();
      try {
        final created = await _syncLocalCourse(course);
        final folderId = (created['id'] as num?)?.toInt();
        if (localId != null && folderId != null) ids[localId] = folderId;
      } catch (error) {
        log(
          level: DebugLogLevel.warning,
          source: 'Portal.Sync.Courses/push',
          message: 'Local category not synced: Portal.Sync.Courses/push '
              "\u2014 '${course['title']}' "
              '(${describeRequestFailure(error)}). Kept locally; will retry '
              'on next sync.',
        );
      }
    }
    return ids;
  }

  /// 7.1 step 3: the portal's `local-<micros>` events, with `course_id`
  /// rewritten through [courseIds] and `client_local_id = "portal:<id>"`.
  /// An accepted event leaves the visible local list for the 30-day
  /// recovery list; a refused one stays local.
  Future<({int pushed, int failed})> _pushLocalEventsToFolder(
      StorageModeRecord record, Map<int, int> courseIds) async {
    final pushed = <Map<String, dynamic>>[];
    final kept = <Map<String, dynamic>>[];
    String? firstCause;
    for (final event in _localEvents) {
      final title = event['title']?.toString() ?? '';
      final localCourse = (event['course_id'] as num?)?.toInt();
      int? courseId = localCourse;
      if (localCourse != null && courseIds.containsKey(localCourse)) {
        courseId = courseIds[localCourse];
      } else if (localCourse != null && localCourse < 0) {
        courseId = null;
        log(
          level: DebugLogLevel.warning,
          source: 'Portal.Sync.Events/push',
          message: 'Planner event course dropped: Portal.Sync.Events/push '
              "\u2014 '$title' referred to local category $localCourse, "
              'which was not copied into the folder; the event is '
              'uncategorized.',
        );
      }
      try {
        await widget.client.createPlannerEvent(kLocalFolderToken, {
          for (final key in const [
            'title',
            'event_date',
            'starts_at',
            'ends_at',
            'difficulty_weight',
            'description',
            'is_completed',
            'completed_at',
          ])
            key: event[key],
          // The repeat rule, sent only when set: the folder refuses a null
          // recurrence_freq or recurrence_interval.
          for (final key in const [
            'recurrence_freq',
            'recurrence_interval',
            'recurrence_end_date',
            'recurrence_count',
          ])
            if (event[key] != null) key: event[key],
          'course_id': courseId,
          'client_local_id': 'portal:${event['id']}',
        });
        pushed.add(event);
      } catch (error) {
        firstCause ??= describeRequestFailure(error);
        kept.add(event);
      }
    }
    if (pushed.isNotEmpty) {
      // The recovery copy is written before the events leave the list.
      await _recordPushedToFolder(record.folderId, pushed);
      _localEvents = kept;
      await _LocalAppStore.saveEvents(_localEvents);
    }
    if (kept.isNotEmpty) {
      log(
        level: DebugLogLevel.warning,
        source: 'Portal.Sync.Events/push',
        message: 'Planner events not moved: Portal.Sync.Events/push \u2014 '
            '${kept.length} of ${kept.length + pushed.length} local events '
            "were not accepted by '${record.folderName}' ($firstCause); "
            'they stay in this browser and the push runs again at the next '
            'start.',
      );
    }
    return (pushed: pushed.length, failed: kept.length);
  }

  /// Appends [events] to the recovery list of [folderId], dropping a list
  /// older than 30 days or of another folder (7.1 step 3).
  Future<void> _recordPushedToFolder(
      String folderId, List<Map<String, dynamic>> events) async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now().toUtc();
    var previous = const <dynamic>[];
    try {
      final raw = jsonDecode(prefs.getString(_kPushedToFolderKey) ?? '{}');
      final at = DateTime.tryParse('${raw['pushed_at']}');
      if (raw['folder_id'] == folderId &&
          at != null &&
          now.difference(at).inDays < 30) {
        previous = raw['events'] as List<dynamic>? ?? const [];
      }
    } catch (_) {/* a damaged list is replaced */}
    await prefs.setString(
        _kPushedToFolderKey,
        jsonEncode({
          'folder_id': folderId,
          'pushed_at': now.toIso8601String(),
          'events': [...previous, ...events],
          'feeds': const <Object>[],
        }));
  }

  void _logBrowserDataMoved(String name, int drafts, int courses, int events) {
    final message = 'Browser data moved: Shared.LocalFolder/connect \u2014 '
        '$drafts drafts, $courses courses, and $events planner items from '
        "this browser are now in '$name'; this browser keeps recoverable "
        'copies for 30 days (drafts and courses in the local recycle bin, '
        'planner items in a recovery list).';
    log(
      level: DebugLogLevel.info,
      source: 'Shared.LocalFolder/connect',
      message: message,
    );
    if (drafts + courses + events > 0) showMessage(message);
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
      cloudApiBaseUrl:
          _localSettings['api_base_url']?.toString() ?? _defaultApiBaseUrl(),
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
      'Cloud notes not pulled: Portal.Sync.Notes/pull \u2014 this app uses '
      "the folder '${_folder?.folderName ?? ''}', which has no cloud copy; "
      'disconnect the folder and sign in to pull cloud notes.';

  /// `clearAppSpecificSessionFields`: a cloud logout clears the planner
  /// events as before; a Disconnect (still in folder mode while the
  /// session is cleared, 2.10 rule 4) drops every folder row from memory
  /// and puts this browser's own cached rows back, so the signed-out
  /// reload that follows cannot write a folder row to `local_cache` (2.7,
  /// 202-N9), as the planner's `_clearPlannerSessionFields` does.
  void _clearFolderSessionFields() {
    _plannerEvents = const [];
    if (!inFolderMode) return;
    List<Map<String, dynamic>> cached(String key) =>
        (_localCache[key] as List<dynamic>? ?? const [])
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList(growable: false);
    _frontPage = Map<String, dynamic>.from(
        _localCache['front_page'] as Map? ?? const {});
    _courses = cached('courses').map(decorateRemoteCourse).toList();
    _activity = cached('activity');
    _activityWeek = null;
    _calendarFeeds = const [];
    _courseNotes = const [];
    _learnerNotes = const [];
    _selectedNote = null;
    _selectedCourse = null;
  }
}
