part of notechondria_frontend;

/// Recycle bin + full-sync + clear-local-data + log-copy + template-
/// reset actions surfaced from the Settings page. `_syncAllLocalData`
/// is the public "sync now" button, `_clearLocalData` is the nuke
/// option, `_restoreTemplateCourses` re-seeds the starter Inbox after
/// a clear, and the rest manage soft-deleted cloud notes. State
/// mutations route through `refreshState()` since extensions can't call
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
      await persistLocalDrafts();
      refreshState();
      log(
        level: DebugLogLevel.info,
        source: 'Editor.Sync.Notes/delete_local',
        message: "Local draft deleted: "
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
    refreshState();
    log(
      level: DebugLogLevel.info,
      source: 'Editor.Sync.Notes/delete',
      message: "Note moved to recycle bin: "
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
    refreshState();
    log(
      level: DebugLogLevel.info,
      source: 'Editor.Sync.Notes/restore',
      message: "Note restored: Editor.Sync.Notes/restore \u2014 "
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

    refreshState();
    log(
      level: DebugLogLevel.info,
      source: 'Editor.Sync.Notes/empty_trash',
      message: 'Recycle bin emptied: Editor.Sync.Notes/empty_trash \u2014 '
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
        log(
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
    if (mounted) refreshState();
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
        final cause = error.toString().replaceFirst('Exception: ', '');
        log(
          level: DebugLogLevel.warning,
          source: 'Editor.Sync.Notes/push',
          message: 'Local draft not synced: '
              'Editor.Sync.Notes/push \u2014 '
              "'${draft['title']}' "
              '($cause). '
              'Kept locally; will retry on next sync.',
        );
        // Stamp the failure on the draft so the learner card can
        // show a distinct "sync failed" icon (vs "not yet synced").
        // Cleared automatically on next successful sync because the
        // draft is removed from `_localDrafts` on success.
        _localDrafts = _localDrafts
            .map((item) => item['id'] == draft['id']
                ? {
                    ...item,
                    'last_sync_error': cause,
                    'last_sync_attempt_at':
                        DateTime.now().toUtc().toIso8601String(),
                  }
                : item)
            .toList(growable: false);
      }
    }
    await persistLocalDrafts();
    if (mounted) refreshState();
  }

  Future<ActionFeedback> _syncAllLocalData({bool announce = true}) async {
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
      if (announce) showMessage(feedback.message);
      return feedback;
    } catch (error) {
      _localStats = {
        ..._localStats,
        'sync_failures':
            ((_localStats['sync_failures'] as num?)?.toInt() ?? 0) + 1,
      };
      await persistLocalStats();
      final cause = error.toString().replaceFirst('Exception: ', '');
      log(
        level: DebugLogLevel.error,
        source: 'Editor.Sync.Notes/push_all',
        message: 'Local data not synced: '
            'Editor.Sync.Notes/push_all \u2014 $cause.',
      );
      if (announce) {
        showMessage(
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
    await persistLocalDrafts();
    await persistLocalCourses();
    await _persistLocalTrashedDrafts();
    await _persistLocalTrashedCourses();
    await persistLocalStats();
    await _persistLocalCache();
    // Re-seed with just an Inbox so the workspace is never truly empty.
    await _ensureStarterWorkspace();
    _selectedCourse = _chooseDefaultCourse(
      remoteCourses: _courses,
      localCourses: _localCourses,
      frontPage: _frontPage,
    );
    if (mounted) refreshState();
    log(
      level: DebugLogLevel.info,
      source: 'Editor.LocalStore/clear',
      message: 'Local data cleared: Editor.LocalStore/clear \u2014 '
          'all drafts/courses/stats/cache wiped and a fresh Inbox seeded.',
    );
    return const ActionFeedback(
        message: 'Local data cleared: Editor.LocalStore/clear \u2014 '
            'all drafts and categories wiped; fresh Inbox created.');
  }

  Future<void> _copyFrontendLogs() async {
    final content = uiLogs.join('\n');
    await Clipboard.setData(ClipboardData(text: content));
    _localStats = {
      ..._localStats,
      'logs_copied': ((_localStats['logs_copied'] as num?)?.toInt() ?? 0) + 1,
    };
    refreshState();
    await persistLocalStats();
    showMessage(
      'Logs copied: Editor.LocalStore/copy_logs \u2014 '
      'frontend debug log now on the clipboard.',
    );
  }

  /// Re-seeds the local starter Inbox + welcome note. Works regardless
  /// of online/offline state — the Inbox lives entirely client-side and
  /// is what new users land on the first time they open the editor. If
  /// the user has wiped their local data and wants to start over, this
  /// is the entry point that reproduces that initial workspace.
  ///
  /// Distinct from `_restoreTemplateCourses`, which calls the backend
  /// admin endpoint to re-seed the cloud template catalog (3 courses).
  /// That stays in the Developer section because it's destructive and
  /// requires admin credentials.
  Future<ActionFeedback> _restoreLocalStarterTemplate() async {
    try {
      // Force a re-seed even when the user already has local categories
      // or drafts: `_ensureStarterWorkspace` short-circuits when ANY
      // local state exists, but the user explicitly tapped "Restore
      // default inbox" because they want the Inbox back regardless of
      // whatever else they've created. We rebuild a fresh Inbox course
      // (idempotent on uuid clash via _buildLocalCourse) and append the
      // welcome drafts only when no draft references the new Inbox id.
      _localSettings = {
        ..._localSettings,
        'starter_workspace_seeded_at': '',
      };
      await persistLocalSettings();
      await _seedStarterInboxAlongsideExisting();
      // The seeder mutates `_localCourses` / `_selectedCourse` directly
      // (it's an extension method that can't call setState). Without
      // refreshState() here, the sidebar would not pick up the new row
      // until the next unrelated rebuild — which made the "Restore"
      // action look like a no-op when the user observed the sidebar
      // immediately after tapping it.
      if (mounted) refreshState();
      const message = 'Starter inbox restored: '
          'Editor.LocalStore/restore_local_starter — '
          'local Inbox + welcome note re-seeded.';
      log(
        level: DebugLogLevel.info,
        source: 'Editor.LocalStore/restore_local_starter',
        message: message,
      );
      showMessage(message);
      return const ActionFeedback(message: message);
    } catch (error) {
      final cause = error.toString().replaceFirst('Exception: ', '');
      log(
        level: DebugLogLevel.error,
        source: 'Editor.LocalStore/restore_local_starter',
        message: 'Starter inbox not restored: '
            'Editor.LocalStore/restore_local_starter — $cause.',
      );
      return ActionFeedback(
          message: 'Starter inbox not restored: '
              'Editor.LocalStore/restore_local_starter — $cause.',
          isError: true);
    }
  }

  /// Manual cleanup of the pre-0.1.127 unprefixed shared-storage keys
  /// left behind by the namespacing migration. Global to the browser
  /// origin, so this clears them for editor / planner / portal at
  /// once. No-op (0 removed) after the keys are already gone.
  Future<ActionFeedback> _clearLegacySharedStorage() async {
    try {
      final removed = await _LocalAppStore.clearLegacyKeys();
      final message = removed == 0
          ? 'No legacy storage to clear: '
              'Editor.LocalStore/clear_legacy — the pre-0.1.127 '
              'unprefixed keys were already removed.'
          : 'Legacy storage cleared: Editor.LocalStore/clear_legacy — '
              'removed $removed unprefixed pre-0.1.127 '
              'key${removed == 1 ? '' : 's'} shared across the apps. '
              'Your current data is unaffected.';
      log(
        level: DebugLogLevel.info,
        source: 'Editor.LocalStore/clear_legacy',
        message: message,
      );
      showMessage(message);
      return ActionFeedback(message: message);
    } catch (error) {
      final cause = error.toString().replaceFirst('Exception: ', '');
      final message = 'Legacy storage not cleared: '
          'Editor.LocalStore/clear_legacy — $cause.';
      log(
        level: DebugLogLevel.error,
        source: 'Editor.LocalStore/clear_legacy',
        message: message,
      );
      return ActionFeedback(message: message, isError: true);
    }
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
      log(
        level: DebugLogLevel.info,
        source: 'Editor.LocalStore/restore_templates',
        message: message,
      );
      showMessage(message);
      return ActionFeedback(message: message);
    } catch (error) {
      final cause = error.toString().replaceFirst('Exception: ', '');
      log(
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
