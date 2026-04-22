part of notechondria_frontend;

/// Maintenance actions.
extension _AppShellMaintenanceX on _AppShellState {
  Future<void> _deleteNoteToRecycleBin(Map<String, dynamic> note) async {
    final noteId = (note['id'] as num?)?.toInt();
    if (noteId == null) {
      return;
    }
    if (noteId < 0) {
      _localDrafts = _localDrafts
          .where((item) => item['id'] != noteId)
          .toList(growable: false);
      await _persistLocalDrafts();
      refreshState();
      log(
        level: DebugLogLevel.info,
        source: 'Portal.Sync.Notes/delete_local',
        message:
            "Local draft deleted: "
            "Portal.Sync.Notes/delete_local \u2014 "
            "'${note['title']}' removed from offline store.",
      );
      return;
    }
    final token = _token;
    if (token == null || token.isEmpty) {
      throw Exception(
        'Note not deleted: '
        'Portal.Sync.Notes/delete \u2014 '
        'no cloud session; sign in first.',
      );
    }
    await widget.client.deleteNote(token, noteId);
    _deletedNotes = await widget.client.getDeletedNotes(token);
    await _loadLearnerNotes(reset: true, query: _learnerSearchQuery);
    await _refreshFrontPageData();
    refreshState();
    log(
      level: DebugLogLevel.info,
      source: 'Portal.Sync.Notes/delete',
      message:
          "Note moved to recycle bin: "
          "Portal.Sync.Notes/delete \u2014 "
          "'${note['title']}' soft-deleted on server.",
    );
  }

  Future<void> _restoreDeletedNote(Map<String, dynamic> note) async {
    final token = _token;
    if (token == null || token.isEmpty) {
      throw Exception(
        'Note not restored: '
        'Portal.Sync.Notes/restore \u2014 '
        'no cloud session; sign in first.',
      );
    }
    final noteId = (note['id'] as num?)?.toInt();
    if (noteId == null) {
      return;
    }
    await widget.client.restoreDeletedNote(token, noteId);
    _deletedNotes = await widget.client.getDeletedNotes(token);
    await _loadLearnerNotes(reset: true, query: _learnerSearchQuery);
    refreshState();
    log(
      level: DebugLogLevel.info,
      source: 'Portal.Sync.Notes/restore',
      message:
          "Note restored: Portal.Sync.Notes/restore \u2014 "
          "'${note['title']}' removed from the recycle bin.",
    );
  }

  Future<void> _emptyDeletedNotes() async {
    final token = _token;
    if (token == null || token.isEmpty) {
      throw Exception(
        'Recycle bin not emptied: '
        'Portal.Sync.Notes/empty_trash \u2014 '
        'no cloud session; sign in first.',
      );
    }
    await widget.client.emptyDeletedNotes(token);
      _deletedNotes = const [];
    refreshState();
    log(
      level: DebugLogLevel.info,
      source: 'Portal.Sync.Notes/empty_trash',
      message:
          'Recycle bin emptied: Portal.Sync.Notes/empty_trash \u2014 '
          'all soft-deleted notes purged on the server.',
    );
  }

  Future<void> _syncAllLocalCourses() async {
    if (_localCourses.isEmpty) {
      return;
    }
    // Per-item try/catch so one failing course doesn't abort the
    // loop and orphan later items.
    for (final course in List<Map<String, dynamic>>.from(_localCourses)) {
      try {
        await _syncLocalCourse(course);
      } catch (error) {
        log(
          level: DebugLogLevel.warning,
          source: 'Portal.Sync.Courses/push',
          message: 'Local category not synced: '
              'Portal.Sync.Courses/push \u2014 '
              "'${course['title']}' "
              '(${error.toString().replaceFirst('Exception: ', '')}). '
              'Kept locally; will retry on next sync.',
        );
      }
    }
    if (mounted) {
      refreshState();
    }
  }

  Future<void> _syncAllLocalDrafts() async {
    if (_localDrafts.isEmpty) {
      return;
    }
    for (final draft in List<Map<String, dynamic>>.from(_localDrafts)) {
      try {
        await _syncLocalDraft(draft);
      } catch (error) {
        log(
          level: DebugLogLevel.warning,
          source: 'Portal.Sync.Notes/push',
          message: 'Local draft not synced: '
              'Portal.Sync.Notes/push \u2014 '
              "'${draft['title']}' "
              '(${error.toString().replaceFirst('Exception: ', '')}). '
              'Kept locally; will retry on next sync.',
        );
      }
    }
    if (mounted) {
      refreshState();
    }
  }

