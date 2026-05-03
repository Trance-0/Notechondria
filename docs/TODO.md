# TODO

Pending version: 0.1

Here is a list of task we need to do now after testing, finishing and solve these bugs in order, and check the item from the list when you are done, ignore the checked items. The following is the list you need to follow:

1. If certain functionality in frontend involves changes in backend, add the backend function in the corresponding module and test them before implementing them in frontend, provide options for hard to implement features.
2. For testing backend, check render-mcp, the api key and database credentials is in the local `sample.test.env`, or `sample.render.env` file.
3. You may Add items to the TODO if
   - You find additional features that I described to you but is not implemented to keep them on track and let me know you get to it.
   - A big task that needs to be decomposed into smaller tasks, and test on each steps.
4. For the bug you fixed on this round, create a new `<Pending-version>.<inc-numeral>.md` in `./docs/` versions, move your finished item (delete the completed item in this file) to this new file, follow the templated defined in previous files.
5. For new features, deleted features, include the detailed descriptions update in `./docs/`
6. **Versioning rule:** On each update, increment the third digit in `./VERSION` (e.g. `0.1.8` -> `0.1.9`). The first two digits (`0.1`) are controlled by humans only — never change them. The `VERSION` file is read by `prepare_env.sh` to tag Docker images as `v<VERSION>.<BUILD_NUMBER>`.
7. Let me know any environment variables need to be updated. After all edits are done, check every test passed. COMMIT and I will push after check.
8. Always finish `**Urgent**` tasks first if exists.
9. PAUSE WHEN CREDIT LIMIT RUNS OUT BEFORE CONTINUE THE NEXT TASK

Completed rounds live in `./docs/versions/<semver>.md` — do **not**
restate them here. When a task is landed, delete its entry from this
file and add a round-log entry to the new version doc.

- [x] **Cross-app shared mixins — 8 of 8 COMPLETE.** 0.1.52
  codified the 1000-LOC ceiling in AGENTS.md §1.5; 0.1.53–0.1.61
  brought every file in the three apps under the cap and shipped
  the first three shared mixins out of
  `notechondria_shared/lib/src/app_shell/`: `AppShellLogMixin`,
  `AppShellAuthActionsMixin`, `AppShellOAuthMixin` (plus the
  shared `AuthClient` interface and `url_strategy` shim).
  0.1.78 added `AppShellLocalPersistMixin`; 0.1.79 added
  `AppShellCourseHelpersMixin`; 0.1.80 added
  `AppShellDraftHelpersMixin`; 0.1.81 added
  `HttpClientInternalsMixin`; 0.1.82 added
  `AppShellSessionMixin`. All eight mixins shipped — the
  byte-identical chunks that used to live three times in
  per-app `_AppShellState` files now live once in
  `notechondria_shared`. See round-logs 0.1.78–0.1.82 for
  per-mixin details.

## Global reusable components

### Start up animations

### Sidebar/Navigation

### Login and account info

- [x] **Full feature parity with editor Settings in portal.** 0.1.87.
  API key section, password-change dialog, email-change dialog,
  config file export/import.

- [x] **Note cover images — planner / portal frontend.** 0.1.86.

- [x] **Multi-device session manager — planner / portal frontend.**
  0.1.86.

- [ ] **Two-factor auth for password login.** Tracked separately
  because it needs a new backend flow plus UI. Scope:
  - Backend: on password login (NOT OAuth — skip 2FA there by
    design), challenge the user with one of two second-factor
    paths:
    1. **Trusted-device approval.** Send a push-style prompt to
       the user's first-registered session (the one created during
       the original email-verify flow). Requires the user to have
       completed email verification during that first sign-up so
       we know the device is genuine.
    2. **Email code.** Same 6-digit flow as the existing
       `/api/v1/auth/resend-verification/` / `VerificationCode`
       helpers — just re-purposed for login confirmation.
  - New endpoints: `POST /api/v1/auth/2fa/challenge/` and
    `POST /api/v1/auth/2fa/verify/`.
  - `LoginApiView` needs a two-step variant: first call returns
    `{pending_2fa: true, challenge_id, channels: [...]}` instead
    of a token. Second call submits the code / approval id and
    returns the full `auth_payload`.
  - Settings UI for choosing / revoking trusted devices (can share
    the sessions card if trusted-device is modelled as a flag on
    Session).

