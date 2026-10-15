part of notechondria_frontend;

typedef EditorLogSink = void Function({
  required String source,
  required String message,
  DebugLogLevel level,
  int? durationMs,
});

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

  /// The single NotechondriaClient for this app instance. Must be
  /// constructed in `initState` — NOT re-created on every `build()`.
  ///
  /// Earlier code wrote `client: widget.client ?? HttpNotechondriaClient()`
  /// inline in `build()`. Every `setState` on this state (e.g. a theme
  /// change) rebuilt `AppShell` with a fresh `HttpNotechondriaClient`
  /// whose `_baseUrl` had reverted to the compile-time default, wiping
  /// the `_loadLocalState.updateBaseUrl(...)` call that had pointed it
  /// at the user's saved API URL. That's why users who saved
  /// `note.zheyuanwu.com` in Settings saw requests still go to the
  /// default `notechondria.trance-0.com` host after any theme tweak.
  /// Caching the client here pins `_baseUrl` for the lifetime of the
  /// app instance; `AppShell.updateBaseUrl` now survives rebuilds.
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
      onGenerateTitle: (context) => AppLocalizations.of(context).appNameEditor,
      debugShowCheckedModeBanner: false,
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
      home: AppShell(
        client: _client,
        onThemeChanged: _handleThemeChanged,
        onLocaleChanged: _handleLocaleChanged,
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
    this.onLocaleChanged,
    this.initialIndex = 0,
    this.appTitle = 'Notechondria',
    this.visibleIndices = const <int>[0, 1, 2, 3, 4],
  });

  final NotechondriaClient client;
  final void Function(String preset, String mode)? onThemeChanged;

  /// Called with the persisted `app_settings['locale']` value
  /// (`system` | `en` | `zh`) whenever the resolved locale should
  /// change — on boot (from saved settings) and when the user picks a
  /// language. Mirrors [onThemeChanged].
  final void Function(String locale)? onLocaleChanged;
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
  String get logAppTag => 'Editor';
  @override
  String? get token => _token;
  @override
  ValueNotifier<String> get splashStatus => _splashStatus;
  // AppShellLocalPersistMixin wiring — read-side getters expose the
  // private `_localX` fields, write-side adapters delegate to the
  // app-private `_LocalAppStore` static methods.
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
  // above for AppShellLocalPersistMixin — same getter satisfies both).
  @override
  String? get currentUsername => _profile?['username']?.toString();
  // AppShellDraftHelpersMixin wiring — read getters already
  // provided above; setters write back to the private fields, and
  // the two per-app hooks forward to the existing local helpers.
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
  // AppShellSessionMixin wiring — setters write back to the
  // private fields; hooks forward to editor-specific helpers.
  // Editor is the only app that persists the session client-side
  // and reads multi-device metadata from the auth payload.
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
  // Session metadata hooks default to no-ops post-Casdoor cutover —
  // Casdoor owns session lifecycle, so the SPA no longer tracks
  // per-device ids / multi-device flags / other-session counts.
  @override
  Future<void> persistSession(String token, Map<String, dynamic> user) =>
      _LocalAppStore.saveSession(token, user);
  @override
  Future<void> clearPersistedSession() => _LocalAppStore.clearSession();

  // ---------------------------------------------------------------------------
  // State
  // ---------------------------------------------------------------------------
  int _selectedIndex = 0;
  bool _isLoading = true;
  bool _showSplash = true;
  String? _errorMessage;
  String? _token;
  Map<String, dynamic>? _profile;
  Map<String, dynamic>? _settings;
  Map<String, dynamic>? _frontPage;
  // True once /auth/casdoor/config/ has confirmed CASDOOR_* env vars
  // are set on the backend (`{configured: true}`). Probed once at
  // boot, then read by `build_helpers.dart` to decide whether to
  // surface the Casdoor SSO button. Stays `false` in shadow mode.
  bool _casdoorConfigured = false;

  /// Casdoor org-login URL derived from the `endpoint` + `organization`
  /// fields returned by `/api/v1/auth/casdoor/config/`. Populated inside
  /// the same probe that flips `_casdoorConfigured`. Threads through to
  /// `_SettingsPage(casdoorOrgLoginUrl: ...)` so the signed-out account
  /// card can render the "Login via third party" + "Sign up via
  /// Casdoor" CTAs that redirect the browser there.
  String? _casdoorOrgLoginUrl;
  List<Map<String, dynamic>> _courses = const [];
  List<Map<String, dynamic>> _localCourses = const [];
  List<Map<String, dynamic>> _courseNotes = const [];
  List<Map<String, dynamic>> _learnerNotes = const [];
  List<Map<String, dynamic>> _localDrafts = const [];
  List<Map<String, dynamic>> _deletedNotes = const [];
  // Client-side recycle-bin buckets. After a local draft / course
  // is successfully promoted to the cloud we MOVE it here instead of
  // deleting outright, so the user can restore if the cloud copy
  // later turns out to be wrong or corrupted. Entries auto-prune
  // 30 days after `trashed_at` (see `_LocalAppStore._pruneTrashed`).
  List<Map<String, dynamic>> _localTrashedDrafts = const [];
  List<Map<String, dynamic>> _localTrashedCourses = const [];
  Map<String, dynamic>? _selectedCourse;
  Map<String, dynamic>? _selectedNote;
  Map<String, dynamic> _localSettings = _LocalAppStore.defaultSettings();
  Map<String, dynamic> _localStats = _LocalAppStore.defaultStats();
  Map<String, dynamic> _localCache = _LocalAppStore.defaultCache();
  bool _hasMoreLearnerNotes = true;
  bool _isLoadingMoreNotes = false;
  bool _coursePanelExpanded = true;
  bool _inboxMigrationPromptShown = false;
  bool _whatsNewPromptShown = false;
  int _learnerNotesOffset = 0;
  String _learnerSearchQuery = '';
  Timer? _splashTimer;
  final ValueNotifier<String> _splashStatus =
      ValueNotifier<String>('Starting editor');

  /// Learner search scope: 'personal' (default) = only the user's own notes,
  /// 'all' = user's notes plus public notes from any other user.
  String _learnerSearchScope = 'personal';

  /// Currently selected category (course) for note filtering. null = all notes.
  int? _selectedCategoryId;

  /// True when the sidebar's Inbox folder is the active selection
  /// (0.1.190). The Inbox has no course id, so it used to share the
  /// `_selectedCategoryId == null` state with "All notes" and rendered
  /// exactly the same list — every note the user owned, categorised ones
  /// included. This flag separates the two.
  bool _uncategorizedSelected = false;

  /// Dedupe-key for the sidebar pin diagnostic so we don't spam the debug
  /// log with one warning per rebuild. Re-emit only when the category set
  /// composition (id/title/is_default tuple) changes. Lives on the State
  /// because the build_helpers extension can't declare instance fields.
  String? _lastSidebarPinDiagnosticKey;

  HttpNotechondriaClient? get _httpClient =>
      widget.client is HttpNotechondriaClient
          ? widget.client as HttpNotechondriaClient
          : null;

  static const List<String> _titles = [
    'Front Page',
    'Notes',
    'Course View',
    'Activity View',
    'Settings',
  ];

  List<int> get _visibleIndices {
    final visible = widget.visibleIndices
        .where((index) => index >= 0 && index < _titles.length)
        .toList(growable: false);
    return visible.isEmpty
        ? List<int>.generate(_titles.length, (i) => i)
        : visible;
  }

  // Unique URL per full-screen tab (0.1.186). Note deep links keep their
  // richer `#/notes/<uuid>` form; a bare tab path never clobbers one
  // (replaceState only fires on explicit tab switches).
  static const List<String> _tabPaths = [
    '/',
    '/notes',
    '/courses',
    '/activity',
    '/settings',
  ];

  void _selectActualIndex(int index) {
    setState(() {
      _selectedIndex = index;
    });
    url_strategy.browserReplaceState(
        '#${_tabPaths[index.clamp(0, _tabPaths.length - 1)]}');
  }

  bool _showWidePageHeader(int index) => false;

  /// All categories visible in the sidebar.
  ///
  /// 0.1.120: the synthetic uncategorized folder is prepended at the
  /// top — it groups every note with no `course_id` (post-refactor
  /// replacement for the pre-0.1.120 hard-coded Inbox course). The
  /// real Course rows follow: `_localCourses` (offline-created drafts
  /// queued for sync) and `_courses` (cloud-backed). Both are always
  /// merged regardless of `_token` so the sidebar doesn't blink during
  /// auth refresh — `_loadInitialData` re-runs after logout and
  /// repopulates `_courses` from the public-feed response, so signed-
  /// out users still get a sensible catalog.
  List<Map<String, dynamic>> get _allCategories {
    // 0.1.182: order the real categories by the user's most recent
    // activity (last opened, else the newest note's edit) so a freshly
    // created project surfaces at the top instead of being buried by
    // the server's static sort order.
    DateTime? recency(Map<String, dynamic> course) {
      final opened =
          DateTime.tryParse(course['last_opened_at']?.toString() ?? '');
      final recent = course['recent_notes'];
      DateTime? noteEdit;
      if (recent is List && recent.isNotEmpty && recent.first is Map) {
        noteEdit = DateTime.tryParse(
            (recent.first as Map)['last_edit']?.toString() ?? '');
      }
      if (opened == null) return noteEdit;
      if (noteEdit == null) return opened;
      return opened.isAfter(noteEdit) ? opened : noteEdit;
    }

    // 0.1.184: the sidebar lists only the user's OWN workspace — local
    // courses plus cloud courses they own or actively subscribe to. The
    // course list endpoint returns the whole public catalog, and listing
    // it here made brand-new accounts see other people's projects in
    // their sidebar (with no subscription involved). Discovery of public
    // courses stays in the Course view; new users see just the Inbox
    // folder until they create or subscribe to something.
    final rows = [
      ..._localCourses,
      ..._courses.where((course) =>
          course['is_owned'] == true || course['is_subscribed'] == true),
    ];
    rows.sort((a, b) {
      final at = recency(a);
      final bt = recency(b);
      if (at == null && bt == null) return 0;
      if (at == null) return 1;
      if (bt == null) return -1;
      return bt.compareTo(at);
    });
    return [
      buildUncategorizedFolder(),
      ...rows,
    ];
  }

  // ---------------------------------------------------------------------------
  // URL routing helpers (web only)
  // ---------------------------------------------------------------------------

  String? _parseNoteUuidFromUrl() {
    // Prefer the fragment snapshotted in `main()` before Flutter's
    // web router could normalize `#/notes/<uuid>` away to `#/`. Fall
    // back to the live `Uri.base` for in-app navigation cases where no
    // boot fragment was captured (e.g. non-web, or a fragment set
    // after launch).
    final fromBoot = parseNoteUuidFromFragment(bootInitialFragment);
    if (fromBoot != null) return fromBoot;
    return parseNoteUuidFromFragment(Uri.base.fragment);
  }

  void _pushNoteUrl(String? noteUuid) {
    final base = Uri.base.removeFragment();
    final newUrl = noteUuid != null ? '$base#/notes/$noteUuid' : '$base#/';
    url_strategy.browserPushState(newUrl);
  }

  void _replaceNoteUrl(String? noteUuid) {
    final base = Uri.base.removeFragment();
    final newUrl = noteUuid != null ? '$base#/notes/$noteUuid' : '$base#/';
    url_strategy.browserReplaceState(newUrl);
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------
  @override
  void initState() {
    super.initState();
    var initial = widget.initialIndex;
    // Cold-start tab deep link (`#/courses` etc.); `#/notes/<uuid>` note
    // links are handled separately by _parseNoteUuidFromUrl.
    final fragment = Uri.base.fragment;
    final tabFromUrl = _tabPaths.indexOf(
        fragment.startsWith('/') ? fragment : '/$fragment');
    if (tabFromUrl > 0) {
      initial = tabFromUrl;
    }
    final clamped = initial.clamp(0, _titles.length - 1);
    _selectedIndex =
        _visibleIndices.contains(clamped) ? clamped : _visibleIndices.first;
    // Route the HTTP client's per-request DEBUG logs into the shared
    // DebugLogController so the user can see every request/response
    // pair in the Debug log card. Level is picked per-status by the
    // client (DEBUG for 2xx/3xx, INFO for 4xx, WARNING for 5xx or
    // network failures).
    _httpClient?.setLogger((level, source, message) {
      if (!mounted) return;
      log(level: level, source: source, message: message);
    });
    _bootstrapApp();
  }

  @override
  void dispose() {
    _splashTimer?.cancel();
    _splashStatus.dispose();
    logController.dispose();
    super.dispose();
  }

  Future<void> _bootstrapApp() async {
    _splashTimer = Timer(const Duration(seconds: 10), () {
      if (mounted && _isLoading) {
        setState(() {
          _isLoading = false;
          _showSplash = false;
        });
      }
    });
    _splashStatus.value = 'Loading local workspace';
    await _loadLocalState();
    // Restore the stored auth token BEFORE handling any OAuth callback.
    // The bind flow needs `_token` to be non-null so it can call the
    // authenticated /auth/bind/* endpoint; otherwise the fallback logic
    // would hit the public /auth/<provider>/ endpoint and either log in
    // as the OAuth identity's email owner or create a new account,
    // effectively overwriting the current user.
    _splashStatus.value = 'Restoring session';
    await _restoreSession();
    _splashStatus.value = 'Completing sign-in';
    await handleOAuthCallback();
    _splashStatus.value = 'Connecting to server';
    await _loadInitialData();
    // Deep-link: if the URL contains a note UUID, load it.
    final deepLinkUuid = _parseNoteUuidFromUrl();
    if (deepLinkUuid != null) {
      await _openNoteByUuid(deepLinkUuid);
    }
  }

  // All state-mutating logic has been extracted into per-concern
  // extensions on `_AppShellState` under `lib/core/*.dart` so this
  // file stays closer to the AGENTS.md \u00a71.5 1000-line ceiling.
  // Each extension picks up the library-private fields on `this`
  // and routes any UI rebuilds through the shared `refreshState()`
  // wrapper below, since `setState` is `@protected` and invisible
  // to extensions.
  //
  //   auth_actions.dart           register / login / verify / etc.
  //   auth_flows.dart             OAuth + session-restore + deep-link
  //   category_actions.dart       create / edit / delete category
  //   course_helpers.dart         read-side course projections
  //   draft_helpers.dart          offline draft store + fallback
  //   draft_sync.dart             push local drafts + pull from cloud
  //   initial_data.dart           _loadInitialData cold-boot fetch
  //   load_local_state.dart       _loadLocalState hydrate from disk
  //   local_archive_io.dart       `.nchron` export / import
  //   local_course_builders.dart  build + promote local courses
  //   local_persist.dart          _persistLocal* + snapshot
  //   local_starter.dart          first-run Inbox seed
  //   local_trash.dart            client-side recycle bin
  //   logging.dart                log / timed<T>
  //   maintenance_actions.dart    sync-now / clear / template reset
  //   note_crud.dart              create / save / import / export
  //   note_loading.dart           learner list + course/note select
  //   note_sessions.dart          cloud note-session tracking
  //   settings_actions.dart       settings panel + avatar upload
  //   settings_helpers.dart       app_settings payload helpers
  //
  // applyAuthPayload + logout moved into the shared
  // AppShellSessionMixin (notechondria_shared 0.1.82). Session
  // metadata hooks are no-ops post-0.1.106 — Casdoor owns the
  // session lifecycle on its side.

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scaffold = LayoutBuilder(
      builder: (context, constraints) {
        final isWideLayout = constraints.maxWidth >= 960;
        if (isWideLayout) return _buildWideScaffold(context);
        return _buildCompactScaffold(context);
      },
    );
    if (_showSplash) {
      return Stack(
        children: [
          scaffold,
          Positioned.fill(
            child: SplashScreen(
              appTitle: l10n.appNameEditor,
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

  // Build helpers (`_buildCompactScaffold`,
  // `_buildDrawerCategoryRow`, `_buildWideScaffold`,
  // `_buildBody`, `_buildPage`) live in `core/build_helpers.dart`
  // as an extension on `_AppShellState` so this file stays closer
  // to the AGENTS.md \u00a71.5 1000-line cap. `build()` itself
  // stays above because Flutter requires the override on State.
}

/// Dialog for creating a new category with optional icon.
class _CreateCategoryDialog extends StatefulWidget {
  const _CreateCategoryDialog({required this.controller});
  final TextEditingController controller;

  @override
  State<_CreateCategoryDialog> createState() => _CreateCategoryDialogState();
}

class _CreateCategoryDialogState extends State<_CreateCategoryDialog> {
  int? _selectedIcon;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.navNewCategory),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: widget.controller,
            autofocus: true,
            decoration: InputDecoration(
              labelText: l10n.categoryNameLabel,
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text(l10n.categoryIconLabel,
                  style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(width: 12),
              ActionChip(
                avatar: Icon(
                  _selectedIcon != null
                      ? _iconFromCodePoint(_selectedIcon!)
                      : Icons.folder_outlined,
                  size: 20,
                ),
                label: Text(_selectedIcon != null
                    ? l10n.commonChange
                    : l10n.commonChoose),
                onPressed: () async {
                  final picked = await _showIconPickerDialog(
                    context,
                    currentCodePoint: _selectedIcon,
                  );
                  if (picked != null) setState(() => _selectedIcon = picked);
                },
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(l10n.commonCreate),
        ),
      ],
    );
  }

  void _submit() {
    Navigator.of(context).pop({
      'title': widget.controller.text,
      'icon': _selectedIcon,
    });
  }
}

/// Dialog for editing a category. When [isOwned] is false, rename +
/// icon + save are hidden (the backend rejects non-owner edits with
/// 403) and the destructive action flips from **Delete** to
/// **Unsubscribe** so a non-owner can still remove a subscribed cloud
/// category from their sidebar without hitting a 403.
class _EditCategoryDialog extends StatefulWidget {
  const _EditCategoryDialog({
    required this.controller,
    required this.isOwned,
    this.initialIcon,
  });
  final TextEditingController controller;
  final int? initialIcon;
  final bool isOwned;

  @override
  State<_EditCategoryDialog> createState() => _EditCategoryDialogState();
}

class _EditCategoryDialogState extends State<_EditCategoryDialog> {
  late int? _selectedIcon;

  @override
  void initState() {
    super.initState();
    _selectedIcon = widget.initialIcon;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isOwned = widget.isOwned;
    return AlertDialog(
      title: Text(
          isOwned ? l10n.categoryEditTitle : l10n.categorySubscribedTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isOwned) ...[
            TextField(
              controller: widget.controller,
              autofocus: true,
              decoration: InputDecoration(
                labelText: l10n.categoryNameLabel,
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Text(l10n.categoryIconLabel,
                    style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(width: 12),
                ActionChip(
                  avatar: Icon(
                    _selectedIcon != null
                        ? _iconFromCodePoint(_selectedIcon!)
                        : Icons.school_outlined,
                    size: 20,
                  ),
                  label: Text(_selectedIcon != null
                      ? l10n.commonChange
                      : l10n.commonChoose),
                  onPressed: () async {
                    final picked = await _showIconPickerDialog(
                      context,
                      currentCodePoint: _selectedIcon,
                    );
                    if (picked != null) {
                      setState(() => _selectedIcon = picked);
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              l10n.categoryDeleteHelp,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ] else ...[
            Text(
              widget.controller.text,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Text(
              l10n.categorySubscribedHelp,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        if (isOwned)
          TextButton(
            onPressed: () => Navigator.of(context).pop({'action': 'delete'}),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(l10n.commonDelete),
          )
        else
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop({'action': 'unsubscribe'}),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(l10n.categoryUnsubscribe),
          ),
        if (isOwned)
          FilledButton(
            onPressed: _save,
            child: Text(l10n.commonSave),
          ),
      ],
    );
  }

  void _save() {
    Navigator.of(context).pop({
      'action': 'save',
      'title': widget.controller.text,
      'icon': _selectedIcon,
    });
  }
}
