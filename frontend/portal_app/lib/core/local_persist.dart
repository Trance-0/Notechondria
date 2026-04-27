part of notechondria_frontend;

/// App-specific local-persist helpers. The byte-identical
/// `_persistLocalSettings` / `_persistLocalDrafts` / `_persistLocalCourses` /
/// `_persistLocalStats` / `_persistUiLogs` methods moved into the shared
/// `AppShellLocalPersistMixin` (notechondria_shared 0.1.78). Call sites
/// use the public `persistLocalSettings()` / etc. names.
///
/// `_persistLocalCache` stays here because portal's cache bucket
/// includes `front_page` + `activity` fields that planner doesn't
/// have and editor doesn't need together.
///
/// Local recycle-bin helpers live in `core/local_trash.dart` as
/// an extension on `_AppShellState` so this file stays under the
/// AGENTS.md \u00a71.5 1000-line ceiling.
extension _AppShellLocalPersistX on _AppShellState {
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
}
