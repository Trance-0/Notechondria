part of notechondria_frontend;

/// Recycle bin + full-sync + clear-local-data + log-copy + template-
/// reset actions surfaced from the Settings page. `_syncAllLocalData`
/// is the public "sync now" button, `_clearLocalData` is the nuke
/// option, `_restoreTemplateCourses` re-seeds the starter Inbox after
/// a clear, and the rest manage soft-deleted cloud notes. State
/// mutations route through `_refresh()` since extensions can't call
/// `setState` directly. Extracted from `app_shell.dart` so that file
/// stays closer to the AGENTS.md §1.5 1000-line ceiling.
extension _AppShellMaintenanceX on _AppShellState {
  Future<void> _deleteNoteToRecycleBin(Map<String, dynamic> note) async {
    final noteId = (note['id'] as num?)?.toInt();
    if (noteId == null) return;
    if (noteId < 0) {
      _localDrafts = _localDrafts
          .where((item) => item['id'] != noteId)
          .toList(growable: false);
      await _persistLocalDrafts();
      _refresh();
      _log(
        level: DebugLogLevel.info,
        source: 'Editor.Sync.Notes/delete_local',
        message:
            "Local draft deleted: "
            "Editor.Sync.Notes/delete_local \u2014 "
            "'${note['title']}' removed from offline store.",
      );
      return;
    }
    final token = _token;
    if (token == null || token.isEmpty) {
      throw Exception(
        'Note not deleted: '
        'Editor.Sync.Notes/delete \u2014 '
        'no cloud session; sign in first.',
      );
    }
    await widget.client.deleteNote(token, noteId);
    _deletedNotes = await widget.client.getDeletedNotes(token);
    await _loadLearnerNotes(reset: true, query: _learnerSearchQuery);
    _refresh();
    _log(
      level: DebugLogLevel.info,
      source: 'Editor.Sync.Notes/delete',
      message:
          "Note moved to recycle bin: "
          "Editor.Sync.Notes/delete \u2014 "
          "'${note['title']}' soft-deleted on server.",
    );
  }

  Future<void> _restoreDeletedNote(Map<String, dynamic> note) async {
    final token = _token;
    if (token == null || token.isEmpty) {
      throw Exception(
        'Note not restored: '
        'Editor.Sync.Notes/restore \u2014 '
        'no cloud session; sign in first.',
      );
    }
    final noteId = (note['id'] as num?)?.toInt();
    if (noteId == null) return;
    await widget.client.restoreDeletedNote(token, noteId);
    _deletedNotes = await widget.client.getDeletedNotes(token);
    await _loadLearnerNotes(reset: true, query: _learnerSearchQuery);
    _refresh();
    _log(
      level: DebugLogLevel.info,
      source: 'Editor.Sync.Notes/restore',
      message:
          "Note restored: Editor.Sync.Notes/restore \u2014 "
          "'${note['title']}' removed from the recycle bin.",
    );
  }

  Future<void> _emptyDeletedNotes() async {
    final token = _token;
    if (token == null || token.isEmpty) {
      throw Exception(
        'Recycle bin not emptied: '
        'Editor.Sync.Notes/empty_trash \u2014 '
        'no cloud session; sign in first.',
      );
    }
    await widget.client.emptyDeletedNotes(token);
    _deletedNotes = const [];

    _refresh();
    _log(
      level: DebugLogLevel.info,
      source: 'Editor.Sync.Notes/empty_trash',
      message:
          'Recycle bin emptied: Editor.Sync.Notes/empty_trash \u2014 '
          'all soft-deleted notes purged on the server.',
    );
  }

  Future<void> _syncAllLocalCourses() async {
    if (_localCourses.isEmpty) return;
    // Per-item try/catch so one failing course sync doesn't bubble
    // up and abort the loop halfway through \u2014 earlier iterations
    // have already been persisted, so a cascade would silently
    // orphan later local courses from their sync attempt.
    for (final course in List<Map<String, dynamic>>.from(_localCourses)) {
      try {
        await _syncLocalCourse(course);
      } catch (error) {
        _log(
          level: DebugLogLevel.warning,
          source: 'Editor.Sync.Courses/push',
          message: 'Local category not synced: '
              'Editor.Sync.Courses/push \u2014 '
              "'${course['title']}' "
              '(${error.toString().replaceFirst('Exception: ', '')}). '
              'Kept locally; will retry on next sync.',
        );
      }
    }
    if (mounted) _refresh();
  }

  Future<void> _syncAllLocalDrafts() async {
    if (_localDrafts.isEmpty) return;
    // Per-item try/catch: the pre-0.1.51 loop would abort on the
    // first failing draft, leaving later drafts un-attempted while
    // earlier ones had already been persisted. Isolate each draft so
    // a single failure can't cascade.
    for (final draft in List<Map<String, dynamic>>.from(_localDrafts)) {
      try {
        await _syncLocalDraft(draft);
      } catch (error) {
        _log(
          level: DebugLogLevel.warning,
          source: 'Editor.Sync.Notes/push',
          message: 'Local draft not synced: '
              'Editor.Sync.Notes/push \u2014 '
              "'${draft['title']}' "
              '(${error.toString().replaceFirst('Exception: ', '')}). '
              'Kept locally; will retry on next sync.',
        );
      }
    }
    if (mounted) _refresh();
  }

