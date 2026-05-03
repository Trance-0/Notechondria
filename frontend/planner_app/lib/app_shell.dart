part of notechondria_frontend;

/// Root application widget that configures theme state and launches the shell.
class NotechondriaApp extends StatefulWidget {
  const NotechondriaApp({
    super.key,
    this.client,
    this.initialIndex = 0,
    this.title = 'Notechondria',
    this.visibleIndices = const <int>[0, 1, 2, 3, 4],
  });

  final NotechondriaClient? client;
  final int initialIndex;
  final String title;
  final List<int> visibleIndices;

  @override
  State<NotechondriaApp> createState() => _NotechondriaAppState();
}

class _NotechondriaAppState extends State<NotechondriaApp> {
  String _themePreset = 'teal';
  ThemeMode _themeMode = ThemeMode.system;

  /// See editor_app/lib/app_shell.dart for the full write-up. Short
  /// version: constructing `HttpNotechondriaClient()` inline in
  /// `build()` makes every `setState` (e.g. theme change) replace the
  /// client with a fresh one at the compile-time default URL, wiping
  /// the `_loadLocalState.updateBaseUrl(...)` that had pointed it at
  /// the user's saved API URL. Cache once here instead.
  late final NotechondriaClient _client =
      widget.client ?? HttpNotechondriaClient();

  void _handleThemeChanged(String preset, String mode) {
    setState(() {
      _themePreset = preset;
      _themeMode = _themeModeFromSetting(mode);
    });
  }

  @override
  Widget build(BuildContext context) {
    final seedColor = _themeSeed(_themePreset);
    return MaterialApp(
      title: widget.title,
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: seedColor,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFFAF8F1),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: seedColor,
          brightness: Brightness.dark,
        ),
      ),
      home: AppShell(
        client: _client,
        onThemeChanged: _handleThemeChanged,
        initialIndex: widget.initialIndex,
        appTitle: widget.title,
        visibleIndices: widget.visibleIndices,
      ),
    );
  }
}

