part of notechondria_frontend;

/// Debug-terminal snapshot of in-memory app state.
extension _AppShellSnapshotX on _AppShellState {
  Map<String, Object?> _snapshotLocalStore() {
    return <String, Object?>{
      'settings': _localSettings,
      'drafts': _localDrafts,
      'courses': _localCourses,
      'stats': _localStats,
      'cache': _localCache,
      'logs': uiLogs,
      'session': _token == null
          ? null
          : {
              'token_present': true,
              'profile': _profile ?? const <String, dynamic>{},
            },
    };
  }
}