  Future<ActionFeedback> _syncAllLocalData({bool announce = true}) async {
    final token = _token;
    if (token == null || token.isEmpty) {
      return const ActionFeedback(
        message: 'Local data not synced: '
            'Portal.Sync.Notes/push_all \u2014 '
            'no cloud session; sign in first.',
        isError: true,
      );
    }
    try {
      await _syncAllLocalCourses();
      await _syncAllLocalDrafts();
      await _loadInitialData();
      const feedback = ActionFeedback(
          message: 'Local data synced: '
              'Portal.Sync.Notes/push_all \u2014 '
              'all local courses and drafts pushed to cloud.');
      if (announce) {
        showMessage(feedback.message);
      }
      return feedback;
    } catch (error) {
      _localStats = {
        ..._localStats,
        'sync_failures': ((_localStats['sync_failures'] as num?)?.toInt() ?? 0) + 1,
      };
      await _persistLocalStats();
      final cause = error.toString().replaceFirst('Exception: ', '');
      log(
        level: DebugLogLevel.error,
        source: 'Portal.Sync.Notes/push_all',
        message: 'Local data not synced: '
            'Portal.Sync.Notes/push_all \u2014 $cause.',
      );
      if (announce) {
        showMessage(
          'Local data not synced: '
          'Portal.Sync.Notes/push_all \u2014 $cause.',
        );
      }
      return ActionFeedback(
          message: 'Local data not synced: '
              'Portal.Sync.Notes/push_all \u2014 $cause.',
          isError: true);
    }
  }

  Future<ActionFeedback> _clearLocalCache() async {
    _localCache = _LocalAppStore.defaultCache();
    _frontPage = _localCourses.isNotEmpty
        ? _frontPageFallbackPayload(const [])
        : const <String, dynamic>{};
    _courses = const [];
    _activity = const [];
    _courseNotes = _isLocalCourse(_selectedCourse)
        ? _localNotesForCourse(_selectedCourse!)
        : const [];
    _selectedCourse = _isLocalCourse(_selectedCourse)
        ? _selectedCourse
        : _chooseDefaultCourse(
            remoteCourses: const [],
            localCourses: _localCourses,
            frontPage: _frontPage,
          );
    _localStats = {
      ..._localStats,
      'cache_clears': ((_localStats['cache_clears'] as num?)?.toInt() ?? 0) + 1,
    };
    await _LocalAppStore.saveCache(_localCache);
    await _persistLocalStats();
    if (mounted) {
      refreshState();
    }
    log(
      level: DebugLogLevel.info,
      source: 'Portal.LocalStore/clear_cache',
      message:
          'Cached remote data cleared: '
          'Portal.LocalStore/clear_cache \u2014 '
          'front-page/courses/activity wiped; local drafts untouched.',
    );
    return const ActionFeedback(
        message: 'Cached remote data cleared: '
            'Portal.LocalStore/clear_cache \u2014 '
            'cloud rows wiped; local drafts kept.');
  }

  Future<ActionFeedback> _clearLocalData() async {
    _localDrafts = const [];
    _localCourses = const [];
    _localTrashedDrafts = const [];
    _localTrashedCourses = const [];
    _selectedNote = null;
    if (_selectedCourse != null && _isLocalCourse(_selectedCourse)) {
      _selectedCourse = _chooseDefaultCourse(
        remoteCourses: _courses,
        localCourses: const [],
        frontPage: _frontPage,
      );
      _courseNotes = _selectedCourse == null || _isLocalCourse(_selectedCourse)
          ? const []
          : _courseNotes;
    }
    _localStats = {
      ..._localStats,
      'local_data_clears':
          ((_localStats['local_data_clears'] as num?)?.toInt() ?? 0) + 1,
    };
    await _persistLocalDrafts();
    await _persistLocalCourses();
    await _persistLocalTrashedDrafts();
    await _persistLocalTrashedCourses();
    await _persistLocalStats();
    if (mounted) {
      refreshState();
    }
    log(
      level: DebugLogLevel.info,
      source: 'Portal.LocalStore/clear',
      message:
          'Local data cleared: Portal.LocalStore/clear \u2014 '
          'local drafts and local courses wiped.',
    );
    return const ActionFeedback(
        message: 'Local data cleared: '
            'Portal.LocalStore/clear \u2014 '
            'local drafts and local courses removed.');
  }