### App preferences

- [x] **Offline-mode — secondary fetch gates — 0.1.89.** "Load public notes"
  button added to all three `_LearnerPage` widgets when `offlineMode` is true
  and notes are empty. Category auto-sync guard added to all three
  `_loadInitialData` methods: authenticated offline-mode users still fetch
  courses so the sidebar category list stays current.

- [x] **Per-app OAuth redirect URI — 0.1.90.** Backend now matches request
  Origin/Referer against `GOOGLE_AUTHORIZED_REDIRECT_URIS` /
  `GITHUB_AUTHORIZED_REDIRECT_URIS` so portal/planner sign-in lands back on
  the calling app instead of the editor. Single-value env vars stay as a
  fallback.

- [x] **MCP skill.md editor (editor_app only) — 0.1.90.** New
  `_McpSkillSection` in editor settings → API settings; persists via
  `Creator.mcp_skill_md` and is surfaced as the MCP `initialize`
  `instructions` field. Portal/planner parity tracked below.

- [x] **Custom note meta variables (editor_app only) — 0.1.90.** Expandable
  list of `(key, value)` pairs in `_NoteMetadataDialog`, persisted on new
  `Note.custom_meta` column and round-tripped to YAML frontmatter on the
  GitHub-sync export. Portal/planner parity tracked below.

- [x] **Experimental GitHub Sync — backend export pipeline + UI shell —
  0.1.90.** New `creators.GithubIntegration` model + `creators.services.
  github_sync` materialize/push helpers + `/api/v1/integrations/github/*`
  endpoints. Frontend has a disabled "Connect to GitHub" card pointing at
  `docs/integrations/github-sync.md`. JWT signing + repo-picker still open
  (see below).

- [x] **Settings UI parity (MCP skill + GitHub Sync) — portal_app and
  planner_app — 0.1.91.** Shared `McpSkillSection` /
  `GithubSyncExperimentalCard` extracted into `notechondria_shared`
  and mounted in portal's Security card and planner's Login&sync
  card. Editor switched to the shared widget too. App-shell wiring
  for `onSaveMcpSkill` added in both apps.

- [x] **Custom-meta expandable list — portal/planner note dialogs —
  0.1.92.** New shared `CustomMetaController` + `CustomMetaListEditor`
  in `notechondria_shared/lib/src/components/`. Editor migrated off
  its private copy; portal and planner `_NoteMetadataDialog`s now mount
  the same widget and their `learner_note_editor.dart` save payload
  strips `custom_meta` from `metadata_json` and sends it on its own
  field. Docs (root `README.md`, `docs/readme.md`,
  `docs/deployment/{deploy,render_free_tier,northflank}.md`) updated
  with the per-app OAuth allow-list and GitHub data-sync env-var
  guidance.

- [x] **Experimental GitHub Sync — wire the actual push path — 0.1.93.**
  - JWT signer landed: `PyJWT>=2.8` + `cryptography>=42` shipped in
    `backend/requirements{,-render}.txt`; `_refresh_installation_token`
    signs the App JWT, exchanges it for an installation token, and
    persists `access_token` + expiry on `GithubIntegration`.
  - Repo-picker UI landed: `GithubSyncExperimentalCard` is now
    stateful with three states (no-callbacks / disconnected /
    connected), reads `/installation/repositories` via the new
    `GET /api/v1/integrations/github/repos/`, and persists the
    chosen repo via the existing callback endpoint.
  - Restore CLI landed at `backend/scripts/github_sync_restore.py`
    (stdlib-only; supports `--dry-run` + `--verbose`; idempotent
    via `client_draft_id`).
  - **Static-asset re-bundling — landed 0.1.94.** Push side gains
    `include_assets=true` toggle on the card and on
    `POST /api/v1/integrations/github/push/`; per-file (50 MB) +
    per-push (200 MB) caps; oversized files recorded in
    `manifest.skipped_assets`. Restore CLI gains `--include-assets`
    and re-uploads through the existing multipart endpoints.
  - **Push-side conflict resolution** still open — Contents API
    PUTs overwrite the remote blob; multi-device edits between
    syncs can lose changes. Next round: fetch-diff-warn before
    overwrite.
  - **Asset rotation / pruning** still open — orphan asset paths
    accumulate as notes are deleted; needs a `--prune-orphans` mode
    that walks the Trees API and removes unreferenced
    `assets/notes/<uuid>/` subtrees in the same commit.

