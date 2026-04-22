part of notechondria_frontend;

/// First-run starter workspace seeder. Runs at boot after local state is
/// loaded and again whenever the app nukes local data, so the user never
/// lands on a completely empty sidebar. Extracted from `app_shell.dart`
/// as an extension on `_AppShellState` so that file stays closer to the
/// AGENTS.md §1.5 1000-line ceiling. Does not call `setState` directly:
/// both callers refresh the UI themselves afterward (see `_loadLocalState`
/// and the wipe-then-reseed flow in `app_shell.dart`).
extension _AppShellLocalStarterX on _AppShellState {
  Future<void> _ensureStarterWorkspace() async {
    if (_frontPage?.isNotEmpty == true ||
        _courses.isNotEmpty ||
        _localCourses.isNotEmpty ||
        _localDrafts.isNotEmpty) {
      return;
    }
    final starterCourse = {
      ..._buildLocalCourse(
        title: 'Inbox',
        description: 'Offline-first local note bucket for the editor app.',
      ),
      'is_default': true,
    };
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
      editorMode: 'M',
      metadataJson: jsonEncode({
        'course_id': starterCourse['id'],
        'module_title': 'Inbox',
        'module_description': 'Local starter notes for the editor app.',
        'storage_layout': 'root/category/<note>/media/.metadata',
      }),
    );
    final starterReference = _buildLocalDraft(
      title: 'Plain-text editor checklist',
      description: 'Starter checklist for the editor modes.',
      content:
          '''# Plain-text editor checklist

- Markdown mode
- Plain text mode
- Structured mode

Add syntax highlighting for plain text and keep notes searchable by title or body.''',
      editorMode: 'T',
      metadataJson: jsonEncode({
        'course_id': starterCourse['id'],
        'module_title': 'Editor setup',
      }),
    );
    _localCourses = [starterCourse];
    _localDrafts = [starterDraft, starterReference];
    _selectedCourse = starterCourse;
    _courseNotes = _localNotesForCourse(starterCourse);
    _frontPage = _frontPageFallbackPayload(const []);
    _localStats = {
      ..._localStats,
      'starter_workspace_seeded_at': DateTime.now().toUtc().toIso8601String(),
    };
    await _persistLocalCourses();
    await _persistLocalDrafts();
    await _persistLocalStats();
    await _persistLocalCache();
    log(
      level: DebugLogLevel.info,
      source: 'Editor.LocalStore/seed_starter',
      message:
          'Starter workspace seeded: '
          'Editor.LocalStore/seed_starter \u2014 '
          'first-run offline Inbox + 2 welcome drafts created.',
    );
  }
}