  Future<ActionFeedback> _syncAllLocalData(
      {bool showMessage = true}) async {
    final token = _token;
    if (token == null || token.isEmpty) {
      return const ActionFeedback(
          message: 'Local data not synced: '
              'Editor.Sync.Notes/push_all \u2014 '
              'no cloud session; sign in first.',
          isError: true);
    }
    try {
      await _syncAllLocalCourses();
      await _syncAllLocalDrafts();
      await _loadInitialData();
      const feedback = ActionFeedback(
          message: 'Local data synced: '
              'Editor.Sync.Notes/push_all \u2014 '
              'all local courses and drafts pushed to cloud.');
      if (showMessage) _showMessage(feedback.message);
      return feedback;
    } catch (error) {
      _localStats = {
        ..._localStats,
        'sync_failures':
            ((_localStats['sync_failures'] as num?)?.toInt() ?? 0) + 1,
      };
      await _persistLocalStats();
      final cause = error.toString().replaceFirst('Exception: ', '');
      _log(
        level: DebugLogLevel.error,
        source: 'Editor.Sync.Notes/push_all',
        message: 'Local data not synced: '
            'Editor.Sync.Notes/push_all \u2014 $cause.',
      );
      if (showMessage) {
        _showMessage(
          'Local data not synced: '
          'Editor.Sync.Notes/push_all \u2014 $cause.',
        );
      }
      return ActionFeedback(
          message: 'Local data not synced: '
              'Editor.Sync.Notes/push_all \u2014 $cause.',
          isError: true);
    }
  }

  Future<ActionFeedback> _clearLocalData() async {
    _localDrafts = const [];
    _localCourses = const [];
    _localTrashedDrafts = const [];
    _localTrashedCourses = const [];
    _deletedNotes = const [];
    _selectedNote = null;
    _selectedCourse = null;
    _courseNotes = const [];
    // Clear cached remote data so stale template courses don't survive.
    _localCache = _LocalAppStore.defaultCache();
    _localStats = {
      ..._LocalAppStore.defaultStats(),
      'local_data_clears':
          ((_localStats['local_data_clears'] as num?)?.toInt() ?? 0) + 1,
    };
    await _persistLocalDrafts();
    await _persistLocalCourses();
    await _persistLocalTrashedDrafts();
    await _persistLocalTrashedCourses();
    await _persistLocalStats();
    await _persistLocalCache();
    // Re-seed with just an Inbox so the workspace is never truly empty.
    await _ensureStarterWorkspace();
    _selectedCourse = _chooseDefaultCourse(
      remoteCourses: _courses,
      localCourses: _localCourses,
      frontPage: _frontPage,
    );
    if (mounted) _refresh();
    _log(
      level: DebugLogLevel.info,
      source: 'Editor.LocalStore/clear',
      message:
          'Local data cleared: Editor.LocalStore/clear \u2014 '
          'all drafts/courses/stats/cache wiped and a fresh Inbox seeded.',
    );
    return const ActionFeedback(
        message: 'Local data cleared: Editor.LocalStore/clear \u2014 '
            'all drafts and categories wiped; fresh Inbox created.');
  }

  Future<void> _copyFrontendLogs() async {
    final content = _uiLogs.join('\n');
    await Clipboard.setData(ClipboardData(text: content));
      _localStats = {
        ..._localStats,
        'logs_copied':
            ((_localStats['logs_copied'] as num?)?.toInt() ?? 0) + 1,
      };
    _refresh();
    await _persistLocalStats();
    _showMessage(
      'Logs copied: Editor.LocalStore/copy_logs \u2014 '
      'frontend debug log now on the clipboard.',
    );
  }

  Future<ActionFeedback> _restoreTemplateCourses() async {
    final token = _token;
    if (token == null || token.isEmpty) {
      return const ActionFeedback(
          message: 'Template courses not restored: '
              'Editor.LocalStore/restore_templates \u2014 '
              'no cloud session; sign in with an admin account first.',
          isError: true);
    }
    try {
      final result = await widget.client.restoreTemplateCourses(token);
      await _loadInitialData();
      final serverMessage = result['message']?.toString();
      final message = serverMessage != null && serverMessage.isNotEmpty
          ? 'Template courses restored: '
              'Editor.LocalStore/restore_templates \u2014 $serverMessage'
          : 'Template courses restored: '
              'Editor.LocalStore/restore_templates \u2014 '
              'server seeded default category tree.';
      _log(
        level: DebugLogLevel.info,
        source: 'Editor.LocalStore/restore_templates',
        message: message,
      );
      _showMessage(message);
      return ActionFeedback(message: message);
    } catch (error) {
      final cause = error.toString().replaceFirst('Exception: ', '');
      _log(
        level: DebugLogLevel.error,
        source: 'Editor.LocalStore/restore_templates',
        message: 'Template courses not restored: '
            'Editor.LocalStore/restore_templates \u2014 $cause.',
      );
      return ActionFeedback(
          message: 'Template courses not restored: '
              'Editor.LocalStore/restore_templates \u2014 $cause.',
          isError: true);
    }
  }
}