### Debug log window

- [ ] Extend per-request timing instrumentation beyond editor_app's
  bootstrap path: planner_app and portal_app still emit mostly
  Info-level messages without `durationMs`. Adopt `_timed(...)`
  wrappers on their bootstrap calls when that code stabilizes.
- [ ] Migrate remaining `_appendUiLog(String)` callback-routed
  entries (via `onLogEvent: _appendUiLog` in module part-files) to
  carry a structured `source` slot so the debug log card's filter
  chip row surfaces them by module. Currently they land as
  Info-level with empty source. Requires threading a richer
  callback type (e.g. `void Function({String source, DebugLogLevel
  level, String message})`) through the learner + note editor
  widgets.

## Editor

### Note view

- [ ] Cloud category "subscribe but keep private" — a user can save
  a reference to a cloud course as one of their local categories
  without republishing it. Needs a new client method + backend
  endpoint (`Backend.Notes.Courses/subscribe_private`) plus a
  sidebar action. Decompose: (a) design subscription data model
  (extend `CourseSubscription` with a visibility flag),
  (b) backend endpoint + tests, (c) frontend wiring.

### Note editor

- [x] **Editor overflow menu already available in planner/portal.**
  Both apps use `_NoteEditorDialog` from `editor_app/lib/modules/note_editor.dart`
  which already ships the PopupMenuButton (Edit note meta / Switch
  editor / View attachments). No additional porting needed.

- [x] **Attachment CDN — remaining deferred items — 0.1.88.**
  IndexedDB web backend replaced the in-memory stub
  (`_WebLocalAttachmentBackend` now uses `idb_shim`-backed
  IndexedDB). Storage-budget UI surface added: `formatBytes` utility
  shared across apps, `_AttachmentStorageTile` widget in editor
  settings showing total bytes + 500 MB warning.

- [x] **Attachment CDN server-side — 0.1.88.**
  `note_attachment_path` now keys by `note.uuid.hex` instead of
  integer `note.id`. New UUID-keyed API endpoints at
  `/notes/uuid/<uuid>/attachments/` for list/upload/delete.
  Backward-compatible with existing integer-keyed endpoints.
  Backend tests cover list, upload, delete, permissions, size caps.

### Editor Settings

- [x] **Planner export/import — 0.1.89.** New `core/local_archive_io.dart`
  wired with `plannerEvents` / `calendarFeeds` / `activityWeek` buckets.
  Portal export/import was already done in 0.1.87.

- [x] **Cross-app export round-trip tests — 0.1.89.** Three new tests in
  `notechondria_shared/test/local_archive_test.dart` covering planner→editor,
  editor→planner, and portal→planner round-trips.

## Planner

- [ ] Planner starter workspace currently seeds a single "Starter
  planning course" + two planning drafts on first run
  (`planner_app/lib/app_shell.dart` `_ensureStarterWorkspace`).
  Decide whether planner should have an analogous
  "Inbox / scratchpad" category instead of a premade course — or
  whether the planning-course semantics make a non-Inbox default
  the right default. Changing planner's starter default is a UX
  break, so gather feedback before touching.

## Backend

### MCP

## Release / CI

- [ ] **Editor + planner GitHub Release workflows.** 0.1.68
  documented the existing `portal-release.yml` workflow in
  [`docs/deployment/release.md`](deployment/release.md). The
  same shape is needed for `editor_app` and `planner_app`.
  Decide tag namespacing before duplicating: a plain `v0.1.68`
  push would fire all three workflows and they'd race to
  publish/update the same GitHub Release. Proposals:
  - `ve0.1.68` → editor, `vp0.1.68` → planner, `v0.1.68` →
    portal. Each workflow filters on its own tag prefix.
  - OR fold all three into a single `frontend-release.yml`
    with a per-app matrix leg and a single publish job at the
    end (attaches all 18 archives to one release). Cleaner
    artefact discovery, harder matrix.
  - Windows code signing is still open — see
    [release.md #not yet automated](deployment/release.md#not-yet-automated).

## Documentation pages
