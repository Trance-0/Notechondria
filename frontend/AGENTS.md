# Frontend AGENTS.md - Split App Development Guide

This directory contains the three standalone Notechondria frontend apps.

## Current shape

- `editor_app/` — offline-first note editor
- `planner_app/` — course/module/calendar planner
- `portal_app/` — router/orchestrator shell
- `README.md` — concise human overview

## Current progress

### editor_app
Implemented now:
- local starter note workspace on first run
- note list, metadata edit, import/export widgets from the learner flow
- 3 editor modes already wired in the old codebase (`P`, `G`, `B`)
- sidebar shows note categories (courses) instead of module navigation; no "Wide layout" subtitle
- compact view uses a three-dot menu button in the app bar instead of a bottom NavigationBar
- reduced settings surface (no section numbering):
  - Login and sync (includes user profile: avatar, username, email, motto, social link when authenticated)
  - Editor preferences (editor mode, theme, API base URL)
  - Configuration (config file download, maintenance actions, recycle bin)
  - Debug log (simplified: only recent UI logs with copy button, no verbose API debug card)
- stale modules removed: `front.dart`, `course.dart`, `activity.dart` — only `learner.dart` and `settings.dart` remain
- large files split: learner into `learner.dart` + `note_editor.dart` + `note_metadata.dart`; settings auth dialogs into `components/auth_dialogs.dart`
- `onDownloadConfig` callback added to `_SettingsPage` for env config file export

Still to deepen:
- stronger independent sync semantics and conflict UX
- `app_shell.dart` (2481 lines) and `client.dart` (812 lines) remain over 500-line target — app_shell is a single stateful class and client is an interface+implementation pair; splitting further requires mixin-based refactor

### planner_app
Implemented now:
- local starter planning workspace on first run
- local course + module discussion seed notes
- local planner events for signed-out use
- activity view usable offline when local planner data exists
- reduced settings surface (no section numbering):
  - Login and sync
  - Planner preferences (theme, deadline weights, API base URL)
  - Debug log (simplified: only recent UI logs with copy button, no verbose API debug card)
- deadline ordering weights stored locally (`deadline_time_weight`, `deadline_importance_weight`)

Still to deepen:
- richer calendar behaviors
- stronger online discussion-board integration
- more detailed module/event editing workflows beyond the new planner home and offline starter state

### portal_app
Implemented now:
- router-shell direction (choice B)
- launch surfaces for editor/planner
- minimal settings/orchestration role
- settings debug log simplified (removed verbose API debug card and Stats section, kept only recent UI logs with copy button)

Still to deepen:
- embed or route into new app-specific surfaces more intentionally
- keep broad monolith internals from leaking back in

## Development rules

1. Do not treat a green build as sufficient. Check the deployed behavior too.
2. Prefer app-specific behavior over copying more of the monolith.
3. If reusing monolith widgets, trim them into the app’s own purpose.
4. Keep offline-first behavior working in `editor_app` and `planner_app`.
5. Keep `portal_app` as orchestration shell, not integrated duplicate.
6. Update `LLM_CHECK.md` when architectural or deployment assumptions change.
7. Re-run local `flutter test` and `flutter build web --no-web-resources-cdn` before pushing.

## Standard verification

From `frontend/`:

```bash
for app in editor_app planner_app portal_app; do
  (cd "$app" && flutter test test/smoke_test.dart -r compact)
  (cd "$app" && flutter build web --release --base-href "/${app%_app}/" --no-web-resources-cdn)
done
```

## Design intent reminders

- Editor app owns note-taking and syncable drafts.
- Planner app treats course as calendar object, module as event/discussion unit, and activity as deadline tracker.
- Portal app should later compose the other two rather than replace them.
