part of notechondria_frontend;

/// Settings page save + avatar + planner event CRUD.
extension _AppShellSettingsActionsX on _AppShellState {
  Future<ActionFeedback> _updateSettings(
    String username,
    String email,
    String motto,
    String socialLink,
    String editorMode,
    String themePreset,
    String themeMode,
    String apiBaseUrl,
    double deadlineTimeWeight,
    double deadlineImportanceWeight,
  ) async {
    final currentSettings = Map<String, dynamic>.from(_settings ?? const {});
    final currentProfile = Map<String, dynamic>.from(_profile ?? const {});
    final currentUsername = currentSettings['username']?.toString() ??
        currentProfile['username']?.toString() ??
        '';
    final currentEmail = currentSettings['email']?.toString() ??
        currentProfile['email']?.toString() ??
        '';
    final currentMotto = currentSettings['motto']?.toString() ?? '';
    final currentSocialLink = currentSettings['social_link']?.toString() ?? '';
    final currentEditorMode = currentSettings['editor_mode']?.toString() ?? 'P';
    final currentThemePreset =
        _localSettings['theme_preset']?.toString() ?? 'teal';
    final currentThemeMode = _localSettings['theme_mode']?.toString() ?? 'S';
    final currentApiBase =
        _localSettings['api_base_url']?.toString() ?? _defaultApiBaseUrl();
    final currentDeadlineTimeWeight =
        (_localSettings['deadline_time_weight'] as num?)?.toDouble() ?? 1.0;
    final currentDeadlineImportanceWeight =
        (_localSettings['deadline_importance_weight'] as num?)?.toDouble() ?? 1.0;
    final nextApiBase = apiBaseUrl.trim().isEmpty || apiBaseUrl.trim().startsWith('/')
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
    if (!_sameTrimmedValue(motto, currentMotto)) {
      remotePayload['motto'] = motto;
      changedFields.add('motto');
    }
    if (!_sameTrimmedValue(socialLink, currentSocialLink)) {
      remotePayload['social_link'] = socialLink;
      changedFields.add('social link');
    }
    if (editorMode != currentEditorMode) {
      remotePayload['editor_mode'] = editorMode;
      changedFields.add('editor mode');
    }
    final localSettingsChanged = themePreset != currentThemePreset ||
        themeMode != currentThemeMode ||
        !_sameTrimmedValue(nextApiBase, currentApiBase) ||
        deadlineTimeWeight != currentDeadlineTimeWeight ||
        deadlineImportanceWeight != currentDeadlineImportanceWeight;
    if (themePreset != currentThemePreset || themeMode != currentThemeMode) {
      changedFields.add('theme');
    }
    if (!_sameTrimmedValue(nextApiBase, currentApiBase)) {
      changedFields.add('API base');
      // Before committing a user-entered API URL, confirm it's really a
      // Notechondria backend with compatible API version. If the handshake
      // fails we abort the save so the user keeps the old URL rather than
      // silently ending up on a dead/foreign host.
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
    if (deadlineTimeWeight != currentDeadlineTimeWeight ||
        deadlineImportanceWeight != currentDeadlineImportanceWeight) {
      changedFields.add('deadline ordering');
    }
    final updatedAt = DateTime.now().toUtc().toIso8601String();
    await _applyLocalAppSettings({
      ..._currentAppSettingsPayload(
        themePreset: themePreset,
        themeMode: themeMode,
        apiBaseUrl: nextApiBase,
      ),
      'deadline_time_weight': deadlineTimeWeight,
      'deadline_importance_weight': deadlineImportanceWeight,
      'updated_at': updatedAt,
    });
    _activityWeek = _buildOfflineActivityWeek();
    _localStats = {
      ..._localStats,
      'settings_saves': ((_localStats['settings_saves'] as num?)?.toInt() ?? 0) +
          1,
    };
    await persistLocalStats();
    if (remotePayload.isEmpty && !localSettingsChanged) {
      return const ActionFeedback(
          message: 'No settings changes: '
              'Planner.Sync.Settings/save \u2014 '
              'nothing to save.');
    }
    final token = _token;
    if (token == null || token.isEmpty) {
      return const ActionFeedback(
          message: 'Settings saved locally: '
              'Planner.Sync.Settings/save \u2014 '
              'no cloud session; will push on next sign-in.');
    }
    try {
      if (localSettingsChanged) {
        remotePayload.addAll({
          'theme_preset': themePreset,
          'theme_mode': themeMode,
          'api_base_url': nextApiBase,
          'app_settings': {
            ..._currentAppSettingsPayload(
              themePreset: themePreset,
              themeMode: themeMode,
              apiBaseUrl: nextApiBase,
            ),
            'deadline_time_weight': deadlineTimeWeight,
            'deadline_importance_weight': deadlineImportanceWeight,
          },
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
        'Settings saved: Planner.Sync.Settings/save \u2014 $summary updated.',
      );
      log(
        level: DebugLogLevel.info,
        source: 'Planner.Sync.Settings/save',
        message:
            'Settings saved: Planner.Sync.Settings/save \u2014 '
            '$summary pushed to cloud.',
      );
      return ActionFeedback(
          message: 'Settings saved: Planner.Sync.Settings/save \u2014 '
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
          if (remotePayload.containsKey('editor_mode')) 'editor_mode': editorMode,
          if (localSettingsChanged) 'theme_preset': themePreset,
          if (localSettingsChanged) 'theme_mode': themeMode,
          if (localSettingsChanged) 'api_base_url': nextApiBase,
          if (localSettingsChanged) 'deadline_time_weight': deadlineTimeWeight,
          if (localSettingsChanged) 'deadline_importance_weight': deadlineImportanceWeight,
        };
        _profile = {
          ...?_profile,
          'username': remotePayload.containsKey('username') && username.isNotEmpty
              ? username
              : fallbackUsername,
          'email': remotePayload.containsKey('email') && email.isNotEmpty
              ? email
              : fallbackEmail,
          'motto': remotePayload.containsKey('motto') ? motto : _profile?['motto'],
          'social_link': remotePayload.containsKey('social_link')
              ? socialLink
              : _profile?['social_link'],
        };
      refreshState();
      final summary = _summarizeChangedFields(changedFields);
      log(
        level: DebugLogLevel.warning,
        source: 'Planner.Sync.Settings/save',
        message:
            'Settings saved locally, cloud push deferred: '
            'Planner.Sync.Settings/save \u2014 '
            'remote update for $summary failed ($detail).',
      );
      return ActionFeedback(
        message: 'Settings saved locally: '
            'Planner.Sync.Settings/save \u2014 '
            'sync pending for $summary (cloud: $detail).',
      );
    }
  }

  Future<ActionFeedback> _createPlannerEvent(
    String title,
    DateTime eventDate,
    int difficultyWeight,
    String description,
  ) async {
    final token = _token;
    if (token == null || token.isEmpty) {
      final event = _buildLocalPlannerEvent(
        title: title,
        eventDate: eventDate,
        difficultyWeight: difficultyWeight,
        description: description,
        courseId: (_selectedCourse?['id'] as num?)?.toInt(),
      );
        _plannerEvents = [event, ..._plannerEvents];
        _activityWeek = _buildOfflineActivityWeek();
      refreshState();
      await _persistLocalCache();
      log(
        level: DebugLogLevel.info,
        source: 'Planner.Sync.Events/create_local',
        message:
            "Local planner event created: "
            "Planner.Sync.Events/create_local \u2014 "
            "'${event['title']}' queued for sync on next sign-in.",
      );
      return const ActionFeedback(
          message: 'Planner event saved locally: '
              'Planner.Sync.Events/create_local \u2014 '
              'queued for sync on next sign-in.');
    }
    try {
      await widget.client.createPlannerEvent(token, {
        'title': title,
        'event_date': _dateOnly(eventDate).toIso8601String().split('T').first,
        'starts_at': eventDate.toIso8601String(),
        'ends_at': eventDate.add(const Duration(hours: 1)).toIso8601String(),
        'difficulty_weight': difficultyWeight,
        'description': description,
        'course_id': _selectedCourse?['id'],
      });
      await _loadActivityWeek(startDate: _activityWeekStart);
      return const ActionFeedback(
          message: 'Planner event created: '
              'Planner.Sync.Events/create \u2014 '
              'added to the activity heatmap.');
    } catch (error) {
      final cause = error.toString().replaceFirst('Exception: ', '');
      return ActionFeedback(
        message: 'Planner event not created: '
            'Planner.Sync.Events/create \u2014 $cause.',
        isError: true,
      );
    }
  }

  Future<ActionFeedback> _uploadAvatar() async {
    final token = _token;
    if (token == null || token.isEmpty) {
      return const ActionFeedback(
        message: 'Avatar not updated: '
            'Planner.Sync.Settings/avatar.upload \u2014 '
            'no cloud session; sign in first.',
        isError: true,
      );
    }
    try {
      final file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(label: 'Images', extensions: ['png', 'jpg', 'jpeg', 'webp']),
        ],
      );
      if (file == null) {
        return const ActionFeedback(
            message: 'Avatar update cancelled: '
                'Planner.Sync.Settings/avatar.upload \u2014 '
                'user closed the file picker without selecting a file.');
      }
      final updated = await widget.client.uploadAvatar(token, file);
      _localStats = {
        ..._localStats,
        'avatar_updates':
            ((_localStats['avatar_updates'] as num?)?.toInt() ?? 0) + 1,
      };
      await persistLocalStats();
        _settings = updated;
        _profile = {
          ...?_profile,
          'image_url': updated['image_url'],
          'username': updated['username'] ?? _profile?['username'],
          'email': updated['email'] ?? _profile?['email'],
          'is_staff': updated['is_staff'] ?? _profile?['is_staff'],
          'is_superuser':
              updated['is_superuser'] ?? _profile?['is_superuser'],
        };
      refreshState();
      log(
        level: DebugLogLevel.info,
        source: 'Planner.Sync.Settings/avatar.upload',
        message:
            'Avatar updated: Planner.Sync.Settings/avatar.upload \u2014 '
            'server accepted new image.',
      );
      return const ActionFeedback(
          message: 'Avatar updated: '
              'Planner.Sync.Settings/avatar.upload \u2014 '
              'server accepted new image.');
    } catch (error) {
      final cause = error.toString().replaceFirst('Exception: ', '');
      log(
        level: DebugLogLevel.error,
        source: 'Planner.Sync.Settings/avatar.upload',
        message: 'Avatar not updated: '
            'Planner.Sync.Settings/avatar.upload \u2014 $cause.',
      );
      return ActionFeedback(
          message: 'Avatar not updated: '
              'Planner.Sync.Settings/avatar.upload \u2014 $cause.',
          isError: true);
    }
  }

  Future<void> _loadActivityWeek({DateTime? startDate}) async {
    final token = _token;
    if (token == null || token.isEmpty) {
      return;
    }
    final effectiveStart = _dateOnly(startDate ?? _activityWeekStart);
    try {
      final week = await widget.client.getActivityWeek(
        token,
        startDate: effectiveStart.toIso8601String().split('T').first,
      );
        _activityWeekStart = effectiveStart;
        _activityWeek = week;
      refreshState();
      log(
        level: DebugLogLevel.debug,
        source: 'Planner.Sync.Activity/load_week',
        message:
            'Activity week loaded: '
            'Planner.Sync.Activity/load_week \u2014 '
            'week starting ${effectiveStart.toIso8601String().split('T').first} '
            'pulled from server.',
      );
    } catch (error) {
      final cause = error.toString().replaceFirst('Exception: ', '');
        _errorMessage = cause;
      refreshState();
      log(
        level: DebugLogLevel.error,
        source: 'Planner.Sync.Activity/load_week',
        message: 'Activity week not loaded: '
            'Planner.Sync.Activity/load_week \u2014 $cause.',
      );
    }
  }
}
