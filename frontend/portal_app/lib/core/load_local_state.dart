part of notechondria_frontend;

/// Cold-boot local state loader.
extension _AppShellLoadLocalStateX on _AppShellState {
  Future<void> _loadLocalState() async {
    final snapshot = await _LocalAppStore.load();
    // First, before anything below can throw (a failed settings write or
    // a corrupt cache value), so a failed start still persists its log
    // lines.
    _mergePersistedLogs(snapshot.logs);
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
    _localEvents = snapshot.events;
    _localTrashedDrafts = snapshot.trashedDrafts;
    _localTrashedCourses = snapshot.trashedCourses;
    _localStats = snapshot.stats;
    _localCache = snapshot.cache;
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
    widget.onLocaleChanged?.call(
      _localSettings['locale']?.toString() ?? 'system',
    );
    if (mounted) {
      refreshState();
    }
  }

  /// Keeps the lines logged earlier in this page session (the startup
  /// step records written before the local load) above the [persisted]
  /// history, then opens the log-persistence gate (`_localLogsLoaded`),
  /// so startup never overwrites the stored history.
  void _mergePersistedLogs(List<String> persisted) {
    final known = persisted.toSet();
    final mergedLogs = [
      ...uiLogs.where((line) => !known.contains(line)),
      ...persisted,
    ].take(uiLogCapacity).toList(growable: false);
    uiLogs
      ..clear()
      ..addAll(mergedLogs);
    logController.replaceAll(
      mergedLogs.map(DebugLogEntry.fromPersistedString),
    );
    _localLogsLoaded = true;
    unawaited(persistUiLogs());
  }

  /// Startup failed before `_loadLocalState` merged the persisted logs
  /// (`_LocalAppStore.load()` threw). Merge whatever history can still be
  /// read and open the gate, so this session's failure lines (and every
  /// Retry) are persisted for the next start.
  Future<void> _recoverLogPersistence() async {
    if (_localLogsLoaded) return;
    var persisted = const <String>[];
    try {
      persisted = await _LocalAppStore.loadLogs();
    } catch (error) {
      log(
        level: DebugLogLevel.warning,
        source: 'Portal.LocalStore/load',
        message: 'Earlier debug log not restored: Portal.LocalStore/load '
            '\u2014 ${describeRequestFailure(error)}; this session\'s lines '
            'are saved on their own.',
      );
    }
    if (!_localLogsLoaded) _mergePersistedLogs(persisted);
  }
}
