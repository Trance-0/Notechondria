part of notechondria_frontend;

/// Cold-boot local-state loader. Runs once at `initState()` to hydrate
/// every in-memory bucket (`_localSettings`, `_localDrafts`,
/// `_localCourses`, `_localTrashedDrafts`, `_localTrashedCourses`,
/// `_localStats`, `_localCache`, `uiLogs`, `_frontPage`, `_courses`,
/// `_selectedCourse`) from `_LocalAppStore`, then seeds the starter
/// workspace if the user has nothing yet and kicks off the one-shot
/// 0.1.37 attachment migration. Includes a small 0.1.38 shim that
/// rewrites stale web `localhost:9080` defaults to the current
/// `_defaultApiBaseUrl()`. Extracted from `app_shell.dart` so that
/// file stays closer to the AGENTS.md §1.5 1000-line ceiling.
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
      refreshState();
    }
    // One-time migration of 0.1.37-era inline base64 queued
    // attachments into LocalAttachmentStore. Run fire-and-forget so
    // first paint isn't blocked on it; the shim itself is idempotent
    // and short-circuits on subsequent boots via the
    // `attachment_store_migrated_at` marker.
    unawaited(_migrateAttachmentStoreIfNeeded());
  }
}