  Future<void> _togglePlannerEventCompletion(
      Map<String, dynamic> event, bool completed) async {
    final token = _token;
    if (token == null || token.isEmpty) {
      throw Exception(
        'Planner event not updated: '
        'Portal.Sync.Events/toggle \u2014 '
        'no cloud session; sign in first.',
      );
    }
    await widget.client.updatePlannerEvent(token, event['id'] as int, {
      'is_completed': completed,
      'completed_at': completed
          ? DateTime.now().toUtc().toIso8601String()
          : null,
    });
    await _loadActivityWeek(startDate: _activityWeekStart);
    final refreshedEvents = await widget.client.getPlannerEvents(token);
      _plannerEvents = refreshedEvents;
    refreshState();
    log(
      level: DebugLogLevel.info,
      source: 'Portal.Sync.Events/toggle',
      message:
          'Planner event ${completed ? "completed" : "reopened"}: '
          'Portal.Sync.Events/toggle \u2014 '
          '"${event['title']}" state updated on server.',
    );
  }

  Future<void> _subscribeToCourse(Map<String, dynamic> course) async {
    final token = _token;
    if (token == null || token.isEmpty) {
      throw Exception(
        'Course not subscribed: '
        'Portal.Sync.Courses/subscribe \u2014 '
        'no cloud session; sign in first.',
      );
    }
    await widget.client.subscribeCourse(token, course['id'] as int);
    await _loadInitialData();
  }

  Future<void> _unsubscribeFromCourse(Map<String, dynamic> course) async {
    final token = _token;
    if (token == null || token.isEmpty) {
      throw Exception(
        'Course not unsubscribed: '
        'Portal.Sync.Courses/unsubscribe \u2014 '
        'no cloud session; sign in first.',
      );
    }
    await widget.client.unsubscribeCourse(token, course['id'] as int);
    await _loadInitialData();
  }

  Future<void> _copyFrontendLogs() async {
    final content = uiLogs.join('\n');
    await Clipboard.setData(ClipboardData(text: content));
      _localStats = {
        ..._localStats,
        'logs_copied': ((_localStats['logs_copied'] as num?)?.toInt() ?? 0) + 1,
      };
    refreshState();
    await _persistLocalStats();
    showMessage(
      'Logs copied: Portal.LocalStore/copy_logs \u2014 '
      'frontend debug log now on the clipboard.',
    );
  }

  Future<ActionFeedback> _restoreTemplateCourses() async {
    final token = _token;
    if (token == null || token.isEmpty) {
      return const ActionFeedback(
        message: 'Template courses not restored: '
            'Portal.LocalStore/restore_templates \u2014 '
            'no cloud session; sign in with an admin account first.',
        isError: true,
      );
    }
    try {
      final result = await widget.client.restoreTemplateCourses(token);
      await _loadInitialData();
      final serverMessage = result['message']?.toString();
      final message = serverMessage != null && serverMessage.isNotEmpty
          ? 'Template courses restored: '
              'Portal.LocalStore/restore_templates \u2014 $serverMessage'
          : 'Template courses restored: '
              'Portal.LocalStore/restore_templates \u2014 '
              'server seeded default portal template tree.';
      log(
        level: DebugLogLevel.info,
        source: 'Portal.LocalStore/restore_templates',
        message: message,
      );
      showMessage(message);
      return ActionFeedback(message: message);
    } catch (error) {
      final cause = error.toString().replaceFirst('Exception: ', '');
      log(
        level: DebugLogLevel.error,
        source: 'Portal.LocalStore/restore_templates',
        message: 'Template courses not restored: '
            'Portal.LocalStore/restore_templates \u2014 $cause.',
      );
      return ActionFeedback(
          message: 'Template courses not restored: '
              'Portal.LocalStore/restore_templates \u2014 $cause.',
          isError: true);
    }
  }
}
