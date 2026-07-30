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

  /// Resolved app locale. `null` follows the device locale (the
  /// `system` setting); a non-null value is the user's explicit
  /// Language choice. Driven from `_localSettings['locale']` via
  /// `onLocaleChanged`, mirroring the theme plumbing.
  Locale? _locale;

  /// See editor_app/lib/app_shell.dart for the full write-up. Short
  /// version: constructing `HttpNotechondriaClient()` inline in
  /// `build()` made every `setState` (e.g. theme change) replace the
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

  void _handleLocaleChanged(String locale) {
    setState(() {
      _locale = resolveLocale(locale);
    });
  }

  @override
  Widget build(BuildContext context) {
    final seedColor = _themeSeed(_themePreset);
    return MaterialApp(
      title: widget.title,
      onGenerateTitle: (context) => AppLocalizations.of(context).appNamePortal,
      debugShowCheckedModeBanner: false,
      // Shared widgets localize via AppLocalizations. `_locale` is the
      // user's Language choice (null = follow device).
      locale: _locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
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
      // 0.1.179: real URL routing (no more single-root-route app). Every
      // surface has a unique, shareable address under the web hash
      // strategy: `#/` front, `#/notes`, `#/courses[/<slug>]`,
      // `#/activity`, `#/settings`, and `#/note/<uuid>` for a routed
      // note page (public notes anonymously; owned/subscribed with auth).
      onGenerateRoute: _generateRoute,
      onGenerateInitialRoutes: _generateInitialRoutes,
    );
  }

  AppShell _buildShell(
      {int initialIndex = 0,
      String? initialCourseSlug,
      String? initialModuleKey}) {
    return AppShell(
      client: _client,
      onThemeChanged: _handleThemeChanged,
      onLocaleChanged: _handleLocaleChanged,
      initialIndex: initialIndex,
      initialCourseSlug: initialCourseSlug,
      initialModuleKey: initialModuleKey,
      appTitle: widget.title,
      visibleIndices: widget.visibleIndices,
    );
  }

  Route<dynamic> _generateRoute(RouteSettings settings) {
    final name = settings.name ?? '/';
    final segments = Uri.parse(name)
        .pathSegments
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
    // `/note/<uuid>` — the routed note page, pushed on top of the shell.
    if (segments.length == 2 && segments.first == 'note') {
      final args = settings.arguments is Map
          ? Map<String, dynamic>.from(settings.arguments as Map)
          : const <String, dynamic>{};
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => _NoteRoutePage(
          client: _client,
          noteUuid: segments[1],
          token: args['token']?.toString(),
          preloaded: args['note'] is Map
              ? Map<String, dynamic>.from(args['note'] as Map)
              : null,
        ),
      );
    }
    // Tab / course-detail routes resolve to the shell.
    var tab = widget.initialIndex;
    String? courseSlug;
    String? moduleKey;
    if (segments.isNotEmpty) {
      switch (segments.first) {
        case 'notes':
          tab = 1;
          break;
        case 'courses':
          tab = 2;
          if (segments.length >= 2) {
            courseSlug = segments[1];
          }
          if (segments.length >= 4 && segments[2] == 'm') {
            moduleKey = segments[3];
          }
          break;
        case 'activity':
          tab = 3;
          break;
        case 'settings':
          tab = 4;
          break;
        default:
          tab = 0;
      }
    }
    return MaterialPageRoute<void>(
      settings: settings,
      builder: (_) => _buildShell(
          initialIndex: tab,
          initialCourseSlug: courseSlug,
          initialModuleKey: moduleKey),
    );
  }

  List<Route<dynamic>> _generateInitialRoutes(String initialRoute) {
    final segments = Uri.parse(initialRoute)
        .pathSegments
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
    if (segments.length == 2 && segments.first == 'note') {
      // Cold-start note deep link: put the shell underneath so Back (and
      // the viewer's close button) lands inside the app, not on a blank
      // page.
      return <Route<dynamic>>[
        _generateRoute(const RouteSettings(name: '/')),
        _generateRoute(RouteSettings(name: initialRoute)),
      ];
    }
    return <Route<dynamic>>[_generateRoute(RouteSettings(name: initialRoute))];
  }
}

