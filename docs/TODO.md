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

- [ ] **File-size rule + cross-app sharing.** 0.1.52 codified the
  1000-LOC hard ceiling in AGENTS.md §1.5 and carved the recycle-bin
  code out of each `app_shell.dart` into a `core/local_trash.dart`
  partial. 0.1.53 brought every file in `frontend/editor_app/lib/`
  under the cap (app_shell.dart 5000 → 552) via 23 per-concern
  extensions on `_AppShellState`. Remaining work below is **not just
  another per-app repeat** — audit showed 63+ methods in
  `{planner,portal}_app/lib/app_shell.dart` are byte-identical to
  editor's, so the next pass promotes shared code up into
  `notechondria_shared` rather than copy-pasting. Plan:

  1. **Shared State mixins in `notechondria_shared/lib/src/app_shell/`.**
     Mixin on `State<StatefulWidget>` with abstract getters for the
     handful of fields each concern needs. Order of extraction
     (from most-independent to most-coupled):
     - `AppShellLogMixin` — `uiLogs`, `logController`, `log`,
       `appendUiLog`, `timed<T>`, `refreshState`, `showMessage`.
     - `AppShellAuthActionsMixin` — `register`, `verify`,
       `resendVerification`, `login`, `requestPasswordReset`,
       `confirmPasswordReset`. Abstract getter `logAppTag` provides
       the `Editor./Planner./Portal.` log-source prefix.
     - `AppShellOAuthMixin` — `launchOAuth`, `handleOAuthCallback`.
     - `AppShellSessionMixin` — `applyAuthPayload`, `logout`.
     - `AppShellLocalPersistMixin` — `_persistLocal*` helpers.
     - `AppShellDraftHelpersMixin` — `storeLocalDraft`,
       `buildOfflineFallbackDraft`.
     - `AppShellCourseHelpersMixin` — `isLocalCourse`,
       `decorateRemoteCourse`, `chooseDefaultCourse`.
     - `HttpClientInternalsMixin` on `HttpNotechondriaClient` — the
       `_send` / `_decode` / `_headers` / `_shapedErrorMessage` stack.

  2. **Migrate editor_app to consume the shared mixins** (per mixin
     as they land — keeps CI green throughout). Verify the smoke
     test still passes after each mixin is absorbed. Delete the
     now-redundant per-app extension files.

  3. **Bring planner_app + portal_app online** by replacing their
     inline methods with `with SharedMixinX<W>`. Each app then
     provides only its app-specific `_loadInitialData` orchestration,
     `_bootstrapApp`, and `build()`. Tests per app should still pass.

  4. **Residual per-app work** (splits that can't share):
     - `{planner,portal}_app/lib/modules/learner.dart` (~1645, ~1504)
       — inlined note editor is the extraction candidate; shape is
       app-specific so this stays per-app.
     - `{planner,portal}_app/lib/modules/activity.dart` (~1438, ~1126)
       — planner-only calendar UI, extract sub-widgets.

  **Shared dependencies added to `notechondria_shared/pubspec.yaml`:**
  `shared_preferences`, `http`, `file_selector` (previously only
  `archive` + `path_provider`). These were already transitive deps
  of every app anyway.

## Bugs

- [ ] Add a regression test for the note-share deep-link path
  (`https://host/#/notes/<uuid>` cold-start with and without
  session, and the OAuth-callback-preserves-fragment case). The
  code fix landed in 0.1.67; the test was deferred because the
  editor smoke-test harness doesn't have a web navigator shim yet.

## Global reusable components

### Start up animations

### Sidebar/Navigation

- [ ] Sync the editor sidebar for the portal sidebar. (Removing
  title, `wide layout` texts. You may create a list of items/widgets
  that feed into the `sidebar` class, the `sidebar` should have some
  properties/functions like `header text` (used in vertical layout),
  `lower left item` (the `new category` trigger should lives in
  that))

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

- [ ] **Multi-device session manager — frontend UI (3 apps).**
  Backend shipped in 0.1.65; `listSessions` and `revokeSession`
  HTTP client methods shipped in 0.1.67 (shared `AuthClient`
  interface plus per-app `HttpNotechondriaClient` implementations).
  Still to do:
  - Active Sessions card in the Settings surface (device label,
    "last seen …", created-at, revoke button, "This device" badge
    on the current session).
  - Multi-device warning banner in all three apps whenever
    `auth_payload` or `session` responses include
    `multi_device: true` — link the banner to the new sessions
    card so the user can audit and revoke.
  - Wire all three apps to call `listSessions` on Settings-open
    and refresh after revoke.

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

## Documentation pages
