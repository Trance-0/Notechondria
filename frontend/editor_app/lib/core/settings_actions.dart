part of notechondria_frontend;

/// Settings-page actions: tiny compare helpers, the user-facing
/// "save settings" orchestrator `_updateSettings`, and the avatar
/// upload flow `_uploadAvatar`. Both top-level methods route
/// post-API state updates through `refreshState()` since extensions
/// can't call `setState` directly. Extracted from `app_shell.dart`
/// so that file stays closer to the AGENTS.md §1.5 1000-line
/// ceiling.
extension _AppShellSettingsActionsX on _AppShellState {
  bool _sameTrimmedValue(String a, String b) => a.trim() == b.trim();

  bool _sameEmailValue(String a, String b) =>
      a.trim().toLowerCase() == b.trim().toLowerCase();

  String _summarizeChangedFields(List<String> fields) {
    final unique = <String>[];
    for (final field in fields) {
      if (field.isEmpty || unique.contains(field)) continue;
      unique.add(field);
    }
    if (unique.isEmpty) return 'settings';
    if (unique.length == 1) return unique.first;
    if (unique.length == 2) return '${unique.first} and ${unique.last}';
    return '${unique[0]}, ${unique[1]} +${unique.length - 2}';
  }

  Future<ActionFeedback> _updateSettings(
    String username,
    String email,
    String motto,
    String socialLink,
    String editorMode,
    String themePreset,
    String themeMode,
    String apiBaseUrl, {
    String firstName = '',
    String lastName = '',
    // 0.1.120: per-account label for the synthetic uncategorized
    // bucket. Optional so older callers (planner / portal) compile
    // unchanged; an empty value falls through to "no change" without
    // touching the server.
    String uncategorizedFolderName = '',
  }) async {
    final currentSettings =
        Map<String, dynamic>.from(_settings ?? const {});
    final currentProfile = Map<String, dynamic>.from(_profile ?? const {});
    final currentUsername = currentSettings['username']?.toString() ??
        currentProfile['username']?.toString() ??
        '';
    final currentEmail = currentSettings['email']?.toString() ??
        currentProfile['email']?.toString() ??
        '';
    final currentMotto = currentSettings['motto']?.toString() ?? '';
    final currentSocialLink =
        currentSettings['social_link']?.toString() ?? '';
    final currentEditorMode =
        currentSettings['editor_mode']?.toString() ?? 'P';
    final currentThemePreset =
        _localSettings['theme_preset']?.toString() ?? 'teal';
    final currentThemeMode =
        _localSettings['theme_mode']?.toString() ?? 'S';
    final currentApiBase =
        _localSettings['api_base_url']?.toString() ?? _defaultApiBaseUrl();
    final nextApiBase =
        apiBaseUrl.trim().isEmpty || apiBaseUrl.trim().startsWith('/')
            ? _defaultApiBaseUrl()
            : apiBaseUrl.trim();
    final changedFields = <String>[];
    final remotePayload = <String, dynamic>{};
    if (!_sameTrimmedValue(username, currentUsername)) {
      remotePayload['username'] = username;
      changedFields.add('username');
    }
    if (!_sameEmailValue(email, currentEmail)) {
      remotePayload['email'] = email;
      changedFields.add('email');
    }
    final currentFirstName = currentSettings['first_name']?.toString() ??
        currentProfile['first_name']?.toString() ??
        '';
    final currentLastName = currentSettings['last_name']?.toString() ??
        currentProfile['last_name']?.toString() ??
        '';
    if (!_sameTrimmedValue(firstName, currentFirstName)) {
      remotePayload['first_name'] = firstName;
      changedFields.add('first name');
    }
    if (!_sameTrimmedValue(lastName, currentLastName)) {
      remotePayload['last_name'] = lastName;
      changedFields.add('last name');
    }
    if (!_sameTrimmedValue(motto, currentMotto)) {
      remotePayload['motto'] = motto;
      changedFields.add('motto');
    }
    if (!_sameTrimmedValue(socialLink, currentSocialLink)) {
      remotePayload['social_link'] = socialLink;
      changedFields.add('social link');
    }
    final currentUncategorized =
        currentSettings['uncategorized_folder_name']?.toString() ?? 'Inbox';
    final nextUncategorized = uncategorizedFolderName.trim();
    if (nextUncategorized.isNotEmpty &&
        nextUncategorized != currentUncategorized) {
      remotePayload['uncategorized_folder_name'] = nextUncategorized;
      changedFields.add('uncategorized folder name');
    }
    if (editorMode != currentEditorMode) {
      remotePayload['editor_mode'] = editorMode;
      changedFields.add('editor mode');
    }
    final localSettingsChanged = themePreset != currentThemePreset ||
        themeMode != currentThemeMode ||
        !_sameTrimmedValue(nextApiBase, currentApiBase);
    if (themePreset != currentThemePreset || themeMode != currentThemeMode) {
      changedFields.add('theme');
    }
    if (!_sameTrimmedValue(nextApiBase, currentApiBase)) {
      changedFields.add('API base');
      // Before committing a user-entered API URL, confirm it's really a
      // Notechondria backend with compatible API version. If the handshake
      // fails we abort the save — keeping the old URL is safer than silently
      // stranding the user on a dead/foreign host.
      final client = widget.client;
      if (client is HttpNotechondriaClient) {
        final handshake = await client.verifyHandshake(nextApiBase);
        if (!handshake.ok) {
          return ActionFeedback(
            message:
                'Backend handshake failed for $nextApiBase: ${handshake.error ?? 'unknown error'}',
          );
        }
      }
    }
    final updatedAt = DateTime.now().toUtc().toIso8601String();
    await _applyLocalAppSettings({
      ..._currentAppSettingsPayload(
        themePreset: themePreset,
        themeMode: themeMode,
        apiBaseUrl: nextApiBase,
      ),
      'updated_at': updatedAt,
    });
    _localStats = {
      ..._localStats,
      'settings_saves':
          ((_localStats['settings_saves'] as num?)?.toInt() ?? 0) + 1,
    };
    await persistLocalStats();
    if (remotePayload.isEmpty && !localSettingsChanged) {
      return const ActionFeedback(
          message: 'No settings changes: '
              'Editor.Sync.Settings/save \u2014 '
              'nothing to save.');
    }
    final token = _token;
    if (token == null || token.isEmpty) {
      return const ActionFeedback(
          message: 'Settings saved locally: '
              'Editor.Sync.Settings/save \u2014 '
              'no cloud session; will push on next sign-in.');
    }
    try {
      if (localSettingsChanged) {
        remotePayload.addAll({
          'theme_preset': themePreset,
          'theme_mode': themeMode,
          'api_base_url': nextApiBase,
          'app_settings': _currentAppSettingsPayload(
            themePreset: themePreset,
            themeMode: themeMode,
            apiBaseUrl: nextApiBase,
          ),
          'app_settings_updated_at': updatedAt,
        });
      }
      final updated = await widget.client.updateSettings(token, {
        ...remotePayload,
      });
        _settings = updated;
        _profile = {
          ...?_profile,
          'username': updated['username'],
          'email': updated['email'],
          'motto': updated['motto'],
          'social_link': updated['social_link'],
          'image_url': updated['image_url'],
          'is_staff': updated['is_staff'] ?? _profile?['is_staff'],
          'is_superuser':
              updated['is_superuser'] ?? _profile?['is_superuser'],
        };
      refreshState();
      final summary = _summarizeChangedFields(changedFields);
      showMessage(
        'Settings saved: Editor.Sync.Settings/save \u2014 $summary updated.',
      );
      log(
        level: DebugLogLevel.info,
        source: 'Editor.Sync.Settings/save',
        message:
            'Settings saved: Editor.Sync.Settings/save \u2014 '
            '$summary pushed to cloud.',
      );
      return ActionFeedback(
          message: 'Settings saved: Editor.Sync.Settings/save \u2014 '
              '$summary updated.');
    } catch (error) {
      final detail = error.toString().replaceFirst('Exception: ', '');
      final fallbackUsername = _profile?['username'];
      final fallbackEmail = _profile?['email'];
        _settings = {
          ...?_settings,
          if (remotePayload.containsKey('username')) 'username': username,
          if (remotePayload.containsKey('email')) 'email': email,
          if (remotePayload.containsKey('motto')) 'motto': motto,
          if (remotePayload.containsKey('social_link'))
            'social_link': socialLink,
          if (remotePayload.containsKey('editor_mode'))
            'editor_mode': editorMode,
          if (localSettingsChanged) 'theme_preset': themePreset,
          if (localSettingsChanged) 'theme_mode': themeMode,
          if (localSettingsChanged) 'api_base_url': nextApiBase,
        };
        _profile = {
          ...?_profile,
          'username':
              remotePayload.containsKey('username') && username.isNotEmpty
                  ? username
                  : fallbackUsername,
          'email': remotePayload.containsKey('email') && email.isNotEmpty
              ? email
              : fallbackEmail,
          'motto': remotePayload.containsKey('motto')
              ? motto
              : _profile?['motto'],
          'social_link': remotePayload.containsKey('social_link')
              ? socialLink
              : _profile?['social_link'],
        };
      refreshState();
      final summary = _summarizeChangedFields(changedFields);
      log(
        level: DebugLogLevel.warning,
        source: 'Editor.Sync.Settings/save',
        message:
            'Settings saved locally, cloud push deferred: '
            'Editor.Sync.Settings/save \u2014 '
            'remote update for $summary failed ($detail).',
      );
      return ActionFeedback(
          message: 'Settings saved locally: '
              'Editor.Sync.Settings/save \u2014 '
              'sync pending for $summary (cloud: $detail).');
    }
  }

