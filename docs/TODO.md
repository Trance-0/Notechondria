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

## Bugs

- [ ] Add a regression test for the note-share deep-link path
  (`https://host/#/notes/<uuid>` cold-start with and without
  session, and the OAuth-callback-preserves-fragment case). The
  code fix landed in 0.1.67; the test was deferred because the
  editor smoke-test harness doesn't have a web navigator shim yet.

- [ ] **Audit login-form autocomplete attributes.** User reported
  Bitwarden failing to autofill on the editor's web login form
  (`autofill.service.ts:528 Did not autofill`). Stack trace is
  Bitwarden-internal so not a code-side bug, but it suggests our
  login fields may not be signalling autocomplete intent properly.
  Verify `autocomplete="username"` /
  `autocomplete="current-password"` on the relevant `<input>`s in
  `auth_dialogs.dart` and `auth_dialogs_wizard.dart`; if missing,
  add them so password managers have a clear hint.

## Global reusable components

### Start up animations

### Sidebar/Navigation

### Login and account info

- [ ] Full feature parity with editor Settings in portal: API key
  section (with rotate button and MCP endpoint helper),
  password-change dialog with identity code verification,
  email-change dialog, config file download. As of 0.1.18 the
  Settings module is visible in portal's sidebar and covers the
  basic account/preferences/sync surfaces, but the v0.1.17
  editor-only additions still need to be ported into
  `portal_app/lib/modules/settings.dart` — this requires syncing
  client methods, app_shell callback wiring, and the
  `_ApiKeySection` widget.

- [ ] **Note cover images — planner / portal frontend.** 0.1.76
  shipped per-note cover images for editor_app: backend model +
  migration + `/notes/<id>/cover/` POST/DELETE endpoint, shared
  `NoteCoverImage` widget in `notechondria_shared` (with theme-
  colored barcode fallback), and the editor's metadata dialog +
  note viewer wired up. planner_app and portal_app don't yet
  expose note metadata editing or a read-only viewer in the same
  shape, so the cover-image upload UI hasn't been ported. When
  those apps grow note edit/view surfaces, mirror the editor
  pattern: add `uploadNoteCoverImage` / `deleteNoteCoverImage` to
  their `NotechondriaClient` interface + http_client (~10 lines
  each, copy from editor), and pass the callbacks into wherever
  they construct the metadata dialog. The viewer side just needs
  `NoteCoverImage(seed: uuid, imageUrl: note['cover_image_url'])`
  above the body — already exported from `notechondria_shared`.

- [ ] **Multi-device session manager — planner / portal frontend.**
  0.1.65 shipped the backend; 0.1.75 wired the editor frontend
  (HTTP client methods on all three apps' `NotechondriaClient`,
  shared `ActiveSessionsCard` widget in `notechondria_shared`,
  `_PersonalInfoPage` / `_SignInSecurityPage` consumption,
  multi-device warning banner above the editor's Settings menu).
  Still to do on planner_app / portal_app: their Settings pages
  haven't been redesigned into the Apple-style sub-page layout
  yet (editor's 0.1.72 / 0.1.73 work hasn't been ported), so
  the `ActiveSessionsCard` doesn't have a natural home there.
  When the planner / portal Settings get sub-pages, drop the
  card into a "Sign in & security" sub-page and thread
  `onListSessions` / `onRevokeSession` / `onCurrentSessionRevoked`
  through `_AppShellState` exactly the way editor's
  `core/build_helpers.dart` already does. The HTTP client
  methods are already in place — only the UI plumbing remains.

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

- [ ] **Offline-mode — secondary fetch gates.** The coarse
  `_loadInitialData` gate landed in 0.1.46. The two finer-grained
  items from the original spec are still open: public-notes list
  in `_LearnerPage` should become an explicit "Load public notes"
  button when offline_mode is true, and category auto-sync from
  cloud needs an additional guard so the authenticated sync path
  still runs even when offline_mode is on.

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

- [ ] **Port editor overflow menu to planner/portal inline editors.**
  The note_editor.dart top-bar overflow menu (Edit note meta /
  Switch editor / View attachments) shipped in 0.1.46 for the
  editor app only. The inlined note editors in
  `planner_app/lib/modules/learner.dart` and
  `portal_app/lib/modules/learner.dart` still use the old layout
  and should adopt the same PopupMenuButton pattern for
  consistency.

- [ ] **Attachment CDN — remaining deferred items.** The frontend
  three-commit plan (shared store + editor wiring + planner/portal
  parity + attachments list) landed across 0.1.40 / 0.1.41 / 0.1.42.
  Still open:
  - IndexedDB web backend to replace the in-memory stub in
    `notechondria_shared/lib/src/local_attachment_store.dart`
    (`_WebLocalAttachmentBackend`) so attachments survive a tab
    refresh. Detailed spec in `docs/versions/0.1.42.md`.
  - Storage-budget UI surface: wire `LocalAttachmentStore.totalBytes()`
    into the debug log card + a settings "Storage" row with a
    "Clear unused local attachments" action. Detailed spec in
    `docs/versions/0.1.42.md`.

### Editor Settings

- [ ] **Planner + Portal export/import** — replicate the 0.1.38
  editor wiring in `planner_app/lib/app_shell.dart` +
  `planner_app/lib/modules/settings.dart` and the portal
  equivalents. Planner must add `plannerEvents` / `calendarFeeds` /
  `activityWeek` buckets to its `LocalArchiveInput`; portal must
  add `frontPage`. Both use the shared helpers so the format stays
  aligned.

- [ ] **Cross-app export round-trip tests** in
  `notechondria_shared/test/local_archive_test.dart`. The parser
  already returns empty defaults for missing optional files, so
  editor ↔ planner ↔ portal round-trips should succeed — add
  tests that assert a planner export imports into editor and vice
  versa without losing shared buckets or crashing on the
  app-specific ones.

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

- [ ] **Attachment CDN server-side.** Currently uploads go to a
  single path. Consider keying by `note.uuid` at the URL level
  (`/notes/<uuid>/attachments/<filename>`) so the frontend can
  invalidate / sync without passing integer ids. Align with the
  frontend `local://<note-uuid>/<safe-filename>` scheme in the
  attachment-CDN rework above.

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
