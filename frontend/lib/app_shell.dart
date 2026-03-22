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
  List<Map<String, dynamic>> _activity = const [];
  List<Map<String, dynamic>> _plannerEvents = const [];
  List<Map<String, dynamic>> _calendarFeeds = const [];
  Map<String, dynamic>? _activityWeek;
  Map<String, dynamic>? _selectedCourse;
  Map<String, dynamic>? _selectedNote;
  DateTime _activityWeekStart = _dateOnly(DateTime.now());
  bool _hasMoreLearnerNotes = true;
  bool _isLoadingMoreNotes = false;
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

  @override
  void initState() {
    super.initState();
    _loadInitialData();
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

  Future<void> _loadInitialData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final frontPage = await widget.client.getFrontPage(token: _token);
      final courses = await widget.client.getCourses();
      final activity = await widget.client.getActivity(token: _token);
      final defaultCourse =
          frontPage['default_course'] as Map<String, dynamic>?;
      final selectedCourse = defaultCourse ??
          (courses.isNotEmpty
              ? Map<String, dynamic>.from(courses.first)
              : null);
      List<Map<String, dynamic>> courseNotes = const [];
      if (selectedCourse != null) {
        courseNotes =
            await widget.client.getCourseNotes(selectedCourse['id'] as int);
      }
      List<Map<String, dynamic>> plannerEvents = const [];
      List<Map<String, dynamic>> learnerNotes = const [];
      List<Map<String, dynamic>> calendarFeeds = const [];
      Map<String, dynamic>? activityWeek;
      if (_token != null && _token!.isNotEmpty) {
        plannerEvents = await widget.client.getPlannerEvents(_token!);
        calendarFeeds = await widget.client.getCalendarFeeds(_token!);
        activityWeek = await widget.client.getActivityWeek(
          _token!,
          startDate: _activityWeekStart.toIso8601String().split('T').first,
        );
      }
      final notePage =
          await widget.client.listNotes(token: _token, limit: 20, offset: 0);
      learnerNotes = (notePage['results'] as List<dynamic>? ?? const [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
      if (_settings != null) {
        _httpClient?.updateBaseUrl(_settings?['api_base_url']?.toString() ??
            _httpClient?.baseUrl ??
            'http://localhost:9080/api/v1');
        widget.onThemeChanged?.call(
          _settings?['theme_preset']?.toString() ?? 'teal',
          _settings?['theme_mode']?.toString() ?? 'S',
        );
      }
      setState(() {
        _frontPage = frontPage;
        _courses = courses;
        _activity = activity;
        _selectedCourse = selectedCourse;
        _courseNotes = courseNotes;
        _learnerNotes = learnerNotes;
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
      final notes = await widget.client.getCourseNotes(course['id'] as int);
      setState(() {
        _courseNotes = notes;
        _selectedNote = null;
        _isLoading = false;
      });
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
    final detail = await widget.client.getNoteDetail(noteId);
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

  Future<void> _applyAuthPayload(Map<String, dynamic> payload) async {
    final token = payload['token']?.toString() ?? '';
    final user = Map<String, dynamic>.from(payload['user'] as Map? ?? {});
    final settings = await widget.client.getSettings(token);
    setState(() {
      _token = token;
      _profile = user;
      _settings = settings;
    });
    _httpClient?.updateBaseUrl(settings['api_base_url']?.toString() ??
        _httpClient?.baseUrl ??
        'http://localhost:9080/api/v1');
    widget.onThemeChanged?.call(
      settings['theme_preset']?.toString() ?? 'teal',
      settings['theme_mode']?.toString() ?? 'S',
    );
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
    final token = _token;
    if (token == null || token.isEmpty) {
      return const ActionFeedback(
        message: 'Sign in first to update account settings.',
        isError: true,
      );
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
      });
      _httpClient?.updateBaseUrl(apiBaseUrl);
      setState(() {
        _settings = updated;
        _profile = {
          ...?_profile,
          'username': updated['username'],
          'email': updated['email'],
        };
      });
      widget.onThemeChanged?.call(themePreset, themeMode);
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

  Future<Map<String, dynamic>> _createNote({
    String? markdown,
    String? title,
  }) async {
    final token = _token;
    if (token == null || token.isEmpty) {
      throw Exception('Sign in to create notes.');
    }
    final mode = _settings?['editor_mode']?.toString() ?? 'P';
    final initialMarkdown =
        (markdown ?? '# ${title ?? 'Untitled note'}\n\n').trim();
    final created = await widget.client.createNote(token, {
      'title': title ?? _extractTitleFromMarkdown(initialMarkdown),
      'description': _excerptFromMarkdown(initialMarkdown),
      'content': initialMarkdown,
      'editor_mode': mode,
      'course_id': _selectedCourse?['id'],
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
    final token = _token;
    if (token == null || token.isEmpty) {
      throw Exception('Sign in to save notes.');
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
    if (token == null || token.isEmpty) {
      return const [];
    }
    return widget.client.getNoteHistory(token, noteId);
  }

  Future<Map<String, dynamic>> _snapshotNote(int noteId,
      {String reason = 'manual'}) async {
    final token = _token;
    if (token == null || token.isEmpty) {
      throw Exception('Sign in to snapshot notes.');
    }
    return widget.client.snapshotNote(token, noteId, reason: reason);
  }

  Future<Map<String, dynamic>> _restoreNoteVersion(
      int noteId, int versionId) async {
    final token = _token;
    if (token == null || token.isEmpty) {
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
          markdown: contents, title: _extractTitleFromMarkdown(contents));
      _showMessage("Imported '${created['title']}'.");
    } catch (error) {
      _showMessage(error.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _exportNote(Map<String, dynamic> note) async {
    try {
      final detail = note['content'] != null
          ? note
          : await widget.client.getNoteDetail(note['id'] as int);
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
    if (token == null || token.isEmpty) {
      return null;
    }
    final session = await widget.client.startNoteSession(token, {
      'note_id': noteId,
      'title': title,
      'summary': summary,
      'started_at': DateTime.now().toIso8601String(),
    });
    _appendUiLog('Started note session for $title.');
    return session['id'] as int?;
  }

  Future<void> _finishNoteSession(int? sessionId,
      {String? title, String? summary}) async {
    final token = _token;
    if (token == null || token.isEmpty || sessionId == null) {
      return;
    }
    await widget.client.updateNoteSession(token, sessionId, {
      if (title != null) 'title': title,
      if (summary != null) 'summary': summary,
      'ended_at': DateTime.now().toIso8601String(),
    });
    await _loadActivityWeek(startDate: _activityWeekStart);
    _appendUiLog('Finished note session ${sessionId.toString()}.');
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
    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            Container(
              width: 240,
              decoration: const BoxDecoration(
                color: Color(0xFFF3F4F6),
                border: Border(
                  right: BorderSide(color: Color(0xFFE5E7EB)),
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
                                    color: const Color(0xFF6B7280),
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
                          const Spacer(),
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
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                    child: Text(
                      _titles[_selectedIndex],
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
          onOpenNote: _openNoteViewer,
        );
      case 1:
        return _LearnerPage(
          notes: _learnerNotes,
          courses: _courses,
          selectedNote: _selectedNote,
          editorMode: _settings?['editor_mode']?.toString() ?? 'P',
          hasMoreNotes: _hasMoreLearnerNotes,
          isLoadingMore: _isLoadingMoreNotes,
          searchQuery: _learnerSearchQuery,
          isAuthenticated: _token != null && _token!.isNotEmpty,
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
        );
      case 2:
        return _CoursePage(
          courses: _courses,
          selectedCourse: _selectedCourse,
          notes: _courseNotes,
          onCourseChanged: _selectCourse,
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
        );
      case 4:
        return _SettingsPage(
          profile: _profile,
          settings: _settings,
          onSave: _updateSettings,
          onLogout: _logout,
          onRegister: _register,
          onVerify: _verify,
          onLogin: _login,
          onRequestPasswordReset: _requestPasswordReset,
          onConfirmPasswordReset: _confirmPasswordReset,
          calendarFeeds: _calendarFeeds,
          courses: _courses,
          onToggleCalendarFeed: _toggleCalendarFeed,
          onDeleteCalendarFeed: _deleteCalendarFeed,
          apiBaseUrl: _httpClient?.baseUrl,
          debugSnapshotListenable: _httpClient?.debugSnapshot,
          uiLogs: _uiLogs,
        );
      default:
        return const SizedBox.shrink();
    }
  }
}
