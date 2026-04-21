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
  // Client-side recycle bin; see editor_app for the contract.
  List<Map<String, dynamic>> _localTrashedDrafts = const [];
  List<Map<String, dynamic>> _localTrashedCourses = const [];
  List<Map<String, dynamic>> _activity = const [];
  List<Map<String, dynamic>> _plannerEvents = const [];
  List<Map<String, dynamic>> _calendarFeeds = const [];
  Map<String, dynamic>? _activityWeek;
  Map<String, dynamic>? _selectedCourse;
  Map<String, dynamic>? _selectedNote;
  Map<String, dynamic> _localSettings = _LocalAppStore.defaultSettings();
  Map<String, dynamic> _localStats = _LocalAppStore.defaultStats();
  Map<String, dynamic> _localCache = _LocalAppStore.defaultCache();
  DateTime _activityWeekStart = _dateOnly(DateTime.now());
  bool _hasMoreLearnerNotes = true;
  bool _isLoadingMoreNotes = false;
  bool _coursePanelExpanded = true;
  Timer? _splashTimer;
  final ValueNotifier<String> _splashStatus =
      ValueNotifier<String>('Starting portal');
  int _learnerNotesOffset = 0;
  String _learnerSearchQuery = '';
  final List<String> _uiLogs = <String>[];
  final DebugLogController _logController = DebugLogController();

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

  bool _showWidePageHeader(int index) => index == 4;

  bool _showCompactPageHeader(int index) => index != 3;

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
      _log(level: level, source: source, message: message);
    });
    _bootstrapApp();
  }

  Future<void> _bootstrapApp() async {
    _splashTimer = Timer(const Duration(seconds: 10), () {
      if (mounted) setState(() { _isLoading = false; _showSplash = false; });
    });
    _splashStatus.value = 'Loading local state';
    await _loadLocalState();
    _splashStatus.value = 'Completing sign-in';
    await _handleOAuthCallback();
    _splashStatus.value = 'Connecting to server';
    await _loadInitialData();
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
        _log(
          level: DebugLogLevel.error,
          source: 'Portal.Auth/oauth.launch',
          message:
              'Cannot start $provider sign-in: Portal.Auth/oauth.launch \u2014 '
              'client_id missing in OAuth config for $provider.',
        );
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
      _log(
        level: DebugLogLevel.error,
        source: 'Portal.Auth/oauth.launch',
        message:
            'OAuth sign-in could not start: Portal.Auth/oauth.launch \u2014 '
            '${error.toString().replaceFirst("Exception: ", "")}.',
      );
    }
  }

  Future<bool> _handleOAuthCallback() async {
    if (!kIsWeb) return false;
    final uri = Uri.base;
    final code = uri.queryParameters['code'];
    final state = uri.queryParameters['state'];
    if (code == null || code.isEmpty) return false;
    if (state != 'google' && state != 'github') return false;

    final cleanUrl = uri.removeFragment().replace(queryParameters: {}).toString();
    url_strategy.browserRedirect(cleanUrl);

    final prefs = await SharedPreferences.getInstance();
    final redirectUri = prefs.getString('oauth_redirect_uri') ?? '';
    final invitationCode = prefs.getString('oauth_invitation_code') ?? '';
    final intent = prefs.getString('oauth_intent') ?? 'register';
    await prefs.remove('oauth_redirect_uri');
    await prefs.remove('oauth_invitation_code');
    await prefs.remove('oauth_intent');

    final providerLabel = state == 'google' ? 'Google' : 'GitHub';
    _splashStatus.value = intent == 'bind'
        ? 'Linking $providerLabel account'
        : 'Completing sign-in via $providerLabel';

    if (intent == 'bind') {
      if (_token == null || _token!.isEmpty) {
        _log(
          level: DebugLogLevel.warning,
          source: 'Portal.Auth/bind',
          message:
              'Account linking aborted: Portal.Auth/bind \u2014 session token '
              'missing at OAuth callback (user signed out between click and '
              'redirect).',
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Account linking aborted: Portal.Auth/bind \u2014 your session '
                'expired before the provider redirected back. Sign in first, '
                'then try linking the account again.',
              ),
            ),
          );
        }
        return false;
      }
      try {
        if (state == 'google') {
          await widget.client.bindGoogle(_token!, code, redirectUri: redirectUri);
        } else {
          await widget.client.bindGithub(_token!, code, redirectUri: redirectUri);
        }
        final provider = state == 'google' ? 'Google' : 'GitHub';
        _log(
          level: DebugLogLevel.info,
          source: 'Portal.Auth/bind',
          message:
              'Linked $provider account: Portal.Auth/bind \u2014 '
              'server accepted the bind token.',
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '$provider account linked: Portal.Auth/bind \u2014 '
                'ready to sign in with $provider next time.',
              ),
            ),
          );
        }
        return true;
      } catch (error) {
        final msg = error.toString().replaceFirst('Exception: ', '');
        _log(
          level: DebugLogLevel.error,
          source: 'Portal.Auth/bind',
          message:
              'Account linking failed: Portal.Auth/bind \u2014 $msg.',
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Account linking failed: Portal.Auth/bind \u2014 $msg.',
              ),
            ),
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
      final providerName = state == 'google' ? 'Google' : 'GitHub';
      _log(
        level: DebugLogLevel.info,
        source: 'Portal.Auth/oauth.callback',
        message:
            'Signed in via $providerName: Portal.Auth/oauth.callback \u2014 '
            'server accepted the authorization code.',
      );
      return true;
    } catch (error) {
      final msg = error.toString().replaceFirst('Exception: ', '');
      // Preserved sentinels: "not_registered" and "No account found"
      // drive the registration-prompt branch below.
      if (msg.contains('not_registered') || msg.contains('No account found')) {
        _log(
          level: DebugLogLevel.warning,
          source: 'Portal.Auth/oauth.callback',
          message:
              'OAuth sign-in rejected: Portal.Auth/oauth.callback \u2014 '
              'No account found for this identity (server replied '
              'not_registered). Register first.',
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'OAuth sign-in rejected: Portal.Auth/oauth.callback \u2014 '
                'No account found for this identity. Please register first.',
              ),
            ),
          );
        }
      } else {
        _log(
          level: DebugLogLevel.error,
          source: 'Portal.Auth/oauth.callback',
          message:
              'OAuth sign-in failed: Portal.Auth/oauth.callback \u2014 $msg.',
        );
      }
      return false;
    }
  }

  @override
  void dispose() {
    _splashTimer?.cancel();
    _splashStatus.dispose();
    _logController.dispose();
    super.dispose();
  }


  void _appendUiLog(String message) {
    _log(message: message, level: DebugLogLevel.info, source: '');
  }

  void _log({
    required String message,
    DebugLogLevel level = DebugLogLevel.debug,
    String source = '',
    int? durationMs,
  }) {
    final entry = DebugLogEntry(
      timestamp: DateTime.now().toUtc(),
      level: level,
      source: source,
      message: message,
      durationMs: durationMs,
    );
    _logController.append(entry);
    setState(() {
      _uiLogs.insert(0, entry.toPersistedString());
      if (_uiLogs.length > 80) {
        _uiLogs.removeRange(80, _uiLogs.length);
      }
    });
    unawaited(_persistUiLogs());
  }

  Map<String, Object?> _snapshotLocalStore() {
    return <String, Object?>{
      'settings': _localSettings,
      'drafts': _localDrafts,
      'courses': _localCourses,
      'stats': _localStats,
      'cache': _localCache,
      'logs': _uiLogs,
      'session': _token == null
          ? null
          : {
              'token_present': true,
              'profile': _profile ?? const <String, dynamic>{},
            },
    };
  }

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
    _localTrashedDrafts = snapshot.trashedDrafts;
    _localTrashedCourses = snapshot.trashedCourses;
    _localStats = snapshot.stats;
    _localCache = snapshot.cache;
    _uiLogs
      ..clear()
      ..addAll(snapshot.logs);
    _logController.replaceAll(
      snapshot.logs.map(DebugLogEntry.fromPersistedString),
    );
    _logController.bindCacheProvider(_snapshotLocalStore);
    _frontPage = Map<String, dynamic>.from(
      snapshot.cache['front_page'] as Map? ?? const {},
    );
    _courses = (snapshot.cache['courses'] as List<dynamic>? ?? const [])
        .map((item) => _decorateRemoteCourse(Map<String, dynamic>.from(item as Map)))
        .toList(growable: false);
    _activity = (snapshot.cache['activity'] as List<dynamic>? ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList(growable: false);
    await _ensureStarterWorkspace();
    if (_selectedCourse == null) {
      _selectedCourse = _chooseDefaultCourse(
        remoteCourses: _courses,
        localCourses: _localCourses,
        frontPage: _frontPage,
      );
    }
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

  Future<void> _persistLocalTrashedDrafts() async {
    await _LocalAppStore.saveTrashedDrafts(_localTrashedDrafts);
  }

  Future<void> _persistLocalTrashedCourses() async {
    await _LocalAppStore.saveTrashedCourses(_localTrashedCourses);
  }

  /// Moves a just-cloud-synced local draft into the client-side
  /// recycle bin. See editor_app for the full contract.
  Future<void> _moveDraftToLocalTrash(
    Map<String, dynamic> draft, {
    int? serverNoteId,
    String? serverNoteUuid,
  }) async {
    final entry = {
      'draft': Map<String, dynamic>.from(draft),
      'trashed_at': DateTime.now().toUtc().toIso8601String(),
      if (serverNoteId != null) 'server_note_id': serverNoteId,
      if (serverNoteUuid != null && serverNoteUuid.isNotEmpty)
        'server_note_uuid': serverNoteUuid,
    };
    _localTrashedDrafts = [entry, ..._localTrashedDrafts];
    await _persistLocalTrashedDrafts();
  }

  Future<void> _moveCourseToLocalTrash(
    Map<String, dynamic> course, {
    int? serverCourseId,
  }) async {
    final entry = {
      'course': Map<String, dynamic>.from(course),
      'trashed_at': DateTime.now().toUtc().toIso8601String(),
      if (serverCourseId != null) 'server_course_id': serverCourseId,
    };
    _localTrashedCourses = [entry, ..._localTrashedCourses];
    await _persistLocalTrashedCourses();
  }

  Future<ActionFeedback> _restoreTrashedDraft(
      Map<String, dynamic> entry) async {
    final raw = entry['draft'];
    if (raw is! Map) {
      return const ActionFeedback(
        message: 'Draft not restored: '
            'Portal.LocalStore/restore_trashed_draft \u2014 '
            'recycle-bin entry was missing its draft payload.',
        isError: true,
      );
    }
    final restored = {
      ...Map<String, dynamic>.from(raw),
      'id': _LocalAppStore.newDraftId(),
      'last_edit': DateTime.now().toUtc().toIso8601String(),
    };
    _localDrafts = [..._localDrafts, restored];
    _localTrashedDrafts = _localTrashedDrafts
        .where((item) => item != entry)
        .toList(growable: false);
    await _persistLocalDrafts();
    await _persistLocalTrashedDrafts();
    if (mounted) setState(() {});
    final title = restored['title']?.toString() ?? 'draft';
    _log(
      level: DebugLogLevel.info,
      source: 'Portal.LocalStore/restore_trashed_draft',
      message:
          'Draft restored from local recycle bin: '
          'Portal.LocalStore/restore_trashed_draft \u2014 '
          "'$title' re-added as a local draft; cloud copy left untouched.",
    );
    return ActionFeedback(
      message:
          'Draft restored: Portal.LocalStore/restore_trashed_draft \u2014 '
          "'$title' is back. The cloud copy was not touched.",
    );
  }

  Future<ActionFeedback> _restoreTrashedCourse(
      Map<String, dynamic> entry) async {
    final raw = entry['course'];
    if (raw is! Map) {
      return const ActionFeedback(
        message: 'Category not restored: '
            'Portal.LocalStore/restore_trashed_course \u2014 '
            'recycle-bin entry was missing its course payload.',
        isError: true,
      );
    }
    final restored = {
      ...Map<String, dynamic>.from(raw),
      'id': _LocalAppStore.newCourseId(),
      'last_edit': DateTime.now().toUtc().toIso8601String(),
    };
    _localCourses = [..._localCourses, restored];
    _localTrashedCourses = _localTrashedCourses
        .where((item) => item != entry)
        .toList(growable: false);
    await _persistLocalCourses();
    await _persistLocalTrashedCourses();
    if (mounted) setState(() {});
    final title = restored['title']?.toString() ?? 'category';
    _log(
      level: DebugLogLevel.info,
      source: 'Portal.LocalStore/restore_trashed_course',
      message:
          'Category restored from local recycle bin: '
          'Portal.LocalStore/restore_trashed_course \u2014 '
          "'$title' re-added as a local category; cloud copy left untouched.",
    );
    return ActionFeedback(
      message:
          'Category restored: Portal.LocalStore/restore_trashed_course \u2014 '
          "'$title' is back. The cloud copy was not touched.",
    );
  }

  Future<void> _openLocalRecycleBinDialog() async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, rebuild) {
          final drafts = List<Map<String, dynamic>>.from(_localTrashedDrafts);
          final courses =
              List<Map<String, dynamic>>.from(_localTrashedCourses);
          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.7,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                    child: Text(
                      'Local recycle bin',
                      style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    child: Text(
                      'Drafts and categories kept here for 30 days after a '
                      'successful cloud sync.',
                      style: Theme.of(ctx).textTheme.bodySmall,
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView(
                      padding: EdgeInsets.zero,
                      children: [
                        if (drafts.isEmpty && courses.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(32),
                            child: Center(
                              child: Text(
                                'Nothing in the local recycle bin yet.',
                              ),
                            ),
                          ),
                        for (final entry in drafts)
                          ListTile(
                            leading: const Icon(Icons.description_outlined),
                            title: Text(
                              (entry['draft']
                                          as Map?)?['title']
                                      ?.toString() ??
                                  'Untitled draft',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              'Draft \u00b7 trashed ${_formatTrashedAt(entry['trashed_at'])}',
                            ),
                            trailing: TextButton.icon(
                              icon: const Icon(Icons.restore),
                              label: const Text('Restore'),
                              onPressed: () async {
                                final feedback =
                                    await _restoreTrashedDraft(entry);
                                if (mounted) _showMessage(feedback.message);
                                if (ctx.mounted) rebuild(() {});
                              },
                            ),
                          ),
                        for (final entry in courses)
                          ListTile(
                            leading: const Icon(Icons.folder_outlined),
                            title: Text(
                              (entry['course']
                                          as Map?)?['title']
                                      ?.toString() ??
                                  'Untitled category',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              'Category \u00b7 trashed ${_formatTrashedAt(entry['trashed_at'])}',
                            ),
                            trailing: TextButton.icon(
                              icon: const Icon(Icons.restore),
                              label: const Text('Restore'),
                              onPressed: () async {
                                final feedback =
                                    await _restoreTrashedCourse(entry);
                                if (mounted) _showMessage(feedback.message);
                                if (ctx.mounted) rebuild(() {});
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        });
      },
    );
  }

  String _formatTrashedAt(Object? raw) {
    final text = raw?.toString();
    if (text == null || text.isEmpty) return 'recently';
    final when = DateTime.tryParse(text)?.toLocal();
    if (when == null) return text;
    final now = DateTime.now();
    final delta = now.difference(when);
    if (delta.inMinutes < 2) return 'just now';
    if (delta.inHours < 1) return '${delta.inMinutes}m ago';
    if (delta.inDays < 1) return '${delta.inHours}h ago';
    if (delta.inDays < 30) return '${delta.inDays}d ago';
    return text.substring(0, 10);
  }

  Future<void> _persistLocalStats() async {
    await _LocalAppStore.saveStats(_localStats);
  }

  Future<void> _persistLocalCache() async {
    _localCache = {
      ..._localCache,
      'front_page': _frontPage ?? const <String, dynamic>{},
      'courses': _courses,
      'activity': _activity,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    await _LocalAppStore.saveCache(_localCache);
  }

  Future<void> _persistUiLogs() async {
    await _LocalAppStore.saveLogs(_uiLogs);
  }


  Future<void> _ensureStarterWorkspace() async {
    if (_frontPage?.isNotEmpty == true) {
      return;
    }
    _frontPage = {
      'default_course': null,
      'carousel_courses': const <Map<String, dynamic>>[],
      'collections': const <Map<String, dynamic>>[],
      'recent_notes': const <Map<String, dynamic>>[],
      'recommended_notes': const <Map<String, dynamic>>[],
      'portal_shell': true,
    };
    _localStats = {
      ..._localStats,
      'starter_workspace_seeded_at': DateTime.now().toUtc().toIso8601String(),
    };
    await _persistLocalStats();
    await _persistLocalCache();
    _log(
      level: DebugLogLevel.info,
      source: 'Portal.LocalStore/seed_starter',
      message:
          'Portal shell starter state seeded: '
          'Portal.LocalStore/seed_starter \u2014 '
          'first-run offline front-page shell created.',
    );
  }

  bool _isLocalCourse(Map<String, dynamic>? course) {
    if (course == null) {
      return false;
    }
    return course['is_local_course'] == true ||
        ((course['id'] as num?)?.toInt() ?? 0) < 0;
  }

  Map<String, dynamic> _decorateRemoteCourse(Map<String, dynamic> course) {
    final owner = Map<String, dynamic>.from(course['owner'] as Map? ?? const {});
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
    final fallbackCourses =
        remoteCourses.isNotEmpty ? remoteCourses.take(3).toList() : _localCourses.take(3).toList();
    return {
      'default_course': fallbackCourses.isNotEmpty ? fallbackCourses.first : null,
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
    final defaultCourse = frontPage?['default_course'] as Map<String, dynamic>?;
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
    var activity = List<Map<String, dynamic>>.from(_activity);
    var courseNotes = List<Map<String, dynamic>>.from(_courseNotes);
    var plannerEvents = List<Map<String, dynamic>>.from(_plannerEvents);
    var calendarFeeds = List<Map<String, dynamic>>.from(_calendarFeeds);
    var learnerNotes = List<Map<String, dynamic>>.from(_learnerNotes);
    var deletedNotes = List<Map<String, dynamic>>.from(_deletedNotes);
    Map<String, dynamic>? activityWeek = _activityWeek;
    Map<String, dynamic> notePage = {
      'results': learnerNotes,
      'has_more': _hasMoreLearnerNotes,
    };
    var updatedCache = false;

    // Offline-mode gate: skip every remote fetch and render from the
    // local cache. Sign-in and explicit sync still work because those
    // paths call into `widget.client` directly, not through here.
    final offlineMode = _localSettings['offline_mode'] == true;
    if (offlineMode) {
      setState(() {
        _frontPage = frontPage;
        _courses = courses;
        _activity = activity;
        _courseNotes = courseNotes;
        _plannerEvents = plannerEvents;
        _calendarFeeds = calendarFeeds;
        _learnerNotes = learnerNotes;
        _deletedNotes = deletedNotes;
        _activityWeek = activityWeek;
        _hasMoreLearnerNotes = notePage['has_more'] == true;
        _learnerNotesOffset = learnerNotes.length;
        _errorMessage = null;
        _isLoading = false;
        _showSplash = false;
      });
      _log(
        source: 'Portal._loadInitialData',
        level: DebugLogLevel.info,
        message:
            'Offline mode: Portal._loadInitialData \u2014 skipped remote '
            'fetches, rendered from local cache.',
      );
      return;
    }

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
    try {
      activity = await widget.client.getActivity(token: _token);
      updatedCache = true;
    } catch (error) {
      errors.add(error.toString().replaceFirst('Exception: ', ''));
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
        plannerEvents = await widget.client.getPlannerEvents(_token!);
      } catch (error) {
        errors.add(error.toString().replaceFirst('Exception: ', ''));
      }
      try {
        calendarFeeds = await widget.client.getCalendarFeeds(_token!);
      } catch (error) {
        errors.add(error.toString().replaceFirst('Exception: ', ''));
      }
      try {
        activityWeek = await widget.client.getActivityWeek(
          _token!,
          startDate: _activityWeekStart.toIso8601String().split('T').first,
        );
      } catch (error) {
        errors.add(error.toString().replaceFirst('Exception: ', ''));
      }
      try {
        deletedNotes = await widget.client.getDeletedNotes(_token!);
      } catch (error) {
        errors.add(error.toString().replaceFirst('Exception: ', ''));
      }
      try {
        notePage =
            await widget.client.listNotes(token: _token, limit: 20, offset: 0);
        learnerNotes = (notePage['results'] as List<dynamic>? ?? const [])
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList(growable: false);
      } catch (error) {
        errors.add(error.toString().replaceFirst('Exception: ', ''));
      }
    } else {
      plannerEvents = const [];
      calendarFeeds = const [];
      activityWeek = null;
      deletedNotes = const [];
      learnerNotes = const [];
      notePage = const {
        'results': [],
        'has_more': false,
      };
    }

    // Detect a rejected DRF token (revoked server-side, or signed by a
    // different SECRET_KEY after a deploy) and clear the in-memory
    // session so the user sees the auth UI instead of silently
    // dropping into offline mode with a stale identity.
    //
    // Portal doesn't persist the token to disk, so only in-memory
    // state needs to be reset.
    //
    // Threshold: require AT LEAST TWO authenticated endpoints to
    // fail with a 401-shaped error before we nuke the session. A
    // single flaky endpoint that happens to 401 (rate limit, server
    // glitch, or the post-login race where one endpoint lags the
    // token commit) used to wipe a freshly-issued session and kick
    // the user back to the login dialog. The user-reported "first
    // login always fails" symptom was this false-positive.
    final authFailureCount = errors.where((message) {
      final lower = message.toLowerCase();
      return lower.contains('invalid token') ||
          lower.contains('authentication credentials were not provided') ||
          lower.contains('token_not_valid') ||
          lower.contains('session rejected:');
    }).length;
    final sessionRejected = _token != null &&
        _token!.isNotEmpty &&
        authFailureCount >= 2;

    setState(() {
      if (sessionRejected) {
        _token = null;
        _profile = null;
      }
      _frontPage = frontPage;
      _courses = courses;
      _activity = activity;
      _selectedCourse = selectedCourse;
      _courseNotes = courseNotes;
      _learnerNotes = learnerNotes;
      _deletedNotes = deletedNotes;
      _selectedNote = null;
      _plannerEvents = plannerEvents;
      _calendarFeeds = calendarFeeds;
      _activityWeek = activityWeek;
      _hasMoreLearnerNotes = notePage['has_more'] == true;
      _learnerNotesOffset = learnerNotes.length;
      _errorMessage = errors.isEmpty ? null : errors.first;
      _isLoading = false;
      _showSplash = false;
    });
    if (updatedCache) {
      await _persistLocalCache();
    }
    _log(
      source: 'Portal._loadInitialData',
      level: errors.isEmpty
          ? DebugLogLevel.info
          : DebugLogLevel.warning,
      message: errors.isEmpty
          ? 'Initial Portal._loadInitialData data loaded '
              '(${courses.length} cloud courses, ${learnerNotes.length} notes).'
          : sessionRejected
              ? 'Session expired \u2014 signed out. Please sign in again.'
              : 'Initial Portal._loadInitialData load used offline fallback: '
                  'Portal.Sync.FrontPage/bootstrap \u2014 ${errors.first}.',
    );
  }

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
            final metadata =
                _decodeNoteMetadata(item['metadata_json']?.toString() ?? '{}');
            return (metadata['offline_source_note_id'] as num?)?.toInt() ==
                sourceId;
          });
    final existingDraft =
        existingIndex >= 0 ? Map<String, dynamic>.from(_localDrafts[existingIndex]) : null;
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

  Future<void> _refreshFrontPageData() async {
    try {
      final frontPage = await widget.client.getFrontPage(token: _token);
      List<Map<String, dynamic>> plannerEvents = _plannerEvents;
      if (_token != null && _token!.isNotEmpty) {
        plannerEvents = await widget.client.getPlannerEvents(_token!);
      }
      setState(() {
        _frontPage = frontPage;
        _plannerEvents = plannerEvents;
      });
      await _persistLocalCache();
      _log(
        level: DebugLogLevel.debug,
        source: 'Portal.Sync.FrontPage/pull',
        message:
            'Front page refreshed: '
            'Portal.Sync.FrontPage/pull \u2014 '
            'carousel + planner events re-pulled from server.',
      );
    } catch (error) {
      final cause = error.toString().replaceFirst('Exception: ', '');
      setState(() {
        _errorMessage = cause;
      });
      _log(
        level: DebugLogLevel.error,
        source: 'Portal.Sync.FrontPage/pull',
        message: 'Front page not refreshed: '
            'Portal.Sync.FrontPage/pull \u2014 $cause.',
      );
    }
  }

  Future<void> _loadLearnerNotes({bool reset = false, String? query}) async {
    if (_token == null || _token!.isEmpty) {
      setState(() {
        _learnerSearchQuery = query ?? _learnerSearchQuery;
      });
      return;
    }
    if (_isLoadingMoreNotes) {
      return;
    }
    final effectiveQuery = query ?? _learnerSearchQuery;
    final nextOffset = reset ? 0 : _learnerNotesOffset;
    setState(() {
      _isLoadingMoreNotes = true;
      if (reset) {
        _learnerSearchQuery = effectiveQuery;
      }
    });
    try {
      final page = await widget.client.listNotes(
        token: _token,
        query: effectiveQuery,
        offset: nextOffset,
        limit: 20,
      );
      final rows = (page['results'] as List<dynamic>? ?? const [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
      setState(() {
        _learnerNotes = reset ? rows : [..._learnerNotes, ...rows];
        _hasMoreLearnerNotes = page['has_more'] == true;
        _learnerNotesOffset = (reset ? 0 : _learnerNotesOffset) + rows.length;
        _isLoadingMoreNotes = false;
      });
    } catch (error) {
      setState(() {
        _isLoadingMoreNotes = false;
        _errorMessage = error.toString().replaceFirst('Exception: ', '');
      });
      final cause = error.toString().replaceFirst('Exception: ', '');
      _log(
        level: DebugLogLevel.error,
        source: 'Portal.Sync.Notes/list',
        message:
            'Notes list load failed: '
            'Portal.Sync.Notes/list \u2014 $cause.',
      );
    }
  }

  Future<void> _selectCourse(Map<String, dynamic> course) async {
    setState(() {
      _selectedCourse = course;
      _isLoading = true;
    });
    if (_isLocalCourse(course)) {
      setState(() {
        _courseNotes = _localNotesForCourse(course);
        _selectedNote = null;
        _selectedIndex = 2;
        _isLoading = false;
      });
      _log(
        level: DebugLogLevel.debug,
        source: 'Portal.UI/open_course',
        message:
            "Opened local course: Portal.UI/open_course \u2014 "
            "'${course['title']}' selected in portal view.",
      );
      return;
    }
    try {
      var effectiveCourse = Map<String, dynamic>.from(course);
      if ((_token?.isNotEmpty ?? false) && course['is_subscribed'] == true) {
        effectiveCourse =
            await widget.client.openCourse(_token!, course['id'] as int);
      }
      final refreshedCourses =
          (await widget.client.getCourses(token: _token)).map(_decorateRemoteCourse).toList();
      final refreshedSelected = refreshedCourses.firstWhere(
        (item) => item['id'] == effectiveCourse['id'],
        orElse: () => effectiveCourse,
      );
      final notes = await widget.client.getCourseNotes(
        refreshedSelected['id'] as int,
        token: _token,
      );
      setState(() {
        _courses = refreshedCourses;
        _selectedCourse = refreshedSelected;
        _courseNotes = notes;
        _selectedNote = null;
        _selectedIndex = 2;
        _isLoading = false;
      });
      await _persistLocalCache();
      _log(
        level: DebugLogLevel.debug,
        source: 'Portal.UI/open_course',
        message:
            "Opened course: Portal.UI/open_course \u2014 "
            "'${refreshedSelected['title']}' loaded from cloud.",
      );
    } catch (error) {
      final cause = error.toString().replaceFirst('Exception: ', '');
      setState(() {
        _selectedCourse = course;
        _courseNotes = const [];
        _errorMessage = cause;
        _isLoading = false;
      });
      _log(
        level: DebugLogLevel.error,
        source: 'Portal.Sync.Courses/load',
        message: 'Course not loaded: '
            'Portal.Sync.Courses/load \u2014 $cause.',
      );
    }
  }

  Future<void> _selectNote(Map<String, dynamic> noteSummary) async {
    setState(() {
      _isLoading = true;
    });
    try {
      final detail = await _fetchNoteDetail(noteSummary['id'] as int);
      setState(() {
        _selectedNote = detail;
        _selectedIndex = 1;
        _isLoading = false;
      });
    } catch (error) {
      final cause = error.toString().replaceFirst('Exception: ', '');
      setState(() {
        _errorMessage = cause;
        _isLoading = false;
      });
      _log(
        level: DebugLogLevel.error,
        source: 'Portal.UI/open_note',
        message:
            'Note not opened: Portal.UI/open_note \u2014 $cause.',
      );
    }
  }

  Future<void> _openNoteViewer(Map<String, dynamic> noteSummary) async {
    Map<String, dynamic> detail;
    try {
      detail = await _fetchNoteDetail(noteSummary['id'] as int);
    } catch (error) {
      final cause = error.toString().replaceFirst('Exception: ', '');
      _showMessage(
        'Note not opened: Portal.UI/open_note_viewer \u2014 $cause.',
      );
      _log(
        level: DebugLogLevel.error,
        source: 'Portal.UI/open_note_viewer',
        message:
            'Note not opened: Portal.UI/open_note_viewer \u2014 $cause.',
      );
      return;
    }
    if (!mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) => _NoteViewerDialog(note: detail),
    );
  }

  Future<Map<String, dynamic>> _fetchNoteDetail(int noteId) async {
    if (noteId < 0) {
      final draft = _localDrafts.firstWhere(
        (item) => item['id'] == noteId,
        orElse: () => <String, dynamic>{},
      );
      if (draft.isEmpty) {
        throw Exception(
          'Local draft not found: '
          'Portal.Sync.Notes/save_local \u2014 '
          'no local draft matches the requested id.',
        );
      }
      setState(() {
        _selectedNote = draft;
      });
      return draft;
    }
    final detail = await widget.client.getNoteDetail(noteId, token: _token);
    setState(() {
      _selectedNote = detail;
    });
    return detail;
  }

  Future<ActionFeedback> _register(
    String username,
    String email,
    String password, {
    String invitationCode = '',
  }) async {
    try {
      final result = await widget.client.register(
        username, email, password, invitationCode: invitationCode,
      );
      final serverMessage = result['message']?.toString();
      return ActionFeedback(
          message: serverMessage != null && serverMessage.isNotEmpty
              ? 'Registration queued: Portal.Auth/register \u2014 $serverMessage'
              : 'Registration queued: Portal.Auth/register \u2014 '
                  'verification email sent to $email.');
    } catch (error) {
      final cause = error.toString().replaceFirst('Exception: ', '');
      return ActionFeedback(
        message:
            'Registration rejected: Portal.Auth/register \u2014 $cause',
        isError: true,
      );
    }
  }

  Future<ActionFeedback> _verify(String email, String code) async {
    try {
      final result = await widget.client.verifyEmail(email, code);
      await _applyAuthPayload(result);
      return const ActionFeedback(
          message:
              'Signed in: Portal.Auth/verify \u2014 email verified and '
              'session issued.');
    } catch (error) {
      final cause = error.toString().replaceFirst('Exception: ', '');
      return ActionFeedback(
        message: 'Email verification failed: Portal.Auth/verify \u2014 $cause',
        isError: true,
      );
    }
  }

  Future<ActionFeedback> _resendVerification(String email) async {
    try {
      final result = await widget.client.resendVerification(email);
      final serverMessage = result['message']?.toString();
      return ActionFeedback(
          message: serverMessage != null && serverMessage.isNotEmpty
              ? 'Verification code resent: '
                  'Portal.Auth/resend_verification \u2014 $serverMessage'
              : 'Verification code resent: '
                  'Portal.Auth/resend_verification \u2014 delivery queued '
                  'to $email.');
    } catch (error) {
      final cause = error.toString().replaceFirst('Exception: ', '');
      return ActionFeedback(
          message: 'Verification code not resent: '
              'Portal.Auth/resend_verification \u2014 $cause',
          isError: true);
    }
  }

  Future<ActionFeedback> _login(String email, String password) async {
    try {
      final result = await widget.client.login(email, password);
      await _applyAuthPayload(result);
      return const ActionFeedback(
          message: 'Signed in: Portal.Auth/login \u2014 '
              'server accepted credentials.');
    } catch (error) {
      final cause = error.toString().replaceFirst('Exception: ', '');
      return ActionFeedback(
        message: 'Sign-in rejected: Portal.Auth/login \u2014 $cause',
        isError: true,
      );
    }
  }

  Future<ActionFeedback> _requestPasswordReset(String email) async {
    try {
      final result = await widget.client.requestPasswordReset(email);
      final serverMessage = result['message']?.toString();
      return ActionFeedback(
          message: serverMessage != null && serverMessage.isNotEmpty
              ? 'Password reset email queued: '
                  'Portal.Auth/password.reset.request \u2014 $serverMessage'
              : 'Password reset email queued: '
                  'Portal.Auth/password.reset.request \u2014 sent to $email.');
    } catch (error) {
      final cause = error.toString().replaceFirst('Exception: ', '');
      return ActionFeedback(
        message: 'Password reset email not sent: '
            'Portal.Auth/password.reset.request \u2014 $cause',
        isError: true,
      );
    }
  }

  Future<ActionFeedback> _confirmPasswordReset(
      String email, String code, String password) async {
    try {
      final result =
          await widget.client.confirmPasswordReset(email, code, password);
      final serverMessage = result['message']?.toString();
      return ActionFeedback(
          message: serverMessage != null && serverMessage.isNotEmpty
              ? 'Password updated: '
                  'Portal.Auth/password.reset.confirm \u2014 $serverMessage'
              : 'Password updated: '
                  'Portal.Auth/password.reset.confirm \u2014 '
                  'server accepted reset code.');
    } catch (error) {
      final cause = error.toString().replaceFirst('Exception: ', '');
      return ActionFeedback(
        message: 'Password not updated: '
            'Portal.Auth/password.reset.confirm \u2014 $cause',
        isError: true,
      );
    }
  }

  Map<String, dynamic> _currentAppSettingsPayload({
    String? themePreset,
    String? themeMode,
    String? apiBaseUrl,
  }) {
    final existingLogPrefs =
        Map<String, dynamic>.from(_localSettings['log_preferences'] as Map? ?? {});
    final effectiveApiBase = (apiBaseUrl ?? _localSettings['api_base_url'] ?? _defaultApiBaseUrl())
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
    if (persist) {
      await _persistLocalSettings();
    }
  }

  /// Toggles the offline-mode flag. Persists via
  /// `_applyLocalAppSettings` so SharedPreferences picks it up, then
  /// re-runs `_loadInitialData` so the new mode takes effect without
  /// forcing the user to restart the app.
  Future<void> _setOfflineMode(bool offlineMode) async {
    await _applyLocalAppSettings({'offline_mode': offlineMode});
    _log(
      level: DebugLogLevel.info,
      source: 'Portal.Sync.Settings/offline_mode',
      message: offlineMode
          ? 'Offline mode enabled: Portal.Sync.Settings/offline_mode \u2014 '
              'remote fetches will be skipped at startup.'
          : 'Offline mode disabled: Portal.Sync.Settings/offline_mode \u2014 '
              'remote fetches re-enabled.',
    );
    await _loadInitialData();
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
        'app_settings_updated_at':
            _localSettings['updated_at'] ?? DateTime.now().toUtc().toIso8601String(),
      };
      _log(
        level: DebugLogLevel.warning,
        source: 'Portal.Sync.Settings/bootstrap',
        message:
            'Remote settings unavailable right after login: '
            'Portal.Sync.Settings/bootstrap \u2014 '
            '${error.toString().replaceFirst('Exception: ', '')}. '
            'Using cached local settings.',
      );
    }
    setState(() {
      _token = token;
      _profile = user;
      _settings = settings;
    });
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
    // Push any local courses + drafts created offline. We deliberately
    // skip _syncAllLocalData's inner _loadInitialData call to avoid
    // the double-bootstrap race that used to make "first login always
    // fail" \u2014 one flaky 401 on the second bootstrap was enough to
    // trip sessionRejected and wipe the freshly-issued token.
    try {
      await _syncAllLocalCourses();
      await _syncAllLocalDrafts();
    } catch (error) {
      _log(
        level: DebugLogLevel.warning,
        source: 'Portal.Sync.Notes/push_all',
        message:
            'Local push after login failed: '
            'Portal.Sync.Notes/push_all \u2014 '
            '${error.toString().replaceFirst('Exception: ', '')}. '
            'Will retry on next manual sync.',
      );
    }
    final displayName =
        user['username']?.toString() ??
            user['email']?.toString() ??
            'user';
    _log(
      level: DebugLogLevel.info,
      source: 'Portal.Auth/applyAuthPayload',
      message:
          'Session established: Portal.Auth/applyAuthPayload \u2014 '
          'authenticated as $displayName.',
    );
    if (mounted) {
      _showMessage('Signed in as $displayName.');
    }
  }

  Future<void> _logout() async {
    final token = _token;
    if (token == null || token.isEmpty) {
      return;
    }
    try {
      await widget.client.logout(token);
    } catch (error) {
      _log(
        level: DebugLogLevel.warning,
        source: 'Portal.Auth/logout',
        message:
            'Cloud logout call failed but local session cleared anyway: '
            'Portal.Auth/logout \u2014 '
            '${error.toString().replaceFirst('Exception: ', '')}.',
      );
    }
    setState(() {
      _token = null;
      _profile = null;
      _settings = null;
      _plannerEvents = const [];
      _deletedNotes = const [];
    });
    await _loadInitialData();
    _showMessage(
      'Signed out: Portal.Auth/logout \u2014 local session cleared.',
    );
    _log(
      level: DebugLogLevel.info,
      source: 'Portal.Auth/logout',
      message:
          'Signed out: Portal.Auth/logout \u2014 local session cleared.',
    );
  }

  bool _sameTrimmedValue(String a, String b) => a.trim() == b.trim();

  bool _sameEmailValue(String a, String b) =>
      a.trim().toLowerCase() == b.trim().toLowerCase();

  String _summarizeChangedFields(List<String> fields) {
    final unique = <String>[];
    for (final field in fields) {
      if (field.isEmpty || unique.contains(field)) {
        continue;
      }
      unique.add(field);
    }
    if (unique.isEmpty) {
      return 'settings';
    }
    if (unique.length == 1) {
      return unique.first;
    }
    if (unique.length == 2) {
      return '${unique.first} and ${unique.last}';
    }
    return '${unique[0]}, ${unique[1]} +${unique.length - 2}';
  }

  bool _sameNoteTitle(Map<String, dynamic> left, Map<String, dynamic> right) {
    final leftTitle = left['title']?.toString().trim().toLowerCase() ?? '';
    final rightTitle = right['title']?.toString().trim().toLowerCase() ?? '';
    return leftTitle.isNotEmpty && leftTitle == rightTitle;
  }

  Map<String, dynamic> _buildPulledLocalDraft(
    Map<String, dynamic> note, {
    Map<String, dynamic>? existingDraft,
  }) {
    final sourceAccount = _profile?['username']?.toString().trim().isNotEmpty == true
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
    if (!mounted) {
      return null;
    }
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
              Text(
                'Local',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                localDraft['description']?.toString().isNotEmpty == true
                    ? localDraft['description'].toString()
                    : _excerptFromMarkdown(
                        localDraft['content']?.toString() ?? '',
                      ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
              Text(
                'Cloud',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
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
            child: const Text('Keep local'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop('cloud'),
            child: const Text('Use server'),
          ),
        ],
      ),
    );
  }

  Future<ActionFeedback> _pullCloudNotesToLocal() async {
    final token = _token;
    if (token == null || token.isEmpty) {
      return const ActionFeedback(
        message: 'Cloud notes not pulled: '
            'Portal.Sync.Notes/pull \u2014 '
            'no cloud session; sign in first.',
        isError: true,
      );
    }
    try {
      final pulledDrafts = List<Map<String, dynamic>>.from(_localDrafts);
      var imported = 0;
      var updated = 0;
      var skipped = 0;
      var offset = 0;
      var hasMore = true;
      while (hasMore) {
        final page = await widget.client.listNotes(
          token: token,
          offset: offset,
          limit: 50,
        );
        final rows = (page['results'] as List<dynamic>? ?? const [])
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList(growable: false);
        hasMore = page['has_more'] == true && rows.isNotEmpty;
        offset += rows.length;
        for (final summary in rows) {
          final noteId = (summary['id'] as num?)?.toInt();
          if (noteId == null) {
            continue;
          }
          final detail = await widget.client.getNoteDetail(noteId, token: token);
          final pulledIndex = pulledDrafts.indexWhere((draft) {
            final metadata =
                _decodeNoteMetadata(draft['metadata_json']?.toString() ?? '{}');
            return (metadata['pulled_from_cloud_note_id'] as num?)?.toInt() ==
                noteId;
          });
          if (pulledIndex >= 0) {
            pulledDrafts[pulledIndex] = _buildPulledLocalDraft(
              detail,
              existingDraft: pulledDrafts[pulledIndex],
            );
            updated += 1;
            continue;
          }
          final conflictIndex =
              pulledDrafts.indexWhere((draft) => _sameNoteTitle(draft, detail));
          if (conflictIndex >= 0) {
            final decision = await _showPullConflictDialog(
              localDraft: pulledDrafts[conflictIndex],
              remoteNote: detail,
            );
            if (!mounted) {
              return const ActionFeedback(
                message: 'Cloud notes pull cancelled: '
                    'Portal.Sync.Notes/pull \u2014 '
                    'widget unmounted during conflict dialog.',
                isError: true,
              );
            }
            if (decision != 'cloud') {
              skipped += 1;
              continue;
            }
            pulledDrafts[conflictIndex] = _buildPulledLocalDraft(
              detail,
              existingDraft: pulledDrafts[conflictIndex],
            );
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
      if (mounted) {
        setState(() {});
      }
      final segments = <String>[];
      if (imported > 0) {
        segments.add('imported $imported');
      }
      if (updated > 0) {
        segments.add('updated $updated');
      }
      if (skipped > 0) {
        segments.add('kept $skipped local');
      }
      final summary = segments.isEmpty
          ? 'local copies already match the cloud'
          : segments.join(', ');
      _log(
        level: DebugLogLevel.info,
        source: 'Portal.Sync.Notes/pull',
        message:
            'Cloud notes pulled: Portal.Sync.Notes/pull \u2014 $summary.',
      );
      return ActionFeedback(
          message: 'Cloud notes pulled: '
              'Portal.Sync.Notes/pull \u2014 $summary.');
    } catch (error) {
      final cause = error.toString().replaceFirst('Exception: ', '');
      _log(
        level: DebugLogLevel.error,
        source: 'Portal.Sync.Notes/pull',
        message: 'Cloud notes not pulled: '
            'Portal.Sync.Notes/pull \u2014 $cause.',
      );
      return ActionFeedback(
          message: 'Cloud notes not pulled: '
              'Portal.Sync.Notes/pull \u2014 $cause.',
          isError: true);
    }
  }

  Future<ActionFeedback> _updateSettings(
    String username,
    String email,
    String motto,
    String socialLink,
    String editorMode,
    String themePreset,
    String themeMode,
    String apiBaseUrl,
  ) async {
    final currentSettings = Map<String, dynamic>.from(_settings ?? const {});
    final currentProfile = Map<String, dynamic>.from(_profile ?? const {});
    final currentUsername = currentSettings['username']?.toString() ??
        currentProfile['username']?.toString() ??
        '';
    final currentEmail = currentSettings['email']?.toString() ??
        currentProfile['email']?.toString() ??
        '';
    final currentMotto = currentSettings['motto']?.toString() ?? '';
    final currentSocialLink = currentSettings['social_link']?.toString() ?? '';
    final currentEditorMode = currentSettings['editor_mode']?.toString() ?? 'P';
    final currentThemePreset =
        _localSettings['theme_preset']?.toString() ?? 'teal';
    final currentThemeMode = _localSettings['theme_mode']?.toString() ?? 'S';
    final currentApiBase =
        _localSettings['api_base_url']?.toString() ?? _defaultApiBaseUrl();
    final nextApiBase = apiBaseUrl.trim().isEmpty || apiBaseUrl.trim().startsWith('/')
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
      // Before committing a user-entered API URL, confirm it's really a
      // Notechondria backend with compatible API version. If the handshake
      // fails we abort the save so the user keeps the old URL rather than
      // silently ending up on a dead/foreign host.
      final client = widget.client;
      if (client is HttpNotechondriaClient) {
        final handshake = await client.verifyHandshake(nextApiBase);
        if (!handshake.ok) {
          return ActionFeedback(
            message:
                'Backend handshake failed for $nextApiBase: ${handshake.error ?? 'unknown error'}',
          );
        }
      }
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
      'settings_saves': ((_localStats['settings_saves'] as num?)?.toInt() ?? 0) +
          1,
    };
    await _persistLocalStats();
    if (remotePayload.isEmpty && !localSettingsChanged) {
      return const ActionFeedback(
          message: 'No settings changes: '
              'Portal.Sync.Settings/save \u2014 '
              'nothing to save.');
    }
    final token = _token;
    if (token == null || token.isEmpty) {
      return const ActionFeedback(
          message: 'Settings saved locally: '
              'Portal.Sync.Settings/save \u2014 '
              'no cloud session; will push on next sign-in.');
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
      _showMessage(
        'Settings saved: Portal.Sync.Settings/save \u2014 $summary updated.',
      );
      _log(
        level: DebugLogLevel.info,
        source: 'Portal.Sync.Settings/save',
        message:
            'Settings saved: Portal.Sync.Settings/save \u2014 '
            '$summary pushed to cloud.',
      );
      return ActionFeedback(
          message: 'Settings saved: Portal.Sync.Settings/save \u2014 '
              '$summary updated.');
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
          if (remotePayload.containsKey('editor_mode')) 'editor_mode': editorMode,
          if (localSettingsChanged) 'theme_preset': themePreset,
          if (localSettingsChanged) 'theme_mode': themeMode,
          if (localSettingsChanged) 'api_base_url': nextApiBase,
        };
        _profile = {
          ...?_profile,
          'username': remotePayload.containsKey('username') && username.isNotEmpty
              ? username
              : fallbackUsername,
          'email': remotePayload.containsKey('email') && email.isNotEmpty
              ? email
              : fallbackEmail,
          'motto': remotePayload.containsKey('motto') ? motto : _profile?['motto'],
          'social_link': remotePayload.containsKey('social_link')
              ? socialLink
              : _profile?['social_link'],
        };
      });
      final summary = _summarizeChangedFields(changedFields);
      _log(
        level: DebugLogLevel.warning,
        source: 'Portal.Sync.Settings/save',
        message:
            'Settings saved locally, cloud push deferred: '
            'Portal.Sync.Settings/save \u2014 '
            'remote update for $summary failed ($detail).',
      );
      return ActionFeedback(
        message: 'Settings saved locally: '
            'Portal.Sync.Settings/save \u2014 '
            'sync pending for $summary (cloud: $detail).',
      );
    }
  }

  Future<ActionFeedback> _createPlannerEvent(
    String title,
    DateTime eventDate,
    int difficultyWeight,
    String description,
  ) async {
    final token = _token;
    if (token == null || token.isEmpty) {
      return const ActionFeedback(
        message: 'Planner event not created: '
            'Portal.Sync.Events/create \u2014 '
            'no cloud session; sign in first.',
        isError: true,
      );
    }
    try {
      await widget.client.createPlannerEvent(token, {
        'title': title,
        'event_date': _dateOnly(eventDate).toIso8601String().split('T').first,
        'starts_at': eventDate.toIso8601String(),
        'ends_at': eventDate.add(const Duration(hours: 1)).toIso8601String(),
        'difficulty_weight': difficultyWeight,
        'description': description,
        'course_id': _selectedCourse?['id'],
      });
      await _refreshFrontPageData();
      await _loadActivityWeek(startDate: _activityWeekStart);
      return const ActionFeedback(
          message: 'Planner event created: '
              'Portal.Sync.Events/create \u2014 '
              'added to the activity heatmap.');
    } catch (error) {
      final cause = error.toString().replaceFirst('Exception: ', '');
      return ActionFeedback(
        message: 'Planner event not created: '
            'Portal.Sync.Events/create \u2014 $cause.',
        isError: true,
      );
    }
  }

  Future<ActionFeedback> _uploadAvatar() async {
    final token = _token;
    if (token == null || token.isEmpty) {
      return const ActionFeedback(
        message: 'Avatar not updated: '
            'Portal.Sync.Settings/avatar.upload \u2014 '
            'no cloud session; sign in first.',
        isError: true,
      );
    }
    try {
      final file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(label: 'Images', extensions: ['png', 'jpg', 'jpeg', 'webp']),
        ],
      );
      if (file == null) {
        return const ActionFeedback(
            message: 'Avatar update cancelled: '
                'Portal.Sync.Settings/avatar.upload \u2014 '
                'user closed the file picker without selecting a file.');
      }
      final updated = await widget.client.uploadAvatar(token, file);
      _localStats = {
        ..._localStats,
        'avatar_updates':
            ((_localStats['avatar_updates'] as num?)?.toInt() ?? 0) + 1,
      };
      await _persistLocalStats();
      setState(() {
        _settings = updated;
        _profile = {
          ...?_profile,
          'image_url': updated['image_url'],
          'username': updated['username'] ?? _profile?['username'],
          'email': updated['email'] ?? _profile?['email'],
          'is_staff': updated['is_staff'] ?? _profile?['is_staff'],
          'is_superuser':
              updated['is_superuser'] ?? _profile?['is_superuser'],
        };
      });
      _log(
        level: DebugLogLevel.info,
        source: 'Portal.Sync.Settings/avatar.upload',
        message:
            'Avatar updated: Portal.Sync.Settings/avatar.upload \u2014 '
            'server accepted new image.',
      );
      return const ActionFeedback(
          message: 'Avatar updated: '
              'Portal.Sync.Settings/avatar.upload \u2014 '
              'server accepted new image.');
    } catch (error) {
      final cause = error.toString().replaceFirst('Exception: ', '');
      _log(
        level: DebugLogLevel.error,
        source: 'Portal.Sync.Settings/avatar.upload',
        message: 'Avatar not updated: '
            'Portal.Sync.Settings/avatar.upload \u2014 $cause.',
      );
      return ActionFeedback(
          message: 'Avatar not updated: '
              'Portal.Sync.Settings/avatar.upload \u2014 $cause.',
          isError: true);
    }
  }

  Future<void> _loadActivityWeek({DateTime? startDate}) async {
    final token = _token;
    if (token == null || token.isEmpty) {
      return;
    }
    final effectiveStart = _dateOnly(startDate ?? _activityWeekStart);
    try {
      final week = await widget.client.getActivityWeek(
        token,
        startDate: effectiveStart.toIso8601String().split('T').first,
      );
      setState(() {
        _activityWeekStart = effectiveStart;
        _activityWeek = week;
      });
      _log(
        level: DebugLogLevel.debug,
        source: 'Portal.Sync.Activity/load_week',
        message:
            'Activity week loaded: '
            'Portal.Sync.Activity/load_week \u2014 '
            'week starting ${effectiveStart.toIso8601String().split('T').first} '
            'pulled from server.',
      );
    } catch (error) {
      final cause = error.toString().replaceFirst('Exception: ', '');
      setState(() {
        _errorMessage = cause;
      });
      _log(
        level: DebugLogLevel.error,
        source: 'Portal.Sync.Activity/load_week',
        message: 'Activity week not loaded: '
            'Portal.Sync.Activity/load_week \u2014 $cause.',
      );
    }
  }

  Map<String, dynamic> _buildLocalCourse({
    required String title,
    String description = '',
    String? clientCourseId,
    String? createdAt,
    int? id,
  }) {
    final nowIso = DateTime.now().toUtc().toIso8601String();
    final effectiveTitle = title.trim().isEmpty ? 'Untitled course' : title.trim();
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

  Future<Map<String, dynamic>> _createLocalCourse(
    String title,
    String description,
  ) async {
    final course = _buildLocalCourse(title: title, description: description);
    _localCourses = [course, ..._localCourses];
    _localStats = {
      ..._localStats,
      'local_courses_created':
          ((_localStats['local_courses_created'] as num?)?.toInt() ?? 0) + 1,
    };
    await _persistLocalCourses();
    await _persistLocalStats();
    setState(() {
      _selectedCourse = course;
      _selectedIndex = 2;
      _courseNotes = _localNotesForCourse(course);
    });
    _log(
      level: DebugLogLevel.info,
      source: 'Portal.Sync.Courses/create_local',
      message:
          "Local course created: "
          "Portal.Sync.Courses/create_local \u2014 "
          "'${course['title']}' queued for sync on next sign-in.",
    );
    return course;
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

  Future<Map<String, dynamic>> _syncLocalCourse(Map<String, dynamic> course) async {
    final token = _token;
    if (token == null || token.isEmpty) {
      throw Exception(
        'Local course not synced: '
        'Portal.Sync.Courses/push \u2014 '
        'no cloud session; sign in first.',
      );
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
    await _moveCourseToLocalTrash(course, serverCourseId: remoteId);
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
    _log(
      level: DebugLogLevel.info,
      source: 'Portal.Sync.Courses/push',
      message:
          "Local course synced: Portal.Sync.Courses/push \u2014 "
          "'${course['title']}' created on server; local ID remapped; "
          'local copy moved to client-side recycle bin.',
    );
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

  Future<Map<String, dynamic>> _syncLocalDraft(Map<String, dynamic> draft) async {
    final token = _token;
    if (token == null || token.isEmpty) {
      throw Exception(
        'Local draft not synced: '
        'Portal.Sync.Notes/push \u2014 '
        'no cloud session; sign in first.',
      );
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
        metadata = {
          ...metadata,
          'course_id': syncedCourse['id'],
        };
        draft = _remapDraftCourseId(
          draft,
          assignedCourseId,
          syncedCourse['id'] as int,
        );
      }
    }
    final pulledFromNoteId =
        (metadata['pulled_from_cloud_note_id'] as num?)?.toInt();
    final pulledFromAccount =
        metadata['pulled_from_account']?.toString().trim().toLowerCase() ?? '';
    final currentAccount = (_profile?['username']?.toString().trim().isNotEmpty == true
            ? _profile!['username'].toString().trim()
            : _profile?['email']?.toString().trim() ?? '')
        .toLowerCase();
    if (pulledFromNoteId != null &&
        pulledFromNoteId > 0 &&
        pulledFromAccount.isNotEmpty &&
        pulledFromAccount == currentAccount) {
      final updated = await widget.client.updateNote(token, pulledFromNoteId, {
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
      if (mounted) {
        setState(() {});
      }
      _log(
        level: DebugLogLevel.info,
        source: 'Portal.Sync.Notes/push',
        message:
            "Local cloud-copy draft synced: "
            "Portal.Sync.Notes/push \u2014 "
            "'${draft['title']}' upstream note updated in place.",
      );
      return updated;
    }
    final created = await widget.client.createNote(token, {
      'title': draft['title'],
      'description': draft['description'] ?? '',
      'content': draft['content'] ?? '',
      'editor_mode': draft['editor_mode'] ?? 'P',
      'course_id': metadata['course_id'],
      'metadata_json': jsonEncode(metadata),
      'client_draft_id': draft['client_draft_id'],
      'is_public': false,
    });
    _localDrafts = _localDrafts
        .where((item) => item['id'] != draft['id'])
        .toList(growable: false);
    await _moveDraftToLocalTrash(
      draft,
      serverNoteId: (created['id'] as num?)?.toInt(),
      serverNoteUuid: created['uuid']?.toString(),
    );
    _localStats = {
      ..._localStats,
      'local_drafts_synced':
          ((_localStats['local_drafts_synced'] as num?)?.toInt() ?? 0) + 1,
      'last_sync_at': DateTime.now().toUtc().toIso8601String(),
    };
    await _persistLocalDrafts();
    await _persistLocalStats();
    await _loadLearnerNotes(reset: true, query: _learnerSearchQuery);
    await _refreshFrontPageData();
    if (mounted) {
      setState(() {});
    }
    _log(
      level: DebugLogLevel.info,
      source: 'Portal.Sync.Notes/push',
      message:
          "Local draft synced: Portal.Sync.Notes/push \u2014 "
          "'${draft['title']}' created on server; local draft moved to "
          'client-side recycle bin.',
    );
    return created;
  }

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
    final payload = {
      'title': title ?? _extractTitleFromMarkdown(initialMarkdown),
      'description': description ?? _excerptFromMarkdown(initialMarkdown),
      'content': initialMarkdown,
      'editor_mode': mode,
      'course_id': null,
      'client_draft_id': clientDraftId,
      'metadata_json': jsonEncode({'section': '', 'autosave': false}),
    };
    try {
      final created = await widget.client.createNote(token, payload);
      await _loadLearnerNotes(reset: true, query: _learnerSearchQuery);
      setState(() {
        _selectedNote = created;
        _selectedIndex = 1;
      });
      return created;
    } catch (error) {
      final draft = _storeLocalDraft(
        _buildOfflineFallbackDraft(payload: payload),
        incrementCreated: true,
      );
      await _persistLocalDrafts();
      await _persistLocalStats();
      final cause = error.toString().replaceFirst('Exception: ', '');
      setState(() {
        _selectedNote = draft;
        _selectedIndex = 1;
      });
      _log(
        level: DebugLogLevel.warning,
        source: 'Portal.Sync.Notes/create',
        message:
            'Note saved locally, cloud create deferred: '
            'Portal.Sync.Notes/create \u2014 $cause.',
      );
      _showMessage(
        'Note saved locally: Portal.Sync.Notes/create \u2014 '
        'backend unavailable ($cause); kept as draft for next sync.',
      );
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
      if (existing.isEmpty) {
        throw Exception(
          'Local draft not found: '
          'Portal.Sync.Notes/save_local \u2014 '
          'no local draft matches the requested id.',
        );
      }
      final updated = _buildLocalDraft(
        id: noteId,
        title: payload['title']?.toString() ?? existing['title']?.toString() ?? 'Untitled note',
        description:
            payload['description']?.toString() ?? existing['description']?.toString() ?? '',
        content: payload['content']?.toString() ?? existing['content']?.toString() ?? '',
        editorMode: payload['editor_mode']?.toString() ??
            existing['editor_mode']?.toString() ??
            'P',
        clientDraftId: existing['client_draft_id']?.toString(),
        createdAt: existing['date_created']?.toString(),
        metadataJson:
            payload['metadata_json']?.toString() ?? existing['metadata_json']?.toString() ?? '{}',
      );
      _localDrafts = _localDrafts
          .map((item) => item['id'] == noteId ? updated : item)
          .toList(growable: false);
      await _persistLocalDrafts();
      setState(() {
        _selectedNote = updated;
      });
      return updated;
    }
    final token = _token;
    if (token == null || token.isEmpty) {
      throw Exception(
        'Note not saved: '
        'Portal.Sync.Notes/save \u2014 '
        'no cloud session; sign in first.',
      );
    }
    try {
      final updated = await widget.client.updateNote(token, noteId, payload);
      await _loadLearnerNotes(reset: true, query: _learnerSearchQuery);
      setState(() {
        _selectedNote = updated;
      });
      return updated;
    } catch (error) {
      final sourceNote = _selectedNote?['id'] == noteId
          ? Map<String, dynamic>.from(_selectedNote!)
          : null;
      final fallbackDraft = _storeLocalDraft(
        _buildOfflineFallbackDraft(
          sourceNote: sourceNote,
          payload: payload,
        ),
      );
      await _persistLocalDrafts();
      final message = error.toString().replaceFirst('Exception: ', '');
      setState(() {
        _selectedNote = fallbackDraft;
      });
      _log(
        level: DebugLogLevel.warning,
        source: 'Portal.Sync.Notes/save',
        message:
            'Note save deferred to local draft: '
            'Portal.Sync.Notes/save \u2014 $message.',
      );
      _showMessage(
        'Note saved locally: Portal.Sync.Notes/save \u2014 '
        'backend unavailable ($message); changes kept as a local draft.',
      );
      return fallbackDraft;
    }
  }

  Future<List<Map<String, dynamic>>> _getNoteHistory(int noteId) async {
    final token = _token;
    if (token == null || token.isEmpty || noteId < 0) {
      return const [];
    }
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
      throw Exception(
        'Note version not restored: '
        'Portal.Sync.Notes/restore_version \u2014 '
        'no cloud session or note is local-only; sign in first.',
      );
    }
    final restored =
        await widget.client.restoreNoteVersion(token, noteId, versionId);
    await _loadLearnerNotes(reset: true, query: _learnerSearchQuery);
    setState(() {
      _selectedNote = restored;
    });
    return restored;
  }

  Future<void> _importMarkdownNote() async {
    try {
      final file = await openFile(
        acceptedTypeGroups: [
          const XTypeGroup(
              label: 'Markdown', extensions: ['md', 'markdown', 'txt']),
        ],
      );
      if (file == null) {
        return;
      }
      final contents = await file.readAsString();
      final created = await _createNote(
        markdown: contents,
        title: _extractTitleFromMarkdown(contents),
        description: '',
      );
      _showMessage("Imported '${created['title']}'.");
    } catch (error) {
      _showMessage(error.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _exportNote(Map<String, dynamic> note) async {
    try {
      final detail = note['content'] != null
          ? note
          : await _fetchNoteDetail(note['id'] as int);
      final location = await getSaveLocation(
        suggestedName: '${detail['title'] ?? 'note'}.md',
        acceptedTypeGroups: [
          const XTypeGroup(label: 'Markdown', extensions: ['md']),
        ],
      );
      if (location == null) {
        return;
      }
      final bytes = Uint8List.fromList(utf8
          .encode(detail['content']?.toString() ?? _noteToMarkdown(detail)));
      final file = XFile.fromData(bytes,
          name: '${detail['title'] ?? 'note'}.md', mimeType: 'text/markdown');
      await file.saveTo(location.path);
      _showMessage("Exported '${detail['title'] ?? 'note'}'.");
    } catch (error) {
      _showMessage(error.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _refreshCalendarState() async {
    final token = _token;
    if (token == null || token.isEmpty) {
      return;
    }
    final feeds = await widget.client.getCalendarFeeds(token);
    final week = await widget.client.getActivityWeek(
      token,
      startDate: _activityWeekStart.toIso8601String().split('T').first,
    );
    setState(() {
      _calendarFeeds = feeds;
      _activityWeek = week;
    });
    _log(
      level: DebugLogLevel.debug,
      source: 'Portal.Sync.Calendar/refresh',
      message:
          'Calendar state refreshed: '
          'Portal.Sync.Calendar/refresh \u2014 '
          'feeds and activity week re-pulled.',
    );
  }

  Future<void> _importCalendarFeed(String rawIcal, String title,
      {int? courseId}) async {
    final token = _token;
    if (token == null || token.isEmpty) {
      throw Exception(
        'Calendar not imported: '
        'Portal.Sync.Calendar/import \u2014 '
        'no cloud session; sign in first.',
      );
    }
    await widget.client.createCalendarFeed(token, {
      'title': title,
      'source_kind': 'I',
      'raw_ical': rawIcal,
      'course_id': courseId,
    });
    await _refreshCalendarState();
    _log(
      level: DebugLogLevel.info,
      source: 'Portal.Sync.Calendar/import',
      message:
          'Calendar imported: Portal.Sync.Calendar/import \u2014 '
          '"$title" iCal feed added.',
    );
  }

  Future<void> _subscribeCalendarFeed(String title, String url,
      {int? courseId}) async {
    final token = _token;
    if (token == null || token.isEmpty) {
      throw Exception(
        'Calendar not subscribed: '
        'Portal.Sync.Calendar/subscribe \u2014 '
        'no cloud session; sign in first.',
      );
    }
    await widget.client.createCalendarFeed(token, {
      'title': title,
      'source_kind': 'S',
      'source_url': url,
      'course_id': courseId,
    });
    await _refreshCalendarState();
    _log(
      level: DebugLogLevel.info,
      source: 'Portal.Sync.Calendar/subscribe',
      message:
          'Calendar subscribed: '
          'Portal.Sync.Calendar/subscribe \u2014 '
          '"$title" feed URL registered.',
    );
  }

  Future<void> _toggleCalendarFeed(
      Map<String, dynamic> feed, bool enabled) async {
    final token = _token;
    if (token == null || token.isEmpty) {
      return;
    }
    await widget.client
        .updateCalendarFeed(token, feed['id'] as int, {'is_enabled': enabled});
    await _refreshCalendarState();
    _log(
      level: DebugLogLevel.info,
      source: 'Portal.Sync.Calendar/toggle',
      message:
          'Calendar feed ${enabled ? "enabled" : "disabled"}: '
          'Portal.Sync.Calendar/toggle \u2014 '
          '"${feed['title']}" now ${enabled ? "visible" : "hidden"}.',
    );
  }

  Future<void> _deleteCalendarFeed(Map<String, dynamic> feed) async {
    final token = _token;
    if (token == null || token.isEmpty) {
      return;
    }
    await widget.client.deleteCalendarFeed(token, feed['id'] as int);
    await _refreshCalendarState();
    _log(
      level: DebugLogLevel.info,
      source: 'Portal.Sync.Calendar/delete',
      message:
          'Calendar feed deleted: '
          'Portal.Sync.Calendar/delete \u2014 '
          '"${feed['title']}" removed from the portal.',
    );
  }

  Future<int?> _startNoteSession(
      int noteId, String title, String summary) async {
    final token = _token;
    if (token == null || token.isEmpty || noteId < 0) {
      return null;
    }
    try {
      final session = await widget.client.startNoteSession(token, {
        'note_id': noteId,
        'title': title,
        'summary': summary,
        'started_at': DateTime.now().toIso8601String(),
      });
      _log(
        level: DebugLogLevel.info,
        source: 'Portal.UI/note_session.start',
        message:
            'Note session started: '
            'Portal.UI/note_session.start \u2014 '
            'tracking edits to "$title".',
      );
      return session['id'] as int?;
    } catch (error) {
      final cause = error.toString().replaceFirst('Exception: ', '');
      _log(
        level: DebugLogLevel.error,
        source: 'Portal.UI/note_session.start',
        message:
            'Note session not started: '
            'Portal.UI/note_session.start \u2014 $cause.',
      );
      return null;
    }
  }

  Future<void> _finishNoteSession(int? sessionId,
      {String? title, String? summary}) async {
    final token = _token;
    if (token == null || token.isEmpty || sessionId == null) {
      return;
    }
    try {
      await widget.client.updateNoteSession(token, sessionId, {
        if (title != null) 'title': title,
        if (summary != null) 'summary': summary,
        'ended_at': DateTime.now().toIso8601String(),
      });
      await _loadActivityWeek(startDate: _activityWeekStart);
      _log(
        level: DebugLogLevel.info,
        source: 'Portal.UI/note_session.finish',
        message:
            'Note session finished: '
            'Portal.UI/note_session.finish \u2014 '
            'session $sessionId closed on server.',
      );
    } catch (error) {
      final cause = error.toString().replaceFirst('Exception: ', '');
      _log(
        level: DebugLogLevel.warning,
        source: 'Portal.UI/note_session.finish',
        message:
            'Note session not closed: '
            'Portal.UI/note_session.finish \u2014 $cause.',
      );
    }
  }

  Future<void> _deleteNoteToRecycleBin(Map<String, dynamic> note) async {
    final noteId = (note['id'] as num?)?.toInt();
    if (noteId == null) {
      return;
    }
    if (noteId < 0) {
      _localDrafts = _localDrafts
          .where((item) => item['id'] != noteId)
          .toList(growable: false);
      await _persistLocalDrafts();
      setState(() {});
      _log(
        level: DebugLogLevel.info,
        source: 'Portal.Sync.Notes/delete_local',
        message:
            "Local draft deleted: "
            "Portal.Sync.Notes/delete_local \u2014 "
            "'${note['title']}' removed from offline store.",
      );
      return;
    }
    final token = _token;
    if (token == null || token.isEmpty) {
      throw Exception(
        'Note not deleted: '
        'Portal.Sync.Notes/delete \u2014 '
        'no cloud session; sign in first.',
      );
    }
    await widget.client.deleteNote(token, noteId);
    _deletedNotes = await widget.client.getDeletedNotes(token);
    await _loadLearnerNotes(reset: true, query: _learnerSearchQuery);
    await _refreshFrontPageData();
    setState(() {});
    _log(
      level: DebugLogLevel.info,
      source: 'Portal.Sync.Notes/delete',
      message:
          "Note moved to recycle bin: "
          "Portal.Sync.Notes/delete \u2014 "
          "'${note['title']}' soft-deleted on server.",
    );
  }

  Future<void> _restoreDeletedNote(Map<String, dynamic> note) async {
    final token = _token;
    if (token == null || token.isEmpty) {
      throw Exception(
        'Note not restored: '
        'Portal.Sync.Notes/restore \u2014 '
        'no cloud session; sign in first.',
      );
    }
    final noteId = (note['id'] as num?)?.toInt();
    if (noteId == null) {
      return;
    }
    await widget.client.restoreDeletedNote(token, noteId);
    _deletedNotes = await widget.client.getDeletedNotes(token);
    await _loadLearnerNotes(reset: true, query: _learnerSearchQuery);
    setState(() {});
    _log(
      level: DebugLogLevel.info,
      source: 'Portal.Sync.Notes/restore',
      message:
          "Note restored: Portal.Sync.Notes/restore \u2014 "
          "'${note['title']}' removed from the recycle bin.",
    );
  }

  Future<void> _emptyDeletedNotes() async {
    final token = _token;
    if (token == null || token.isEmpty) {
      throw Exception(
        'Recycle bin not emptied: '
        'Portal.Sync.Notes/empty_trash \u2014 '
        'no cloud session; sign in first.',
      );
    }
    await widget.client.emptyDeletedNotes(token);
    setState(() {
      _deletedNotes = const [];
    });
    _log(
      level: DebugLogLevel.info,
      source: 'Portal.Sync.Notes/empty_trash',
      message:
          'Recycle bin emptied: Portal.Sync.Notes/empty_trash \u2014 '
          'all soft-deleted notes purged on the server.',
    );
  }

  Future<void> _syncAllLocalCourses() async {
    if (_localCourses.isEmpty) {
      return;
    }
    // Per-item try/catch so one failing course doesn't abort the
    // loop and orphan later items.
    for (final course in List<Map<String, dynamic>>.from(_localCourses)) {
      try {
        await _syncLocalCourse(course);
      } catch (error) {
        _log(
          level: DebugLogLevel.warning,
          source: 'Portal.Sync.Courses/push',
          message: 'Local category not synced: '
              'Portal.Sync.Courses/push \u2014 '
              "'${course['title']}' "
              '(${error.toString().replaceFirst('Exception: ', '')}). '
              'Kept locally; will retry on next sync.',
        );
      }
    }
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _syncAllLocalDrafts() async {
    if (_localDrafts.isEmpty) {
      return;
    }
    for (final draft in List<Map<String, dynamic>>.from(_localDrafts)) {
      try {
        await _syncLocalDraft(draft);
      } catch (error) {
        _log(
          level: DebugLogLevel.warning,
          source: 'Portal.Sync.Notes/push',
          message: 'Local draft not synced: '
              'Portal.Sync.Notes/push \u2014 '
              "'${draft['title']}' "
              '(${error.toString().replaceFirst('Exception: ', '')}). '
              'Kept locally; will retry on next sync.',
        );
      }
    }
    if (mounted) {
      setState(() {});
    }
  }

  Future<ActionFeedback> _syncAllLocalData({bool showMessage = true}) async {
    final token = _token;
    if (token == null || token.isEmpty) {
      return const ActionFeedback(
        message: 'Local data not synced: '
            'Portal.Sync.Notes/push_all \u2014 '
            'no cloud session; sign in first.',
        isError: true,
      );
    }
    try {
      await _syncAllLocalCourses();
      await _syncAllLocalDrafts();
      await _loadInitialData();
      const feedback = ActionFeedback(
          message: 'Local data synced: '
              'Portal.Sync.Notes/push_all \u2014 '
              'all local courses and drafts pushed to cloud.');
      if (showMessage) {
        _showMessage(feedback.message);
      }
      return feedback;
    } catch (error) {
      _localStats = {
        ..._localStats,
        'sync_failures': ((_localStats['sync_failures'] as num?)?.toInt() ?? 0) + 1,
      };
      await _persistLocalStats();
      final cause = error.toString().replaceFirst('Exception: ', '');
      _log(
        level: DebugLogLevel.error,
        source: 'Portal.Sync.Notes/push_all',
        message: 'Local data not synced: '
            'Portal.Sync.Notes/push_all \u2014 $cause.',
      );
      if (showMessage) {
        _showMessage(
          'Local data not synced: '
          'Portal.Sync.Notes/push_all \u2014 $cause.',
        );
      }
      return ActionFeedback(
          message: 'Local data not synced: '
              'Portal.Sync.Notes/push_all \u2014 $cause.',
          isError: true);
    }
  }

  Future<ActionFeedback> _clearLocalCache() async {
    _localCache = _LocalAppStore.defaultCache();
    _frontPage = _localCourses.isNotEmpty
        ? _frontPageFallbackPayload(const [])
        : const <String, dynamic>{};
    _courses = const [];
    _activity = const [];
    _courseNotes = _isLocalCourse(_selectedCourse)
        ? _localNotesForCourse(_selectedCourse!)
        : const [];
    _selectedCourse = _isLocalCourse(_selectedCourse)
        ? _selectedCourse
        : _chooseDefaultCourse(
            remoteCourses: const [],
            localCourses: _localCourses,
            frontPage: _frontPage,
          );
    _localStats = {
      ..._localStats,
      'cache_clears': ((_localStats['cache_clears'] as num?)?.toInt() ?? 0) + 1,
    };
    await _LocalAppStore.saveCache(_localCache);
    await _persistLocalStats();
    if (mounted) {
      setState(() {});
    }
    _log(
      level: DebugLogLevel.info,
      source: 'Portal.LocalStore/clear_cache',
      message:
          'Cached remote data cleared: '
          'Portal.LocalStore/clear_cache \u2014 '
          'front-page/courses/activity wiped; local drafts untouched.',
    );
    return const ActionFeedback(
        message: 'Cached remote data cleared: '
            'Portal.LocalStore/clear_cache \u2014 '
            'cloud rows wiped; local drafts kept.');
  }

  Future<ActionFeedback> _clearLocalData() async {
    _localDrafts = const [];
    _localCourses = const [];
    _localTrashedDrafts = const [];
    _localTrashedCourses = const [];
    _selectedNote = null;
    if (_selectedCourse != null && _isLocalCourse(_selectedCourse)) {
      _selectedCourse = _chooseDefaultCourse(
        remoteCourses: _courses,
        localCourses: const [],
        frontPage: _frontPage,
      );
      _courseNotes = _selectedCourse == null || _isLocalCourse(_selectedCourse)
          ? const []
          : _courseNotes;
    }
    _localStats = {
      ..._localStats,
      'local_data_clears':
          ((_localStats['local_data_clears'] as num?)?.toInt() ?? 0) + 1,
    };
    await _persistLocalDrafts();
    await _persistLocalCourses();
    await _persistLocalTrashedDrafts();
    await _persistLocalTrashedCourses();
    await _persistLocalStats();
    if (mounted) {
      setState(() {});
    }
    _log(
      level: DebugLogLevel.info,
      source: 'Portal.LocalStore/clear',
      message:
          'Local data cleared: Portal.LocalStore/clear \u2014 '
          'local drafts and local courses wiped.',
    );
    return const ActionFeedback(
        message: 'Local data cleared: '
            'Portal.LocalStore/clear \u2014 '
            'local drafts and local courses removed.');
  }

  Future<void> _togglePlannerEventCompletion(
      Map<String, dynamic> event, bool completed) async {
    final token = _token;
    if (token == null || token.isEmpty) {
      throw Exception(
        'Planner event not updated: '
        'Portal.Sync.Events/toggle \u2014 '
        'no cloud session; sign in first.',
      );
    }
    await widget.client.updatePlannerEvent(token, event['id'] as int, {
      'is_completed': completed,
      'completed_at': completed
          ? DateTime.now().toUtc().toIso8601String()
          : null,
    });
    await _loadActivityWeek(startDate: _activityWeekStart);
    final refreshedEvents = await widget.client.getPlannerEvents(token);
    setState(() {
      _plannerEvents = refreshedEvents;
    });
    _log(
      level: DebugLogLevel.info,
      source: 'Portal.Sync.Events/toggle',
      message:
          'Planner event ${completed ? "completed" : "reopened"}: '
          'Portal.Sync.Events/toggle \u2014 '
          '"${event['title']}" state updated on server.',
    );
  }

  Future<void> _subscribeToCourse(Map<String, dynamic> course) async {
    final token = _token;
    if (token == null || token.isEmpty) {
      throw Exception(
        'Course not subscribed: '
        'Portal.Sync.Courses/subscribe \u2014 '
        'no cloud session; sign in first.',
      );
    }
    await widget.client.subscribeCourse(token, course['id'] as int);
    await _loadInitialData();
  }

  Future<void> _unsubscribeFromCourse(Map<String, dynamic> course) async {
    final token = _token;
    if (token == null || token.isEmpty) {
      throw Exception(
        'Course not unsubscribed: '
        'Portal.Sync.Courses/unsubscribe \u2014 '
        'no cloud session; sign in first.',
      );
    }
    await widget.client.unsubscribeCourse(token, course['id'] as int);
    await _loadInitialData();
  }

  Future<void> _copyFrontendLogs() async {
    final content = _uiLogs.join('\n');
    await Clipboard.setData(ClipboardData(text: content));
    setState(() {
      _localStats = {
        ..._localStats,
        'logs_copied': ((_localStats['logs_copied'] as num?)?.toInt() ?? 0) + 1,
      };
    });
    await _persistLocalStats();
    _showMessage(
      'Logs copied: Portal.LocalStore/copy_logs \u2014 '
      'frontend debug log now on the clipboard.',
    );
  }

  Future<ActionFeedback> _restoreTemplateCourses() async {
    final token = _token;
    if (token == null || token.isEmpty) {
      return const ActionFeedback(
        message: 'Template courses not restored: '
            'Portal.LocalStore/restore_templates \u2014 '
            'no cloud session; sign in with an admin account first.',
        isError: true,
      );
    }
    try {
      final result = await widget.client.restoreTemplateCourses(token);
      await _loadInitialData();
      final serverMessage = result['message']?.toString();
      final message = serverMessage != null && serverMessage.isNotEmpty
          ? 'Template courses restored: '
              'Portal.LocalStore/restore_templates \u2014 $serverMessage'
          : 'Template courses restored: '
              'Portal.LocalStore/restore_templates \u2014 '
              'server seeded default portal template tree.';
      _log(
        level: DebugLogLevel.info,
        source: 'Portal.LocalStore/restore_templates',
        message: message,
      );
      _showMessage(message);
      return ActionFeedback(message: message);
    } catch (error) {
      final cause = error.toString().replaceFirst('Exception: ', '');
      _log(
        level: DebugLogLevel.error,
        source: 'Portal.LocalStore/restore_templates',
        message: 'Template courses not restored: '
            'Portal.LocalStore/restore_templates \u2014 $cause.',
      );
      return ActionFeedback(
          message: 'Template courses not restored: '
              'Portal.LocalStore/restore_templates \u2014 $cause.',
          isError: true);
    }
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

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
                          for (final index in _visibleIndices.where((index) => index != 4))
                            SidebarItem(
                              icon: (_destinations[index].icon as Icon).icon!,
                              label: _titles[index],
                              selected: _selectedIndex == index,
                              onTap: () => _selectActualIndex(index),
                            ),
                          if (subscribedCourses.isNotEmpty && _visibleIndices.contains(2)) ...[
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
          onLogEvent: _appendUiLog,
        );
      case 2:
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
      case 3:
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
          debugLogController: _logController,
          uiLogs: _uiLogs,
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
