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
    await _ensureStarterWorkspace();
    // 0.1.84: cold-boot lands on "All Notes" (no category
    // selected) regardless of cached state. The previous
    // `_chooseDefaultCourse` auto-pick would land previously-
    // signed-in users on their cloud Inbox even when signed-out
    // — and after 0.1.83 made Inbox private, that view returned
    // zero notes for non-owners, looking broken. Leaving
    // `_selectedCourse` null so the user lands on the public-
    // notes feed and can navigate into a category by tap.
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
    // One-time migration of 0.1.37-era inline base64 queued
    // attachments into LocalAttachmentStore. Run fire-and-forget so
    // first paint isn't blocked on it; the shim itself is idempotent
    // and short-circuits on subsequent boots via the
    // `attachment_store_migrated_at` marker.
    unawaited(_migrateAttachmentStoreIfNeeded());
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
        source: 'Editor.LocalStore/load',
        message: 'Earlier debug log not restored: Editor.LocalStore/load '
            '\u2014 ${describeRequestFailure(error)}; this session\'s lines '
            'are saved on their own.',
      );
    }
    if (!_localLogsLoaded) _mergePersistedLogs(persisted);
  }
}
