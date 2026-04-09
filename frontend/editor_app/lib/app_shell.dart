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

class _AppShellState extends State<AppShell> {
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
  /// Learner search scope: 'personal' (default) = only the user's own notes,
  /// 'all' = user's notes plus public notes from any other user.
  String _learnerSearchScope = 'personal';
  final List<String> _uiLogs = <String>[];

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

  /// All categories: local courses first, then remote courses.
  List<Map<String, dynamic>> get _allCategories =>
      [..._localCourses, ..._courses];

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
    _bootstrapApp();
  }

  @override
  void dispose() {
    _splashTimer?.cancel();
    super.dispose();
  }

  Future<void> _bootstrapApp() async {
    _splashTimer = Timer(const Duration(seconds: 10), () {
      if (mounted && _isLoading) setState(() { _isLoading = false; _showSplash = false; });
    });
    await _loadLocalState();
    // Check for OAuth callback before restoring session.
    final oauthHandled = await _handleOAuthCallback();
    if (!oauthHandled) {
      await _restoreSession();
    }
    await _loadInitialData();
    // Deep-link: if the URL contains a note UUID, load it.
    final deepLinkUuid = _parseNoteUuidFromUrl();
    if (deepLinkUuid != null) {
      await _openNoteByUuid(deepLinkUuid);
    }
  }

  // ---------------------------------------------------------------------------
  // OAuth helpers
  // ---------------------------------------------------------------------------

  Future<void> _launchOAuth(String provider, {String invitationCode = '', String intent = 'register'}) async {
    try {
      final config = await widget.client.getOAuthConfig();
      final providerConfig = Map<String, dynamic>.from(
        config[provider] as Map? ?? {},
      );
      final clientId = providerConfig['client_id']?.toString() ?? '';
      final redirectUri = providerConfig['redirect_uri']?.toString() ?? '';
      if (clientId.isEmpty) {
        _appendUiLog('$provider OAuth not configured (missing client_id).');
        return;
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('oauth_redirect_uri', redirectUri);
      await prefs.setString('oauth_invitation_code', invitationCode);
      await prefs.setString('oauth_intent', intent);

      final String authUrl;
      if (provider == 'google') {
        authUrl = Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
          'client_id': clientId,
          'redirect_uri': redirectUri,
          'response_type': 'code',
          'scope': 'openid email profile',
          'state': 'google',
          'access_type': 'offline',
          'prompt': 'select_account',
        }).toString();
      } else {
        authUrl = Uri.https('github.com', '/login/oauth/authorize', {
          'client_id': clientId,
          'redirect_uri': redirectUri,
          'scope': 'user:email',
          'state': 'github',
        }).toString();
      }
      url_strategy.browserRedirect(authUrl);
    } catch (error) {
      _appendUiLog('OAuth launch failed: ${error.toString().replaceFirst("Exception: ", "")}');
    }
  }

  /// Check [Uri.base] for an OAuth callback `?code=&state=` and complete login.
  /// Returns true if an OAuth callback was handled.
  Future<bool> _handleOAuthCallback() async {
    if (!kIsWeb) return false;
    final uri = Uri.base;
    final code = uri.queryParameters['code'];
    final state = uri.queryParameters['state'];
    if (code == null || code.isEmpty) return false;
    if (state != 'google' && state != 'github') return false;

    // Clean the URL so a page refresh doesn't re-process the code.
    final cleanUrl = uri.removeFragment().replace(queryParameters: {}).toString();
    url_strategy.browserReplaceState(cleanUrl);

    final prefs = await SharedPreferences.getInstance();
    final redirectUri = prefs.getString('oauth_redirect_uri') ?? '';
    final invitationCode = prefs.getString('oauth_invitation_code') ?? '';
    final intent = prefs.getString('oauth_intent') ?? 'register';
    await prefs.remove('oauth_redirect_uri');
    await prefs.remove('oauth_invitation_code');
    await prefs.remove('oauth_intent');

    // Bind flow: user is already authenticated, link the social account.
    if (intent == 'bind' && _token != null) {
      try {
        if (state == 'google') {
          await widget.client.bindGoogle(_token!, code, redirectUri: redirectUri);
        } else {
          await widget.client.bindGithub(_token!, code, redirectUri: redirectUri);
        }
        final provider = state == 'google' ? 'Google' : 'GitHub';
        _appendUiLog('Linked $provider account.');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$provider account linked successfully.')),
          );
        }
        return true;
      } catch (error) {
        final msg = error.toString().replaceFirst('Exception: ', '');
        _appendUiLog('Account linking failed: $msg');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Account linking failed: $msg')),
          );
        }
        return false;
      }
    }

    try {
      final Map<String, dynamic> result;
      if (state == 'google') {
        result = await widget.client.loginWithGoogle(code, redirectUri: redirectUri, invitationCode: invitationCode, intent: intent);
      } else {
        result = await widget.client.loginWithGithub(code, redirectUri: redirectUri, invitationCode: invitationCode, intent: intent);
      }
      await _applyAuthPayload(result);
      _appendUiLog('Signed in via ${state == 'google' ? 'Google' : 'GitHub'}.');
      return true;
    } catch (error) {
      final msg = error.toString().replaceFirst('Exception: ', '');
      if (msg.contains('not_registered') || msg.contains('No account found')) {
        _appendUiLog('No account found. Please register first.');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No account found for this identity. Please register first.')),
          );
        }
      } else {
        _appendUiLog('OAuth login failed: $msg');
      }
      return false;
    }
  }

  /// Fetch a note by UUID and open it in the viewer/editor.
  Future<void> _openNoteByUuid(String uuid) async {
    setState(() => _isLoading = true);
    try {
      final detail = await widget.client.getNoteByUuid(uuid, token: _token);
      setState(() {
        _selectedNote = detail;
        _selectedIndex = 1;
        _isLoading = false;
      });
      _replaceNoteUrl(uuid);
      // Open the note viewer/editor dialog after the frame renders.
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _showNoteDialogForDeepLink(detail);
        });
      }
    } catch (error) {
      setState(() {
        _errorMessage = 'Could not load note: ${error.toString().replaceFirst('Exception: ', '')}';
        _isLoading = false;
      });
    }
  }

  void _showNoteDialogForDeepLink(Map<String, dynamic> detail) {
    final canEdit = detail['can_edit'] == true;
    if (canEdit) {
      // Owner: open in editor.
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => _NoteEditorDialog(
          note: detail,
          courses: [..._localCourses, ..._courses],
          editorMode: _settings?['editor_mode']?.toString() ?? 'P',
          onSave: _saveNote,
          onSnapshot: _snapshotNote,
          onGetHistory: _getNoteHistory,
          onRestoreVersion: _restoreNoteVersion,
          onLogEvent: _appendUiLog,
          onUploadAttachment: _uploadNoteAttachment,
        ),
      );
    } else {
      // Non-owner: read-only viewer.
      showDialog<void>(
        context: context,
        builder: (context) => _NoteViewerDialog(
          note: detail,
          onEdit: null,
          onExport: () => _exportNote(detail),
          onDelete: null,
        ),
      );
    }
  }

  /// Restores a persisted auth session if one exists. Validates the token
  /// against the backend via `/auth/session/`; if the token is stale the
  /// persisted session is cleared.
  Future<void> _restoreSession() async {
    final session = await _LocalAppStore.loadSession();
    if (session == null) return;
    final token = session['token']?.toString() ?? '';
    if (token.isEmpty) return;
    try {
      final check = await widget.client.checkSession(token);
      if (check['authenticated'] == true) {
        await _applyAuthPayload(check);
        return;
      }
    } catch (_) {
      // Token invalid or network down — fall through and clear.
    }
    await _LocalAppStore.clearSession();
  }


  void _appendUiLog(String message) {
    final timestamp = DateTime.now().toIso8601String();
    setState(() {
      _uiLogs.insert(0, '[$timestamp] $message');
      if (_uiLogs.length > 80) {
        _uiLogs.removeRange(80, _uiLogs.length);
      }
    });
    unawaited(_persistUiLogs());
  }

  // ---------------------------------------------------------------------------
  // Local state persistence
  // ---------------------------------------------------------------------------
  Future<void> _loadLocalState() async {
    final snapshot = await _LocalAppStore.load();
    _localSettings = snapshot.settings;
    final storedApiBase = _localSettings['api_base_url']?.toString() ?? '';
    if (kIsWeb &&
        (storedApiBase == '/api/v1' ||
            storedApiBase == 'http://localhost:9080' ||
            storedApiBase == 'http://localhost:9080/api/v1')) {
      _localSettings = {
        ..._localSettings,
        'api_base_url': _defaultApiBaseUrl(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
      await _LocalAppStore.saveSettings(_localSettings);
    }
    _localDrafts = snapshot.drafts;
    _localCourses = snapshot.courses;
    _localStats = snapshot.stats;
    _localCache = snapshot.cache;
    _uiLogs
      ..clear()
      ..addAll(snapshot.logs);
    _frontPage = Map<String, dynamic>.from(
      snapshot.cache['front_page'] as Map? ?? const {},
    );
    _courses = (snapshot.cache['courses'] as List<dynamic>? ?? const [])
        .map((item) =>
            _decorateRemoteCourse(Map<String, dynamic>.from(item as Map)))
        .toList(growable: false);
    await _ensureStarterWorkspace();
    _selectedCourse ??= _chooseDefaultCourse(
      remoteCourses: _courses,
      localCourses: _localCourses,
      frontPage: _frontPage,
    );
    _httpClient?.updateBaseUrl(
      _localSettings['api_base_url']?.toString() ?? _defaultApiBaseUrl(),
    );
    widget.onThemeChanged?.call(
      _localSettings['theme_preset']?.toString() ?? 'teal',
      _localSettings['theme_mode']?.toString() ?? 'S',
    );
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _persistLocalSettings() async {
    await _LocalAppStore.saveSettings(_localSettings);
  }

  Future<void> _persistLocalDrafts() async {
    await _LocalAppStore.saveDrafts(_localDrafts);
  }

  Future<void> _persistLocalCourses() async {
    await _LocalAppStore.saveCourses(_localCourses);
  }

  Future<void> _persistLocalStats() async {
    await _LocalAppStore.saveStats(_localStats);
  }

  Future<void> _persistLocalCache() async {
    _localCache = {
      ..._localCache,
      'front_page': _frontPage ?? const <String, dynamic>{},
      'courses': _courses,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    await _LocalAppStore.saveCache(_localCache);
  }

  Future<void> _persistUiLogs() async {
    await _LocalAppStore.saveLogs(_uiLogs);
  }

  // ---------------------------------------------------------------------------
  // Starter workspace
  // ---------------------------------------------------------------------------
  Future<void> _ensureStarterWorkspace() async {
    if (_frontPage?.isNotEmpty == true ||
        _courses.isNotEmpty ||
        _localCourses.isNotEmpty ||
        _localDrafts.isNotEmpty) {
      return;
    }
    final starterCourse = {
      ..._buildLocalCourse(
        title: 'Inbox',
        description: 'Offline-first local note bucket for the editor app.',
      ),
      'is_default': true,
    };
    final starterDraft = _buildLocalDraft(
      title: 'Welcome to the editor workspace',
      description: 'Starter note describing the offline storage layout.',
      content: '''# Welcome to the editor workspace

This app is the offline-first markdown editor.

## Suggested local structure

```
root/
- category/
- <note>/
- media/
- .metadata
- note-<created_timestamp>.md
```

Use this draft as a starting point and sync later when you sign in.''',
      editorMode: 'M',
      metadataJson: jsonEncode({
        'course_id': starterCourse['id'],
        'module_title': 'Inbox',
        'module_description': 'Local starter notes for the editor app.',
        'storage_layout': 'root/category/<note>/media/.metadata',
      }),
    );
    final starterReference = _buildLocalDraft(
      title: 'Plain-text editor checklist',
      description: 'Starter checklist for the editor modes.',
      content:
          '''# Plain-text editor checklist

- Markdown mode
- Plain text mode
- Structured mode

Add syntax highlighting for plain text and keep notes searchable by title or body.''',
      editorMode: 'T',
      metadataJson: jsonEncode({
        'course_id': starterCourse['id'],
        'module_title': 'Editor setup',
      }),
    );
    _localCourses = [starterCourse];
    _localDrafts = [starterDraft, starterReference];
    _selectedCourse = starterCourse;
    _courseNotes = _localNotesForCourse(starterCourse);
    _frontPage = _frontPageFallbackPayload(const []);
    _localStats = {
      ..._localStats,
      'starter_workspace_seeded_at': DateTime.now().toUtc().toIso8601String(),
    };
    await _persistLocalCourses();
    await _persistLocalDrafts();
    await _persistLocalStats();
    await _persistLocalCache();
    _appendUiLog(
        'Seeded starter editor workspace for first-run offline use.');
  }

  // ---------------------------------------------------------------------------
  // Course / category helpers
  // ---------------------------------------------------------------------------
  bool _isLocalCourse(Map<String, dynamic>? course) {
    if (course == null) return false;
    return course['is_local_course'] == true ||
        ((course['id'] as num?)?.toInt() ?? 0) < 0;
  }

  Map<String, dynamic> _decorateRemoteCourse(Map<String, dynamic> course) {
    final owner =
        Map<String, dynamic>.from(course['owner'] as Map? ?? const {});
    final username = _profile?['username']?.toString() ?? '';
    final isOwned = username.isNotEmpty &&
        owner['username']?.toString().toLowerCase() == username.toLowerCase();
    return {
      ...course,
      'is_local_course': false,
      'is_owned': course['is_owned'] == true || isOwned,
    };
  }

  Map<String, dynamic> _frontPageFallbackPayload(
    List<Map<String, dynamic>> remoteCourses,
  ) {
    final fallbackCourses = remoteCourses.isNotEmpty
        ? remoteCourses.take(3).toList()
        : _localCourses.take(3).toList();
    return {
      'default_course':
          fallbackCourses.isNotEmpty ? fallbackCourses.first : null,
      'carousel_courses': fallbackCourses,
      'collections': fallbackCourses,
      'recent_notes': const <Map<String, dynamic>>[],
      'recommended_notes': const <Map<String, dynamic>>[],
    };
  }

  Map<String, dynamic>? _chooseDefaultCourse({
    required List<Map<String, dynamic>> remoteCourses,
    required List<Map<String, dynamic>> localCourses,
    required Map<String, dynamic>? frontPage,
  }) {
    final retainedCourseId = (_selectedCourse?['id'] as num?)?.toInt();
    if (retainedCourseId != null) {
      for (final course in [...localCourses, ...remoteCourses]) {
        if ((course['id'] as num?)?.toInt() == retainedCourseId) {
          return Map<String, dynamic>.from(course);
        }
      }
    }
    final defaultCourse =
        frontPage?['default_course'] as Map<String, dynamic>?;
    if (defaultCourse != null && defaultCourse.isNotEmpty) {
      final defaultId = (defaultCourse['id'] as num?)?.toInt();
      for (final course in [...localCourses, ...remoteCourses]) {
        if ((course['id'] as num?)?.toInt() == defaultId) {
          return Map<String, dynamic>.from(course);
        }
      }
      return Map<String, dynamic>.from(defaultCourse);
    }
    if (localCourses.isNotEmpty) {
      return Map<String, dynamic>.from(localCourses.first);
    }
    if (remoteCourses.isNotEmpty) {
      return Map<String, dynamic>.from(remoteCourses.first);
    }
    return null;
  }

  List<Map<String, dynamic>> _localNotesForCourse(
      Map<String, dynamic> course) {
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

  // ---------------------------------------------------------------------------
  // Initial data loading
  // ---------------------------------------------------------------------------
  Future<void> _loadInitialData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    final errors = <String>[];
    _httpClient?.updateBaseUrl(
      _localSettings['api_base_url']?.toString() ?? _defaultApiBaseUrl(),
    );
    widget.onThemeChanged?.call(
      _localSettings['theme_preset']?.toString() ?? 'teal',
      _localSettings['theme_mode']?.toString() ?? 'S',
    );

    var frontPage = _frontPage ?? _frontPageFallbackPayload(_courses);
    var courses = List<Map<String, dynamic>>.from(_courses);
    var courseNotes = List<Map<String, dynamic>>.from(_courseNotes);
    var learnerNotes = List<Map<String, dynamic>>.from(_learnerNotes);
    var deletedNotes = List<Map<String, dynamic>>.from(_deletedNotes);
    Map<String, dynamic> notePage = {
      'results': learnerNotes,
      'has_more': _hasMoreLearnerNotes,
    };
    var updatedCache = false;

    try {
      frontPage = await widget.client.getFrontPage(token: _token);
      updatedCache = true;
    } catch (error) {
      errors.add(error.toString().replaceFirst('Exception: ', ''));
    }
    try {
      courses = (await widget.client.getCourses(token: _token))
          .map(_decorateRemoteCourse)
          .toList(growable: false);
      updatedCache = true;
    } catch (error) {
      errors.add(error.toString().replaceFirst('Exception: ', ''));
    }

    // If the remote courses include a default (Inbox) category, drop the
    // local default to avoid a duplicate Inbox row in the sidebar.
    if (courses.any((c) => c['is_default'] == true)) {
      final hadLocalDefault =
          _localCourses.any((c) => c['is_default'] == true);
      if (hadLocalDefault) {
        _localCourses = _localCourses
            .where((c) => c['is_default'] != true)
            .toList(growable: false);
        await _persistLocalCourses();
      }
    }

    final selectedCourse = _chooseDefaultCourse(
      remoteCourses: courses,
      localCourses: _localCourses,
      frontPage: frontPage,
    );
    if (selectedCourse != null) {
      if (_isLocalCourse(selectedCourse)) {
        courseNotes = _localNotesForCourse(selectedCourse);
      } else {
        try {
          courseNotes = await widget.client.getCourseNotes(
            selectedCourse['id'] as int,
            token: _token,
          );
        } catch (error) {
          errors.add(error.toString().replaceFirst('Exception: ', ''));
          courseNotes = const [];
        }
      }
    } else {
      courseNotes = const [];
    }

    if (_token != null && _token!.isNotEmpty) {
      try {
        deletedNotes = await widget.client.getDeletedNotes(_token!);
      } catch (error) {
        errors.add(error.toString().replaceFirst('Exception: ', ''));
      }
    } else {
      deletedNotes = const [];
    }
    try {
      notePage = await widget.client.listNotes(
        token: (_token != null && _token!.isNotEmpty) ? _token : null,
        limit: 20,
        offset: 0,
        scope: (_token != null && _token!.isNotEmpty) ? 'personal' : 'all',
      );
      learnerNotes = (notePage['results'] as List<dynamic>? ?? const [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList(growable: false);
    } catch (error) {
      errors.add(error.toString().replaceFirst('Exception: ', ''));
    }

    setState(() {
      _frontPage = frontPage;
      _courses = courses;
      _selectedCourse = selectedCourse;
      _courseNotes = courseNotes;
      _learnerNotes = learnerNotes;
      _deletedNotes = deletedNotes;
      _selectedNote = null;
      _hasMoreLearnerNotes = notePage['has_more'] == true;
      _learnerNotesOffset = learnerNotes.length;
      _errorMessage = errors.isEmpty ? null : errors.first;
      _isLoading = false;
      _showSplash = false;
    });
    if (updatedCache) {
      await _persistLocalCache();
    }
    _appendUiLog(
      errors.isEmpty
          ? 'Initial data loaded.'
          : 'Initial load used offline fallback: ${errors.first}',
    );
  }

  // ---------------------------------------------------------------------------
  // Draft / note helpers
  // ---------------------------------------------------------------------------
  Map<String, dynamic> _storeLocalDraft(
    Map<String, dynamic> draft, {
    bool incrementCreated = false,
  }) {
    final existingIndex =
        _localDrafts.indexWhere((item) => item['id'] == draft['id']);
    final nextDrafts = List<Map<String, dynamic>>.from(_localDrafts);
    if (existingIndex >= 0) {
      nextDrafts[existingIndex] = draft;
      nextDrafts.insert(0, nextDrafts.removeAt(existingIndex));
    } else {
      nextDrafts.insert(0, draft);
    }
    _localDrafts = List<Map<String, dynamic>>.unmodifiable(nextDrafts);
    if (incrementCreated) {
      _localStats = {
        ..._localStats,
        'local_drafts_created':
            ((_localStats['local_drafts_created'] as num?)?.toInt() ?? 0) + 1,
      };
    }
    return draft;
  }

  Map<String, dynamic> _buildOfflineFallbackDraft({
    Map<String, dynamic>? sourceNote,
    required Map<String, dynamic> payload,
  }) {
    final sourceId = (sourceNote?['id'] as num?)?.toInt();
    final existingIndex = sourceId == null
        ? -1
        : _localDrafts.indexWhere((item) {
            final metadata = _decodeNoteMetadata(
                item['metadata_json']?.toString() ?? '{}');
            return (metadata['offline_source_note_id'] as num?)?.toInt() ==
                sourceId;
          });
    final existingDraft = existingIndex >= 0
        ? Map<String, dynamic>.from(_localDrafts[existingIndex])
        : null;
    final metadata = _decodeNoteMetadata(
      payload['metadata_json']?.toString() ??
          sourceNote?['metadata_json']?.toString() ??
          '{}',
    );
    if (sourceId != null) {
      metadata['offline_source_note_id'] = sourceId;
    }
    return _buildLocalDraft(
      id: (existingDraft?['id'] as num?)?.toInt(),
      clientDraftId: existingDraft?['client_draft_id']?.toString(),
      createdAt: existingDraft?['date_created']?.toString() ??
          sourceNote?['date_created']?.toString(),
      title: payload['title']?.toString() ??
          sourceNote?['title']?.toString() ??
          'Untitled note',
      description: payload['description']?.toString() ??
          sourceNote?['description']?.toString() ??
          '',
      content: payload['content']?.toString() ??
          sourceNote?['content']?.toString() ??
          '# Untitled note\n\n',
      editorMode: payload['editor_mode']?.toString() ??
          sourceNote?['editor_mode']?.toString() ??
          'P',
      metadataJson: jsonEncode(metadata),
    );
  }

  // ---------------------------------------------------------------------------
  // Note loading & selection
  // ---------------------------------------------------------------------------
  Future<void> _loadLearnerNotes({
    bool reset = false,
    String? query,
    String? scope,
  }) async {
    if (_isLoadingMoreNotes) return;
    final isAuthenticated = _token != null && _token!.isNotEmpty;
    final effectiveQuery = query ?? _learnerSearchQuery;
    // Anonymous users always see public notes (scope=all).
    final effectiveScope =
        isAuthenticated ? (scope ?? _learnerSearchScope) : 'all';
    final nextOffset = reset ? 0 : _learnerNotesOffset;
    setState(() {
      _isLoadingMoreNotes = true;
      if (reset) {
        _learnerSearchQuery = effectiveQuery;
        _learnerSearchScope = effectiveScope;
      }
    });
    try {
      final activeCourseId = _selectedCategoryId;
      final page = await widget.client.listNotes(
        token: isAuthenticated ? _token : null,
        query: effectiveQuery,
        offset: nextOffset,
        limit: 20,
        courseId: (activeCourseId != null && activeCourseId > 0) ? activeCourseId : null,
        scope: effectiveScope,
      );
      final rows = (page['results'] as List<dynamic>? ?? const [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
      setState(() {
        _learnerNotes = reset ? rows : [..._learnerNotes, ...rows];
        _hasMoreLearnerNotes = page['has_more'] == true;
        _learnerNotesOffset =
            (reset ? 0 : _learnerNotesOffset) + rows.length;
        _isLoadingMoreNotes = false;
      });
    } catch (error) {
      setState(() {
        _isLoadingMoreNotes = false;
        _errorMessage = error.toString().replaceFirst('Exception: ', '');
      });
      _appendUiLog(
          'Learner notes load failed: ${error.toString().replaceFirst('Exception: ', '')}');
    }
  }

  Future<void> _selectCourse(Map<String, dynamic> course) async {
    final courseId = (course['id'] as num?)?.toInt();
    setState(() {
      _selectedCourse = course;
      _selectedCategoryId = courseId;
      _selectedIndex = 1;
      _selectedNote = null;
    });
    _replaceNoteUrl(null);
    if (_isLocalCourse(course)) {
      _appendUiLog('Opened local category ${course['title']}.');
    } else {
      _appendUiLog('Opened category ${course['title']}.');
    }
    await _loadLearnerNotes(reset: true, query: _learnerSearchQuery);
  }

  Future<void> _selectNote(Map<String, dynamic> noteSummary) async {
    setState(() => _isLoading = true);
    try {
      final detail = await _fetchNoteDetail(noteSummary['id'] as int);
      setState(() {
        _selectedNote = detail;
        _selectedIndex = 1;
        _isLoading = false;
      });
      final uuid = detail['uuid']?.toString();
      if (uuid != null) _pushNoteUrl(uuid);
    } catch (error) {
      setState(() {
        _errorMessage = error.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
      });
      _appendUiLog(
          'Note selection failed: ${error.toString().replaceFirst('Exception: ', '')}');
    }
  }


  Future<Map<String, dynamic>> _fetchNoteDetail(int noteId) async {
    if (noteId < 0) {
      final draft = _localDrafts.firstWhere(
        (item) => item['id'] == noteId,
        orElse: () => <String, dynamic>{},
      );
      if (draft.isEmpty) throw Exception('Local draft not found.');
      setState(() => _selectedNote = draft);
      return draft;
    }
    final detail = await widget.client.getNoteDetail(noteId, token: _token);
    setState(() => _selectedNote = detail);
    return detail;
  }

  // ---------------------------------------------------------------------------
  // Authentication
  // ---------------------------------------------------------------------------
  Future<ActionFeedback> _register(
    String username,
    String email,
    String password, {
    String invitationCode = '',
  }) async {
    try {
      final result = await widget.client.register(
        username,
        email,
        password,
        invitationCode: invitationCode,
      );
      return ActionFeedback(
          message:
              result['message']?.toString() ?? 'Verification email sent.');
    } catch (error) {
      return ActionFeedback(
          message: error.toString().replaceFirst('Exception: ', ''),
          isError: true);
    }
  }

  Future<ActionFeedback> _verify(String email, String code) async {
    try {
      final result = await widget.client.verifyEmail(email, code);
      await _applyAuthPayload(result);
      return const ActionFeedback(
          message: 'Email verified. You are now signed in.');
    } catch (error) {
      return ActionFeedback(
          message: error.toString().replaceFirst('Exception: ', ''),
          isError: true);
    }
  }

  Future<ActionFeedback> _resendVerification(String email) async {
    try {
      final result = await widget.client.resendVerification(email);
      return ActionFeedback(
          message: result['message']?.toString() ??
              'Verification code resent.');
    } catch (error) {
      return ActionFeedback(
          message: error.toString().replaceFirst('Exception: ', ''),
          isError: true);
    }
  }

  Future<ActionFeedback> _login(String email, String password) async {
    try {
      final result = await widget.client.login(email, password);
      await _applyAuthPayload(result);
      return const ActionFeedback(message: 'Login successful.');
    } catch (error) {
      return ActionFeedback(
          message: error.toString().replaceFirst('Exception: ', ''),
          isError: true);
    }
  }

  Future<ActionFeedback> _requestPasswordReset(String email) async {
    try {
      final result = await widget.client.requestPasswordReset(email);
      return ActionFeedback(
          message: result['message']?.toString() ??
              'Password reset email sent.');
    } catch (error) {
      return ActionFeedback(
          message: error.toString().replaceFirst('Exception: ', ''),
          isError: true);
    }
  }

  Future<ActionFeedback> _confirmPasswordReset(
      String email, String code, String password) async {
    try {
      final result =
          await widget.client.confirmPasswordReset(email, code, password);
      return ActionFeedback(
          message: result['message']?.toString() ?? 'Password updated.');
    } catch (error) {
      return ActionFeedback(
          message: error.toString().replaceFirst('Exception: ', ''),
          isError: true);
    }
  }

  Map<String, dynamic> _currentAppSettingsPayload({
    String? themePreset,
    String? themeMode,
    String? apiBaseUrl,
  }) {
    final existingLogPrefs = Map<String, dynamic>.from(
        _localSettings['log_preferences'] as Map? ?? {});
    final effectiveApiBase =
        (apiBaseUrl ?? _localSettings['api_base_url'] ?? _defaultApiBaseUrl())
            .toString()
            .trim();
    return {
      'theme_preset': themePreset ?? _localSettings['theme_preset'] ?? 'teal',
      'theme_mode': themeMode ?? _localSettings['theme_mode'] ?? 'S',
      'api_base_url': effectiveApiBase.startsWith('/')
          ? _defaultApiBaseUrl()
          : effectiveApiBase,
      'log_preferences': existingLogPrefs,
    };
  }

  Future<void> _applyLocalAppSettings(Map<String, dynamic> settings,
      {bool persist = true}) async {
    final normalizedApiBase = (settings['api_base_url']?.toString() ??
            _localSettings['api_base_url']?.toString() ??
            _defaultApiBaseUrl())
        .trim();
    _localSettings = {
      ..._localSettings,
      ...settings,
      'api_base_url': normalizedApiBase.startsWith('/')
          ? _defaultApiBaseUrl()
          : normalizedApiBase,
    };
    _httpClient?.updateBaseUrl(
      _localSettings['api_base_url']?.toString() ?? _defaultApiBaseUrl(),
    );
    widget.onThemeChanged?.call(
      _localSettings['theme_preset']?.toString() ?? 'teal',
      _localSettings['theme_mode']?.toString() ?? 'S',
    );
    if (persist) await _persistLocalSettings();
  }

  DateTime _parseUpdatedAt(String? raw) {
    return DateTime.tryParse(raw ?? '')?.toUtc() ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  }

  Future<void> _applyAuthPayload(Map<String, dynamic> payload) async {
    final token = payload['token']?.toString() ?? '';
    final user = Map<String, dynamic>.from(payload['user'] as Map? ?? {});
    Map<String, dynamic> settings;
    try {
      settings = await widget.client.getSettings(token);
      final localUpdated =
          _parseUpdatedAt(_localSettings['updated_at']?.toString());
      final serverUpdated =
          _parseUpdatedAt(settings['app_settings_updated_at']?.toString());
      if (localUpdated.isAfter(serverUpdated)) {
        settings = await widget.client.updateSettings(token, {
          'app_settings': _currentAppSettingsPayload(),
          'app_settings_updated_at': _localSettings['updated_at'],
          'theme_preset': _localSettings['theme_preset'],
          'theme_mode': _localSettings['theme_mode'],
          'api_base_url': _localSettings['api_base_url'],
        });
      } else {
        final serverAppSettings = Map<String, dynamic>.from(
          settings['app_settings'] as Map? ??
              _currentAppSettingsPayload(
                themePreset: settings['theme_preset']?.toString(),
                themeMode: settings['theme_mode']?.toString(),
                apiBaseUrl: settings['api_base_url']?.toString(),
              ),
        );
        await _applyLocalAppSettings({
          ...serverAppSettings,
          'updated_at': settings['app_settings_updated_at']?.toString() ??
              DateTime.now().toUtc().toIso8601String(),
        });
      }
    } catch (error) {
      settings = {
        'username': user['username'],
        'email': user['email'],
        'editor_mode': _settings?['editor_mode'] ?? 'P',
        'theme_preset': _localSettings['theme_preset'],
        'theme_mode': _localSettings['theme_mode'],
        'api_base_url': _localSettings['api_base_url'],
        'app_settings': _currentAppSettingsPayload(),
        'app_settings_updated_at': _localSettings['updated_at'] ??
            DateTime.now().toUtc().toIso8601String(),
      };
      _appendUiLog(
          'Settings bootstrap after login fell back to local state: ${error.toString().replaceFirst('Exception: ', '')}');
    }
    setState(() {
      _token = token;
      _profile = user;
      _settings = settings;
    });
    await _LocalAppStore.saveSession(token, user);
    await _applyLocalAppSettings({
      'theme_preset': settings['theme_preset']?.toString() ??
          _localSettings['theme_preset'],
      'theme_mode':
          settings['theme_mode']?.toString() ?? _localSettings['theme_mode'],
      'api_base_url': settings['api_base_url']?.toString() ??
          _localSettings['api_base_url'],
      'updated_at': settings['app_settings_updated_at']?.toString() ??
          _localSettings['updated_at'],
      'log_preferences': Map<String, dynamic>.from(
        (settings['app_settings'] as Map?)?['log_preferences'] as Map? ??
            _localSettings['log_preferences'] as Map? ??
            {},
      ),
    });
    await _loadInitialData();
    await _syncAllLocalData(showMessage: false);
    _appendUiLog(
        'Authenticated as ${user['username'] ?? user['email'] ?? 'user'}.');
  }

  Future<void> _logout() async {
    final token = _token;
    if (token == null || token.isEmpty) return;
    try {
      await widget.client.logout(token);
    } catch (error) {
      _appendUiLog(
          'Cloud logout failed, cleared local session anyway: ${error.toString().replaceFirst('Exception: ', '')}');
    }
    setState(() {
      _token = null;
      _profile = null;
      _settings = null;
      _deletedNotes = const [];
    });
    await _LocalAppStore.clearSession();
    await _loadInitialData();
    _showMessage('Signed out.');
    _appendUiLog('Signed out.');
  }

  // ---------------------------------------------------------------------------
  // Settings
  // ---------------------------------------------------------------------------
  bool _sameTrimmedValue(String a, String b) => a.trim() == b.trim();

  bool _sameEmailValue(String a, String b) =>
      a.trim().toLowerCase() == b.trim().toLowerCase();

  String _summarizeChangedFields(List<String> fields) {
    final unique = <String>[];
    for (final field in fields) {
      if (field.isEmpty || unique.contains(field)) continue;
      unique.add(field);
    }
    if (unique.isEmpty) return 'settings';
    if (unique.length == 1) return unique.first;
    if (unique.length == 2) return '${unique.first} and ${unique.last}';
    return '${unique[0]}, ${unique[1]} +${unique.length - 2}';
  }

  Future<ActionFeedback> _updateSettings(
    String username,
    String email,
    String motto,
    String socialLink,
    String editorMode,
    String themePreset,
    String themeMode,
    String apiBaseUrl, {
    String firstName = '',
    String lastName = '',
  }) async {
    final currentSettings =
        Map<String, dynamic>.from(_settings ?? const {});
    final currentProfile = Map<String, dynamic>.from(_profile ?? const {});
    final currentUsername = currentSettings['username']?.toString() ??
        currentProfile['username']?.toString() ??
        '';
    final currentEmail = currentSettings['email']?.toString() ??
        currentProfile['email']?.toString() ??
        '';
    final currentMotto = currentSettings['motto']?.toString() ?? '';
    final currentSocialLink =
        currentSettings['social_link']?.toString() ?? '';
    final currentEditorMode =
        currentSettings['editor_mode']?.toString() ?? 'P';
    final currentThemePreset =
        _localSettings['theme_preset']?.toString() ?? 'teal';
    final currentThemeMode =
        _localSettings['theme_mode']?.toString() ?? 'S';
    final currentApiBase =
        _localSettings['api_base_url']?.toString() ?? _defaultApiBaseUrl();
    final nextApiBase =
        apiBaseUrl.trim().isEmpty || apiBaseUrl.trim().startsWith('/')
            ? _defaultApiBaseUrl()
            : apiBaseUrl.trim();
    final changedFields = <String>[];
    final remotePayload = <String, dynamic>{};
    if (!_sameTrimmedValue(username, currentUsername)) {
      remotePayload['username'] = username;
      changedFields.add('username');
    }
    if (!_sameEmailValue(email, currentEmail)) {
      remotePayload['email'] = email;
      changedFields.add('email');
    }
    final currentFirstName = currentSettings['first_name']?.toString() ??
        currentProfile['first_name']?.toString() ??
        '';
    final currentLastName = currentSettings['last_name']?.toString() ??
        currentProfile['last_name']?.toString() ??
        '';
    if (!_sameTrimmedValue(firstName, currentFirstName)) {
      remotePayload['first_name'] = firstName;
      changedFields.add('first name');
    }
    if (!_sameTrimmedValue(lastName, currentLastName)) {
      remotePayload['last_name'] = lastName;
      changedFields.add('last name');
    }
    if (!_sameTrimmedValue(motto, currentMotto)) {
      remotePayload['motto'] = motto;
      changedFields.add('motto');
    }
    if (!_sameTrimmedValue(socialLink, currentSocialLink)) {
      remotePayload['social_link'] = socialLink;
      changedFields.add('social link');
    }
    if (editorMode != currentEditorMode) {
      remotePayload['editor_mode'] = editorMode;
      changedFields.add('editor mode');
    }
    final localSettingsChanged = themePreset != currentThemePreset ||
        themeMode != currentThemeMode ||
        !_sameTrimmedValue(nextApiBase, currentApiBase);
    if (themePreset != currentThemePreset || themeMode != currentThemeMode) {
      changedFields.add('theme');
    }
    if (!_sameTrimmedValue(nextApiBase, currentApiBase)) {
      changedFields.add('API base');
    }
    final updatedAt = DateTime.now().toUtc().toIso8601String();
    await _applyLocalAppSettings({
      ..._currentAppSettingsPayload(
        themePreset: themePreset,
        themeMode: themeMode,
        apiBaseUrl: nextApiBase,
      ),
      'updated_at': updatedAt,
    });
    _localStats = {
      ..._localStats,
      'settings_saves':
          ((_localStats['settings_saves'] as num?)?.toInt() ?? 0) + 1,
    };
    await _persistLocalStats();
    if (remotePayload.isEmpty && !localSettingsChanged) {
      return const ActionFeedback(message: 'No changes.');
    }
    final token = _token;
    if (token == null || token.isEmpty) {
      return const ActionFeedback(message: 'Saved locally.');
    }
    try {
      if (localSettingsChanged) {
        remotePayload.addAll({
          'theme_preset': themePreset,
          'theme_mode': themeMode,
          'api_base_url': nextApiBase,
          'app_settings': _currentAppSettingsPayload(
            themePreset: themePreset,
            themeMode: themeMode,
            apiBaseUrl: nextApiBase,
          ),
          'app_settings_updated_at': updatedAt,
        });
      }
      final updated = await widget.client.updateSettings(token, {
        ...remotePayload,
      });
      setState(() {
        _settings = updated;
        _profile = {
          ...?_profile,
          'username': updated['username'],
          'email': updated['email'],
          'motto': updated['motto'],
          'social_link': updated['social_link'],
          'image_url': updated['image_url'],
          'is_staff': updated['is_staff'] ?? _profile?['is_staff'],
          'is_superuser':
              updated['is_superuser'] ?? _profile?['is_superuser'],
        };
      });
      final summary = _summarizeChangedFields(changedFields);
      _showMessage('Saved $summary.');
      _appendUiLog('Settings updated: $summary.');
      return ActionFeedback(message: 'Saved $summary.');
    } catch (error) {
      final detail = error.toString().replaceFirst('Exception: ', '');
      final fallbackUsername = _profile?['username'];
      final fallbackEmail = _profile?['email'];
      setState(() {
        _settings = {
          ...?_settings,
          if (remotePayload.containsKey('username')) 'username': username,
          if (remotePayload.containsKey('email')) 'email': email,
          if (remotePayload.containsKey('motto')) 'motto': motto,
          if (remotePayload.containsKey('social_link'))
            'social_link': socialLink,
          if (remotePayload.containsKey('editor_mode'))
            'editor_mode': editorMode,
          if (localSettingsChanged) 'theme_preset': themePreset,
          if (localSettingsChanged) 'theme_mode': themeMode,
          if (localSettingsChanged) 'api_base_url': nextApiBase,
        };
        _profile = {
          ...?_profile,
          'username':
              remotePayload.containsKey('username') && username.isNotEmpty
                  ? username
                  : fallbackUsername,
          'email': remotePayload.containsKey('email') && email.isNotEmpty
              ? email
              : fallbackEmail,
          'motto': remotePayload.containsKey('motto')
              ? motto
              : _profile?['motto'],
          'social_link': remotePayload.containsKey('social_link')
              ? socialLink
              : _profile?['social_link'],
        };
      });
      final summary = _summarizeChangedFields(changedFields);
      _appendUiLog('Cloud settings sync failed for $summary: $detail');
      return ActionFeedback(
          message: 'Saved locally. Sync pending for $summary.');
    }
  }

  Future<ActionFeedback> _uploadAvatar() async {
    final token = _token;
    if (token == null || token.isEmpty) {
      return const ActionFeedback(
          message: 'Sign in first to update your avatar.', isError: true);
    }
    try {
      final file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(
              label: 'Images', extensions: ['png', 'jpg', 'jpeg', 'webp']),
        ],
      );
      if (file == null) {
        return const ActionFeedback(message: 'Avatar update cancelled.');
      }
      final bytes = await file.readAsBytes();
      if (!mounted) {
        return const ActionFeedback(message: 'Avatar update cancelled.');
      }
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => _AvatarPreviewDialog(imageBytes: bytes),
      );
      if (confirmed != true) {
        return const ActionFeedback(message: 'Avatar update cancelled.');
      }
      final updated = await widget.client.uploadAvatar(token, file);
      _localStats = {
        ..._localStats,
        'avatar_updates':
            ((_localStats['avatar_updates'] as num?)?.toInt() ?? 0) + 1,
      };
      await _persistLocalStats();
      // Bust the image cache so the new avatar displays immediately.
      final rawUrl = updated['image_url']?.toString() ?? '';
      final bustUrl = rawUrl.isNotEmpty
          ? '$rawUrl${rawUrl.contains('?') ? '&' : '?'}t=${DateTime.now().millisecondsSinceEpoch}'
          : rawUrl;
      imageCache.clear();
      imageCache.clearLiveImages();
      setState(() {
        _settings = {...updated, 'image_url': bustUrl};
        _profile = {
          ...?_profile,
          'image_url': bustUrl,
          'username': updated['username'] ?? _profile?['username'],
          'email': updated['email'] ?? _profile?['email'],
          'is_staff': updated['is_staff'] ?? _profile?['is_staff'],
          'is_superuser':
              updated['is_superuser'] ?? _profile?['is_superuser'],
        };
      });
      _appendUiLog('Avatar updated.');
      return const ActionFeedback(message: 'Avatar updated.');
    } catch (error) {
      final message = error.toString().replaceFirst('Exception: ', '');
      _appendUiLog('Avatar update failed: $message');
      return ActionFeedback(message: message, isError: true);
    }
  }

  // ---------------------------------------------------------------------------
  // Category (course) management
  // ---------------------------------------------------------------------------

  /// Creates a new category. Cloud if signed in, otherwise local.
  Future<ActionFeedback> _createCategory(String title, {int? icon}) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) {
      return const ActionFeedback(
          message: 'Category name cannot be empty.', isError: true);
    }
    final token = _token;
    try {
      if (token != null && token.isNotEmpty) {
        final created = await widget.client.createCourse(token, {
          'title': trimmed,
          'description': '',
          if (icon != null) 'icon': icon,
        });
        final decorated = _decorateRemoteCourse(created);
        setState(() {
          _courses = [decorated, ..._courses];
        });
        await _persistLocalCache();
        _appendUiLog("Created category '$trimmed'.");
      } else {
        final localCourse = _buildLocalCourse(title: trimmed);
        if (icon != null) localCourse['icon'] = icon;
        setState(() {
          _localCourses = [..._localCourses, localCourse];
        });
        await _persistLocalCourses();
        _appendUiLog("Created local category '$trimmed'.");
      }
      return ActionFeedback(message: "Created '$trimmed'.");
    } catch (error) {
      final message = error.toString().replaceFirst('Exception: ', '');
      _appendUiLog('Create category failed: $message');
      return ActionFeedback(message: message, isError: true);
    }
  }

  /// Updates a category title and/or icon. Handles local-only and cloud courses.
  Future<ActionFeedback> _updateCategory(
    Map<String, dynamic> course,
    String newTitle, {
    int? icon,
  }) async {
    final trimmed = newTitle.trim();
    if (trimmed.isEmpty) {
      return const ActionFeedback(
          message: 'Category name cannot be empty.', isError: true);
    }
    if (course['is_default'] == true) {
      return const ActionFeedback(
          message: 'The default category cannot be edited.', isError: true);
    }
    final courseId = (course['id'] as num?)?.toInt();
    final isLocal = _isLocalCourse(course);
    try {
      if (isLocal) {
        setState(() {
          _localCourses = _localCourses
              .map((item) => item['id'] == course['id']
                  ? {...item, 'title': trimmed, 'icon': icon}
                  : item)
              .toList(growable: false);
          if ((_selectedCourse?['id'] as num?)?.toInt() == courseId) {
            _selectedCourse = {
              ...?_selectedCourse,
              'title': trimmed,
              'icon': icon,
            };
          }
        });
        await _persistLocalCourses();
      } else {
        final token = _token;
        if (token == null || token.isEmpty || courseId == null) {
          return const ActionFeedback(
              message: 'Sign in to edit cloud categories.', isError: true);
        }
        final updated = await widget.client.updateCourse(
          token,
          courseId,
          {'title': trimmed, 'icon': icon},
        );
        final decorated = _decorateRemoteCourse(updated);
        setState(() {
          _courses = _courses
              .map((item) => (item['id'] as num?)?.toInt() == courseId
                  ? decorated
                  : item)
              .toList(growable: false);
          if ((_selectedCourse?['id'] as num?)?.toInt() == courseId) {
            _selectedCourse = decorated;
          }
        });
        await _persistLocalCache();
      }
      _appendUiLog("Updated category '$trimmed'.");
      return ActionFeedback(message: "Updated '$trimmed'.");
    } catch (error) {
      final message = error.toString().replaceFirst('Exception: ', '');
      _appendUiLog('Update category failed: $message');
      return ActionFeedback(message: message, isError: true);
    }
  }

  /// Deletes a category. Notes in it are moved to the user's default category.
  Future<ActionFeedback> _deleteCategory(Map<String, dynamic> course) async {
    if (course['is_default'] == true) {
      return const ActionFeedback(
          message: 'The default category cannot be deleted.', isError: true);
    }
    final courseId = (course['id'] as num?)?.toInt();
    final isLocal = _isLocalCourse(course);
    try {
      if (isLocal) {
        // Find the local default (Inbox) category to reassign notes.
        final defaultLocal = _localCourses.cast<Map<String, dynamic>?>().firstWhere(
          (c) => c?['is_default'] == true && c?['id'] != course['id'],
          orElse: () => null,
        );
        final defaultLocalId = (defaultLocal?['id'] as num?)?.toInt();
        setState(() {
          _localCourses = _localCourses
              .where((item) => item['id'] != course['id'])
              .toList(growable: false);
          // Move drafts from the deleted category into the default category.
          if (courseId != null && defaultLocalId != null) {
            _localDrafts = _localDrafts.map((draft) {
              if (_draftCourseId(draft) != courseId) return draft;
              return _remapDraftCourseId(draft, courseId, defaultLocalId);
            }).toList(growable: false);
          } else {
            // Fallback: strip course_id so they at least remain visible.
            _localDrafts = _localDrafts.map((draft) {
              if (_draftCourseId(draft) != courseId) return draft;
              final metadata = _decodeNoteMetadata(
                  draft['metadata_json']?.toString() ?? '{}');
              metadata.remove('course_id');
              return {
                ...draft,
                'metadata_json': jsonEncode(metadata),
              };
            }).toList(growable: false);
          }
          if ((_selectedCourse?['id'] as num?)?.toInt() == courseId) {
            _selectedCourse = defaultLocal;
            _selectedCategoryId = defaultLocalId;
          }
        });
        await _persistLocalCourses();
        await _persistLocalDrafts();
      } else {
        final token = _token;
        if (token == null || token.isEmpty || courseId == null) {
          return const ActionFeedback(
              message: 'Sign in to delete cloud categories.', isError: true);
        }
        await widget.client.deleteCourse(token, courseId);
        // Find the remote default category to land on after deletion.
        final defaultRemote = _courses.cast<Map<String, dynamic>?>().firstWhere(
          (c) => c?['is_default'] == true && (c?['id'] as num?)?.toInt() != courseId,
          orElse: () => null,
        );
        setState(() {
          _courses = _courses
              .where((item) => (item['id'] as num?)?.toInt() != courseId)
              .toList(growable: false);
          if ((_selectedCourse?['id'] as num?)?.toInt() == courseId) {
            _selectedCourse = defaultRemote;
            _selectedCategoryId = (defaultRemote?['id'] as num?)?.toInt();
          }
        });
        await _persistLocalCache();
        await _loadLearnerNotes(reset: true, query: _learnerSearchQuery);
      }
      _appendUiLog("Deleted category '${course['title']}'.");
      return ActionFeedback(
          message: "Deleted '${course['title']}'. Notes moved to default.");
    } catch (error) {
      final message = error.toString().replaceFirst('Exception: ', '');
      _appendUiLog('Delete category failed: $message');
      return ActionFeedback(message: message, isError: true);
    }
  }

  /// Renders a single sidebar category row with the shared tooltip, long-press,
  /// and right-click handlers. Pulled out so the pinned Inbox row and the
  /// draggable rows inside the reorderable list share the exact same look.
  Widget _buildCategoryRow(Map<String, dynamic> cat) {
    return Tooltip(
      message: cat['is_default'] == true
          ? cat['title']?.toString() ?? 'Category'
          : 'Long-press or right-click to rename or delete. Drag to reorder.',
      waitDuration: const Duration(milliseconds: 600),
      child: GestureDetector(
        onLongPress: () => _promptEditCategory(cat),
        onSecondaryTap: () => _promptEditCategory(cat),
        child: _SidebarItem(
          icon: cat['is_local_course'] == true
              ? Icons.folder_outlined
              : (cat['is_default'] == true
                  ? Icons.inbox_outlined
                  : Icons.school_outlined),
          label: cat['title']?.toString() ?? 'Category',
          selected:
              _selectedCategoryId == (cat['id'] as num?)?.toInt(),
          onTap: () => _selectCourse(cat),
        ),
      ),
    );
  }

  /// Applies a new ordering for the draggable categories in the sidebar. The
  /// default Inbox is pinned and never included in [newOrder]. Local-only
  /// categories are reordered in memory; remote ones are persisted through
  /// `/courses/reorder/` so the order survives across sessions.
  Future<void> _reorderCategories(List<Map<String, dynamic>> newOrder) async {
    // Split the drag result into local vs cloud buckets. Local drafts keep the
    // in-memory order the user just chose; cloud courses get persisted.
    final newLocal = <Map<String, dynamic>>[];
    final newRemote = <Map<String, dynamic>>[];
    for (final course in newOrder) {
      if (_isLocalCourse(course)) {
        newLocal.add(course);
      } else {
        newRemote.add(course);
      }
    }

    setState(() {
      _localCourses = List<Map<String, dynamic>>.from(newLocal);
      _courses = List<Map<String, dynamic>>.from(newRemote);
    });

    // Persist local ordering regardless of auth state.
    await _persistLocalCourses();

    final token = _token;
    if (token == null || token.isEmpty || newRemote.isEmpty) {
      _appendUiLog('Reordered categories locally.');
      return;
    }

    final remoteIds = <int>[
      for (final course in newRemote)
        if ((course['id'] as num?) != null) (course['id'] as num).toInt(),
    ];
    try {
      final refreshed = await widget.client.reorderCourses(token, remoteIds);
      final decorated =
          refreshed.map(_decorateRemoteCourse).toList(growable: false);
      setState(() {
        _courses = decorated;
      });
      await _persistLocalCache();
      _appendUiLog('Reordered ${remoteIds.length} cloud categories.');
    } catch (error) {
      final message = error.toString().replaceFirst('Exception: ', '');
      _appendUiLog('Reorder categories failed: $message');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Reorder failed: $message')),
        );
      }
    }
  }

  /// Shows a dialog to create a new category with optional icon.
  Future<void> _promptCreateCategory() async {
    final controller = TextEditingController();
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => _CreateCategoryDialog(controller: controller),
    );
    controller.dispose();
    if (result == null) return;
    final title = result['title'] as String? ?? '';
    if (title.trim().isEmpty) return;
    final icon = result['icon'] as int?;
    await _createCategory(title, icon: icon);
  }

  /// Shows an edit dialog for a category (rename + icon + delete).
  Future<void> _promptEditCategory(Map<String, dynamic> course) async {
    if (course['is_default'] == true) {
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.inbox_outlined),
              const SizedBox(width: 8),
              Text(course['title']?.toString() ?? 'Inbox'),
            ],
          ),
          content: const Text(
            'This is the default category. It cannot be renamed or deleted.\n\n'
            'Notes that lose their category are automatically moved here.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }
    final controller =
        TextEditingController(text: course['title']?.toString() ?? '');
    final currentIcon = (course['icon'] as num?)?.toInt();
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => _EditCategoryDialog(
        controller: controller,
        initialIcon: currentIcon,
      ),
    );
    controller.dispose();
    if (result == null) return;
    final action = result['action'] as String;
    if (action == 'delete') {
      final confirmed = await _confirmWithDelay(
        title: 'Delete category?',
        message:
            "'${course['title']}' will be removed. All notes inside will move to the default category.",
      );
      if (confirmed) {
        final feedback = await _deleteCategory(course);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(feedback.message)),
          );
        }
      }
    } else if (action == 'save') {
      final newTitle = result['title'] as String? ?? '';
      final newIcon = result['icon'] as int?;
      final feedback = await _updateCategory(course, newTitle, icon: newIcon);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(feedback.message)),
        );
      }
    }
  }

  /// Shows a confirmation dialog with a 3-second delay before enabling the
  /// destructive action button. Used for clear-data style operations.
  Future<bool> _confirmWithDelay({
    required String title,
    required String message,
    String confirmLabel = 'Delete',
    int delaySeconds = 3,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => _ConfirmWithDelayDialog(
        title: title,
        message: message,
        confirmLabel: confirmLabel,
        delaySeconds: delaySeconds,
      ),
    );
    return result == true;
  }

  // ---------------------------------------------------------------------------
  // Local course & draft building
  // ---------------------------------------------------------------------------
  Map<String, dynamic> _buildLocalCourse({
    required String title,
    String description = '',
    String? clientCourseId,
    String? createdAt,
    int? id,
  }) {
    final nowIso = DateTime.now().toUtc().toIso8601String();
    final effectiveTitle =
        title.trim().isEmpty ? 'Untitled course' : title.trim();
    final ownerLabel = _profile?['username']?.toString() ?? 'Local';
    return {
      'id': id ?? -DateTime.now().microsecondsSinceEpoch,
      'client_course_id': clientCourseId ?? _LocalAppStore.newCourseId(),
      'slug': _slugifyLocalText(effectiveTitle, fallback: 'local-course'),
      'title': effectiveTitle,
      'description': description.trim(),
      'cover_image_url': '',
      'is_default': false,
      'is_subscribed': false,
      'subscriber_count': 0,
      'last_opened_at': nowIso,
      'date_created': createdAt ?? nowIso,
      'last_edit': nowIso,
      'is_local_course': true,
      'is_owned': true,
      'owner': {
        'username': ownerLabel,
        'display_name': ownerLabel,
        'image_url': '',
      },
      'recent_notes': const <Map<String, dynamic>>[],
      'media': const <Map<String, dynamic>>[],
    };
  }

  int? _draftCourseId(Map<String, dynamic> draft) {
    final metadata =
        _decodeNoteMetadata(draft['metadata_json']?.toString() ?? '{}');
    return (metadata['course_id'] as num?)?.toInt() ??
        (draft['course_id'] as num?)?.toInt();
  }

  Map<String, dynamic> _remapDraftCourseId(
    Map<String, dynamic> draft,
    int fromCourseId,
    int toCourseId,
  ) {
    final metadata =
        _decodeNoteMetadata(draft['metadata_json']?.toString() ?? '{}');
    if ((metadata['course_id'] as num?)?.toInt() == fromCourseId) {
      metadata['course_id'] = toCourseId;
    }
    return {
      ...draft,
      'course_id': toCourseId,
      'metadata_json': jsonEncode(metadata),
      'last_edit': DateTime.now().toUtc().toIso8601String(),
    };
  }

  Future<Map<String, dynamic>> _syncLocalCourse(
      Map<String, dynamic> course) async {
    final token = _token;
    if (token == null || token.isEmpty) {
      throw Exception('Sign in to sync local courses.');
    }
    final created = await widget.client.createCourse(token, {
      'title': course['title'],
      'description': course['description'] ?? '',
      'client_course_id': course['client_course_id'],
    });
    final localId = (course['id'] as num?)?.toInt();
    final remoteId = (created['id'] as num?)?.toInt();
    if (localId != null && remoteId != null) {
      _localDrafts = _localDrafts
          .map((draft) => _draftCourseId(draft) == localId
              ? _remapDraftCourseId(draft, localId, remoteId)
              : draft)
          .toList(growable: false);
    }
    final selectedCourseId = (_selectedCourse?['id'] as num?)?.toInt();
    _localCourses = _localCourses
        .where((item) => item['id'] != course['id'])
        .toList(growable: false);
    _courses = [
      _decorateRemoteCourse(created),
      ..._courses.where((item) => item['id'] != created['id']),
    ];
    if (selectedCourseId != null && selectedCourseId == localId) {
      _selectedCourse = _decorateRemoteCourse(created);
      _courseNotes = const [];
    }
    _localStats = {
      ..._localStats,
      'local_courses_synced':
          ((_localStats['local_courses_synced'] as num?)?.toInt() ?? 0) + 1,
      'last_sync_at': DateTime.now().toUtc().toIso8601String(),
    };
    await _persistLocalCourses();
    await _persistLocalDrafts();
    await _persistLocalStats();
    await _persistLocalCache();
    _appendUiLog("Synced local category '${course['title']}'.");
    return created;
  }

  Map<String, dynamic> _buildLocalDraft({
    required String title,
    required String content,
    String description = '',
    String editorMode = 'P',
    String? clientDraftId,
    String? createdAt,
    int? id,
    String metadataJson = '{}',
  }) {
    final nowIso = DateTime.now().toUtc().toIso8601String();
    final effectiveTitle =
        title.trim().isEmpty ? _extractTitleFromMarkdown(content) : title.trim();
    final body = _bodyWithoutTitle(content);
    return {
      'id': id ?? -DateTime.now().microsecondsSinceEpoch,
      'client_draft_id': clientDraftId ?? _LocalAppStore.newDraftId(),
      'title': effectiveTitle,
      'description':
          description.isEmpty ? _excerptFromMarkdown(content) : description,
      'content': _composeMarkdown(effectiveTitle, body),
      'metadata_json': metadataJson,
      'preview_lines': body
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .take(3)
          .toList(),
      'editor_mode': editorMode,
      'is_public': false,
      'course_id': null,
      'date_created': createdAt ?? nowIso,
      'last_edit': nowIso,
      'is_local_draft': true,
      'author': {
        'username': 'Local Draft',
        'display_name': 'Local Draft',
        'image_url': '',
      },
    };
  }

  // ---------------------------------------------------------------------------
  // Draft sync & pull
  // ---------------------------------------------------------------------------
  bool _sameNoteTitle(Map<String, dynamic> left, Map<String, dynamic> right) {
    final leftTitle = left['title']?.toString().trim().toLowerCase() ?? '';
    final rightTitle = right['title']?.toString().trim().toLowerCase() ?? '';
    return leftTitle.isNotEmpty && leftTitle == rightTitle;
  }

  Map<String, dynamic> _buildPulledLocalDraft(
    Map<String, dynamic> note, {
    Map<String, dynamic>? existingDraft,
  }) {
    final sourceAccount =
        _profile?['username']?.toString().trim().isNotEmpty == true
            ? _profile!['username'].toString().trim()
            : _profile?['email']?.toString().trim() ?? '';
    final metadata = {
      ..._decodeNoteMetadata(note['metadata_json']?.toString() ?? '{}'),
      'pulled_from_cloud_note_id': note['id'],
      'pulled_from_account': sourceAccount,
      'is_cloud_copy': true,
      'source_note_last_edit': note['last_edit']?.toString(),
    };
    return _buildLocalDraft(
      id: (existingDraft?['id'] as num?)?.toInt(),
      clientDraftId: existingDraft?['client_draft_id']?.toString(),
      createdAt: existingDraft?['date_created']?.toString() ??
          note['date_created']?.toString(),
      title: note['title']?.toString() ?? 'Untitled note',
      description: note['description']?.toString() ??
          note['excerpt']?.toString() ??
          '',
      content: note['content']?.toString() ?? _noteToMarkdown(note),
      editorMode: note['editor_mode']?.toString() ??
          existingDraft?['editor_mode']?.toString() ??
          'P',
      metadataJson: jsonEncode(metadata),
    );
  }

  Future<String?> _showPullConflictDialog({
    required Map<String, dynamic> localDraft,
    required Map<String, dynamic> remoteNote,
  }) async {
    if (!mounted) return null;
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Resolve note conflict'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'A local note and a cloud note share the title "${remoteNote['title'] ?? 'Untitled note'}".',
              ),
              const SizedBox(height: 16),
              Text('Local',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(
                localDraft['description']?.toString().isNotEmpty == true
                    ? localDraft['description'].toString()
                    : _excerptFromMarkdown(
                        localDraft['content']?.toString() ?? ''),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
              Text('Cloud',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(
                remoteNote['description']?.toString().isNotEmpty == true
                    ? remoteNote['description'].toString()
                    : remoteNote['excerpt']?.toString() ?? '',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop('local'),
              child: const Text('Keep local')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop('cloud'),
              child: const Text('Use server')),
        ],
      ),
    );
  }

  Future<ActionFeedback> _pullCloudNotesToLocal() async {
    final token = _token;
    if (token == null || token.isEmpty) {
      return const ActionFeedback(
          message: 'Sign in to pull cloud notes.', isError: true);
    }
    try {
      final pulledDrafts = List<Map<String, dynamic>>.from(_localDrafts);
      var imported = 0;
      var updated = 0;
      var skipped = 0;
      var offset = 0;
      var hasMore = true;
      while (hasMore) {
        final page = await widget.client
            .listNotes(token: token, offset: offset, limit: 50);
        final rows = (page['results'] as List<dynamic>? ?? const [])
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList(growable: false);
        hasMore = page['has_more'] == true && rows.isNotEmpty;
        offset += rows.length;
        for (final summary in rows) {
          final noteId = (summary['id'] as num?)?.toInt();
          if (noteId == null) continue;
          final detail =
              await widget.client.getNoteDetail(noteId, token: token);
          final pulledIndex = pulledDrafts.indexWhere((draft) {
            final metadata = _decodeNoteMetadata(
                draft['metadata_json']?.toString() ?? '{}');
            return (metadata['pulled_from_cloud_note_id'] as num?)
                    ?.toInt() ==
                noteId;
          });
          if (pulledIndex >= 0) {
            pulledDrafts[pulledIndex] = _buildPulledLocalDraft(detail,
                existingDraft: pulledDrafts[pulledIndex]);
            updated += 1;
            continue;
          }
          final conflictIndex = pulledDrafts
              .indexWhere((draft) => _sameNoteTitle(draft, detail));
          if (conflictIndex >= 0) {
            final decision = await _showPullConflictDialog(
                localDraft: pulledDrafts[conflictIndex],
                remoteNote: detail);
            if (!mounted) {
              return const ActionFeedback(
                  message: 'Cloud pull cancelled.', isError: true);
            }
            if (decision != 'cloud') {
              skipped += 1;
              continue;
            }
            pulledDrafts[conflictIndex] = _buildPulledLocalDraft(detail,
                existingDraft: pulledDrafts[conflictIndex]);
            updated += 1;
            continue;
          }
          pulledDrafts.insert(0, _buildPulledLocalDraft(detail));
          imported += 1;
        }
      }
      _localDrafts = List<Map<String, dynamic>>.unmodifiable(pulledDrafts);
      _localStats = {
        ..._localStats,
        'cloud_notes_pulled':
            ((_localStats['cloud_notes_pulled'] as num?)?.toInt() ?? 0) +
                imported +
                updated,
        'last_pull_at': DateTime.now().toUtc().toIso8601String(),
      };
      await _persistLocalDrafts();
      await _persistLocalStats();
      // Refresh remote courses and notes so the full cloud state is visible.
      await _loadInitialData();
      if (mounted) setState(() {});
      final segments = <String>[];
      if (imported > 0) segments.add('pulled $imported');
      if (updated > 0) segments.add('updated $updated');
      if (skipped > 0) segments.add('kept $skipped local');
      final message = segments.isEmpty
          ? 'Cloud notes already match local copies.'
          : segments.join(', ');
      _appendUiLog('Cloud pull completed: $message.');
      return ActionFeedback(message: message);
    } catch (error) {
      final message = error.toString().replaceFirst('Exception: ', '');
      _appendUiLog('Cloud pull failed: $message');
      return ActionFeedback(message: 'Pull failed.', isError: true);
    }
  }

  Future<Map<String, dynamic>> _syncLocalDraft(
      Map<String, dynamic> draft) async {
    final token = _token;
    if (token == null || token.isEmpty) {
      throw Exception('Sign in to sync local drafts.');
    }
    var metadata =
        _decodeNoteMetadata(draft['metadata_json']?.toString() ?? '{}');
    final assignedCourseId = (metadata['course_id'] as num?)?.toInt();
    if (assignedCourseId != null && assignedCourseId < 0) {
      Map<String, dynamic>? localCourse;
      for (final item in _localCourses) {
        if ((item['id'] as num?)?.toInt() == assignedCourseId) {
          localCourse = item;
          break;
        }
      }
      if (localCourse != null) {
        final syncedCourse = await _syncLocalCourse(localCourse);
        metadata = {...metadata, 'course_id': syncedCourse['id']};
        draft = _remapDraftCourseId(
            draft, assignedCourseId, syncedCourse['id'] as int);
      }
    }
    final pulledFromNoteId =
        (metadata['pulled_from_cloud_note_id'] as num?)?.toInt();
    final pulledFromAccount =
        metadata['pulled_from_account']?.toString().trim().toLowerCase() ??
            '';
    final currentAccount =
        (_profile?['username']?.toString().trim().isNotEmpty == true
                ? _profile!['username'].toString().trim()
                : _profile?['email']?.toString().trim() ?? '')
            .toLowerCase();
    if (pulledFromNoteId != null &&
        pulledFromNoteId > 0 &&
        pulledFromAccount.isNotEmpty &&
        pulledFromAccount == currentAccount) {
      final updated =
          await widget.client.updateNote(token, pulledFromNoteId, {
        'title': draft['title'],
        'description': draft['description'] ?? '',
        'content': draft['content'] ?? '',
        'editor_mode': draft['editor_mode'] ?? 'P',
        'course_id': metadata['course_id'],
        'metadata_json': jsonEncode(metadata),
        'is_public': false,
      });
      _localDrafts = _localDrafts
          .map((item) => item['id'] == draft['id']
              ? {
                  ...draft,
                  'last_edit': updated['last_edit'] ?? draft['last_edit'],
                  'metadata_json': jsonEncode({
                    ...metadata,
                    'source_note_last_edit': updated['last_edit'],
                  }),
                }
              : item)
          .toList(growable: false);
      _localStats = {
        ..._localStats,
        'local_drafts_synced':
            ((_localStats['local_drafts_synced'] as num?)?.toInt() ?? 0) + 1,
        'last_sync_at': DateTime.now().toUtc().toIso8601String(),
      };
      await _persistLocalDrafts();
      await _persistLocalStats();
      await _loadLearnerNotes(reset: true, query: _learnerSearchQuery);
      if (mounted) setState(() {});
      _appendUiLog("Synced local cloud copy '${draft['title']}'.");
      return updated;
    }
    final syncCourseId = (metadata['course_id'] as num?)?.toInt();
    final syncClientDraftId = draft['client_draft_id']?.toString();
    final created = await widget.client.createNote(token, <String, dynamic>{
      'title': draft['title'] ?? 'Untitled note',
      'description': draft['description'] ?? '',
      'content': draft['content'] ?? '',
      'editor_mode': draft['editor_mode'] ?? 'P',
      if (syncCourseId != null && syncCourseId > 0) 'course_id': syncCourseId,
      'metadata_json': jsonEncode(metadata),
      if (syncClientDraftId != null && syncClientDraftId.isNotEmpty)
        'client_draft_id': syncClientDraftId,
      'is_public': false,
    });
    _localDrafts = _localDrafts
        .where((item) => item['id'] != draft['id'])
        .toList(growable: false);
    _localStats = {
      ..._localStats,
      'local_drafts_synced':
          ((_localStats['local_drafts_synced'] as num?)?.toInt() ?? 0) + 1,
      'last_sync_at': DateTime.now().toUtc().toIso8601String(),
    };
    await _persistLocalDrafts();
    await _persistLocalStats();
    await _loadLearnerNotes(reset: true, query: _learnerSearchQuery);
    if (mounted) setState(() {});
    _appendUiLog("Synced local draft '${draft['title']}'.");
    return created;
  }

  // ---------------------------------------------------------------------------
  // Note CRUD
  // ---------------------------------------------------------------------------
  Future<Map<String, dynamic>> _createNote({
    String? markdown,
    String? title,
    String? description,
    String? clientDraftId,
  }) async {
    final token = _token;
    final mode = _settings?['editor_mode']?.toString() ??
        _profile?['editor_mode']?.toString() ??
        'P';
    final initialMarkdown =
        (markdown ?? '# ${title ?? 'Untitled note'}\n\n').trim();
    if (token == null || token.isEmpty) {
      final draft = _buildLocalDraft(
        title: title ?? _extractTitleFromMarkdown(initialMarkdown),
        content: initialMarkdown,
        description: description ?? '',
        editorMode: mode,
        clientDraftId: clientDraftId,
      );
      _localDrafts = [draft, ..._localDrafts];
      _localStats = {
        ..._localStats,
        'local_drafts_created':
            ((_localStats['local_drafts_created'] as num?)?.toInt() ?? 0) + 1,
      };
      await _persistLocalDrafts();
      await _persistLocalStats();
      setState(() {
        _selectedNote = draft;
        _selectedIndex = 1;
      });
      return draft;
    }
    final payload = <String, dynamic>{
      'title': title ?? _extractTitleFromMarkdown(initialMarkdown),
      'description':
          description ?? _excerptFromMarkdown(initialMarkdown),
      'content': initialMarkdown,
      'editor_mode': mode,
      'metadata_json': jsonEncode({'section': '', 'autosave': false}),
      if (clientDraftId != null) 'client_draft_id': clientDraftId,
    };
    try {
      final created = await widget.client.createNote(token, payload);
      await _loadLearnerNotes(reset: true, query: _learnerSearchQuery);
      setState(() {
        _selectedNote = created;
        _selectedIndex = 1;
      });
      final uuid = created['uuid']?.toString();
      if (uuid != null) _pushNoteUrl(uuid);
      return created;
    } catch (error) {
      final draft = _storeLocalDraft(
        _buildOfflineFallbackDraft(payload: payload),
        incrementCreated: true,
      );
      await _persistLocalDrafts();
      await _persistLocalStats();
      final message = error.toString().replaceFirst('Exception: ', '');
      setState(() {
        _selectedNote = draft;
        _selectedIndex = 1;
      });
      _appendUiLog(
          'Cloud create failed, saved local draft instead: $message');
      _showMessage('Backend unavailable. Saved as a local draft.');
      return draft;
    }
  }

  Future<Map<String, dynamic>> _saveNote(
      int noteId, Map<String, dynamic> payload) async {
    if (noteId < 0) {
      final existing = _localDrafts.firstWhere(
        (item) => item['id'] == noteId,
        orElse: () => <String, dynamic>{},
      );
      if (existing.isEmpty) throw Exception('Local draft not found.');
      final updated = _buildLocalDraft(
        id: noteId,
        title: payload['title']?.toString() ??
            existing['title']?.toString() ??
            'Untitled note',
        description: payload['description']?.toString() ??
            existing['description']?.toString() ??
            '',
        content: payload['content']?.toString() ??
            existing['content']?.toString() ??
            '',
        editorMode: payload['editor_mode']?.toString() ??
            existing['editor_mode']?.toString() ??
            'P',
        clientDraftId: existing['client_draft_id']?.toString(),
        createdAt: existing['date_created']?.toString(),
        metadataJson: payload['metadata_json']?.toString() ??
            existing['metadata_json']?.toString() ??
            '{}',
      );
      _localDrafts = _localDrafts
          .map((item) => item['id'] == noteId ? updated : item)
          .toList(growable: false);
      await _persistLocalDrafts();
      setState(() => _selectedNote = updated);
      return updated;
    }
    final token = _token;
    if (token == null || token.isEmpty) {
      throw Exception('Sign in to save cloud notes.');
    }
    try {
      final updated = await widget.client.updateNote(token, noteId, payload);
      await _loadLearnerNotes(reset: true, query: _learnerSearchQuery);
      setState(() => _selectedNote = updated);
      final uuid = updated['uuid']?.toString();
      if (uuid != null) _replaceNoteUrl(uuid);
      return updated;
    } catch (error) {
      final sourceNote = _selectedNote?['id'] == noteId
          ? Map<String, dynamic>.from(_selectedNote!)
          : null;
      final fallbackDraft = _storeLocalDraft(
        _buildOfflineFallbackDraft(sourceNote: sourceNote, payload: payload),
      );
      await _persistLocalDrafts();
      final message = error.toString().replaceFirst('Exception: ', '');
      setState(() => _selectedNote = fallbackDraft);
      _appendUiLog(
          'Cloud save failed, kept local draft instead: $message');
      _showMessage('Backend unavailable. Changes were saved locally.');
      return fallbackDraft;
    }
  }

  Future<Map<String, dynamic>> _uploadNoteAttachment(
      int noteId, XFile file) async {
    final token = _token;
    if (token == null || token.isEmpty) {
      throw Exception('Sign in to upload attachments.');
    }
    return widget.client.uploadNoteAttachment(token, noteId, file);
  }

  Future<List<Map<String, dynamic>>> _getNoteHistory(int noteId) async {
    final token = _token;
    if (token == null || token.isEmpty || noteId < 0) return const [];
    return widget.client.getNoteHistory(token, noteId);
  }

  Future<Map<String, dynamic>> _snapshotNote(int noteId,
      {String reason = 'manual'}) async {
    final token = _token;
    if (token == null || token.isEmpty || noteId < 0) {
      return {'id': noteId, 'reason': reason};
    }
    return widget.client.snapshotNote(token, noteId, reason: reason);
  }

  Future<Map<String, dynamic>> _restoreNoteVersion(
      int noteId, int versionId) async {
    final token = _token;
    if (token == null || token.isEmpty || noteId < 0) {
      throw Exception('Sign in to restore notes.');
    }
    final restored =
        await widget.client.restoreNoteVersion(token, noteId, versionId);
    await _loadLearnerNotes(reset: true, query: _learnerSearchQuery);
    setState(() => _selectedNote = restored);
    return restored;
  }

  /// Imports one or more notes from a markdown file or a zip archive. Mirrors
  /// the export flow: each note may carry a YAML frontmatter block whose
  /// `title`/`description`/`category` fields are round-tripped back into the
  /// created note. Zip archives iterate every `.md` entry at any depth so a
  /// recursive export can be re-imported in one step.
  Future<void> _importMarkdownNote() async {
    try {
      final file = await openFile(
        acceptedTypeGroups: [
          const XTypeGroup(
              label: 'Markdown or zip',
              extensions: ['md', 'markdown', 'txt', 'zip']),
        ],
      );
      if (file == null) return;
      final name = file.name.toLowerCase();
      if (name.endsWith('.zip')) {
        await _importNotesFromZip(file);
      } else {
        final contents = await file.readAsString();
        final parsed = _parseImportedMarkdown(contents);
        final created = await _createNote(
          markdown: parsed.body,
          title: parsed.title ?? _extractTitleFromMarkdown(parsed.body),
          description: parsed.description ?? '',
        );
        _showMessage("Imported '${created['title']}'.");
      }
    } catch (error) {
      _showMessage(error.toString().replaceFirst('Exception: ', ''));
    }
  }

  /// Decodes a zip archive and creates one note per `.md` entry.
  Future<void> _importNotesFromZip(XFile file) async {
    final bytes = await file.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    int importedCount = 0;
    int skippedCount = 0;
    for (final entry in archive) {
      if (!entry.isFile) continue;
      final lowerName = entry.name.toLowerCase();
      if (!(lowerName.endsWith('.md') || lowerName.endsWith('.markdown'))) {
        // Non-markdown entries (media, .metadata) are skipped — the current
        // import path only creates notes, not media attachments.
        skippedCount += 1;
        continue;
      }
      try {
        final content = utf8.decode(entry.content as List<int>);
        final parsed = _parseImportedMarkdown(content);
        // Fall back to the zip entry filename (without extension) when the
        // markdown has no title + no frontmatter.
        final fallbackTitle = entry.name.split('/').last.replaceAll(
              RegExp(r'\.(md|markdown)$', caseSensitive: false),
              '',
            );
        final derivedTitle = _extractTitleFromMarkdown(parsed.body);
        await _createNote(
          markdown: parsed.body,
          title: parsed.title ??
              (derivedTitle == 'Untitled note'
                  ? (fallbackTitle.isEmpty
                      ? 'Imported note'
                      : fallbackTitle)
                  : derivedTitle),
          description: parsed.description ?? '',
        );
        importedCount += 1;
      } catch (error) {
        _appendUiLog('Skipped "${entry.name}": $error');
        skippedCount += 1;
      }
    }
    if (importedCount == 0) {
      _showMessage('No markdown entries found in archive.');
    } else {
      final suffix = skippedCount > 0 ? ' ($skippedCount skipped)' : '';
      _showMessage('Imported $importedCount note(s) from zip.$suffix');
    }
  }

  /// Splits imported markdown into optional YAML frontmatter + body. Recognizes
  /// the exact frontmatter shape we emit during export (`title`, `description`,
  /// `category`, `author`, `last_edit`).
  _ImportedMarkdown _parseImportedMarkdown(String content) {
    final lines = content.split('\n');
    if (lines.isEmpty || lines.first.trim() != '---') {
      return _ImportedMarkdown(body: content);
    }
    final closingIndex = lines.indexWhere((l) => l.trim() == '---', 1);
    if (closingIndex < 0) {
      return _ImportedMarkdown(body: content);
    }
    final headerLines = lines.sublist(1, closingIndex);
    final body = lines.sublist(closingIndex + 1).join('\n').trimLeft();
    String? title;
    String? description;
    for (final line in headerLines) {
      final colonIdx = line.indexOf(':');
      if (colonIdx <= 0) continue;
      final key = line.substring(0, colonIdx).trim().toLowerCase();
      var value = line.substring(colonIdx + 1).trim();
      // Strip surrounding quotes from yaml-escape output.
      if (value.length >= 2 &&
          ((value.startsWith('"') && value.endsWith('"')) ||
              (value.startsWith("'") && value.endsWith("'")))) {
        value = value.substring(1, value.length - 1);
      }
      if (key == 'title') {
        title = value;
      } else if (key == 'description') {
        description = value;
      }
    }
    return _ImportedMarkdown(
      title: title,
      description: description,
      body: body,
    );
  }

  Future<void> _exportNote(Map<String, dynamic> note) async {
    try {
      final detail = note['content'] != null
          ? note
          : await _fetchNoteDetail(note['id'] as int);
      // Resolve category + sibling notes so the options dialog can show how
      // many notes a recursive export would include.
      final courseMap =
          Map<String, dynamic>.from(detail['course'] as Map? ?? const {});
      final courseId = courseMap['id'] as int?;
      final categoryTitle = courseMap['title']?.toString() ?? 'Category';
      final siblings = await _collectCategoryNotes(detail, courseId);

      if (!mounted) return;
      final options = await showDialog<_ExportOptions>(
        context: context,
        builder: (ctx) => _ExportOptionsDialog(
          noteTitle: detail['title']?.toString() ?? 'Untitled note',
          categoryTitle: categoryTitle,
          siblingCount: siblings.length,
        ),
      );
      if (options == null) return;

      final notesToExport = options.recursive ? siblings : [detail];
      final baseName = options.recursive
          ? _slugifyLocalText(categoryTitle, fallback: 'category')
          : _slugifyLocalText(
              detail['title']?.toString() ?? 'note',
              fallback: 'note');

      if (options.format == 'zip') {
        await _writeNotesAsZip(
          notes: notesToExport,
          baseName: baseName,
          includeMetadata: options.includeMetadata,
        );
      } else {
        await _writeNotesAsMarkdown(
          notes: notesToExport,
          baseName: baseName,
          includeMetadata: options.includeMetadata,
          combined: options.recursive,
        );
      }
    } catch (error) {
      _showMessage(error.toString().replaceFirst('Exception: ', ''));
    }
  }

  /// Returns the list of notes that share a category with [detail]. Falls back
  /// to the single note when no category info is available. Used by the export
  /// options dialog and the recursive export path.
  Future<List<Map<String, dynamic>>> _collectCategoryNotes(
      Map<String, dynamic> detail, int? courseId) async {
    if (courseId == null) {
      return [detail];
    }
    final local = _localDrafts
        .where((d) =>
            (Map<String, dynamic>.from(d['course'] as Map? ?? const {}))['id'] ==
            courseId)
        .map((d) => Map<String, dynamic>.from(d))
        .toList();
    List<Map<String, dynamic>> remote = const [];
    final token = _token;
    if (token != null && token.isNotEmpty && courseId >= 0) {
      try {
        final list = await widget.client.getCourseNotes(courseId, token: token);
        remote = [
          for (final n in list)
            n['content'] != null
                ? Map<String, dynamic>.from(n)
                : await _fetchNoteDetail(n['id'] as int),
        ];
      } catch (_) {
        remote = const [];
      }
    }
    final combined = <Map<String, dynamic>>[...local, ...remote];
    // Deduplicate by id, keep the richer (with content) version.
    final byId = <dynamic, Map<String, dynamic>>{};
    for (final n in combined) {
      final id = n['id'];
      if (!byId.containsKey(id) ||
          (byId[id]!['content'] == null && n['content'] != null)) {
        byId[id] = n;
      }
    }
    final result = byId.values.toList();
    if (result.isEmpty) result.add(detail);
    return result;
  }

  /// Builds YAML frontmatter block prepended to exported markdown when the
  /// user opts in to metadata.
  String _frontmatterForNote(Map<String, dynamic> note) {
    final author =
        Map<String, dynamic>.from(note['author'] as Map? ?? const {});
    final course =
        Map<String, dynamic>.from(note['course'] as Map? ?? const {});
    final buffer = StringBuffer('---\n');
    buffer.writeln('title: ${_yamlEscape(note['title']?.toString() ?? '')}');
    if ((author['username']?.toString() ?? '').isNotEmpty) {
      buffer.writeln('author: ${_yamlEscape(author['username'].toString())}');
    }
    if ((course['title']?.toString() ?? '').isNotEmpty) {
      buffer.writeln('category: ${_yamlEscape(course['title'].toString())}');
    }
    if ((note['last_edit']?.toString() ?? '').isNotEmpty) {
      buffer.writeln('last_edit: ${note['last_edit']}');
    }
    if ((note['description']?.toString() ?? '').isNotEmpty) {
      buffer.writeln(
          'description: ${_yamlEscape(note['description'].toString())}');
    }
    buffer.writeln('---');
    return buffer.toString();
  }

  String _yamlEscape(String value) {
    if (value.contains(':') || value.contains('#') || value.contains('\n')) {
      return '"${value.replaceAll('"', '\\"').replaceAll('\n', ' ')}"';
    }
    return value;
  }

  String _noteMarkdownBody(Map<String, dynamic> note) {
    return note['content']?.toString() ?? _noteToMarkdown(note);
  }

  /// Writes notes as a markdown file. When [combined] is true, all notes are
  /// concatenated with `---` separators into a single file.
  Future<void> _writeNotesAsMarkdown({
    required List<Map<String, dynamic>> notes,
    required String baseName,
    required bool includeMetadata,
    required bool combined,
  }) async {
    final location = await getSaveLocation(
      suggestedName: '$baseName.md',
      acceptedTypeGroups: [
        const XTypeGroup(label: 'Markdown', extensions: ['md']),
      ],
    );
    if (location == null) return;
    final buffer = StringBuffer();
    for (var i = 0; i < notes.length; i++) {
      final note = notes[i];
      if (includeMetadata) {
        buffer.writeln(_frontmatterForNote(note));
        buffer.writeln();
      }
      buffer.writeln(_noteMarkdownBody(note));
      if (combined && i < notes.length - 1) {
        buffer.writeln();
        buffer.writeln('---');
        buffer.writeln();
      }
    }
    final bytes = Uint8List.fromList(utf8.encode(buffer.toString()));
    final file = XFile.fromData(bytes,
        name: '$baseName.md', mimeType: 'text/markdown');
    await file.saveTo(location.path);
    _showMessage('Exported ${notes.length} note(s) to ${location.path}.');
  }

  /// Writes notes as a zip archive where each note becomes a separate .md.
  Future<void> _writeNotesAsZip({
    required List<Map<String, dynamic>> notes,
    required String baseName,
    required bool includeMetadata,
  }) async {
    final location = await getSaveLocation(
      suggestedName: '$baseName.zip',
      acceptedTypeGroups: [
        const XTypeGroup(label: 'Zip archive', extensions: ['zip']),
      ],
    );
    if (location == null) return;
    final archive = Archive();
    final seen = <String>{};
    for (final note in notes) {
      final title = note['title']?.toString() ?? 'Untitled note';
      var slug = _slugifyLocalText(title, fallback: 'note');
      var finalSlug = slug;
      var counter = 1;
      while (seen.contains('$finalSlug.md')) {
        counter += 1;
        finalSlug = '$slug-$counter';
      }
      seen.add('$finalSlug.md');
      final buffer = StringBuffer();
      if (includeMetadata) {
        buffer.writeln(_frontmatterForNote(note));
        buffer.writeln();
      }
      buffer.writeln(_noteMarkdownBody(note));
      final data = utf8.encode(buffer.toString());
      archive.addFile(ArchiveFile('$finalSlug.md', data.length, data));
    }
    final zipData = ZipEncoder().encode(archive);
    if (zipData == null) {
      _showMessage('Failed to encode zip archive.');
      return;
    }
    final file = XFile.fromData(Uint8List.fromList(zipData),
        name: '$baseName.zip', mimeType: 'application/zip');
    await file.saveTo(location.path);
    _showMessage('Exported ${notes.length} note(s) to ${location.path}.');
  }

  // ---------------------------------------------------------------------------
  // Note sessions
  // ---------------------------------------------------------------------------
  Future<int?> _startNoteSession(
      int noteId, String title, String summary) async {
    final token = _token;
    if (token == null || token.isEmpty || noteId < 0) return null;
    try {
      final session = await widget.client.startNoteSession(token, {
        'note_id': noteId,
        'title': title,
        'summary': summary,
        'started_at': DateTime.now().toIso8601String(),
      });
      _appendUiLog('Started note session for $title.');
      return session['id'] as int?;
    } catch (error) {
      _appendUiLog(
          'Note session start failed: ${error.toString().replaceFirst('Exception: ', '')}');
      return null;
    }
  }

  Future<void> _finishNoteSession(int? sessionId,
      {String? title, String? summary}) async {
    final token = _token;
    if (token == null || token.isEmpty || sessionId == null) return;
    try {
      await widget.client.updateNoteSession(token, sessionId, {
        if (title != null) 'title': title,
        if (summary != null) 'summary': summary,
        'ended_at': DateTime.now().toIso8601String(),
      });
      _appendUiLog('Finished note session ${sessionId.toString()}.');
    } catch (error) {
      _appendUiLog(
          'Note session finish failed: ${error.toString().replaceFirst('Exception: ', '')}');
    }
  }

  // ---------------------------------------------------------------------------
  // Delete, restore, sync, clear
  // ---------------------------------------------------------------------------
  Future<void> _deleteNoteToRecycleBin(Map<String, dynamic> note) async {
    final noteId = (note['id'] as num?)?.toInt();
    if (noteId == null) return;
    if (noteId < 0) {
      _localDrafts = _localDrafts
          .where((item) => item['id'] != noteId)
          .toList(growable: false);
      await _persistLocalDrafts();
      setState(() {});
      _appendUiLog("Deleted local draft '${note['title']}'.");
      return;
    }
    final token = _token;
    if (token == null || token.isEmpty) {
      throw Exception('Sign in to delete notes.');
    }
    await widget.client.deleteNote(token, noteId);
    _deletedNotes = await widget.client.getDeletedNotes(token);
    await _loadLearnerNotes(reset: true, query: _learnerSearchQuery);
    setState(() {});
    _appendUiLog("Moved note '${note['title']}' to recycle bin.");
  }

  Future<void> _restoreDeletedNote(Map<String, dynamic> note) async {
    final token = _token;
    if (token == null || token.isEmpty) {
      throw Exception('Sign in to restore notes.');
    }
    final noteId = (note['id'] as num?)?.toInt();
    if (noteId == null) return;
    await widget.client.restoreDeletedNote(token, noteId);
    _deletedNotes = await widget.client.getDeletedNotes(token);
    await _loadLearnerNotes(reset: true, query: _learnerSearchQuery);
    setState(() {});
    _appendUiLog("Restored note '${note['title']}'.");
  }

  Future<void> _emptyDeletedNotes() async {
    final token = _token;
    if (token == null || token.isEmpty) {
      throw Exception('Sign in to empty the recycle bin.');
    }
    await widget.client.emptyDeletedNotes(token);
    setState(() => _deletedNotes = const []);
    _appendUiLog('Emptied recycle bin.');
  }

  Future<void> _syncAllLocalCourses() async {
    if (_localCourses.isEmpty) return;
    for (final course in List<Map<String, dynamic>>.from(_localCourses)) {
      await _syncLocalCourse(course);
    }
    if (mounted) setState(() {});
  }

  Future<void> _syncAllLocalDrafts() async {
    if (_localDrafts.isEmpty) return;
    for (final draft in List<Map<String, dynamic>>.from(_localDrafts)) {
      await _syncLocalDraft(draft);
    }
    if (mounted) setState(() {});
  }

  Future<ActionFeedback> _syncAllLocalData(
      {bool showMessage = true}) async {
    final token = _token;
    if (token == null || token.isEmpty) {
      return const ActionFeedback(
          message: 'Sign in to sync local courses and drafts.',
          isError: true);
    }
    try {
      await _syncAllLocalCourses();
      await _syncAllLocalDrafts();
      await _loadInitialData();
      const feedback =
          ActionFeedback(message: 'Local data synced to the cloud.');
      if (showMessage) _showMessage(feedback.message);
      return feedback;
    } catch (error) {
      _localStats = {
        ..._localStats,
        'sync_failures':
            ((_localStats['sync_failures'] as num?)?.toInt() ?? 0) + 1,
      };
      await _persistLocalStats();
      final message = error.toString().replaceFirst('Exception: ', '');
      _appendUiLog('Local data sync failed: $message');
      if (showMessage) _showMessage('Local data sync failed: $message');
      return ActionFeedback(message: message, isError: true);
    }
  }

  Future<ActionFeedback> _clearLocalData() async {
    _localDrafts = const [];
    _localCourses = const [];
    _deletedNotes = const [];
    _selectedNote = null;
    _selectedCourse = null;
    _courseNotes = const [];
    // Clear cached remote data so stale template courses don't survive.
    _localCache = _LocalAppStore.defaultCache();
    _localStats = {
      ..._LocalAppStore.defaultStats(),
      'local_data_clears':
          ((_localStats['local_data_clears'] as num?)?.toInt() ?? 0) + 1,
    };
    await _persistLocalDrafts();
    await _persistLocalCourses();
    await _persistLocalStats();
    await _persistLocalCache();
    // Re-seed with just an Inbox so the workspace is never truly empty.
    await _ensureStarterWorkspace();
    _selectedCourse = _chooseDefaultCourse(
      remoteCourses: _courses,
      localCourses: _localCourses,
      frontPage: _frontPage,
    );
    if (mounted) setState(() {});
    _appendUiLog('Cleared all local data. Fresh Inbox created.');
    return const ActionFeedback(
        message: 'All local data cleared. Fresh Inbox created.');
  }

  Future<void> _copyFrontendLogs() async {
    final content = _uiLogs.join('\n');
    await Clipboard.setData(ClipboardData(text: content));
    setState(() {
      _localStats = {
        ..._localStats,
        'logs_copied':
            ((_localStats['logs_copied'] as num?)?.toInt() ?? 0) + 1,
      };
    });
    await _persistLocalStats();
    _showMessage('Frontend logs copied.');
  }

  Future<ActionFeedback> _restoreTemplateCourses() async {
    final token = _token;
    if (token == null || token.isEmpty) {
      return const ActionFeedback(
          message: 'Sign in with an admin account first.', isError: true);
    }
    try {
      final result = await widget.client.restoreTemplateCourses(token);
      await _loadInitialData();
      final message =
          result['message']?.toString() ?? 'Template courses restored.';
      _appendUiLog(message);
      _showMessage(message);
      return ActionFeedback(message: message);
    } catch (error) {
      final message = error.toString().replaceFirst('Exception: ', '');
      _appendUiLog('Template restore failed: $message');
      return ActionFeedback(message: message, isError: true);
    }
  }

  /// Generates a downloadable config file content from local settings.
  String _buildConfigFileContent() {
    final username = _profile?['username']?.toString() ?? '';
    final email = _settings?['email']?.toString() ??
        _profile?['email']?.toString() ??
        '';
    final apiBase =
        _localSettings['api_base_url']?.toString() ?? _defaultApiBaseUrl();
    final themePreset = _localSettings['theme_preset']?.toString() ?? 'teal';
    final themeMode = _localSettings['theme_mode']?.toString() ?? 'S';
    final editorMode = _settings?['editor_mode']?.toString() ?? 'P';
    return [
      '# Notechondria Editor configuration',
      '# Generated ${DateTime.now().toUtc().toIso8601String()}',
      '',
      'API_BASE_URL=$apiBase',
      'THEME_PRESET=$themePreset',
      'THEME_MODE=$themeMode',
      'EDITOR_MODE=$editorMode',
      if (username.isNotEmpty) 'USERNAME=$username',
      if (email.isNotEmpty) 'EMAIL=$email',
      '',
      '# Add custom environment variables below',
      '',
    ].join('\n');
  }

  Future<void> _downloadConfigFile() async {
    try {
      final username = _profile?['username']?.toString() ?? 'editor';
      final content = _buildConfigFileContent();
      final location = await getSaveLocation(
        suggestedName: 'notechondria-$username.env',
        acceptedTypeGroups: [
          const XTypeGroup(label: 'Config', extensions: ['env', 'txt']),
        ],
      );
      if (location == null) return;
      final bytes = Uint8List.fromList(utf8.encode(content));
      final file = XFile.fromData(bytes,
          name: 'notechondria-$username.env', mimeType: 'text/plain');
      await file.saveTo(location.path);
      _showMessage('Configuration file saved.');
      _appendUiLog('Downloaded configuration file.');
    } catch (error) {
      _showMessage(error.toString().replaceFirst('Exception: ', ''));
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

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
            child: _SplashScreen(
              appTitle: widget.appTitle,
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

  /// Compact (mobile/narrow) layout with a hamburger drawer for navigation.
  Widget _buildCompactScaffold(BuildContext context) {
    // Show current folder/category name instead of app title.
    String compactTitle;
    if (_selectedIndex == 1) {
      if (_selectedCategoryId != null) {
        compactTitle = _selectedCourse?['title']?.toString() ?? 'Category';
      } else {
        compactTitle = 'All Notes';
      }
    } else {
      compactTitle = widget.appTitle;
    }
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        title: Text(compactTitle),
        backgroundColor: Colors.transparent,
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu),
            tooltip: 'Navigation',
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
      ),
      drawer: Drawer(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              // "All Notes" item
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: _SidebarItem(
                  icon: Icons.menu_book_outlined,
                  label: 'All Notes',
                  selected:
                      _selectedIndex == 1 && _selectedCategoryId == null,
                  onTap: () {
                    Navigator.of(context).pop(); // close drawer
                    setState(() {
                      _selectedCategoryId = null;
                      _selectedIndex = 1;
                    });
                    _loadLearnerNotes(
                        reset: true, query: _learnerSearchQuery);
                  },
                ),
              ),
              // Categories section
              if (_allCategories.isNotEmpty) ...[
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: InkWell(
                    onTap: () => setState(() =>
                        _coursePanelExpanded = !_coursePanelExpanded),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Categories',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                          Icon(_coursePanelExpanded
                              ? Icons.expand_less
                              : Icons.expand_more),
                        ],
                      ),
                    ),
                  ),
                ),
                if (_coursePanelExpanded)
                  Expanded(
                    child: Builder(builder: (context) {
                      final pinned = _allCategories
                          .where((c) => c['is_default'] == true)
                          .toList(growable: false);
                      final draggable = _allCategories
                          .where((c) => c['is_default'] != true)
                          .toList(growable: false);
                      return Column(
                        children: [
                          for (var ci = 0; ci < pinned.length; ci++)
                            _StaggeredFadeIn(
                              index: ci,
                              slideOffset: const Offset(0.06, 0),
                              child: Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(12, 0, 12, 4),
                                child: _buildDrawerCategoryRow(pinned[ci]),
                              ),
                            ),
                          Expanded(
                            child: ReorderableListView.builder(
                              padding:
                                  const EdgeInsets.fromLTRB(12, 0, 12, 0),
                              buildDefaultDragHandles: false,
                              itemCount: draggable.length,
                              onReorder: (oldIndex, newIndex) {
                                if (newIndex > oldIndex) newIndex -= 1;
                                final reordered =
                                    List<Map<String, dynamic>>.from(
                                        draggable);
                                final moved =
                                    reordered.removeAt(oldIndex);
                                reordered.insert(newIndex, moved);
                                _reorderCategories(
                                    [...pinned, ...reordered]);
                              },
                              itemBuilder: (context, index) {
                                final cat = draggable[index];
                                final key = ValueKey(
                                    'dcat-${cat['id']?.toString() ?? index}');
                                return KeyedSubtree(
                                  key: key,
                                  child: _StaggeredFadeIn(
                                    index: index + pinned.length,
                                    slideOffset: const Offset(0.06, 0),
                                    child: Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 4),
                                      child: ReorderableDragStartListener(
                                        index: index,
                                        child:
                                            _buildDrawerCategoryRow(cat),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          Padding(
                            padding:
                                const EdgeInsets.fromLTRB(12, 4, 12, 8),
                            child: _SidebarItem(
                              icon: Icons.add_circle_outline,
                              label: 'New category',
                              selected: false,
                              onTap: () {
                                Navigator.of(context).pop();
                                _promptCreateCategory();
                              },
                            ),
                          ),
                        ],
                      );
                    }),
                  )
                else
                  const Spacer(),
              ] else ...[
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: _SidebarItem(
                    icon: Icons.add_circle_outline,
                    label: 'New category',
                    selected: false,
                    onTap: () {
                      Navigator.of(context).pop();
                      _promptCreateCategory();
                    },
                  ),
                ),
                const Spacer(),
              ],
              // Settings at bottom
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                child: _SidebarItem(
                  icon: Icons.settings_outlined,
                  label: 'Settings',
                  selected: _selectedIndex == 4,
                  onTap: () {
                    Navigator.of(context).pop();
                    _selectActualIndex(4);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
      body: _buildBody(),
    );
  }

  /// Category row for the compact drawer. Closes the drawer on tap, then
  /// selects the course. Long-press opens the edit dialog (same as wide).
  Widget _buildDrawerCategoryRow(Map<String, dynamic> cat) {
    return GestureDetector(
      onLongPress: () {
        Navigator.of(context).pop();
        _promptEditCategory(cat);
      },
      onSecondaryTap: () {
        Navigator.of(context).pop();
        _promptEditCategory(cat);
      },
      child: _SidebarItem(
        icon: _courseIcon(cat),
        label: cat['title']?.toString() ?? 'Category',
        selected: _selectedCategoryId == (cat['id'] as num?)?.toInt(),
        onTap: () {
          Navigator.of(context).pop();
          _selectCourse(cat);
        },
      ),
    );
  }

  /// Wide (horizontal) layout with category sidebar.
  Widget _buildWideScaffold(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            // ---- Sidebar ----
            Container(
              width: 240,
              decoration: BoxDecoration(
                color: colorScheme.surface,
                border: Border(
                    right: BorderSide(color: colorScheme.outlineVariant)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 20),
                  // "All Notes" item
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: _SidebarItem(
                      icon: Icons.menu_book_outlined,
                      label: 'All Notes',
                      selected: _selectedIndex == 1 &&
                          _selectedCategoryId == null,
                      onTap: () {
                        setState(() {
                          _selectedCategoryId = null;
                          _selectedIndex = 1;
                        });
                        _loadLearnerNotes(reset: true, query: _learnerSearchQuery);
                      },
                    ),
                  ),
                  // Categories section
                  if (_allCategories.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: InkWell(
                        onTap: () => setState(() =>
                            _coursePanelExpanded = !_coursePanelExpanded),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Categories',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                              ),
                              Icon(_coursePanelExpanded
                                  ? Icons.expand_less
                                  : Icons.expand_more),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (_coursePanelExpanded)
                      Expanded(
                        child: Builder(builder: (context) {
                          // Pin the default (Inbox) category at the top so it
                          // stays out of the drag-reorder zone.
                          final pinned = _allCategories
                              .where((c) => c['is_default'] == true)
                              .toList(growable: false);
                          final draggable = _allCategories
                              .where((c) => c['is_default'] != true)
                              .toList(growable: false);
                          return Column(
                            children: [
                              for (var ci = 0; ci < pinned.length; ci++)
                                _StaggeredFadeIn(
                                  index: ci,
                                  slideOffset: const Offset(0.06, 0),
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                        12, 0, 12, 4),
                                    child: _buildCategoryRow(pinned[ci]),
                                  ),
                                ),
                              Expanded(
                                child: ReorderableListView.builder(
                                  padding: const EdgeInsets.fromLTRB(
                                      12, 0, 12, 0),
                                  buildDefaultDragHandles: false,
                                  itemCount: draggable.length,
                                  onReorder: (oldIndex, newIndex) {
                                    // Flutter's ReorderableListView passes
                                    // newIndex as the target slot *before*
                                    // removal, so shift it left when moving
                                    // down the list.
                                    if (newIndex > oldIndex) newIndex -= 1;
                                    final reordered = List<Map<String, dynamic>>
                                        .from(draggable);
                                    final moved = reordered.removeAt(oldIndex);
                                    reordered.insert(newIndex, moved);
                                    // _reorderCategories synchronously updates
                                    // _localCourses/_courses via setState, so
                                    // the next rebuild already reflects the
                                    // new order — no local mutation needed.
                                    _reorderCategories([...pinned, ...reordered]);
                                  },
                                  itemBuilder: (context, index) {
                                    final cat = draggable[index];
                                    final key = ValueKey(
                                        'cat-${cat['id']?.toString() ?? index}');
                                    return KeyedSubtree(
                                      key: key,
                                      child: _StaggeredFadeIn(
                                        index: index + pinned.length,
                                        slideOffset: const Offset(0.06, 0),
                                        child: Padding(
                                          padding: const EdgeInsets.only(bottom: 4),
                                          child: ReorderableDragStartListener(
                                            index: index,
                                            child: _buildCategoryRow(cat),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                    12, 4, 12, 8),
                                child: _SidebarItem(
                                  icon: Icons.add_circle_outline,
                                  label: 'New category',
                                  selected: false,
                                  onTap: _promptCreateCategory,
                                ),
                              ),
                            ],
                          );
                        }),
                      )
                    else
                      const Spacer(),
                  ] else ...[
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: _SidebarItem(
                        icon: Icons.add_circle_outline,
                        label: 'New category',
                        selected: false,
                        onTap: _promptCreateCategory,
                      ),
                    ),
                    const Spacer(),
                  ],
                  // Settings at bottom
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                    child: _SidebarItem(
                      icon: Icons.settings_outlined,
                      label: 'Settings',
                      selected: _selectedIndex == 4,
                      onTap: () => _selectActualIndex(4),
                    ),
                  ),
                ],
              ),
            ),
            // ---- Main content ----
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
                            ?.copyWith(fontWeight: FontWeight.w700),
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
                            horizontal: 16, vertical: 12),
                        child: Row(
                          children: [
                            Icon(Icons.cloud_off_outlined,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onErrorContainer),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(_errorMessage!,
                                  style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onErrorContainer)),
                            ),
                            TextButton(
                                onPressed: _loadInitialData,
                                child: const Text('Retry')),
                            IconButton(
                              onPressed: () =>
                                  setState(() => _errorMessage = null),
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

  Widget _buildPage() {
    switch (_selectedIndex) {
      case 1:
        return _LearnerPage(
          notes: _learnerNotes,
          localDrafts: _localDrafts,
          courses: [..._localCourses, ..._courses],
          selectedNote: _selectedNote,
          editorMode: _settings?['editor_mode']?.toString() ?? 'P',
          hasMoreNotes: _hasMoreLearnerNotes,
          isLoadingMore: _isLoadingMoreNotes,
          searchQuery: _learnerSearchQuery,
          searchScope: _learnerSearchScope,
          isAuthenticated: _token != null && _token!.isNotEmpty,
          currentUsername: _profile?['username']?.toString() ?? '',
          apiBaseUrl: _httpClient?.baseUrl,
          onSearchChanged: (value) =>
              _loadLearnerNotes(reset: true, query: value),
          onSearchScopeChanged: (value) =>
              _loadLearnerNotes(reset: true, scope: value),
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
          onLogEvent: _appendUiLog,
          onUploadAttachment: _uploadNoteAttachment,
        );
      case 4:
        return _SettingsPage(
          profile: _profile,
          settings: _settings,
          localSettings: _localSettings,
          localStats: _localStats,
          deletedNotes: _deletedNotes,
          onSave: _updateSettings,
          onLogout: _logout,
          onRegister: _register,
          onValidateInvitation: (code) => widget.client.validateInvitation(code),
          onVerify: _verify,
          onResendVerification: _resendVerification,
          onLogin: _login,
          onRequestPasswordReset: _requestPasswordReset,
          onConfirmPasswordReset: _confirmPasswordReset,
          onGoogleLogin: (invitationCode) => _launchOAuth('google', invitationCode: invitationCode),
          onGithubLogin: (invitationCode) => _launchOAuth('github', invitationCode: invitationCode),
          onGoogleLoginOnly: () => _launchOAuth('google', intent: 'login'),
          onGithubLoginOnly: () => _launchOAuth('github', intent: 'login'),
          onBindGoogle: () => _launchOAuth('google', intent: 'bind'),
          onBindGithub: () => _launchOAuth('github', intent: 'bind'),
          onListSocialAccounts: _token != null ? () => widget.client.listSocialAccounts(_token!) : null,
          onUnlinkSocialAccount: _token != null ? (provider) => widget.client.unlinkSocialAccount(_token!, provider) : null,
          onChangePassword: _token != null ? (current, newPw) => widget.client.changePassword(_token!, current, newPw) : null,
          onChangeEmailRequest: _token != null ? (email) => widget.client.changeEmailRequest(_token!, email) : null,
          onChangeEmailConfirm: _token != null ? (email, code) => widget.client.changeEmailConfirm(_token!, email, code) : null,
          onRestoreDeletedNote: _restoreDeletedNote,
          onEmptyDeletedNotes: _emptyDeletedNotes,
          onCopyLogs: _copyFrontendLogs,
          onUploadAvatar: _uploadAvatar,
          onSyncLocalData: _syncAllLocalData,
          onPullCloudData: _pullCloudNotesToLocal,
          onClearLocalData: _clearLocalData,
          onRestoreTemplateCourses: _restoreTemplateCourses,
          onDownloadConfig: _downloadConfigFile,
          localDraftCount: _localDrafts.length,
          localCourseCount: _localCourses.length,
          apiBaseUrl: _httpClient?.baseUrl,
          debugSnapshotListenable: _httpClient?.debugSnapshot,
          debugHistoryListenable: _httpClient?.debugHistory,
          uiLogs: _uiLogs,
        );
      default:
        return const SizedBox.shrink();
    }
  }
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

/// Dialog for editing a category (rename + icon + delete).
class _EditCategoryDialog extends StatefulWidget {
  const _EditCategoryDialog({
    required this.controller,
    this.initialIcon,
  });
  final TextEditingController controller;
  final int? initialIcon;

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
    return AlertDialog(
      title: const Text('Edit category'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                  if (picked != null) setState(() => _selectedIcon = picked);
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Deleting moves all notes to the default category.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop({'action': 'delete'}),
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error,
          ),
          child: const Text('Delete'),
        ),
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
