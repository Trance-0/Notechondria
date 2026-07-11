part of notechondria_frontend;

/// Settings + avatar + planner events.
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
        !_sameTrimmedValue(nextApiBase, currentApiBase);
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
              'Portal.Sync.Settings/save \u2014 '
              'nothing to save.');
    }
    final token = _token;
    if (token == null || token.isEmpty) {
      return const ActionFeedback(
          message: 'Settings saved locally: '
              'Portal.Sync.Settings/save \u2014 '
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
        'is_superuser': updated['is_superuser'] ?? _profile?['is_superuser'],
      };
      refreshState();
      final summary = _summarizeChangedFields(changedFields);
      showMessage(
        'Settings saved: Portal.Sync.Settings/save \u2014 $summary updated.',
      );
      log(
        level: DebugLogLevel.info,
        source: 'Portal.Sync.Settings/save',
        message: 'Settings saved: Portal.Sync.Settings/save \u2014 '
            '$summary pushed to cloud.',
      );
      return ActionFeedback(
          message: 'Settings saved: Portal.Sync.Settings/save \u2014 '
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
        if (remotePayload.containsKey('social_link')) 'social_link': socialLink,
        if (remotePayload.containsKey('editor_mode')) 'editor_mode': editorMode,
        if (localSettingsChanged) 'theme_preset': themePreset,
        if (localSettingsChanged) 'theme_mode': themeMode,
        if (localSettingsChanged) 'api_base_url': nextApiBase,
      };
      _profile = {
        ...?_profile,
        'username': remotePayload.containsKey('username') && username.isNotEmpty
            ? username
            : fallbackUsername,
        'email': remotePayload.containsKey('email') && email.isNotEmpty
            ? email
            : fallbackEmail,
        'motto':
            remotePayload.containsKey('motto') ? motto : _profile?['motto'],
        'social_link': remotePayload.containsKey('social_link')
            ? socialLink
            : _profile?['social_link'],
      };
      refreshState();
      final summary = _summarizeChangedFields(changedFields);
      log(
        level: DebugLogLevel.warning,
        source: 'Portal.Sync.Settings/save',
        message: 'Settings saved locally, cloud push deferred: '
            'Portal.Sync.Settings/save \u2014 '
            'remote update for $summary failed ($detail).',
      );
      return ActionFeedback(
        message: 'Settings saved locally: '
            'Portal.Sync.Settings/save \u2014 '
            'sync pending for $summary (cloud: $detail).',
      );
    }
  }

  Future<ActionFeedback> _createPlannerEvent(
    String title,
    DateTime eventDate,
    int difficultyWeight,
    String description, {
    DateTime? endsAt,
  }) async {
    // Drawn drag supplies an explicit end; otherwise a one-hour block.
    final resolvedEnd = (endsAt != null && endsAt.isAfter(eventDate))
        ? endsAt
        : eventDate.add(const Duration(hours: 1));
    final token = _token;
    if (token == null || token.isEmpty) {
      // Signed-out / offline: keep the event on this device so guests
      // can plan without an account. Local events render in the
      // calendar + todo board next to cloud events (0.1.162) but do
      // not sync automatically.
      final event = <String, dynamic>{
        'id': 'local-${DateTime.now().microsecondsSinceEpoch}',
        'is_local': true,
        'title': title,
        'event_date': _dateOnly(eventDate).toIso8601String().split('T').first,
        'starts_at': eventDate.toIso8601String(),
        'ends_at': resolvedEnd.toIso8601String(),
        'difficulty_weight': difficultyWeight,
        'description': description,
        'is_completed': false,
        'completed_at': null,
        'course_id': null,
      };
      _localEvents = [..._localEvents, event];
      await _LocalAppStore.saveEvents(_localEvents);
      await _loadActivityWeek(startDate: _activityWeekStart);
      log(
        level: DebugLogLevel.info,
        source: 'Portal.LocalStore',
        message: 'Planner event created locally: '
            'Portal.LocalStore/event.create \u2014 '
            'stored on this device only (no cloud session); '
            'sign in to create cloud events.',
      );
      return const ActionFeedback(
          message: 'Planner event created locally: '
              'Portal.LocalStore/event.create \u2014 '
              'stored on this device; it will not sync to the cloud.');
    }
    try {
      await widget.client.createPlannerEvent(token, {
        'title': title,
        'event_date': _dateOnly(eventDate).toIso8601String().split('T').first,
        'starts_at': eventDate.toIso8601String(),
        'ends_at': resolvedEnd.toIso8601String(),
        'difficulty_weight': difficultyWeight,
        'description': description,
        'course_id': _selectedCourse?['id'],
      });
      await _refreshFrontPageData();
      await _loadActivityWeek(startDate: _activityWeekStart);
      return const ActionFeedback(
          message: 'Planner event created: '
              'Portal.Sync.Events/create \u2014 '
              'added to the activity heatmap.');
    } catch (error) {
      final cause = error.toString().replaceFirst('Exception: ', '');
      return ActionFeedback(
        message: 'Planner event not created: '
            'Portal.Sync.Events/create \u2014 $cause.',
        isError: true,
      );
    }
  }

  Future<ActionFeedback> _uploadAvatar() async {
    final token = _token;
    if (token == null || token.isEmpty) {
      return const ActionFeedback(
        message: 'Avatar not updated: '
            'Portal.Sync.Settings/avatar.upload \u2014 '
            'no cloud session; sign in first.',
        isError: true,
      );
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
                'Portal.Sync.Settings/avatar.upload \u2014 '
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
        'is_superuser': updated['is_superuser'] ?? _profile?['is_superuser'],
      };
      refreshState();
      log(
        level: DebugLogLevel.info,
        source: 'Portal.Sync.Settings/avatar.upload',
        message: 'Avatar updated: Portal.Sync.Settings/avatar.upload \u2014 '
            'server accepted new image.',
      );
      return const ActionFeedback(
          message: 'Avatar updated: '
              'Portal.Sync.Settings/avatar.upload \u2014 '
              'server accepted new image.');
    } catch (error) {
      final cause = error.toString().replaceFirst('Exception: ', '');
      log(
        level: DebugLogLevel.error,
        source: 'Portal.Sync.Settings/avatar.upload',
        message: 'Avatar not updated: '
            'Portal.Sync.Settings/avatar.upload \u2014 $cause.',
      );
      return ActionFeedback(
          message: 'Avatar not updated: '
              'Portal.Sync.Settings/avatar.upload \u2014 $cause.',
          isError: true);
    }
  }

  Future<void> _loadActivityWeek({DateTime? startDate, int? rangeDays}) async {
    final token = _token;
    final effectiveStart = _dateOnly(startDate ?? _activityWeekStart);
    final effectiveRange = rangeDays ?? _activityRangeDays;
    if (token == null || token.isEmpty) {
      // Signed-out / offline: serve the window purely from the
      // device-local events so guests still get a working calendar.
      _activityWeekStart = effectiveStart;
      _activityRangeDays = effectiveRange;
      _activityWeek = _localWeekPayload(effectiveStart, effectiveRange);
      refreshState();
      return;
    }
    try {
      final week = await widget.client.getActivityWeek(
        token,
        startDate: effectiveStart.toIso8601String().split('T').first,
        days: effectiveRange,
      );
      _activityWeekStart = effectiveStart;
      _activityRangeDays = effectiveRange;
      _activityWeek = _mergeLocalEventsIntoWeek(week);
      refreshState();
      log(
        level: DebugLogLevel.debug,
        source: 'Portal.Sync.Activity/load_week',
        message: 'Activity week loaded: '
            'Portal.Sync.Activity/load_week \u2014 '
            'week starting ${effectiveStart.toIso8601String().split('T').first} '
            'pulled from server.',
      );
    } catch (error) {
      final cause = error.toString().replaceFirst('Exception: ', '');
      _errorMessage = cause;
      refreshState();
      log(
        level: DebugLogLevel.error,
        source: 'Portal.Sync.Activity/load_week',
        message: 'Activity week not loaded: '
            'Portal.Sync.Activity/load_week \u2014 $cause.',
      );
    }
  }

  /// Builds a calendar payload for signed-out / offline users from the
  /// device-local events only. Mirrors the server
  /// `calendar_week_payload` shape so the Activity widgets need no
  /// special-casing.
  Map<String, dynamic> _localWeekPayload(DateTime start, int rangeDays) {
    String iso(DateTime d) => d.toIso8601String().split('T').first;
    final days = <Map<String, dynamic>>[];
    for (var i = 0; i < rangeDays; i++) {
      final date = iso(start.add(Duration(days: i)));
      days.add({
        'date': date,
        'events': [
          for (final e in _localEvents)
            if (e['event_date']?.toString() == date)
              {...e, 'kind': 'plan', 'source_id': e['id']},
        ],
      });
    }
    final windowEnd = iso(start.add(Duration(days: rangeDays - 1)));
    final deadlines = [
      for (final e in _localEvents)
        if (e['is_completed'] != true) {...e},
      for (final e in _localEvents)
        if (e['is_completed'] == true &&
            (e['event_date']?.toString() ?? '').compareTo(iso(start)) >= 0 &&
            (e['event_date']?.toString() ?? '').compareTo(windowEnd) <= 0)
          {...e},
    ];
    deadlines.sort((a, b) {
      final byDone = (a['is_completed'] == true ? 1 : 0)
          .compareTo(b['is_completed'] == true ? 1 : 0);
      if (byDone != 0) return byDone;
      return (a['starts_at']?.toString() ?? '')
          .compareTo(b['starts_at']?.toString() ?? '');
    });
    return {
      'start_date': iso(start),
      'previous_week_start': iso(start.subtract(Duration(days: rangeDays))),
      'next_week_start': iso(start.add(Duration(days: rangeDays))),
      'days': days,
      'deadlines': deadlines,
    };
  }

  /// Splices the device-local events into a server week payload so a
  /// signed-in user still sees events created while signed out.
  Map<String, dynamic> _mergeLocalEventsIntoWeek(Map<String, dynamic> week) {
    if (_localEvents.isEmpty) return week;
    final merged = Map<String, dynamic>.from(week);
    merged['days'] = [
      for (final raw in merged['days'] as List<dynamic>? ?? const [])
        () {
          final day = Map<String, dynamic>.from(raw as Map);
          final date = day['date']?.toString() ?? '';
          day['events'] = [
            ...(day['events'] as List<dynamic>? ?? const []),
            for (final e in _localEvents)
              if (e['event_date']?.toString() == date)
                {...e, 'kind': 'plan', 'source_id': e['id']},
          ];
          return day;
        }(),
    ];
    merged['deadlines'] = [
      ...(merged['deadlines'] as List<dynamic>? ?? const []),
      for (final e in _localEvents)
        if (e['is_completed'] != true) {...e},
    ];
    return merged;
  }
}
