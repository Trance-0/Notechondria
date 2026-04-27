part of notechondria_frontend;

/// First-run starter.
extension _AppShellStarterX on _AppShellState {
  Future<void> _ensureStarterWorkspace() async {
    if (_frontPage?.isNotEmpty == true) {
      return;
    }
    _frontPage = {
      'default_course': null,
      'carousel_courses': const <Map<String, dynamic>>[],
      'collections': const <Map<String, dynamic>>[],
      'recent_notes': const <Map<String, dynamic>>[],
      'recommended_notes': const <Map<String, dynamic>>[],
      'portal_shell': true,
    };
    _localStats = {
      ..._localStats,
      'starter_workspace_seeded_at': DateTime.now().toUtc().toIso8601String(),
    };
    await persistLocalStats();
    await _persistLocalCache();
    log(
      level: DebugLogLevel.info,
      source: 'Portal.LocalStore/seed_starter',
      message:
          'Portal shell starter state seeded: '
          'Portal.LocalStore/seed_starter \u2014 '
          'first-run offline front-page shell created.',
    );
  }
}
