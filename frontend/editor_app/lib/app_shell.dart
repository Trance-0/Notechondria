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
    _bootstrapApp();
  }

  Future<void> _bootstrapApp() async {
    await _loadLocalState();
    await _loadInitialData();
  }

  bool get _hasRenderableLocalState =>
      (_frontPage?.isNotEmpty ?? false) ||
      _courses.isNotEmpty ||
      _localCourses.isNotEmpty ||
      _localDrafts.isNotEmpty ||
      _selectedIndex == 4;

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
    if (_frontPage?.isNotEmpty == true ||
        _courses.isNotEmpty ||
        _localCourses.isNotEmpty ||
        _localDrafts.isNotEmpty) {
      return;
    }
    final starterCourse = _buildLocalCourse(
      title: 'Inbox',
      description: 'Offline-first local note bucket for the editor app.',
    );
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
      content: '''# Plain-text editor checklist

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
    _appendUiLog('Seeded starter editor workspace for first-run offline use.');
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
      _errorMessage = errors.isEmpty ? null : errors.first;
      _isLoading = false;
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
      _appendUiLog('Front page refreshed.');
    } catch (error) {
      final message = error.toString().replaceFirst('Exception: ', '');
      setState(() {
        _errorMessage = message;
      });
      _appendUiLog('Front page refresh failed: $message');
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
      _appendUiLog(
          'Learner notes load failed: ${error.toString().replaceFirst('Exception: ', '')}');
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
      _appendUiLog('Opened local course ${course['title']}.');
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
      _appendUiLog('Opened course ${refreshedSelected['title']}.');
    } catch (error) {
      final message = error.toString().replaceFirst('Exception: ', '');
      setState(() {
        _selectedCourse = course;
        _courseNotes = const [];
        _errorMessage = message;
        _isLoading = false;
      });
      _appendUiLog('Course load failed: $message');
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
    Map<String, dynamic> detail;
    try {
      detail = await _fetchNoteDetail(noteSummary['id'] as int);
    } catch (error) {
      _showMessage(error.toString().replaceFirst('Exception: ', ''));
      _appendUiLog(
          'Note viewer failed: ${error.toString().replaceFirst('Exception: ', '')}');
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
      _appendUiLog(
          'Settings bootstrap after login fell back to local state: ${error.toString().replaceFirst('Exception: ', '')}');
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
    await _syncAllLocalData(showMessage: false);
    _appendUiLog(
        'Authenticated as ${user['username'] ?? user['email'] ?? 'user'}.');
  }

  Future<void> _logout() async {
    final token = _token;
    if (token == null || token.isEmpty) {
      return;
    }
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
      _plannerEvents = const [];
      _deletedNotes = const [];
    });
    await _loadInitialData();
    _showMessage('Signed out.');
    _appendUiLog('Signed out.');
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
        message: 'Sign in to pull cloud notes.',
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
                message: 'Cloud pull cancelled.',
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
        segments.add('pulled $imported');
      }
      if (updated > 0) {
        segments.add('updated $updated');
      }
      if (skipped > 0) {
        segments.add('kept $skipped local');
      }
      final message =
          segments.isEmpty ? 'Cloud notes already match local copies.' : segments.join(', ');
      _appendUiLog('Cloud pull completed: $message.');
      return ActionFeedback(message: message);
    } catch (error) {
      final message = error.toString().replaceFirst('Exception: ', '');
      _appendUiLog('Cloud pull failed: $message');
      return ActionFeedback(message: 'Pull failed.', isError: true);
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
      _appendUiLog('Cloud settings sync failed for $summary: $detail');
      return ActionFeedback(
        message: 'Saved locally. Sync pending for $summary.',
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
    try {
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
    } catch (error) {
      final message = error.toString().replaceFirst('Exception: ', '');
      setState(() {
        _errorMessage = message;
      });
      _appendUiLog('Activity week load failed: $message');
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
    _appendUiLog("Created local course '${course['title']}'.");
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
    _appendUiLog("Synced local course '${course['title']}'.");
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
      _appendUiLog("Synced local cloud copy '${draft['title']}'.");
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
      final message = error.toString().replaceFirst('Exception: ', '');
      setState(() {
        _selectedNote = draft;
        _selectedIndex = 1;
      });
      _appendUiLog('Cloud create failed, saved local draft instead: $message');
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
      _appendUiLog('Cloud save failed, kept local draft instead: $message');
      _showMessage('Backend unavailable. Changes were saved locally.');
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

  Future<void> _syncAllLocalCourses() async {
    if (_localCourses.isEmpty) {
      return;
    }
    for (final course in List<Map<String, dynamic>>.from(_localCourses)) {
      await _syncLocalCourse(course);
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
      await _syncLocalDraft(draft);
    }
    if (mounted) {
      setState(() {});
    }
  }

  Future<ActionFeedback> _syncAllLocalData({bool showMessage = true}) async {
    final token = _token;
    if (token == null || token.isEmpty) {
      return const ActionFeedback(
        message: 'Sign in to sync local courses and drafts.',
        isError: true,
      );
    }
    try {
      await _syncAllLocalCourses();
      await _syncAllLocalDrafts();
      await _loadInitialData();
      const feedback = ActionFeedback(message: 'Local data synced to the cloud.');
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
      final message = error.toString().replaceFirst('Exception: ', '');
      _appendUiLog('Local data sync failed: $message');
      if (showMessage) {
        _showMessage('Local data sync failed: $message');
      }
      return ActionFeedback(message: message, isError: true);
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
    _appendUiLog('Cleared cached remote data.');
    return const ActionFeedback(message: 'Cached remote data cleared.');
  }

  Future<ActionFeedback> _clearLocalData() async {
    _localDrafts = const [];
    _localCourses = const [];
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
    await _persistLocalStats();
    if (mounted) {
      setState(() {});
    }
    _appendUiLog('Removed local drafts and local courses.');
    return const ActionFeedback(message: 'Local drafts and local courses removed.');
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
                            _SidebarItem(
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
        child: _isLoading && !_hasRenderableLocalState
            ? const Center(child: CircularProgressIndicator())
            : Column(
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
                  Expanded(child: _buildPage()),
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
          apiBaseUrl: _httpClient?.baseUrl,
          onOpenNote: _openNoteViewer,
          onOpenCourse: _selectCourse,
        );
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
          localCourses: _localCourses,
          selectedCourse: _selectedCourse,
          notes: _courseNotes,
          localNotes: _localDrafts,
          isAuthenticated: _token != null && _token!.isNotEmpty,
          canCreateLocalCourses: true,
          apiBaseUrl: _httpClient?.baseUrl,
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
          onVerify: _verify,
          onLogin: _login,
          onRequestPasswordReset: _requestPasswordReset,
          onConfirmPasswordReset: _confirmPasswordReset,
          onRestoreDeletedNote: _restoreDeletedNote,
          onEmptyDeletedNotes: _emptyDeletedNotes,
          onCopyLogs: _copyFrontendLogs,
          onUploadAvatar: _uploadAvatar,
          onSyncLocalData: _syncAllLocalData,
          onPullCloudData: _pullCloudNotesToLocal,
          onClearLocalCache: _clearLocalCache,
          onClearLocalData: _clearLocalData,
          onRestoreTemplateCourses: _restoreTemplateCourses,
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
