part of notechondria_frontend;

/// First-run starter content seeder. Runs at boot after local state is
/// loaded and again whenever the app nukes local data, so the user
/// never lands on a completely empty editor. Extracted from
/// `app_shell.dart` as an extension on `_AppShellState` so that file
/// stays closer to the AGENTS.md §1.5 1000-line ceiling. Does not
/// call `setState` directly: both callers refresh the UI themselves
/// afterward (see `_loadLocalState` and the wipe-then-reseed flow in
/// `app_shell.dart`).
///
/// 0.1.120: pre-refactor this file managed a magic local "Inbox"
/// course (matching the server-side `is_default=True` row). With the
/// Inbox concept retired in favour of a frontend-only synthetic
/// uncategorized bucket, the seeder no longer creates any local
/// course — it just drops a welcome draft with no `course_id`, which
/// the synthetic bucket picks up automatically.
extension _AppShellLocalStarterX on _AppShellState {
  /// Cold-boot guarantor. If the user has no notes anywhere (cached
  /// cloud + local drafts), drop a welcome draft into the
  /// uncategorized bucket. Idempotent and additive.
  Future<void> _ensureStarterWorkspace() async {
    final hasAnyDraft = _localDrafts.isNotEmpty;
    final hasAnyCloudNote =
        _courses.any((c) => (c['recent_notes'] as List?)?.isNotEmpty == true);
    if (hasAnyDraft || hasAnyCloudNote) return;
    await _seedStarterWelcomeDraft();
  }

  /// Drops a welcome draft with no `course_id` so it surfaces in the
  /// synthetic uncategorized bucket. Idempotent: skips if a welcome
  /// draft (matched by client-id prefix) is already present.
  Future<void> _seedStarterWelcomeDraft() async {
    const welcomeMarker = 'welcome-draft';
    final alreadySeeded = _localDrafts.any((draft) {
      final id = draft['client_draft_id']?.toString() ?? '';
      return id.startsWith(welcomeMarker);
    });
    if (alreadySeeded) return;

    final welcome = _buildLocalDraft(
      title: 'Welcome to the editor workspace',
      description: 'Starter note for the offline-first editor.',
      content: '''# Welcome to the editor workspace

This app is the offline-first markdown editor.

## Tips

- New notes start without a category and land in the uncategorized
  bucket at the top of the sidebar.
- Pick a category from the metadata picker, or rename the
  uncategorized bucket from Settings → Display.
- Sync runs automatically once you sign in.

Use this draft as a starting point and edit / delete it freely.''',
      editorMode: 'G',
      metadataJson: jsonEncode(<String, dynamic>{}),
    );
    welcome['client_draft_id'] = welcomeMarker;
    _localDrafts = [..._localDrafts, welcome];
    _localStats = {
      ..._localStats,
      'starter_workspace_seeded_at': DateTime.now().toUtc().toIso8601String(),
    };
    await persistLocalDrafts();
    await persistLocalStats();
    await _persistLocalCache();
    log(
      level: DebugLogLevel.info,
      source: 'Editor.LocalStore/restore_local_starter',
      message: 'Starter welcome draft seeded into uncategorized bucket: '
          'Editor.LocalStore/restore_local_starter — '
          'no prior notes detected; one draft inserted with no course_id.',
    );
  }

  /// Backwards-compat alias: pre-0.1.120 callers (e.g. the
  /// maintenance "restore" action) imported this name. Re-exports
  /// `_seedStarterWelcomeDraft` so older code paths keep compiling
  /// during the refactor.
  Future<void> _seedStarterInboxAlongsideExisting() =>
      _seedStarterWelcomeDraft();
}
