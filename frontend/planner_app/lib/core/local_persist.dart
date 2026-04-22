part of notechondria_frontend;

/// _LocalAppStore persist helpers.
extension _AppShellLocalPersistX on _AppShellState {
  Future<void> _persistLocalSettings() async {
    await _LocalAppStore.saveSettings(_localSettings);
  }

  Future<void> _persistLocalDrafts() async {
    await _LocalAppStore.saveDrafts(_localDrafts);
  }

  Future<void> _persistLocalCourses() async {
    await _LocalAppStore.saveCourses(_localCourses);
  }

  // Local recycle-bin helpers live in `core/local_trash.dart` as
  // an extension on `_AppShellState` so this file stays under the
  // AGENTS.md \u00a71.5 1000-line ceiling.

  Future<void> _persistLocalStats() async {
    await _LocalAppStore.saveStats(_localStats);
  }

  Future<void> _persistLocalCache() async {
    _localCache = {
      ..._localCache,
      'courses': _courses,
      'activity': _activity,
      'planner_events': _plannerEvents,
      'activity_week': _activityWeek ?? const <String, dynamic>{},
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    await _LocalAppStore.saveCache(_localCache);
  }

  Future<void> _persistUiLogs() async {
    await _LocalAppStore.saveLogs(uiLogs);
  }
}