/// Main application shell that owns loading, navigation, and shared app state.
class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.client,
    this.onThemeChanged,
    this.initialIndex = 0,
    this.appTitle = 'Notechondria',
    this.visibleIndices = const <int>[0, 1, 2, 3, 4],
  });

  final NotechondriaClient client;
  final void Function(String preset, String mode)? onThemeChanged;
  final int initialIndex;
  final String appTitle;
  final List<int> visibleIndices;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell>
    with
        AppShellLogMixin<AppShell>,
        AppShellLocalPersistMixin<AppShell>,
        AppShellCourseHelpersMixin<AppShell>,
        AppShellDraftHelpersMixin<AppShell>,
        AppShellAuthActionsMixin<AppShell>,
        AppShellOAuthMixin<AppShell>,
        AppShellSessionMixin<AppShell> {
  @override
  final List<String> uiLogs = <String>[];
  @override
  final DebugLogController logController = DebugLogController();
  @override
  AuthClient get authClient => widget.client;
  @override
  String get logAppTag => 'Planner';
  @override
  String? get token => _token;
  @override
  ValueNotifier<String> get splashStatus => _splashStatus;
  // AppShellLocalPersistMixin wiring.
  @override
  Map<String, dynamic> get localSettings => _localSettings;
  @override
  List<Map<String, dynamic>> get localDrafts => _localDrafts;
  @override
  List<Map<String, dynamic>> get localCourses => _localCourses;
  @override
  Map<String, dynamic> get localStats => _localStats;
  @override
  List<String> get persistedUiLogs => uiLogs;
  @override
  Future<void> saveLocalSettings(Map<String, dynamic> v) =>
      _LocalAppStore.saveSettings(v);
  @override
  Future<void> saveLocalDrafts(List<Map<String, dynamic>> v) =>
      _LocalAppStore.saveDrafts(v);
  @override
  Future<void> saveLocalCourses(List<Map<String, dynamic>> v) =>
      _LocalAppStore.saveCourses(v);
  @override
  Future<void> saveLocalStats(Map<String, dynamic> v) =>
      _LocalAppStore.saveStats(v);
  @override
  Future<void> saveLocalLogs(List<String> v) => _LocalAppStore.saveLogs(v);
  // AppShellCourseHelpersMixin wiring (localCourses already provided
  // above for AppShellLocalPersistMixin).
  @override
  String? get currentUsername => _profile?['username']?.toString();
  // AppShellDraftHelpersMixin wiring.
  @override
  set localDrafts(List<Map<String, dynamic>> value) => _localDrafts = value;
  @override
  set localStats(Map<String, dynamic> value) => _localStats = value;
  @override
  Map<String, dynamic> decodeNoteMetadata(String raw) =>
      _decodeNoteMetadata(raw);
  @override
  Map<String, dynamic> buildLocalDraft({
    required String title,
    required String content,
    String description = '',
    String editorMode = 'P',
    String? clientDraftId,
    String? createdAt,
    int? id,
    String metadataJson = '{}',
  }) =>
      _buildLocalDraft(
        title: title,
        content: content,
        description: description,
        editorMode: editorMode,
        clientDraftId: clientDraftId,
        createdAt: createdAt,
        id: id,
        metadataJson: metadataJson,
      );
  // AppShellSessionMixin wiring. Planner has no multi-device UI
  // and doesn't persist the session client-side, so the metadata
  // and persistSession hooks fall through to the mixin defaults.
  // The one per-app override is `clearAppSpecificSessionFields`,
  // which resets `_plannerEvents` on logout.
  @override
  set token(String? value) => _token = value;
  @override
  Map<String, dynamic>? get profile => _profile;
  @override
  set profile(Map<String, dynamic>? value) => _profile = value;
  @override
  Map<String, dynamic>? get settings => _settings;
  @override
  set settings(Map<String, dynamic>? value) => _settings = value;
  @override
  List<Map<String, dynamic>> get deletedNotes => _deletedNotes;
  @override
  set deletedNotes(List<Map<String, dynamic>> value) => _deletedNotes = value;
  @override
  Map<String, dynamic> currentAppSettingsPayload({
    String? themePreset,
    String? themeMode,
    String? apiBaseUrl,
  }) =>
      _currentAppSettingsPayload(
        themePreset: themePreset,
        themeMode: themeMode,
        apiBaseUrl: apiBaseUrl,
      );
  @override
  Future<void> applyLocalAppSettings(
    Map<String, dynamic> settings, {
    bool persist = true,
  }) =>
      _applyLocalAppSettings(settings, persist: persist);
  @override
  Future<void> loadInitialData() => _loadInitialData();
  @override
  Future<void> syncAllLocalCourses() => _syncAllLocalCourses();
  @override
  Future<void> syncAllLocalDrafts() => _syncAllLocalDrafts();
  @override
  void clearAppSpecificSessionFields() {
    _plannerEvents = const [];
  }

  @override
  void applySessionMetadata(Map<String, dynamic> payload) {
    final sessionMap = payload['session'] as Map?;
    _currentSessionId = (sessionMap?['id'] as num?)?.toInt();
    _multiDevice = payload['multi_device'] == true;
    _otherSessionsCount =
        (payload['other_sessions_count'] as num?)?.toInt() ?? 0;
  }

  @override
  void clearSessionMetadata() {
    _currentSessionId = null;
    _multiDevice = false;
    _otherSessionsCount = 0;
  }

  int _selectedIndex = 0;
  bool _isLoading = true;
  bool _showSplash = true;
  String? _errorMessage;
  String? _token;
  Map<String, dynamic>? _profile;
  Map<String, dynamic>? _settings;
  // True once /auth/casdoor/config/ has confirmed CASDOOR_* env vars
  // are set on the backend. Probed once on _loadInitialData; drives
  // whether `_SettingsPage`'s AuthHub renders the Casdoor SSO button.
  bool _casdoorConfigured = false;
  List<Map<String, dynamic>> _courses = const [];
  List<Map<String, dynamic>> _localCourses = const [];
  List<Map<String, dynamic>> _courseNotes = const [];
  List<Map<String, dynamic>> _learnerNotes = const [];
  List<Map<String, dynamic>> _localDrafts = const [];
  List<Map<String, dynamic>> _deletedNotes = const [];
  // Client-side recycle bin: drafts / courses moved here after a
  // successful cloud sync so the user can restore. See editor_app
  // for the rationale + auto-prune policy.
  List<Map<String, dynamic>> _localTrashedDrafts = const [];
  List<Map<String, dynamic>> _localTrashedCourses = const [];
  List<Map<String, dynamic>> _activity = const [];
  List<Map<String, dynamic>> _plannerEvents = const [];
  List<Map<String, dynamic>> _calendarFeeds = const [];
  Map<String, dynamic>? _activityWeek;
  Map<String, dynamic>? _selectedCourse;
  Map<String, dynamic>? _selectedNote;
  // Session metadata from /auth/session/ — drives the Active Sessions
  // card in Settings. Not persisted; refreshed on every cold boot.
  int? _currentSessionId;
  bool _multiDevice = false;
  int _otherSessionsCount = 0;
  Map<String, dynamic> _localSettings = _LocalAppStore.defaultSettings();
  Map<String, dynamic> _localStats = _LocalAppStore.defaultStats();
  Map<String, dynamic> _localCache = _LocalAppStore.defaultCache();
  DateTime _activityWeekStart = _dateOnly(DateTime.now());
  bool _hasMoreLearnerNotes = true;
  bool _isLoadingMoreNotes = false;
  bool _coursePanelExpanded = true;
  int _learnerNotesOffset = 0;
  Timer? _splashTimer;
  final ValueNotifier<String> _splashStatus =
      ValueNotifier<String>('Starting planner');
  String _learnerSearchQuery = '';

  HttpNotechondriaClient? get _httpClient =>
      widget.client is HttpNotechondriaClient
          ? widget.client as HttpNotechondriaClient
          : null;

  static const List<String> _titles = [
    'Learner View',
    'Course View',
    'Activity View',
    'Settings',
  ];

  static const List<NavigationDestination> _destinations = [
    NavigationDestination(
        icon: Icon(Icons.menu_book_outlined), label: 'Learner'),
    NavigationDestination(icon: Icon(Icons.school_outlined), label: 'Course'),
    NavigationDestination(
        icon: Icon(Icons.timeline_outlined), label: 'Activity'),
    NavigationDestination(
        icon: Icon(Icons.settings_outlined), label: 'Settings'),
  ];

  List<int> get _visibleIndices {
    final visible = widget.visibleIndices
        .where((index) => index >= 0 && index < _titles.length)
        .toList(growable: false);
    return visible.isEmpty ? List<int>.generate(_titles.length, (i) => i) : visible;
  }

  int get _selectedNavIndex {
    final idx = _visibleIndices.indexOf(_selectedIndex);
    return idx >= 0 ? idx : 0;
  }

  void _selectActualIndex(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  void _handleVisibleDestinationSelected(int visibleIndex) {
    final actual = _visibleIndices[visibleIndex];
    _selectActualIndex(actual);
  }

  bool _showWidePageHeader(int index) => index == 3;

  bool _showCompactPageHeader(int index) => index != 2;

  @override
  void initState() {
    super.initState();
    final clamped = widget.initialIndex.clamp(0, _titles.length - 1);
    _selectedIndex = _visibleIndices.contains(clamped) ? clamped : _visibleIndices.first;
    // Route the HTTP client's per-request DEBUG logs into the shared
    // DebugLogController so every request/response pair is visible in
    // the Debug log card.
    _httpClient?.setLogger((level, source, message) {
      if (!mounted) return;
      log(level: level, source: source, message: message);
    });
    _bootstrapApp();
  }

  Future<void> _bootstrapApp() async {
    _splashTimer = Timer(const Duration(seconds: 10), () {
      if (mounted) setState(() { _isLoading = false; _showSplash = false; });
    });
    _splashStatus.value = 'Loading local planner data';
    await _loadLocalState();
    _splashStatus.value = 'Completing sign-in';
    await handleOAuthCallback();
    _splashStatus.value = 'Connecting to server';
    await _loadInitialData();
  }

  // ---------------------------------------------------------------------------
  // OAuth helpers
  // ---------------------------------------------------------------------------

  @override
  void dispose() {
    _splashTimer?.cancel();
    _splashStatus.dispose();
    logController.dispose();
    super.dispose();
  }


  // `_snapshotLocalStore` lives in `core/snapshot.dart`.

  // `_loadLocalState` lives in `core/load_local_state.dart`.

  // `_persistLocal*` helpers live in `core/local_persist.dart`.


  // Planner builders live in `core/planner_builders.dart`.

  // Starter workspace lives in `core/local_starter.dart`.

  // Course helpers live in `core/course_helpers.dart`.

  List<Map<String, dynamic>> _localNotesForCourse(Map<String, dynamic> course) {
    final localId = (course['id'] as num?)?.toInt();
    final syncedId = (course['synced_course_id'] as num?)?.toInt();
    return _localDrafts.where((draft) {
      final metadata =
          _decodeNoteMetadata(draft['metadata_json']?.toString() ?? '{}');
      final courseId = (metadata['course_id'] as num?)?.toInt() ??
          (draft['course_id'] as num?)?.toInt();
      return courseId == localId || (syncedId != null && courseId == syncedId);
    }).map((item) => Map<String, dynamic>.from(item)).toList(growable: false);
  }

  // `_loadInitialData` lives in `core/initial_data.dart`.

  // Draft helpers live in `core/draft_helpers.dart`.



  // Note loading lives in `core/note_loading.dart`.

  // Settings helpers live in `core/settings_helpers.dart`.

  // applyAuthPayload + logout moved into the shared
  // AppShellSessionMixin (notechondria_shared 0.1.82). Per-app
  // wiring (clearAppSpecificSessionFields resets _plannerEvents)
  // is at the top of this class. _parseUpdatedAt was inlined into
  // the mixin too — same body in all three apps.

  // Settings comparers live in `core/settings_comparers.dart`.

  // Draft sync lives in `core/draft_sync.dart`.

  // Settings actions live in `core/settings_actions.dart`.

  // Local course/draft builders live in `core/local_course_builders.dart`.

  // Note CRUD lives in `core/note_crud.dart`.

  // Calendar actions live in `core/calendar.dart`.

  // Note-session tracking lives in `core/note_sessions.dart`.

  // Maintenance actions live in `core/maintenance_actions.dart`.

  @override
  Widget build(BuildContext context) {
    final scaffold = LayoutBuilder(
      builder: (context, constraints) {
        final isWideLayout = constraints.maxWidth >= 960;
        if (isWideLayout) {
          return _buildWideScaffold(context);
        }
        return _buildCompactScaffold();
      },
    );
    if (_showSplash) {
      return Stack(
        children: [
          scaffold,
          Positioned.fill(
            child: SplashScreen(
              appTitle: widget.appTitle,
              appVersion: _kAppVersion,
              loadingStatus: _splashStatus,
              apiBaseUrl: _localSettings['api_base_url']?.toString(),
              onFinished: () {
                setState(() { _showSplash = false; if (_isLoading) _isLoading = false; });
              },
            ),
          ),
        ],
      );
    }
    return scaffold;
  }

  Widget _buildCompactScaffold() {
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        title: _showCompactPageHeader(_selectedIndex)
            ? Text(_titles[_selectedIndex])
            : null,
        backgroundColor: Colors.transparent,
      ),
      body: _buildBody(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedNavIndex,
        onDestinationSelected: _handleVisibleDestinationSelected,
        destinations: _visibleIndices.map((index) => _destinations[index]).toList(growable: false),
      ),
    );
  }

  Widget _buildWideScaffold(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final subscribedCourses =
        _courses.where((course) => course['is_subscribed'] == true).toList();
    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            Container(
              width: 240,
              decoration: BoxDecoration(
                color: colorScheme.surface,
                border: Border(
                  right: BorderSide(color: colorScheme.outlineVariant),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.appTitle,
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Wide layout',
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Column(
                        children: [
                          // Non-settings entries only; Settings is pinned to
                          // the bottom of the sidebar below. Planner_app has
                          // only 4 modules (0=Learner, 1=Course, 2=Activity,
                          // 3=Settings).
                          for (final index in _visibleIndices.where((index) => index != 3))
                            SidebarItem(
                              icon: (_destinations[index].icon as Icon).icon!,
                              label: _titles[index],
                              selected: _selectedIndex == index,
                              onTap: () => _selectActualIndex(index),
                            ),
                          if (subscribedCourses.isNotEmpty && _visibleIndices.contains(1)) ...[
                            const SizedBox(height: 12),
                            Flexible(
                              child: _WideCourseSidebarSection(
                                expanded: _coursePanelExpanded,
                                courses: subscribedCourses,
                                selectedCourseId:
                                    (_selectedCourse?['id'] as num?)?.toInt(),
                                onToggleExpanded: () {
                                  setState(() {
                                    _coursePanelExpanded = !_coursePanelExpanded;
                                  });
                                },
                                onSelectCourse: (course) {
                                  setState(() {
                                    _selectedIndex = 1;
                                  });
                                  _selectCourse(course);
                                },
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (_visibleIndices.contains(3))
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                      child: SidebarItem(
                        icon: Icons.settings_outlined,
                        label: 'Settings',
                        selected: _selectedIndex == 3,
                        onTap: () => _selectActualIndex(3),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_showWidePageHeader(_selectedIndex))
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                      child: Text(
                        _titles[_selectedIndex],
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ),
                  Expanded(child: _buildBody()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: SelectionArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
                  if (_isLoading)
                    const LinearProgressIndicator(minHeight: 2),
                  if (_errorMessage != null)
                    Material(
                      color: Theme.of(context).colorScheme.errorContainer,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.cloud_off_outlined,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onErrorContainer,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: TextStyle(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onErrorContainer,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: _loadInitialData,
                              child: const Text('Retry'),
                            ),
                            IconButton(
                              onPressed: () {
                                setState(() {
                                  _errorMessage = null;
                                });
                              },
                              icon: const Icon(Icons.close),
                              tooltip: 'Dismiss',
                            ),
                          ],
                        ),
                      ),
                    ),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      switchInCurve: Curves.easeOut,
                      switchOutCurve: Curves.easeIn,
                      transitionBuilder: (child, animation) {
                        return FadeTransition(
                          opacity: animation,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0.03, 0),
                              end: Offset.zero,
                            ).animate(animation),
                            child: child,
                          ),
                        );
                      },
                      child: KeyedSubtree(
                        key: ValueKey<int>(_selectedIndex),
                        child: _buildPage(),
                      ),
                    ),
                  ),
          ],
        ),
      ),
    );
  }

  void _handleDestinationSelected(int index) {
    _selectActualIndex(index);
  }

  Widget _buildPage() {
    switch (_selectedIndex) {
      case 0:
        return _LearnerPage(
          notes: _learnerNotes,
          localDrafts: _localDrafts,
          courses: (_token == null || _token!.isEmpty)
              ? [..._localCourses]
              : [..._localCourses, ..._courses],
          selectedNote: _selectedNote,
          editorMode: _settings?['editor_mode']?.toString() ?? 'P',
          hasMoreNotes: _hasMoreLearnerNotes,
          isLoadingMore: _isLoadingMoreNotes,
          searchQuery: _learnerSearchQuery,
          isAuthenticated: _token != null && _token!.isNotEmpty,
          apiBaseUrl: _localSettings['api_base_url']?.toString() ??
              _httpClient?.baseUrl,
          onSearchChanged: (value) =>
              _loadLearnerNotes(reset: true, query: value),
          onLoadMore: () => _loadLearnerNotes(),
          onOpenNote: _selectNote,
          onFetchNoteDetail: _fetchNoteDetail,
          onCreateNote: _createNote,
          onImportMarkdown: _importMarkdownNote,
          onExportNote: _exportNote,
          onSaveNote: _saveNote,
          onGetNoteHistory: _getNoteHistory,
          onSnapshotNote: _snapshotNote,
          onRestoreNoteVersion: _restoreNoteVersion,
          onStartNoteSession: _startNoteSession,
          onFinishNoteSession: _finishNoteSession,
          onDeleteNote: _deleteNoteToRecycleBin,
          onSyncLocalDraft: _syncLocalDraft,
          onSyncAllLocalDrafts: _syncAllLocalDrafts,
          onLogEvent: appendUiLog,
          onUploadCover: _token != null
              ? (noteId, file) =>
                  widget.client.uploadNoteCoverImage(_token!, noteId, file)
              : null,
          onDeleteCover: _token != null
              ? (noteId) =>
                  widget.client.deleteNoteCoverImage(_token!, noteId)
              : null,
          offlineMode: _localSettings['offline_mode'] == true,
          onLoadPublicNotes: () => _loadLearnerNotes(),
        );
      case 1:
        return _CoursePage(
          courses: _courses,
          localCourses: _localCourses,
          selectedCourse: _selectedCourse,
          notes: _courseNotes,
          localNotes: _localDrafts,
          isAuthenticated: _token != null && _token!.isNotEmpty,
          canCreateLocalCourses: true,
          apiBaseUrl: _localSettings['api_base_url']?.toString() ??
              _httpClient?.baseUrl,
          onCourseChanged: _selectCourse,
          onCreateLocalCourse: _createLocalCourse,
          onSyncLocalData: _syncAllLocalData,
          onSubscribe: _subscribeToCourse,
          onUnsubscribe: _unsubscribeFromCourse,
          onFetchNoteDetail: _fetchNoteDetail,
        );
      case 2:
        return _ActivityPage(
          activityWeek: _activityWeek,
          isAuthenticated: _token != null && _token!.isNotEmpty,
          plannerEvents: _plannerEvents,
          onCreatePlannerEvent: _createPlannerEvent,
          onImportCalendar: _importCalendarFeed,
          onSubscribeCalendar: _subscribeCalendarFeed,
          onNavigateWeek: (direction) => _loadActivityWeek(
            startDate: _activityWeekStart.add(Duration(days: direction * 7)),
          ),
          onShiftStartDay: (dayDelta) => _loadActivityWeek(
            startDate: _activityWeekStart.add(Duration(days: dayDelta)),
          ),
          onTogglePlannerEventCompletion: _togglePlannerEventCompletion,
        );
      case 3:
        return _SettingsPage(
          profile: _profile,
          settings: _settings,
          localSettings: _localSettings,
          localStats: _localStats,
          deletedNotes: _deletedNotes,
          onSave: _updateSettings,
          onLogout: logout,
          onRegister: register,
          onValidateInvitation: (code) => widget.client.validateInvitation(code),
          onVerify: verify,
          onResendVerification: resendVerification,
          onLogin: login,
          onRequestPasswordReset: requestPasswordReset,
          onConfirmPasswordReset: confirmPasswordReset,
          onGoogleLogin: (invitationCode) => launchOAuth('google', invitationCode: invitationCode),
          onGithubLogin: (invitationCode) => launchOAuth('github', invitationCode: invitationCode),
          onGoogleLoginOnly: () => launchOAuth('google', intent: 'login'),
          onGithubLoginOnly: () => launchOAuth('github', intent: 'login'),
          onCasdoorLogin: _casdoorConfigured
              ? () => launchOAuth('casdoor', intent: 'login')
              : null,
          onBindCasdoor: (_casdoorConfigured && _token != null)
              ? () => launchOAuth('casdoor', intent: 'bind')
              : null,
          onUnlinkCasdoor: (_casdoorConfigured && _token != null)
              ? () async {
                  try {
                    await widget.client.casdoorUnlink(_token!);
                    if (mounted) {
                      _settings = {
                        ..._settings ?? <String, dynamic>{},
                        'casdoor_linked': false,
                      };
                      refreshState();
                    }
                  } catch (_) {/* swallowed; UI stays stale */}
                }
              : null,
          onBindGoogle: () => launchOAuth('google', intent: 'bind'),
          onBindGithub: () => launchOAuth('github', intent: 'bind'),
          onListSocialAccounts: _token != null ? () => widget.client.listSocialAccounts(_token!) : null,
          onUnlinkSocialAccount: _token != null ? (provider) => widget.client.unlinkSocialAccount(_token!, provider) : null,
          onRestoreDeletedNote: _restoreDeletedNote,
          onEmptyDeletedNotes: _emptyDeletedNotes,
          onCopyLogs: _copyFrontendLogs,
          onUploadAvatar: _uploadAvatar,
          onSyncLocalData: _syncAllLocalData,
          onPullCloudData: _pullCloudNotesToLocal,
          onClearLocalCache: _clearLocalCache,
          onClearLocalData: _clearLocalData,
          onRestoreTemplateCourses: _restoreTemplateCourses,
          onOpenLocalRecycleBin: _openLocalRecycleBinDialog,
          localTrashedDraftCount: _localTrashedDrafts.length,
          localTrashedCourseCount: _localTrashedCourses.length,
          onOfflineModeChanged: _setOfflineMode,
          localDraftCount: _localDrafts.length,
          localCourseCount: _localCourses.length,
          apiBaseUrl: _localSettings['api_base_url']?.toString() ??
              _httpClient?.baseUrl,
          debugSnapshotListenable: _httpClient?.debugSnapshot,
          debugHistoryListenable: _httpClient?.debugHistory,
          debugLogController: logController,
          uiLogs: uiLogs,
          onListSessions: _token != null
              ? () => widget.client.listSessions(_token!)
              : null,
          onRevokeSession: _token != null
              ? (sessionId) => widget.client.revokeSession(_token!, sessionId)
              : null,
          onCurrentSessionRevoked: () {
            _token = null;
            _profile = null;
            _settings = null;
            _deletedNotes = const [];
            _currentSessionId = null;
            _multiDevice = false;
            _otherSessionsCount = 0;
            refreshState();
            unawaited(_loadInitialData());
          },
          onExportLocalData: _exportLocalArchive,
          onRestoreFromLocalImport: _restoreFromLocalImport,
          onSaveMcpSkill: _token != null
              ? (skillMd) async {
                  try {
                    final result = await widget.client.updateSettings(
                      _token!,
                      {'mcp_skill_md': skillMd},
                    );
                    if (mounted) {
                      _settings = {
                        ..._settings ?? <String, dynamic>{},
                        'mcp_skill_md':
                            result['mcp_skill_md']?.toString() ?? skillMd,
                      };
                      refreshState();
                    }
                    return const ActionFeedback(
                      message: 'Agent skill saved.',
                    );
                  } catch (e) {
                    final msg =
                        e.toString().replaceFirst('Exception: ', '');
                    return ActionFeedback(
                      message:
                          'Agent skill not saved: '
                          'Planner.Settings/skill.save — $msg.',
                      isError: true,
                    );
                  }
                }
              : null,
          githubSyncCardBuilder: _token != null
              ? () => GithubSyncExperimentalCard(
                    onLoadStatus: () =>
                        widget.client.githubSyncStatus(_token!),
                    onListRepos: () =>
                        widget.client.githubSyncRepos(_token!),
                    onConnect: ({
                      required String installationId,
                      String? accountLogin,
                      String? repoFullName,
                      String? repoDefaultBranch,
                    }) =>
                        widget.client.githubSyncCallback(_token!, {
                      'installation_id': installationId,
                      if (accountLogin != null && accountLogin.isNotEmpty)
                        'account_login': accountLogin,
                      if (repoFullName != null && repoFullName.isNotEmpty)
                        'repo_full_name': repoFullName,
                      if (repoDefaultBranch != null &&
                          repoDefaultBranch.isNotEmpty)
                        'repo_default_branch': repoDefaultBranch,
                    }),
                    onPushNow: ({bool includeAssets = false}) =>
                        widget.client.githubSyncPush(
                      _token!,
                      includeAssets: includeAssets,
                    ),
                    onDisconnect: () =>
                        widget.client.githubSyncDisconnect(_token!),
                  )
              : null,
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

class _WideCourseSidebarSection extends StatelessWidget {
  const _WideCourseSidebarSection({
    required this.expanded,
    required this.courses,
    required this.selectedCourseId,
    required this.onToggleExpanded,
    required this.onSelectCourse,
  });

  final bool expanded;
  final List<Map<String, dynamic>> courses;
  final int? selectedCourseId;
  final VoidCallback onToggleExpanded;
  final ValueChanged<Map<String, dynamic>> onSelectCourse;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: colorScheme.surfaceVariant.withOpacity(0.35),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: onToggleExpanded,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Courses',
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Icon(expanded ? Icons.expand_less : Icons.expand_more),
                ],
              ),
            ),
          ),
          if (expanded)
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                children: [
                  for (final course in courses)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: InkWell(
                        onTap: () => onSelectCourse(course),
                        borderRadius: BorderRadius.circular(12),
                        child: Ink(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            color: selectedCourseId == course['id']
                                ? colorScheme.primaryContainer
                                : Colors.transparent,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                course['title']?.toString() ?? 'Course',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: selectedCourseId == course['id']
                                          ? colorScheme.onPrimaryContainer
                                          : null,
                                    ),
                              ),
                              if ((course['last_opened_at']?.toString() ?? '')
                                  .isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  'Opened ${formatCompactTimestamp(course['last_opened_at'].toString())}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: selectedCourseId == course['id']
                                            ? colorScheme.onPrimaryContainer
                                            : colorScheme.onSurfaceVariant,
                                      ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