  Future<ActionFeedback> _uploadAvatar() async {
    final token = _token;
    if (token == null || token.isEmpty) {
      return const ActionFeedback(
          message: 'Avatar not updated: '
              'Editor.Sync.Settings/avatar.upload \u2014 '
              'no cloud session; sign in first.',
          isError: true);
    }
    try {
      final file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(
              label: 'Images', extensions: ['png', 'jpg', 'jpeg', 'webp']),
        ],
      );
      if (file == null) {
        return const ActionFeedback(
            message: 'Avatar update cancelled: '
                'Editor.Sync.Settings/avatar.upload \u2014 '
                'user closed the file picker without selecting a file.');
      }
      final bytes = await file.readAsBytes();
      if (!mounted) {
        return const ActionFeedback(
            message: 'Avatar update cancelled: '
                'Editor.Sync.Settings/avatar.upload \u2014 '
                'widget unmounted before confirmation dialog opened.');
      }
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => _AvatarPreviewDialog(imageBytes: bytes),
      );
      if (confirmed != true) {
        return const ActionFeedback(
            message: 'Avatar update cancelled: '
                'Editor.Sync.Settings/avatar.upload \u2014 '
                'user rejected the avatar preview.');
      }
      final updated = await widget.client.uploadAvatar(token, file);
      _localStats = {
        ..._localStats,
        'avatar_updates':
            ((_localStats['avatar_updates'] as num?)?.toInt() ?? 0) + 1,
      };
      await persistLocalStats();
      // Bust the image cache so the new avatar displays immediately.
      final rawUrl = updated['image_url']?.toString() ?? '';
      final bustUrl = rawUrl.isNotEmpty
          ? '$rawUrl${rawUrl.contains('?') ? '&' : '?'}t=${DateTime.now().millisecondsSinceEpoch}'
          : rawUrl;
      imageCache.clear();
      imageCache.clearLiveImages();
        _settings = {...updated, 'image_url': bustUrl};
        _profile = {
          ...?_profile,
          'image_url': bustUrl,
          'username': updated['username'] ?? _profile?['username'],
          'email': updated['email'] ?? _profile?['email'],
          'is_staff': updated['is_staff'] ?? _profile?['is_staff'],
          'is_superuser':
              updated['is_superuser'] ?? _profile?['is_superuser'],
        };
      refreshState();
      log(
        level: DebugLogLevel.info,
        source: 'Editor.Sync.Settings/avatar.upload',
        message:
            'Avatar updated: Editor.Sync.Settings/avatar.upload \u2014 '
            'server accepted new image.',
      );
      return const ActionFeedback(
          message: 'Avatar updated: '
              'Editor.Sync.Settings/avatar.upload \u2014 '
              'server accepted new image.');
    } catch (error) {
      final cause = error.toString().replaceFirst('Exception: ', '');
      log(
        level: DebugLogLevel.error,
        source: 'Editor.Sync.Settings/avatar.upload',
        message: 'Avatar not updated: '
            'Editor.Sync.Settings/avatar.upload \u2014 $cause.',
      );
      return ActionFeedback(
          message: 'Avatar not updated: '
              'Editor.Sync.Settings/avatar.upload \u2014 $cause.',
          isError: true);
    }
  }
}
