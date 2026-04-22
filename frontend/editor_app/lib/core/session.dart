part of notechondria_frontend;

/// The two session mutators kept in one place: `_applyAuthPayload` is
/// the orchestrator that runs after any successful login/OAuth/session
/// restore (it picks the newer of local-vs-server settings, saves the
/// session, reloads data, and pushes any offline courses/drafts); and
/// `_logout` flips everything back to the anonymous state. State
/// mutations route through `_refresh()` since extensions can't call
/// `setState` directly. Extracted from `app_shell.dart` so that file
/// stays closer to the AGENTS.md §1.5 1000-line ceiling.
extension _AppShellSessionX on _AppShellState {
  Future<void> _applyAuthPayload(Map<String, dynamic> payload) async {
    final token = payload['token']?.toString() ?? '';
    final user = Map<String, dynamic>.from(payload['user'] as Map? ?? {});
    Map<String, dynamic> settings;
    try {
      settings = await widget.client.getSettings(token);
      final localUpdated =
          _parseUpdatedAt(_localSettings['updated_at']?.toString());
      final serverUpdated =
          _parseUpdatedAt(settings['app_settings_updated_at']?.toString());
      if (localUpdated.isAfter(serverUpdated)) {
        settings = await widget.client.updateSettings(token, {
          'app_settings': _currentAppSettingsPayload(),
          'app_settings_updated_at': _localSettings['updated_at'],
          'theme_preset': _localSettings['theme_preset'],
          'theme_mode': _localSettings['theme_mode'],
          'api_base_url': _localSettings['api_base_url'],
        });
      } else {
        final serverAppSettings = Map<String, dynamic>.from(
          settings['app_settings'] as Map? ??
              _currentAppSettingsPayload(
                themePreset: settings['theme_preset']?.toString(),
                themeMode: settings['theme_mode']?.toString(),
                apiBaseUrl: settings['api_base_url']?.toString(),
              ),
        );
        await _applyLocalAppSettings({
          ...serverAppSettings,
          'updated_at': settings['app_settings_updated_at']?.toString() ??
              DateTime.now().toUtc().toIso8601String(),
        });
      }
    } catch (error) {
      settings = {
        'username': user['username'],
        'email': user['email'],
        'editor_mode': _settings?['editor_mode'] ?? 'P',
        'theme_preset': _localSettings['theme_preset'],
        'theme_mode': _localSettings['theme_mode'],
        'api_base_url': _localSettings['api_base_url'],
        'app_settings': _currentAppSettingsPayload(),
        'app_settings_updated_at': _localSettings['updated_at'] ??
            DateTime.now().toUtc().toIso8601String(),
      };
      _log(
        level: DebugLogLevel.warning,
        source: 'Editor.Sync.Settings/bootstrap',
        message:
            'Remote settings unavailable right after login: '
            'Editor.Sync.Settings/bootstrap \u2014 '
            '${error.toString().replaceFirst('Exception: ', '')}. '
            'Using cached local settings.',
      );
    }
      _token = token;
      _profile = user;
      _settings = settings;
    _refresh();
    await _LocalAppStore.saveSession(token, user);
    await _applyLocalAppSettings({
      'theme_preset': settings['theme_preset']?.toString() ??
          _localSettings['theme_preset'],
      'theme_mode':
          settings['theme_mode']?.toString() ?? _localSettings['theme_mode'],
      'api_base_url': settings['api_base_url']?.toString() ??
          _localSettings['api_base_url'],
      'updated_at': settings['app_settings_updated_at']?.toString() ??
          _localSettings['updated_at'],
      'log_preferences': Map<String, dynamic>.from(
        (settings['app_settings'] as Map?)?['log_preferences'] as Map? ??
            _localSettings['log_preferences'] as Map? ??
            {},
      ),
    });
    await _loadInitialData();
    // Push any local courses + drafts created offline. Skip
    // _syncAllLocalData's inner _loadInitialData call to avoid the
    // double-bootstrap race where a single flaky 401 on the second
    // bootstrap tripped sessionRejected and wiped the fresh token.
    try {
      await _syncAllLocalCourses();
      await _syncAllLocalDrafts();
    } catch (error) {
      _log(
        level: DebugLogLevel.warning,
        source: 'Editor.Sync.Notes/push_all',
        message:
            'Local push after login failed: '
            'Editor.Sync.Notes/push_all \u2014 '
            '${error.toString().replaceFirst('Exception: ', '')}. '
            'Will retry on next manual sync.',
      );
    }
    final displayName =
        user['username']?.toString() ??
            user['email']?.toString() ??
            'user';
    _log(
      level: DebugLogLevel.info,
      source: 'Editor.Auth/applyAuthPayload',
      message:
          'Session established: Editor.Auth/applyAuthPayload \u2014 '
          'authenticated as $displayName.',
    );
    if (mounted) {
      _showMessage('Signed in as $displayName.');
    }
  }

  Future<void> _logout() async {
    final token = _token;
    if (token == null || token.isEmpty) return;
    try {
      await widget.client.logout(token);
    } catch (error) {
      _log(
        level: DebugLogLevel.warning,
        source: 'Editor.Auth/logout',
        message:
            'Cloud logout call failed but local session cleared anyway: '
            'Editor.Auth/logout \u2014 '
            '${error.toString().replaceFirst('Exception: ', '')}.',
      );
    }
      _token = null;
      _profile = null;
      _settings = null;
      _deletedNotes = const [];
    _refresh();
    await _LocalAppStore.clearSession();
    await _loadInitialData();
    _showMessage(
      'Signed out: Editor.Auth/logout \u2014 local session cleared.',
    );
    _log(
      level: DebugLogLevel.info,
      source: 'Editor.Auth/logout',
      message:
          'Signed out: Editor.Auth/logout \u2014 local session cleared.',
    );
  }
}
