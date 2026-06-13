part of notechondria_frontend;

/// Cold-boot local state loader.
extension _AppShellLoadLocalStateX on _AppShellState {
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
    uiLogs
      ..clear()
      ..addAll(snapshot.logs);
    logController.replaceAll(
      snapshot.logs.map(DebugLogEntry.fromPersistedString),
    );
    logController.bindCacheProvider(_snapshotLocalStore);
    _frontPage = Map<String, dynamic>.from(
      snapshot.cache['front_page'] as Map? ?? const {},
    );
    _courses = (snapshot.cache['courses'] as List<dynamic>? ?? const [])
        .map((item) =>
            decorateRemoteCourse(Map<String, dynamic>.from(item as Map)))
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
      refreshState();
    }
  }
}
