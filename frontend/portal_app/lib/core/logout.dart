part of notechondria_frontend;

/// Logout flow.
extension _AppShellLogoutX on _AppShellState {
  Future<void> _logout() async {
    final token = _token;
    if (token == null || token.isEmpty) {
      return;
    }
    try {
      await widget.client.logout(token);
    } catch (error) {
      log(
        level: DebugLogLevel.warning,
        source: 'Portal.Auth/logout',
        message:
            'Cloud logout call failed but local session cleared anyway: '
            'Portal.Auth/logout \u2014 '
            '${error.toString().replaceFirst('Exception: ', '')}.',
      );
    }
      _token = null;
      _profile = null;
      _settings = null;
      _plannerEvents = const [];
      _deletedNotes = const [];
    refreshState();
    await _loadInitialData();
    showMessage(
      'Signed out: Portal.Auth/logout \u2014 local session cleared.',
    );
    log(
      level: DebugLogLevel.info,
      source: 'Portal.Auth/logout',
      message:
          'Signed out: Portal.Auth/logout \u2014 local session cleared.',
    );
  }
}
