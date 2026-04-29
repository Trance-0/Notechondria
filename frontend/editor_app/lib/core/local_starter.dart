part of notechondria_frontend;

/// First-run starter workspace seeder. Runs at boot after local state is
/// loaded and again whenever the app nukes local data, so the user never
/// lands on a completely empty sidebar. Extracted from `app_shell.dart`
/// as an extension on `_AppShellState` so that file stays closer to the
/// AGENTS.md §1.5 1000-line ceiling. Does not call `setState` directly:
/// both callers refresh the UI themselves afterward (see `_loadLocalState`
/// and the wipe-then-reseed flow in `app_shell.dart`).
extension _AppShellLocalStarterX on _AppShellState {
  /// Cold-boot guarantor: if the user has no Inbox anywhere
  /// (cached cloud OR local), seed a local one. Idempotent and
  /// additive — won't clobber any drafts the user already has.
  ///
  /// 0.1.84 rewrote this from a "all-or-nothing first run"
  /// seeder into a thin wrapper around
  /// `_seedStarterInboxAlongsideExisting`. The earlier short-
  /// circuit guard `if (_frontPage?.isNotEmpty ...) return` would
  /// silently suppress seeding for previously-signed-in users
  /// whose `_localCache['front_page']` was non-empty but their
  /// cached `_courses` had no Inbox row — leaving them with no
  /// usable default category in the offline view. The new
  /// approach checks the actual Inbox presence and is robust
  /// against stale cache payloads.
  Future<void> _ensureStarterWorkspace() async {
    bool hasInbox(Iterable<Map<String, dynamic>> courses) {
      for (final course in courses) {
        if (course['title']?.toString().trim().toLowerCase() == 'inbox') {
          return true;
        }
      }
      return false;
    }
    if (hasInbox(_courses) || hasInbox(_localCourses)) {
      if (_token == null || _token!.isEmpty) {
        // Local-only user: ensure the Inbox is selected even
        // when found from a prior session, so the sidebar shows
        // a usable default category on cold boot.
        for (final course in _localCourses) {
          if (course['title']?.toString().trim().toLowerCase() == 'inbox') {
            _selectedCourse ??= course;
            _courseNotes = _localNotesForCourse(course);
            break;
          }
        }
      }
      return;
    }
    await _seedStarterInboxAlongsideExisting();
  }

  /// Re-seed (or rediscover) the starter Inbox so the user always has
  /// one. Idempotent: if a local category named "Inbox" already
  /// exists, reuse it; otherwise create a fresh one. Welcome drafts
  /// are only appended when the discovered/created Inbox has zero
  /// drafts pointing at it, so tapping "Restore" twice doesn't
  /// duplicate either the category or its starter notes.
  Future<void> _seedStarterInboxAlongsideExisting() async {
    // Inbox is GLOBALLY unique per user — at most one row total
    // across local + cloud lists. Check both before creating a
    // fresh local one. If a cloud Inbox already exists (signed-in
    // user), select it and stop; the user already has their
    // Inbox.
    Map<String, dynamic>? existingCloudInbox;
    for (final course in _courses) {
      final title = course['title']?.toString().trim().toLowerCase() ?? '';
      if (title == 'inbox') {
        existingCloudInbox = course;
        break;
      }
    }
    if (existingCloudInbox != null) {
      _selectedCourse = existingCloudInbox;
      _frontPage ??= frontPageFallbackPayload(_courses);
      _localStats = {
        ..._localStats,
        'starter_workspace_seeded_at':
            DateTime.now().toUtc().toIso8601String(),
      };
      await persistLocalStats();
      log(
        level: DebugLogLevel.info,
        source: 'Editor.LocalStore/restore_local_starter',
        message:
            'Starter Inbox already on cloud: '
            'Editor.LocalStore/restore_local_starter — '
            "selected existing remote Inbox '${existingCloudInbox['title']}'; "
            'no local copy created.',
      );
      return;
    }
    Map<String, dynamic>? existingInbox;
    for (final course in _localCourses) {
      final title = course['title']?.toString().trim().toLowerCase() ?? '';
      if (title == 'inbox') {
        existingInbox = course;
        break;
      }
    }
    final inboxCourse = existingInbox ??
        {
          ..._buildLocalCourse(
            title: 'Inbox',
            description:
                'Offline-first local note bucket for the editor app.',
          ),
          'is_default': true,
        };
    if (existingInbox == null) {
      _localCourses = [..._localCourses, inboxCourse];
    }
    final inboxId = inboxCourse['id'];
    final hasDrafts = _localDrafts.any((draft) {
      final metadataJson = draft['metadata_json']?.toString() ?? '';
      if (metadataJson.isEmpty) return false;
      final metadata = _decodeNoteMetadata(metadataJson);
      return metadata['course_id'] == inboxId;
    });
    if (!hasDrafts) {
      final starterDraft = _buildLocalDraft(
        title: 'Welcome to the editor workspace',
        description: 'Starter note describing the offline storage layout.',
        content: '''# Welcome to the editor workspace

This app is the offline-first markdown editor.

## Suggested local structure

```
root/
- category/
- <note>/
- media/
- .metadata
- note-<created_timestamp>.md
```

Use this draft as a starting point and sync later when you sign in.''',
        editorMode: 'G',
        metadataJson: jsonEncode({
          'course_id': inboxId,
          'module_title': 'Inbox',
          'module_description': 'Local starter notes for the editor app.',
          'storage_layout': 'root/category/<note>/media/.metadata',
        }),
      );
      final starterReference = _buildLocalDraft(
        title: 'Plain-text editor checklist',
        description: 'Starter checklist for the editor modes.',
        content: '''# Plain-text editor checklist

- Markdown mode
- Plain text mode
- Structured mode

Add syntax highlighting for plain text and keep notes searchable by title or body.''',
        editorMode: 'P',
        metadataJson: jsonEncode({
          'course_id': inboxId,
          'module_title': 'Editor setup',
        }),
      );
      _localDrafts = [..._localDrafts, starterDraft, starterReference];
    }
    _selectedCourse = inboxCourse;
    _courseNotes = _localNotesForCourse(inboxCourse);
    _frontPage ??= frontPageFallbackPayload(const []);
    _localStats = {
      ..._localStats,
      'starter_workspace_seeded_at': DateTime.now().toUtc().toIso8601String(),
    };
    await persistLocalCourses();
    await persistLocalDrafts();
    await persistLocalStats();
    await _persistLocalCache();
    log(
      level: DebugLogLevel.info,
      source: 'Editor.LocalStore/restore_local_starter',
      message: existingInbox == null
          ? 'Starter Inbox created: '
              'Editor.LocalStore/restore_local_starter \u2014 '
              'no existing Inbox; fresh course + 2 welcome drafts seeded.'
          : (hasDrafts
              ? 'Starter Inbox reused: '
                  'Editor.LocalStore/restore_local_starter \u2014 '
                  'existing Inbox already has notes; nothing seeded.'
              : 'Starter Inbox refilled: '
                  'Editor.LocalStore/restore_local_starter \u2014 '
                  'existing empty Inbox; 2 welcome drafts seeded.'),
    );
  }
}
