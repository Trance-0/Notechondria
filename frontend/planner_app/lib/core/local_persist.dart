part of notechondria_frontend;

/// App-specific local-persist helpers. The byte-identical
/// `_persistLocalSettings` / `_persistLocalDrafts` / `_persistLocalCourses` /
/// `_persistLocalStats` / `_persistUiLogs` methods moved into the shared
/// `AppShellLocalPersistMixin` (notechondria_shared 0.1.78). Call sites
/// use the public `persistLocalSettings()` / etc. names.
///
/// `_persistLocalCache` stays here because planner's cache bucket
/// includes `activity` / `planner_events` / `activity_week` fields that
/// editor / portal don't have.
///
/// Local recycle-bin helpers live in `core/local_trash.dart` as
/// an extension on `_AppShellState` so this file stays under the
/// AGENTS.md \u00a71.5 1000-line ceiling.
extension _AppShellLocalPersistX on _AppShellState {
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
}