/// Main application shell that owns loading, navigation, and shared app state.
class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.client,
    this.onThemeChanged,
    this.onLocaleChanged,
    this.initialIndex = 0,
    this.initialCourseSlug,
    this.initialModuleKey,
    this.appTitle = 'Notechondria',
    this.visibleIndices = const <int>[0, 1, 2, 3, 4],
  });

  final NotechondriaClient client;
  final void Function(String preset, String mode)? onThemeChanged;

  /// Called with the persisted `app_settings['locale']` value so the
  /// root `MaterialApp` can rebuild with the chosen locale.
  final void Function(String locale)? onLocaleChanged;
  final int initialIndex;

  /// Deep-link target from a `#/courses/<slug>` URL: after boot, the shell
  /// opens this course on the Course tab (best-effort — unknown slugs just
  /// land on the course list).
  final String? initialCourseSlug;

  /// Optional module deep link (`#/courses/<slug>/m/<key>`): once the
  /// course's notes load, the matching module opens.
  final String? initialModuleKey;
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
  String get logAppTag => 'Portal';
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
  // AppShellSessionMixin wiring. 0.1.182: the portal now persists the
  // session like the editor — previously every page reload signed the
  // user out (token was memory-only), which surfaced as "logged in but
  // no login info shown / no subscribed courses / no course filter".
  @override
  Future<void> persistSession(String token, Map<String, dynamic> user) =>
      _LocalAppStore.saveSession(token, user);
  @override
  Future<void> clearPersistedSession() => _LocalAppStore.clearSession();
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

  // Session metadata hooks default to no-ops post-Casdoor cutover —
  // session lifecycle lives on the Casdoor side now.

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

  /// Casdoor org-login URL derived from the `endpoint` + `organization`
  /// fields returned by `/api/v1/auth/casdoor/config/`. Threads through
  /// to `_SettingsPage` -> `AuthHub` so the signed-out card can render
  /// the "Login via third party" + "Sign up via Casdoor" CTAs.
  String? _casdoorOrgLoginUrl;
  Map<String, dynamic>? _frontPage;
  List<Map<String, dynamic>> _courses = const [];
  List<Map<String, dynamic>> _localCourses = const [];
  List<Map<String, dynamic>> _courseNotes = const [];
  // Lazy course-notes paging (0.1.185): first page loads with the course,
  // further pages stream in on scroll. `_courseNotesLoading` gates the
  // course view behind a progress bar so stale/placeholder content never
  // renders before real data.
  bool _courseNotesLoading = false;
  bool _courseNotesHasMore = false;
  int _courseNotesOffset = 0;
  bool _courseNotesLoadingMore = false;
  List<Map<String, dynamic>> _learnerNotes = const [];
  List<Map<String, dynamic>> _localDrafts = const [];
  List<Map<String, dynamic>> _deletedNotes = const [];
  // Client-side recycle bin; see editor_app for the contract.
  List<Map<String, dynamic>> _localTrashedDrafts = const [];
  List<Map<String, dynamic>> _localTrashedCourses = const [];
  List<Map<String, dynamic>> _activity = const [];
  List<Map<String, dynamic>> _plannerEvents = const [];
  // Signed-out / offline planner events, persisted per device
  // (_LocalAppStore.saveEvents). Merged into the Activity calendar and
  // todo board next to cloud events; never auto-synced.
  List<Map<String, dynamic>> _localEvents = const [];
  List<Map<String, dynamic>> _calendarFeeds = const [];
  Map<String, dynamic>? _activityWeek;
  Map<String, dynamic>? _selectedCourse;
  Map<String, dynamic>? _selectedNote;
  Map<String, dynamic> _localSettings = _LocalAppStore.defaultSettings();
  Map<String, dynamic> _localStats = _LocalAppStore.defaultStats();
  Map<String, dynamic> _localCache = _LocalAppStore.defaultCache();
  DateTime _activityWeekStart = _dateOnly(DateTime.now());
  // Number of days the horizontal activity calendar pulls + renders. The
  // 3-day / 1-week / 1-month range selector swaps this; the backend clamps
  // it to {3, 7, 30}.
  int _activityRangeDays = 7;
  // Learner / public-notes feed filters. `_learnerScope` is one of
  // public | private | all (signed-in only; guests are forced to public);
  // `_learnerSort` is newest | oldest | popular; `_learnerWindow` is a
  // recency bound 3 | 7 | 30 | 365 | all.
  String _learnerScope = 'public';
  String _learnerSort = 'newest';
  String _learnerWindow = 'all';
  bool _hasMoreLearnerNotes = true;
  bool _isLoadingMoreNotes = false;
  bool _coursePanelExpanded = true;
  bool _whatsNewPromptShown = false;
  Timer? _splashTimer;
  final ValueNotifier<String> _splashStatus =
      ValueNotifier<String>('Starting portal');
  int _learnerNotesOffset = 0;
  String _learnerSearchQuery = '';

  HttpNotechondriaClient? get _httpClient =>
      widget.client is HttpNotechondriaClient
          ? widget.client as HttpNotechondriaClient
          : null;

  static const List<String> _titles = [
    'Front page',
    'Learner',
    'Course',
    'Activity',
    'Settings',
  ];

  static const List<NavigationDestination> _destinations = [
    NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Front page'),
    NavigationDestination(
        icon: Icon(Icons.menu_book_outlined), label: 'Learner'),
    NavigationDestination(icon: Icon(Icons.school_outlined), label: 'Course'),
    NavigationDestination(
        icon: Icon(Icons.timeline_outlined), label: 'Activity'),
    NavigationDestination(
        icon: Icon(Icons.settings_outlined), label: 'Settings'),
  ];

  // `_titles`/`_destinations` stay const for index math + icons; the
  // human-visible labels are resolved per-locale here so the nav rail and
  // bottom bar localize like the rest of the shell.
  String _navTitle(AppLocalizations l10n, int index) {
    switch (index) {
      case 0:
        return l10n.navFrontPage;
      case 1:
        return l10n.navLearner;
      case 2:
        return l10n.navCourse;
      case 3:
        return l10n.navActivity;
      case 4:
        return l10n.navSettings;
      default:
        return _titles[index];
    }
  }

  List<int> get _visibleIndices {
    final visible = widget.visibleIndices
        .where((index) => index >= 0 && index < _titles.length)
        .toList(growable: false);
    return visible.isEmpty
        ? List<int>.generate(_titles.length, (i) => i)
        : visible;
  }

  int get _selectedNavIndex {
    final idx = _visibleIndices.indexOf(_selectedIndex);
    return idx >= 0 ? idx : 0;
  }

  /// URL path for each tab index — keeps the address bar in sync with the
  /// active tab so every tab has a unique, shareable URL.
  static const List<String> _tabPaths = [
    '/',
    '/notes',
    '/courses',
    '/activity',
    '/settings',
  ];

  void _syncTabUrl() {
    final index = _selectedIndex.clamp(0, _tabPaths.length - 1);
    url_strategy.replaceBrowserPath(_tabPaths[index]);
  }

  void _selectActualIndex(int index) {
    setState(() {
      _selectedIndex = index;
    });
    _syncTabUrl();
  }

  void _handleVisibleDestinationSelected(int visibleIndex) {
    final actual = _visibleIndices[visibleIndex];
    _selectActualIndex(actual);
  }

  bool _showWidePageHeader(int index) => index == 4;

  bool _showCompactPageHeader(int index) => index != 3;

  @override
  void initState() {
    super.initState();
    final clamped = widget.initialIndex.clamp(0, _titles.length - 1);
    _selectedIndex =
        _visibleIndices.contains(clamped) ? clamped : _visibleIndices.first;
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
      if (mounted)
        setState(() {
          _isLoading = false;
          _showSplash = false;
        });
    });
    _splashStatus.value = 'Loading local state';
    await _loadLocalState();
    _splashStatus.value = 'Restoring session';
    await _restoreSession();
    _splashStatus.value = 'Completing sign-in';
    final freshSignIn = await handleOAuthCallback();
    _splashStatus.value = 'Connecting to server';
    await _loadInitialData();
    if (freshSignIn) {
      await _applyKeepOfflineChoice();
    }
    await _openInitialCourseDeepLink();
  }

  /// Honours the sign-in card's "keep offline data after login" choice
  /// right after a fresh OAuth sign-in (0.1.180). Kept (default): the
  /// cloud is pulled into the local cache in the background — every local
  /// save carries a `last_edit` timestamp, and when both sides changed
  /// the pull's conflict dialog prompts the user to pick which version to
  /// keep. Unchecked: local drafts are cleared so a shared machine never
  /// leaks the previous user's offline notes into this account.
  Future<void> _applyKeepOfflineChoice() async {
    final keep = _localSettings['keep_offline_data_on_login'] != false;
    if (!keep) {
      _localDrafts = [];
      await saveLocalDrafts(_localDrafts);
      refreshState();
      log(
        level: DebugLogLevel.info,
        source: 'Portal.Sync.Session/keep_offline',
        message: 'Local drafts cleared on sign-in: '
            'Portal.Sync.Session/keep_offline — '
            '"keep offline data" was unchecked.',
      );
      return;
    }
    // Background merge; failures only log (never block the session).
    unawaited(_pullCloudNotesToLocal().then((feedback) {
      log(
        level: feedback.isError ? DebugLogLevel.warning : DebugLogLevel.info,
        source: 'Portal.Sync.Session/keep_offline',
        message: 'Post-login cloud→local pull: '
            'Portal.Sync.Session/keep_offline — ${feedback.message}',
      );
    }));
  }

  /// Restores a persisted auth session if one exists (mirrors the
  /// editor). Validates the stored token against `/auth/session/`; a
  /// stale token clears the persisted session instead of restoring it.
  Future<void> _restoreSession() async {
    final session = await _LocalAppStore.loadSession();
    if (session == null) return;
    final token = session['token']?.toString() ?? '';
    if (token.isEmpty) return;
    try {
      final check = await widget.client.checkSession(token);
      if (check['authenticated'] == true) {
        await applyAuthPayload(check);
        return;
      }
    } catch (_) {
      // Token invalid or network down — fall through and clear.
    }
    await _LocalAppStore.clearSession();
  }

  /// Resolves a `#/courses/<slug>` cold-start deep link once the course
  /// list is loaded. Unknown slugs stay on the course-list tab.
  Future<void> _openInitialCourseDeepLink() async {
    final slug = widget.initialCourseSlug;
    if (slug == null || slug.isEmpty || !mounted) {
      return;
    }
    Map<String, dynamic>? match;
    for (final course in _courses) {
      if (course['slug']?.toString() == slug) {
        match = course;
        break;
      }
    }
    if (match != null) {
      await _selectCourse(match);
    }
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

  // Snapshot lives in `core/snapshot.dart`.

  // `_loadLocalState` lives in `core/load_local_state.dart`.

  // Persist helpers live in `core/local_persist.dart`.

  // Starter lives in `core/local_starter.dart`.

  // Course helpers live in `core/course_helpers.dart`.

  List<Map<String, dynamic>> _localNotesForCourse(Map<String, dynamic> course) {
    final localId = (course['id'] as num?)?.toInt();
    final syncedId = (course['synced_course_id'] as num?)?.toInt();
    return _localDrafts
        .where((draft) {
          final metadata =
              _decodeNoteMetadata(draft['metadata_json']?.toString() ?? '{}');
          final courseId = (metadata['course_id'] as num?)?.toInt() ??
              (draft['course_id'] as num?)?.toInt();
          return courseId == localId ||
              (syncedId != null && courseId == syncedId);
        })
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
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

  // Note-sessions live in `core/note_sessions.dart`.

  // Maintenance lives in `core/maintenance_actions.dart`.

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scaffold = LayoutBuilder(
      builder: (context, constraints) {
        final isWideLayout = constraints.maxWidth >= 960;
        if (isWideLayout) {
          return _buildWideScaffold(context);
        }
        return _buildCompactScaffold(context);
      },
    );
    if (_showSplash) {
      // A user-chosen startup image (Preferences → Startup image; local
      // upload or remote URL) replaces the default reactor splash. It
      // spans the screen with a fixed aspect ratio (BoxFit.cover).
      final splashLocal = _localSettings['splash_image_local']?.toString() ?? '';
      final splashUrl = _localSettings['splash_image_url']?.toString() ?? '';
      final useCustomSplash = splashLocal.isNotEmpty || splashUrl.isNotEmpty;
      return Stack(
        children: [
          scaffold,
          Positioned.fill(
            child: useCustomSplash
                ? _CustomSplashOverlay(
                    appTitle: l10n.appNamePortal,
                    appVersion: _kAppVersion,
                    localImageUrl: splashLocal,
                    remoteImageUrl: splashUrl,
                    loadingStatus: _splashStatus,
                    onFinished: () {
                      setState(() {
                        _showSplash = false;
                        if (_isLoading) _isLoading = false;
                      });
                    },
                  )
                : SplashScreen(
                    appTitle: l10n.appNamePortal,
                    appVersion: _kAppVersion,
                    loadingStatus: _splashStatus,
                    apiBaseUrl: _localSettings['api_base_url']?.toString(),
                    onFinished: () {
                      setState(() {
                        _showSplash = false;
                        if (_isLoading) _isLoading = false;
                      });
                    },
                  ),
          ),
        ],
      );
    }
    return scaffold;
  }

  Widget _buildCompactScaffold(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        title: _showCompactPageHeader(_selectedIndex)
            ? Text(_navTitle(l10n, _selectedIndex))
            : null,
        backgroundColor: Colors.transparent,
      ),
      body: _buildBody(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedNavIndex,
        onDestinationSelected: _handleVisibleDestinationSelected,
        destinations: _visibleIndices
            .map((index) => NavigationDestination(
                  icon: _destinations[index].icon,
                  label: _navTitle(l10n, index),
                ))
            .toList(growable: false),
      ),
    );
  }

  Widget _buildWideScaffold(BuildContext context) {
    final l10n = AppLocalizations.of(context);
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
                          l10n.appNamePortal,
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(
                                fontWeight: FontWeight.w800,
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
                          for (final index
                              in _visibleIndices.where((index) => index != 4))
                            SidebarItem(
                              icon: (_destinations[index].icon as Icon).icon!,
                              label: _navTitle(l10n, index),
                              selected: _selectedIndex == index,
                              onTap: () => _selectActualIndex(index),
                            ),
                          if (subscribedCourses.isNotEmpty &&
                              _visibleIndices.contains(2)) ...[
                            const SizedBox(height: 12),
                            Flexible(
                              child: _WideCourseSidebarSection(
                                expanded: _coursePanelExpanded,
                                courses: subscribedCourses,
                                selectedCourseId:
                                    (_selectedCourse?['id'] as num?)?.toInt(),
                                onToggleExpanded: () {
                                  setState(() {
                                    _coursePanelExpanded =
                                        !_coursePanelExpanded;
                                  });
                                },
                                onSelectCourse: (course) {
                                  setState(() {
                                    _selectedIndex = 2;
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
                  if (_visibleIndices.contains(4))
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                      child: SidebarItem(
                        icon: Icons.settings_outlined,
                        label: 'Settings',
                        selected: _selectedIndex == 4,
                        onTap: () => _selectActualIndex(4),
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
                        _navTitle(l10n, _selectedIndex),
                        style:
                            Theme.of(context).textTheme.headlineSmall?.copyWith(
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
            VersionUpdateBanner(
              frontendVersion: _kAppVersion,
              probe: _probeBackendVersion,
            ),
            if (_isLoading) const LinearProgressIndicator(minHeight: 2),
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
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          friendlyError(
                              AppLocalizations.of(context), _errorMessage!),
                          style: TextStyle(
                            color:
                                Theme.of(context).colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                      if (_localSettings['offline_mode'] != true)
                        TextButton(
                          onPressed: () => _setOfflineMode(true),
                          child: Text(
                              AppLocalizations.of(context).errorWorkOffline),
                        ),
                      TextButton(
                        onPressed: _loadInitialData,
                        child: Text(AppLocalizations.of(context).commonRetry),
                      ),
                      IconButton(
                        onPressed: () {
                          setState(() {
                            _errorMessage = null;
                          });
                        },
                        icon: const Icon(Icons.close),
                        tooltip: AppLocalizations.of(context).commonDismiss,
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
        return _FrontPage(
          frontPage: _frontPage ?? const {},
          profile: _profile,
          apiBaseUrl: _localSettings['api_base_url']?.toString() ??
              _httpClient?.baseUrl,
          onOpenNote: _openNoteViewer,
          onOpenCourse: _selectCourse,
        );
      case 1:
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
          feedScope: _learnerScope,
          feedSort: _learnerSort,
          feedWindow: _learnerWindow,
          onChangeFeedFilters: ({scope, sort, window}) =>
              _setLearnerFilters(scope: scope, sort: sort, window: window),
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
              ? (noteId) => widget.client.deleteNoteCoverImage(_token!, noteId)
              : null,
          offlineMode: _localSettings['offline_mode'] == true,
          onLoadPublicNotes: () => _loadLearnerNotes(),
        );
      case 2:
        return _CoursePage(
          courses: _courses,
          localCourses: _localCourses,
          selectedCourse: _selectedCourse,
          notes: _courseNotes,
          notesLoading: _courseNotesLoading,
          notesHasMore: _courseNotesHasMore,
          notesLoadingMore: _courseNotesLoadingMore,
          onLoadMoreNotes: _loadMoreCourseNotes,
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
          onOpenRoutedNote: _openNoteViewer,
          initialModuleKey: widget.initialModuleKey,
          onEditCourse: _updateCourseMeta,
          onTransferCourse: _transferCourseOwnership,
          onImportCourseFromGit: _importCourseFromGit,
        );
      case 3:
        return _ActivityPage(
          activityWeek: _activityWeek,
          isAuthenticated: _token != null && _token!.isNotEmpty,
          plannerEvents: [..._localEvents, ..._plannerEvents],
          courses: (_token == null || _token!.isEmpty)
              ? _localCourses
              : [..._localCourses, ..._courses],
          rangeDays: _activityRangeDays,
          onCreatePlannerEvent: _createPlannerEvent,
          onImportCalendar: _importCalendarFeed,
          onSubscribeCalendar: _subscribeCalendarFeed,
          onNavigateWeek: (direction) => _loadActivityWeek(
            startDate:
                _activityWeekStart.add(Duration(days: direction * _activityRangeDays)),
          ),
          onShiftStartDay: (dayDelta) => _loadActivityWeek(
            startDate: _activityWeekStart.add(Duration(days: dayDelta)),
          ),
          onChangeRange: (days) => _loadActivityWeek(rangeDays: days),
          onTogglePlannerEventCompletion: _togglePlannerEventCompletion,
          onUpdatePlannerEvent: _updatePlannerEvent,
          onEditCourse: _updateCourseMeta,
          onTransferCourse: _transferCourseOwnership,
        );
      case 4:
        return _SettingsPage(
          profile: _profile,
          settings: _settings,
          localSettings: _localSettings,
          localStats: _localStats,
          deletedNotes: _deletedNotes,
          onSave: _updateSettings,
          onLogout: logout,
          onLogin: login,
          onReplayTour: _replayOnboarding,
          currentLocale: _localSettings['locale']?.toString() ?? 'system',
          onSetLocale: _setLocale,
          onProbeStorageArch: _probeStorageArch,
          casdoorOrgLoginUrl: _casdoorOrgLoginUrl,
          onCasdoorLogin: () => launchOAuth('casdoor', intent: 'login'),
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
          onApplyLocalSettings: _applyLocalAppSettings,
          localDraftCount: _localDrafts.length,
          localCourseCount: _localCourses.length,
          apiBaseUrl: _localSettings['api_base_url']?.toString() ??
              _httpClient?.baseUrl,
          debugSnapshotListenable: _httpClient?.debugSnapshot,
          debugHistoryListenable: _httpClient?.debugHistory,
          debugLogController: logController,
          uiLogs: uiLogs,
          onRotateApiKey: _token != null
              ? () async {
                  try {
                    final result = await widget.client.rotateApiKey(_token!);
                    final newPrefix =
                        result['api_key_prefix']?.toString() ?? '';
                    if (newPrefix.isNotEmpty && mounted) {
                      _settings = {
                        ..._settings ?? <String, dynamic>{},
                        'api_key_prefix': newPrefix,
                      };
                      refreshState();
                    }
                    log(
                      level: DebugLogLevel.info,
                      source: 'Portal.UI',
                      message: 'API key rotated: Portal.UI/api_key.rotate — '
                          'new prefix ${newPrefix.isEmpty ? "<unknown>" : newPrefix}; '
                          'the previous key is now invalid.',
                    );
                    return result;
                  } catch (e) {
                    // A stale Casdoor session is the common cause: the app
                    // renders from local cache so it looks signed in, but
                    // this direct server call 401s. Log the effective cause
                    // so the Debug log explains the SnackBar.
                    log(
                      level: DebugLogLevel.warning,
                      source: 'Portal.UI',
                      message: 'API key was NOT rotated: '
                          'Portal.UI/api_key.rotate — '
                          '${e.toString().replaceFirst('Exception: ', '')} '
                          '(if this is a 401, the sign-in session has '
                          'expired — sign in again and retry).',
                    );
                    rethrow;
                  }
                }
              : null,
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
                    final msg = e.toString().replaceFirst('Exception: ', '');
                    return ActionFeedback(
                      message: 'Agent skill not saved: '
                          'Portal.Settings/skill.save — $msg.',
                      isError: true,
                    );
                  }
                }
              : null,
          githubSyncCardBuilder: _token != null
              ? () => GithubSyncExperimentalCard(
                    appId: 'portal',
                    onLoadStatus: () => widget.client.githubSyncStatus(_token!),
                    onListRepos: () => widget.client.githubSyncRepos(_token!),
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
          onExportLocalData: _exportLocalArchive,
          onRestoreFromLocalImport: _restoreFromLocalImport,
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

/// Fullscreen startup overlay showing the user's custom splash image
/// (local upload via LocalAttachmentStore, else a remote URL) instead of
/// the default reactor animation. The image spans the whole screen with a
/// fixed x-y aspect ratio (BoxFit.cover). Auto-dismisses after a short
/// beat (tap to skip); falls back to a plain surface if the image fails.
class _CustomSplashOverlay extends StatefulWidget {
  const _CustomSplashOverlay({
    required this.appTitle,
    required this.appVersion,
    this.localImageUrl = '',
    this.remoteImageUrl = '',
    this.loadingStatus,
    this.onFinished,
  });

  final String appTitle;
  final String appVersion;
  final String localImageUrl;
  final String remoteImageUrl;
  final ValueListenable<String>? loadingStatus;
  final VoidCallback? onFinished;

  @override
  State<_CustomSplashOverlay> createState() => _CustomSplashOverlayState();
}

class _CustomSplashOverlayState extends State<_CustomSplashOverlay> {
  Timer? _timer;
  double _opacity = 1;
  Uint8List? _localBytes;

  @override
  void initState() {
    super.initState();
    if (widget.localImageUrl.isNotEmpty) {
      LocalAttachmentStore.open()
          .then((store) => store.getBytes(localUrl: widget.localImageUrl))
          .then((bytes) {
        if (mounted) setState(() => _localBytes = bytes);
      }).catchError((_) {
        // Missing/corrupt local image → plain surface fallback below.
      });
    }
    _timer = Timer(const Duration(milliseconds: 2400), _dismiss);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _dismiss() {
    if (!mounted || _opacity == 0) return;
    setState(() => _opacity = 0);
    Timer(const Duration(milliseconds: 350), () {
      if (mounted) widget.onFinished?.call();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Widget image;
    if (_localBytes != null) {
      image = Image.memory(_localBytes!, fit: BoxFit.cover);
    } else if (widget.remoteImageUrl.isNotEmpty &&
        widget.localImageUrl.isEmpty) {
      image = Image.network(
        widget.remoteImageUrl,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) =>
            ColoredBox(color: theme.colorScheme.surface),
      );
    } else {
      image = ColoredBox(color: theme.colorScheme.surface);
    }
    return AnimatedOpacity(
      opacity: _opacity,
      duration: const Duration(milliseconds: 350),
      child: GestureDetector(
        onTap: _dismiss,
        child: Material(
          child: Stack(
            fit: StackFit.expand,
            children: [
              image,
              // Bottom scrim so the title/status stay legible on any image.
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 140,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withOpacity(0.55),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 24,
                bottom: 24,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.appTitle,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'v${widget.appVersion}',
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: Colors.white70),
                    ),
                    if (widget.loadingStatus != null) ...[
                      const SizedBox(height: 4),
                      ValueListenableBuilder<String>(
                        valueListenable: widget.loadingStatus!,
                        builder: (context, value, _) => Text(
                          value,
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: Colors.white70),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
