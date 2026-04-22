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
        client: widget.client ?? HttpNotechondriaClient(),
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
    with AppShellLogMixin<AppShell> {
  @override
  final List<String> uiLogs = <String>[];
  @override
  final DebugLogController logController = DebugLogController();
  @override
  Future<void> persistUiLogs() => _persistUiLogs();

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

  void _selectActualIndex(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  bool _showWidePageHeader(int index) => false;

  /// All categories visible in the sidebar. Cloud (`_courses`) rows are
  /// hidden while the user is offline / signed out so the editor reads as
  /// a local-only workspace until they re-authenticate. Cached cloud note
  /// content stays addressable by UUID so mid-edit work isn't dropped.
  List<Map<String, dynamic>> get _allCategories {
    if (_token == null || _token!.isEmpty) {
      return [..._localCourses];
    }
    return [..._localCourses, ..._courses];
  }

  // ---------------------------------------------------------------------------
  // URL routing helpers (web only)
  // ---------------------------------------------------------------------------

  /// Parse the URL hash fragment for a note UUID.
  /// Expected format: `#/notes/<uuid>`
  static final _noteUuidPattern = RegExp(
    r'^/?notes/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$',
    caseSensitive: false,
  );

  String? _parseNoteUuidFromUrl() {
    final fragment = Uri.base.fragment; // everything after #
    final match = _noteUuidPattern.firstMatch(fragment);
    return match?.group(1);
  }

  void _pushNoteUrl(String? noteUuid) {
    final base = Uri.base.removeFragment();
    final newUrl = noteUuid != null
        ? '$base#/notes/$noteUuid'
        : '$base#/';
    url_strategy.browserPushState(newUrl);
  }

  void _replaceNoteUrl(String? noteUuid) {
    final base = Uri.base.removeFragment();
    final newUrl = noteUuid != null
        ? '$base#/notes/$noteUuid'
        : '$base#/';
    url_strategy.browserReplaceState(newUrl);
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------
  @override
  void initState() {
    super.initState();
    final clamped = widget.initialIndex.clamp(0, _titles.length - 1);
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
      if (mounted && _isLoading) setState(() { _isLoading = false; _showSplash = false; });
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
    await _handleOAuthCallback();
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
  //   auth_actions.dart           _register / _login / _verify / etc.
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
  //   session.dart                _applyAuthPayload + _logout
  //   settings_actions.dart       settings panel + avatar upload
  //   settings_helpers.dart       app_settings payload helpers

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
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
    return AlertDialog(
      title: const Text('New category'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: widget.controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Category name',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text('Icon:', style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(width: 12),
              ActionChip(
                avatar: Icon(
                  _selectedIcon != null
                      ? _iconFromCodePoint(_selectedIcon!)
                      : Icons.folder_outlined,
                  size: 20,
                ),
                label: Text(_selectedIcon != null ? 'Change' : 'Choose'),
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
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Create'),
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
    final isOwned = widget.isOwned;
    return AlertDialog(
      title: Text(isOwned ? 'Edit category' : 'Subscribed category'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isOwned) ...[
            TextField(
              controller: widget.controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Category name',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Text('Icon:', style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(width: 12),
                ActionChip(
                  avatar: Icon(
                    _selectedIcon != null
                        ? _iconFromCodePoint(_selectedIcon!)
                        : Icons.school_outlined,
                    size: 20,
                  ),
                  label: Text(_selectedIcon != null ? 'Change' : 'Choose'),
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
              'Deleting moves all notes to the default category.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ] else ...[
            Text(
              widget.controller.text,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Text(
              'This category is published by another user. Renaming, '
              'icon changes and deletion are only available to the owner. '
              'You can still unsubscribe to remove it from your sidebar.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        if (isOwned)
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop({'action': 'delete'}),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          )
        else
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop({'action': 'unsubscribe'}),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Unsubscribe'),
          ),
        if (isOwned)
          FilledButton(
            onPressed: _save,
            child: const Text('Save'),
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
