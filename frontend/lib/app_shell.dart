part of notechondria_frontend;

/// Root application widget that configures theme state and launches the shell.
class NotechondriaApp extends StatefulWidget {
  const NotechondriaApp({super.key, this.client});

  final NotechondriaClient? client;

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
      title: 'Notechondria',
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
      ),
    );
  }
}

/// Main application shell that owns loading, navigation, and shared app state.
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.client, this.onThemeChanged});

  final NotechondriaClient client;
  final void Function(String preset, String mode)? onThemeChanged;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;
  bool _isLoading = true;
  String? _errorMessage;
  String? _token;
  Map<String, dynamic>? _profile;
  Map<String, dynamic>? _settings;
  Map<String, dynamic>? _frontPage;
  List<Map<String, dynamic>> _courses = const [];
  List<Map<String, dynamic>> _courseNotes = const [];
  List<Map<String, dynamic>> _learnerNotes = const [];
  List<Map<String, dynamic>> _localDrafts = const [];
  List<Map<String, dynamic>> _deletedNotes = const [];
  List<Map<String, dynamic>> _activity = const [];
  List<Map<String, dynamic>> _plannerEvents = const [];
  List<Map<String, dynamic>> _calendarFeeds = const [];
  Map<String, dynamic>? _activityWeek;
  Map<String, dynamic>? _selectedCourse;
  Map<String, dynamic>? _selectedNote;
  Map<String, dynamic> _localSettings = _LocalAppStore.defaultSettings();
  Map<String, dynamic> _localStats = _LocalAppStore.defaultStats();
  DateTime _activityWeekStart = _dateOnly(DateTime.now());
  bool _hasMoreLearnerNotes = true;
  bool _isLoadingMoreNotes = false;
  bool _coursePanelExpanded = true;
  int _learnerNotesOffset = 0;
  String _learnerSearchQuery = '';
  final List<String> _uiLogs = <String>[];

  HttpNotechondriaClient? get _httpClient =>
      widget.client is HttpNotechondriaClient
          ? widget.client as HttpNotechondriaClient
          : null;

  static const List<String> _titles = [
    'Front Page',
    'Learner View',
    'Course View',
    'Activity View',
    'Settings',
  ];

  static const List<NavigationDestination> _destinations = [
    NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Front'),
    NavigationDestination(
        icon: Icon(Icons.menu_book_outlined), label: 'Learner'),
    NavigationDestination(icon: Icon(Icons.school_outlined), label: 'Course'),
    NavigationDestination(
        icon: Icon(Icons.timeline_outlined), label: 'Activity'),
    NavigationDestination(
        icon: Icon(Icons.settings_outlined), label: 'Settings'),
  ];

  bool _showWidePageHeader(int index) => index >= 3;

  @override
  void initState() {
    super.initState();
    _bootstrapApp();
  }

  Future<void> _bootstrapApp() async {
    await _loadLocalState();
    await _loadInitialData();
  }

  void _appendUiLog(String message) {
    final timestamp = DateTime.now().toIso8601String();
    setState(() {
      _uiLogs.insert(0, '[$timestamp] $message');
      if (_uiLogs.length > 80) {
        _uiLogs.removeRange(80, _uiLogs.length);
      }
    });
  }

  Future<void> _loadLocalState() async {
    final snapshot = await _LocalAppStore.load();
    _localSettings = snapshot.settings;
    _localDrafts = snapshot.drafts;
    _localStats = snapshot.stats;
    _httpClient?.updateBaseUrl(
      _localSettings['api_base_url']?.toString() ?? 'http://localhost:9080/api/v1',
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

  Future<void> _persistLocalStats() async {
    await _LocalAppStore.saveStats(_localStats);
  }

  Future<void> _loadInitialData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      _httpClient?.updateBaseUrl(
        _localSettings['api_base_url']?.toString() ?? 'http://localhost:9080/api/v1',
      );
      widget.onThemeChanged?.call(
        _localSettings['theme_preset']?.toString() ?? 'teal',
        _localSettings['theme_mode']?.toString() ?? 'S',
      );
      final frontPage = await widget.client.getFrontPage(token: _token);
      final courses = await widget.client.getCourses(token: _token);
      final activity = await widget.client.getActivity(token: _token);
      final defaultCourse = frontPage['default_course'] as Map<String, dynamic>?;
      final retainedCourseId = (_selectedCourse?['id'] as num?)?.toInt();
      Map<String, dynamic>? selectedCourse;
      if (retainedCourseId != null) {
        for (final course in courses) {
          if (course['id'] == retainedCourseId) {
            selectedCourse = Map<String, dynamic>.from(course);
            break;
          }
        }
      }
      selectedCourse ??= defaultCourse != null
          ? Map<String, dynamic>.from(defaultCourse)
          : (courses.isNotEmpty ? Map<String, dynamic>.from(courses.first) : null);
      List<Map<String, dynamic>> courseNotes = const [];
      if (selectedCourse != null) {
        courseNotes = await widget.client.getCourseNotes(
          selectedCourse['id'] as int,
          token: _token,
        );
      }
      List<Map<String, dynamic>> plannerEvents = const [];
      List<Map<String, dynamic>> calendarFeeds = const [];
      List<Map<String, dynamic>> learnerNotes = const [];
      List<Map<String, dynamic>> deletedNotes = const [];
      Map<String, dynamic>? activityWeek;
      Map<String, dynamic> notePage = const {
        'results': [],
        'has_more': false,
      };
      if (_token != null && _token!.isNotEmpty) {
        plannerEvents = await widget.client.getPlannerEvents(_token!);
        calendarFeeds = await widget.client.getCalendarFeeds(_token!);
        activityWeek = await widget.client.getActivityWeek(
          _token!,
          startDate: _activityWeekStart.toIso8601String().split('T').first,
        );
        deletedNotes = await widget.client.getDeletedNotes(_token!);
        notePage =
            await widget.client.listNotes(token: _token, limit: 20, offset: 0);
        learnerNotes = (notePage['results'] as List<dynamic>? ?? const [])
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();
      }
      setState(() {
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
        _isLoading = false;
      });
      _appendUiLog('Initial data loaded.');
    } catch (error) {
      setState(() {
        _errorMessage = error.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
      });
      _appendUiLog(
          'Initial load failed: ${error.toString().replaceFirst('Exception: ', '')}');
    }
  }

  Future<void> _refreshFrontPageData() async {
    final frontPage = await widget.client.getFrontPage(token: _token);
    List<Map<String, dynamic>> plannerEvents = _plannerEvents;
    if (_token != null && _token!.isNotEmpty) {
      plannerEvents = await widget.client.getPlannerEvents(_token!);
    }
    setState(() {
      _frontPage = frontPage;
      _plannerEvents = plannerEvents;
    });
    _appendUiLog('Front page refreshed.');
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
      _appendUiLog(
          'Learner notes load failed: ${error.toString().replaceFirst('Exception: ', '')}');
    }
  }

  Future<void> _selectCourse(Map<String, dynamic> course) async {
    setState(() {
      _selectedCourse = course;
      _isLoading = true;
    });
    try {
      var effectiveCourse = Map<String, dynamic>.from(course);
      if ((_token?.isNotEmpty ?? false) && course['is_subscribed'] == true) {
        effectiveCourse =
            await widget.client.openCourse(_token!, course['id'] as int);
      }
      final refreshedCourses = await widget.client.getCourses(token: _token);
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
        _isLoading = false;
      });
      _appendUiLog('Opened course ${refreshedSelected['title']}.');
    } catch (error) {
      setState(() {
        _errorMessage = error.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
      });
      _appendUiLog(
          'Course load failed: ${error.toString().replaceFirst('Exception: ', '')}');
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
      setState(() {
        _errorMessage = error.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
      });
      _appendUiLog(
          'Note selection failed: ${error.toString().replaceFirst('Exception: ', '')}');
    }
  }

  Future<void> _openNoteViewer(Map<String, dynamic> noteSummary) async {
    final detail = await _fetchNoteDetail(noteSummary['id'] as int);
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
        throw Exception('Local draft not found.');
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

  Future<ActionFeedback> _register(String email, String password) async {
    try {
      final result = await widget.client.register(email, password);
      return ActionFeedback(
          message: result['message']?.toString() ?? 'Verification email sent.');
    } catch (error) {
      return ActionFeedback(
        message: error.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
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
        isError: true,
      );
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
        isError: true,
      );
    }
  }

  Future<ActionFeedback> _requestPasswordReset(String email) async {
    try {
      final result = await widget.client.requestPasswordReset(email);
      return ActionFeedback(
          message:
              result['message']?.toString() ?? 'Password reset email sent.');
    } catch (error) {
      return ActionFeedback(
        message: error.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
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
    return {
      'theme_preset': themePreset ?? _localSettings['theme_preset'] ?? 'teal',
      'theme_mode': themeMode ?? _localSettings['theme_mode'] ?? 'S',
      'api_base_url': apiBaseUrl ??
          _localSettings['api_base_url'] ??
          'http://localhost:9080/api/v1',
      'log_preferences': existingLogPrefs,
    };
  }

  Future<void> _applyLocalAppSettings(Map<String, dynamic> settings,
      {bool persist = true}) async {
    _localSettings = {
      ..._localSettings,
      ...settings,
    };
    _httpClient?.updateBaseUrl(
      _localSettings['api_base_url']?.toString() ?? 'http://localhost:9080/api/v1',
    );
    widget.onThemeChanged?.call(
      _localSettings['theme_preset']?.toString() ?? 'teal',
      _localSettings['theme_mode']?.toString() ?? 'S',
    );
    if (persist) {
      await _persistLocalSettings();
    }
  }

  DateTime _parseUpdatedAt(String? raw) {
    return DateTime.tryParse(raw ?? '')?.toUtc() ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  }

  Future<void> _applyAuthPayload(Map<String, dynamic> payload) async {
    final token = payload['token']?.toString() ?? '';
    final user = Map<String, dynamic>.from(payload['user'] as Map? ?? {});
    var settings = await widget.client.getSettings(token);
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
    _appendUiLog(
        'Authenticated as ${user['username'] ?? user['email'] ?? 'user'}.');
  }

  Future<void> _logout() async {
    final token = _token;
    if (token == null || token.isEmpty) {
      return;
    }
    await widget.client.logout(token);
    setState(() {
      _token = null;
      _profile = null;
      _settings = null;
      _plannerEvents = const [];
      _deletedNotes = const [];
    });
    await _loadInitialData();
    _showMessage('Signed out.');
    _appendUiLog('Signed out.');
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
    final updatedAt = DateTime.now().toUtc().toIso8601String();
    await _applyLocalAppSettings({
      ..._currentAppSettingsPayload(
        themePreset: themePreset,
        themeMode: themeMode,
        apiBaseUrl: apiBaseUrl,
      ),
      'updated_at': updatedAt,
    });
    _localStats = {
      ..._localStats,
      'settings_saves': ((_localStats['settings_saves'] as num?)?.toInt() ?? 0) +
          1,
    };
    await _persistLocalStats();
    final token = _token;
    if (token == null || token.isEmpty) {
      return const ActionFeedback(message: 'Local app settings updated.');
    }
    try {
      final updated = await widget.client.updateSettings(token, {
        'username': username,
        'email': email,
        'motto': motto,
        'social_link': socialLink,
        'editor_mode': editorMode,
        'theme_preset': themePreset,
        'theme_mode': themeMode,
        'api_base_url': apiBaseUrl,
        'app_settings': _currentAppSettingsPayload(
          themePreset: themePreset,
          themeMode: themeMode,
          apiBaseUrl: apiBaseUrl,
        ),
        'app_settings_updated_at': updatedAt,
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
      _showMessage('Settings updated.');
      _appendUiLog('Settings updated.');
      return const ActionFeedback(message: 'Settings updated.');
    } catch (error) {
      final message = error.toString().replaceFirst('Exception: ', '');
      _appendUiLog('Settings update failed: $message');
      return ActionFeedback(message: message, isError: true);
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
        message: 'Sign in first to create planning events.',
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
          message: 'Future event added to the heatmap.');
    } catch (error) {
      return ActionFeedback(
        message: error.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    }
  }

  Future<ActionFeedback> _uploadAvatar() async {
    final token = _token;
    if (token == null || token.isEmpty) {
      return const ActionFeedback(
        message: 'Sign in first to update your avatar.',
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
        return const ActionFeedback(message: 'Avatar update cancelled.');
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
      _appendUiLog('Avatar updated.');
      return const ActionFeedback(message: 'Avatar updated.');
    } catch (error) {
      final message = error.toString().replaceFirst('Exception: ', '');
      _appendUiLog('Avatar update failed: $message');
      return ActionFeedback(message: message, isError: true);
    }
  }

  Future<void> _loadActivityWeek({DateTime? startDate}) async {
    final token = _token;
    if (token == null || token.isEmpty) {
      return;
    }
    final effectiveStart = _dateOnly(startDate ?? _activityWeekStart);
    final week = await widget.client.getActivityWeek(
      token,
      startDate: effectiveStart.toIso8601String().split('T').first,
    );
    setState(() {
      _activityWeekStart = effectiveStart;
      _activityWeek = week;
    });
    _appendUiLog(
        'Activity week loaded for ${effectiveStart.toIso8601String().split('T').first}.');
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
      throw Exception('Sign in to sync local drafts.');
    }
    final metadata =
        _decodeNoteMetadata(draft['metadata_json']?.toString() ?? '{}');
    final created = await widget.client.createNote(token, {
      'title': draft['title'],
      'description': draft['description'] ?? '',
      'content': draft['content'] ?? '',
      'editor_mode': draft['editor_mode'] ?? 'P',
      'course_id': metadata['course_id'],
      'metadata_json': draft['metadata_json'] ?? '{}',
      'client_draft_id': draft['client_draft_id'],
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
    await _refreshFrontPageData();
    if (mounted) {
      setState(() {});
    }
    _appendUiLog("Synced local draft '${draft['title']}'.");
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
    final created = await widget.client.createNote(token, {
      'title': title ?? _extractTitleFromMarkdown(initialMarkdown),
      'description': description ?? _excerptFromMarkdown(initialMarkdown),
      'content': initialMarkdown,
      'editor_mode': mode,
      'course_id': null,
      'client_draft_id': clientDraftId,
      'metadata_json': jsonEncode({'section': '', 'autosave': false}),
    });
    await _loadLearnerNotes(reset: true, query: _learnerSearchQuery);
    setState(() {
      _selectedNote = created;
      _selectedIndex = 1;
    });
    return created;
  }

  Future<Map<String, dynamic>> _saveNote(
      int noteId, Map<String, dynamic> payload) async {
    if (noteId < 0) {
      final existing = _localDrafts.firstWhere(
        (item) => item['id'] == noteId,
        orElse: () => <String, dynamic>{},
      );
      if (existing.isEmpty) {
        throw Exception('Local draft not found.');
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
      throw Exception('Sign in to save cloud notes.');
    }
    final updated = await widget.client.updateNote(token, noteId, payload);
    await _loadLearnerNotes(reset: true, query: _learnerSearchQuery);
    setState(() {
      _selectedNote = updated;
    });
    return updated;
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
      throw Exception('Sign in to restore notes.');
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
    _appendUiLog('Calendar state refreshed.');
  }

  Future<void> _importCalendarFeed(String rawIcal, String title,
      {int? courseId}) async {
    final token = _token;
    if (token == null || token.isEmpty) {
      throw Exception('Sign in to import calendars.');
    }
    await widget.client.createCalendarFeed(token, {
      'title': title,
      'source_kind': 'I',
      'raw_ical': rawIcal,
      'course_id': courseId,
    });
    await _refreshCalendarState();
    _appendUiLog('Imported calendar $title.');
  }

  Future<void> _subscribeCalendarFeed(String title, String url,
      {int? courseId}) async {
    final token = _token;
    if (token == null || token.isEmpty) {
      throw Exception('Sign in to subscribe calendars.');
    }
    await widget.client.createCalendarFeed(token, {
      'title': title,
      'source_kind': 'S',
      'source_url': url,
      'course_id': courseId,
    });
    await _refreshCalendarState();
    _appendUiLog('Subscribed calendar $title.');
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
    _appendUiLog(
        '${enabled ? 'Enabled' : 'Disabled'} calendar ${feed['title']}.');
  }

  Future<void> _deleteCalendarFeed(Map<String, dynamic> feed) async {
    final token = _token;
    if (token == null || token.isEmpty) {
      return;
    }
    await widget.client.deleteCalendarFeed(token, feed['id'] as int);
    await _refreshCalendarState();
    _appendUiLog('Deleted calendar ${feed['title']}.');
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
      _appendUiLog('Finished note session ${sessionId.toString()}.');
    } catch (error) {
      _appendUiLog(
          'Note session finish failed: ${error.toString().replaceFirst('Exception: ', '')}');
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
    await _refreshFrontPageData();
    setState(() {});
    _appendUiLog("Moved note '${note['title']}' to recycle bin.");
  }

  Future<void> _restoreDeletedNote(Map<String, dynamic> note) async {
    final token = _token;
    if (token == null || token.isEmpty) {
      throw Exception('Sign in to restore notes.');
    }
    final noteId = (note['id'] as num?)?.toInt();
    if (noteId == null) {
      return;
    }
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
    setState(() {
      _deletedNotes = const [];
    });
    _appendUiLog('Emptied recycle bin.');
  }

  Future<void> _syncAllLocalDrafts() async {
    if (_localDrafts.isEmpty) {
      return;
    }
    for (final draft in List<Map<String, dynamic>>.from(_localDrafts)) {
      await _syncLocalDraft(draft);
    }
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _togglePlannerEventCompletion(
      Map<String, dynamic> event, bool completed) async {
    final token = _token;
    if (token == null || token.isEmpty) {
      throw Exception('Sign in to update activities.');
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
    _appendUiLog(
        '${completed ? 'Completed' : 'Reopened'} planner event ${event['title']}.');
  }

  Future<void> _subscribeToCourse(Map<String, dynamic> course) async {
    final token = _token;
    if (token == null || token.isEmpty) {
      throw Exception('Sign in to subscribe to courses.');
    }
    await widget.client.subscribeCourse(token, course['id'] as int);
    await _loadInitialData();
  }

  Future<void> _unsubscribeFromCourse(Map<String, dynamic> course) async {
    final token = _token;
    if (token == null || token.isEmpty) {
      throw Exception('Sign in to unsubscribe from courses.');
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
    _showMessage('Frontend logs copied.');
  }

  Future<ActionFeedback> _restoreTemplateCourses() async {
    final token = _token;
    if (token == null || token.isEmpty) {
      return const ActionFeedback(
        message: 'Sign in with an admin account first.',
        isError: true,
      );
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

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWideLayout = constraints.maxWidth >= 960;
        if (isWideLayout) {
          return _buildWideScaffold(context);
        }
        return _buildCompactScaffold();
      },
    );
  }

  Widget _buildCompactScaffold() {
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        title: Text(_titles[_selectedIndex]),
        backgroundColor: Colors.transparent,
      ),
      body: _buildBody(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: _handleDestinationSelected,
        destinations: _destinations,
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
                          'Notechondria',
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
                          _SidebarItem(
                            icon: Icons.home_outlined,
                            label: 'Front',
                            selected: _selectedIndex == 0,
                            onTap: () => _handleDestinationSelected(0),
                          ),
                          _SidebarItem(
                            icon: Icons.menu_book_outlined,
                            label: 'Learner',
                            selected: _selectedIndex == 1,
                            onTap: () => _handleDestinationSelected(1),
                          ),
                          _SidebarItem(
                            icon: Icons.school_outlined,
                            label: 'Course',
                            selected: _selectedIndex == 2,
                            onTap: () => _handleDestinationSelected(2),
                          ),
                          _SidebarItem(
                            icon: Icons.timeline_outlined,
                            label: 'Activity',
                            selected: _selectedIndex == 3,
                            onTap: () => _handleDestinationSelected(3),
                          ),
                          if (subscribedCourses.isNotEmpty) ...[
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
                          const SizedBox(height: 12),
                          _SidebarItem(
                            icon: Icons.settings_outlined,
                            label: 'Settings',
                            selected: _selectedIndex == 4,
                            onTap: () => _handleDestinationSelected(4),
                          ),
                          const SizedBox(height: 16),
                        ],
                      ),
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
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage != null
                ? _ErrorState(
                    message: _errorMessage!,
                    onRetry: _loadInitialData,
                    apiBaseUrl: _httpClient?.baseUrl,
                    debugSnapshot: _httpClient?.debugSnapshot.value,
                  )
                : _buildPage(),
      ),
    );
  }

  void _handleDestinationSelected(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  Widget _buildPage() {
    switch (_selectedIndex) {
      case 0:
        return _FrontPage(
          frontPage: _frontPage ?? const {},
          profile: _profile,
          apiBaseUrl: _httpClient?.baseUrl,
          onOpenNote: _openNoteViewer,
          onOpenCourse: _selectCourse,
          onRestoreTemplateCourses: _restoreTemplateCourses,
        );
      case 1:
        return _LearnerPage(
          notes: _learnerNotes,
          localDrafts: _localDrafts,
          courses: _courses,
          selectedNote: _selectedNote,
          editorMode: _settings?['editor_mode']?.toString() ?? 'P',
          hasMoreNotes: _hasMoreLearnerNotes,
          isLoadingMore: _isLoadingMoreNotes,
          searchQuery: _learnerSearchQuery,
          isAuthenticated: _token != null && _token!.isNotEmpty,
          apiBaseUrl: _httpClient?.baseUrl,
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
          selectedCourse: _selectedCourse,
          notes: _courseNotes,
          isAuthenticated: _token != null && _token!.isNotEmpty,
          apiBaseUrl: _httpClient?.baseUrl,
          onCourseChanged: _selectCourse,
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
          onVerify: _verify,
          onLogin: _login,
          onRequestPasswordReset: _requestPasswordReset,
          onConfirmPasswordReset: _confirmPasswordReset,
          onRestoreDeletedNote: _restoreDeletedNote,
          onEmptyDeletedNotes: _emptyDeletedNotes,
          onCopyLogs: _copyFrontendLogs,
          onUploadAvatar: _uploadAvatar,
          apiBaseUrl: _httpClient?.baseUrl,
          debugSnapshotListenable: _httpClient?.debugSnapshot,
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
                                  'Opened ${_formatCompactTimestamp(course['last_opened_at'].toString())}',
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
