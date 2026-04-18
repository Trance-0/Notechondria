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

## Bugs

- [ ] Replicate the 0.1.20 editor_app bug fixes (invalid-token
  session-clear + bind-without-token short-circuit) into planner_app
  and portal_app. Their `app_shell.dart` files inline the same flow
  as editor's but were not touched this round.

## Global reusable components

- [x] **Urgent**: Shared UI extracted into `frontend/notechondria_shared/`
  in 0.1.21. Single source of truth for `SidebarItem` +
  `ConfirmWithDelayDialog`, `ApiDebugCard` + `ApiDebugSummary`,
  `ErrorStateView`, `SplashScreen`, the auth-dialog stack
  (`AuthHub`, `RegistrationWizard`, `EmailPasswordDialog`,
  `EmailCodeDialog`, `PasswordResetDialog`, `FeedbackText`), and
  `AppPreferencesCard`. Cross-cutting models/utilities (`ActionFeedback`,
  `ApiDebugSnapshot`, `showBlurDialog`, `formatCompactTimestamp`)
  moved with them. Each app consumes the shared package via
  `path: ../notechondria_shared` and imports the barrel once at
  `lib/main.dart`.

### Start up animations

- [ ] Completing: mobile view cross-fade gap. On narrow layouts the
  incoming metabolite skeletal formula currently fades in only after the
  previous one has already faded out, producing a perceptible blank
  moment. Spec: neither formula should fully fade away between steps —
  the new one must start emerging before the old one has fully receded,
  so there is always at least one visible structure. Tune cross-fade
  overlap in `_drawSkeletalFormula` step-boundary logic
  (`_KrebsCyclePainter.paint`) rather than only the outgoing alpha curve.
- [ ] Background particles are currently anchored to the circle's radius
  (`radiusFraction` × cycle radius) which keeps them visually inside the
  ring. Spec: let them drift across the full screen (use screen-space
  positions, seed from rng, bounce or wrap at viewport edges). The cycle
  ring itself stays in place; only the tiny accompanying molecules move
  freely.
- [ ] Add the configured backend domain name after the version string in
  the splash bottom-left. Shape: `v0.1.x · notechondria.render.com`
  when `api_base_url` is set, or `v0.1.x · offline` when empty.
  `SplashScreen` takes a new optional `apiBaseUrl` parameter sourced
  from each app_shell's `_localSettings['api_base_url']`.

### Sidebar/Navigation

- [ ] Sync the editor sidebar for the portal sidebar. (Removing title, `wide layout` texts. You may create a list of items/widgets that feed into the `sidebar` class, the `sidebar` should have some properties/functions like `header text` (used in vertical layout), `lower left item` (the `new category` trigger should lives in that))

### Login and account info

- [ ] Full feature parity with editor Settings: API key section (with rotate
  button and MCP endpoint helper), password-change dialog with identity code
  verification, email-change dialog, config file download. As of 0.1.18 the
  Settings module is visible in portal's sidebar and covers the basic
  account/preferences/sync surfaces, but the v0.1.17 editor-only additions
  still need to be ported into `portal_app/lib/modules/settings.dart` — this
  requires syncing client methods, app_shell callback wiring, and the
  `_ApiKeySection` widget.

### App preferences

### Debug log window

- [ ] Extend per-request timing instrumentation beyond editor_app's
  bootstrap path: planner_app and portal_app still emit mostly Info-level
  messages without `durationMs`. Adopt `_timed(...)` wrappers on their
  bootstrap calls when that code stabilizes.
- [ ] Migrate remaining `_appendUiLog(String)` callers to the richer
  `_log({level, source, message})` form so `source` reflects the actual
  emitting class/method. Current wrapper still records them at Info level
  with an empty source, which reads as `-` in the log row.

### §1.7 message-compliance migration (canonical AGENTS.md §1.7)

The canonical AGENTS.md §1.7 now requires every error/warning/info
message (frontend and backend) to contain three components:
consequence + `<module>/<process>` + cause. The shape is
`"<consequence>: <module>/<process> \u2014 <cause>"`. The canonical
module names for this project are documented in
[docs/AGENTS.md](./AGENTS.md).

**Preserved parser sentinels** (must survive verbatim in any rewrite):

- `invalid token`, `authentication credentials were not provided`,
  `token_not_valid` \u2014 consumed by editor `_loadInitialData`
  session-rejection detector.
- `not_registered`, `No account found` \u2014 OAuth registration prompt
  in editor/planner/portal `_handleOAuthCallback`.
- `bind` \u2014 backend binding-rejection detail, asserted by
  `backend/creators/tests.py`.

Decompose by module so each round produces a reviewable diff. Order:

- [x] OAuth launch + callback messages in editor_app (done in the 0.1.25
  pass, see `docs/versions/0.1.25.md`). Remaining OAuth sites in
  planner/portal still need the same treatment.
- [x] `Editor.Auth` round: editor_app `_register` / `_verify` /
  `_resendVerification` / `_login` / `_requestPasswordReset` /
  `_confirmPasswordReset` / `_applyAuthPayload` / `_logout` migrated in
  0.1.26. Legacy `_appendUiLog` wrapper kept for call-site compatibility
  but primary error/info surfaces now use the full shape.
- [x] `Planner.Auth` and `Portal.Auth` rounds (0.1.27): same method
  surface migrated in both apps. OAuth launch + callback + bind failure
  paths now emit `Planner.Auth/*` / `Portal.Auth/*` sources. Preserved
  substring sentinels (`not_registered`, `No account found`) remain in
  the branch selector and in the log message body so the
  registration-prompt branch still fires.
- [x] `Backend.Creators.Auth/bind.*` phased details (0.1.26): bind
  endpoints for Google and GitHub now emit per-phase `detail` strings
  covering `config_lookup`, `token_exchange`, `token_verify` / profile
  fetch, and `db_write`. Network errors on the Google/GitHub side
  return `502`; missing server OAuth config returns `503`. The public
  `bind` substring sentinel in `creators.tests` is unchanged.
- [x] `Shared.AuthDialog` round (0.1.31): invitation-validate and
  catch-all branches in `RegistrationWizard`; email-required validator
  in `EmailCodeDialog._resend`; client-side form validators in
  `_validateEmailForm`; password-match check in the reset-confirm
  action of `PasswordResetDialog` all migrated.
- [x] `Editor.Sync.Courses` round (0.1.31): `_createCategory`,
  `_updateCategory`, `_deleteCategory`, `_reorderCategories`, and
  `_syncLocalCourse` in `editor_app/lib/app_shell.dart` rewritten to
  `Editor.Sync.Courses/{create,update,delete,reorder,push}` shape.
- [x] `Editor.Sync.Settings` round (0.1.32): `_updateSettings`
  save/no-change/save-locally/remote-fail paths + `_uploadAvatar`
  success/cancel/error paths migrated to
  `Editor.Sync.Settings/{save,avatar.upload}` sources.
- [x] `Editor.Sync.Notes` round (0.1.32): `_pullCloudNotesToLocal`
  (missing-session, cancel, success, error), `_syncLocalDraft`
  (missing-session guard + cloud-copy and fresh-create success logs),
  `_restoreDeletedNote`, `_emptyDeletedNotes`, and `_syncAllLocalData`
  (all top-level sync entrypoint messages) migrated to
  `Editor.Sync.Notes/{pull,push,push_all,restore,empty_trash}` sources.
- [x] `Editor.LocalStore` round (0.1.33): `_ensureStarterWorkspace`,
  `_clearLocalData`, `_restoreTemplateCourses`, `_copyFrontendLogs`,
  `_downloadConfigFile`, and the ZIP-import per-entry skip log
  migrated. Sources:
  `Editor.LocalStore/{seed_starter,clear,restore_templates,copy_logs,download_config,import_zip}`.
- [x] `Editor.UI` round (0.1.33): `_selectCourse`, `_selectNote`,
  `_startNoteSession` / `_finishNoteSession`, the learner-notes list
  load failure path, and the in-editor save/create offline-fallback
  toasts migrated. Sources include
  `Editor.UI/{open_course,open_note,note_session.start,note_session.finish}`
  and `Editor.Sync.Notes/{list,create,save,delete,delete_local}`
  (some UI actions escalated from `Editor.UI` to
  `Editor.Sync.Notes` when they actually drive sync work).
  No direct `_appendUiLog(String)` call sites remain in
  `editor_app/lib/app_shell.dart`; the thin wrapper stays for
  callback signatures (`onLogEvent: _appendUiLog`) that some
  part-files still call.
- [x] `Planner.*` round (0.1.34): every direct `_appendUiLog(String)`
  call site in `planner_app/lib/app_shell.dart` replaced with the
  structured `_log(...)` form. Migrated surfaces cover
  `Planner.LocalStore/{seed_starter,clear,clear_cache,copy_logs,restore_templates}`,
  `Planner.Sync.Settings/{save,avatar.upload}`,
  `Planner.Sync.Courses/{push,create_local,load,subscribe,unsubscribe}`,
  `Planner.Sync.Notes/{pull,push,create,save,save_local,delete,delete_local,restore,empty_trash,push_all,list}`,
  `Planner.Sync.Events/{create,create_local,toggle,toggle_local}`,
  `Planner.Sync.Calendar/{refresh,import,subscribe,toggle,delete}`,
  `Planner.Sync.Activity/load_week`, and
  `Planner.UI/{open_course,open_note,open_note_viewer,note_session.start,note_session.finish}`.
- [x] `Portal.*` round (0.1.35): every direct `_appendUiLog(String)`
  call site in `portal_app/lib/app_shell.dart` replaced with the
  structured `_log(...)` form. Migrated surfaces cover
  `Portal.LocalStore/{seed_starter,clear,clear_cache,copy_logs,restore_templates}`,
  `Portal.Sync.FrontPage/{bootstrap,pull}`,
  `Portal.Sync.Settings/{save,avatar.upload}`,
  `Portal.Sync.Courses/{push,create_local,load,subscribe,unsubscribe}`,
  `Portal.Sync.Notes/{pull,push,create,save,save_local,delete,delete_local,restore,restore_version,empty_trash,push_all,list}`,
  `Portal.Sync.Events/{create,toggle}`,
  `Portal.Sync.Calendar/{refresh,import,subscribe,toggle,delete}`,
  `Portal.Sync.Activity/load_week`, and
  `Portal.UI/{open_course,open_note,open_note_viewer,note_session.start,note_session.finish}`.
- [x] `Backend.Creators.Auth` + `Backend.Creators.Settings` round
  (0.1.29): every non-bind `serializers.ValidationError(...)` and the
  `Response({"detail": ...})` branches in the
  `ChangePasswordApiView.post` path migrated to
  `Backend.Creators.{Auth,Settings}/<process>` shape. Register /
  login / verify / resend_verification / password.reset.{request,confirm}
  / password.change / email.change.{request,confirm} / settings.update
  / oauth.register all covered. Preserved `bind` substring sentinel
  unchanged. 29 creators tests still pass.
- [x] `Backend.Notes.*` round (0.1.28): every `Response({"detail": ...})`
  and `serializers.ValidationError(...)` in `backend/notes/api.py`
  migrated to `Backend.Notes.{Courses,Notes,Blocks}/<process>` shape.
  Covers course CRUD (create/update/delete), note CRUD via id and UUID,
  block add/update/delete/reorder, note access check,
  history/snapshot/restore endpoints.
- [x] `Backend.Mcp.Protocol` round (0.1.30): auth, parse, sse_get,
  session.delete, tools.call, and dispatch branches in
  `backend/mcp/views.py` and `backend/mcp/protocol.py` rewritten.
- [x] `Backend.Gptutils` round (0.1.30): the `_AI_DISABLED_MESSAGE`
  pointer and the `ResizedImageValidator.validate` /
  `validate_user_name` raises in `backend/gptutils/forms.py` rewritten.
- [x] `Backend.Creators.forms` (0.1.30): the `RepassValidator`,
  `ResizedImageValidator`, `validate_user_name`, and
  `validate_registration_code` raises in `backend/creators/forms.py`
  rewritten. These serve the legacy Django form-based registration UI;
  the DRF path is covered by the 0.1.29 round.

Each round: rewrite, run `python manage.py test` (backend) or
`flutter analyze` + `flutter test test/smoke_test.dart` (frontend),
commit with `<module>: migrate messages to AGENTS.md \u00a71.7 shape`.
Do not bundle unrelated changes.

## Editor

### Note view

- [ ] Planner starter workspace currently seeds a single "Starter
  planning course" + two planning drafts on first run
  (`planner_app/lib/app_shell.dart` `_ensureStarterWorkspace`). For
  offline-first parity with the editor (which already seeds only an
  Inbox), review whether planner should have an analogous
  "Inbox / scratchpad" category instead of a premade course \u2014 or
  whether the planning-course semantics make a non-Inbox default the
  right default for planner. Decide before changing; changing planner's
  starter default is a UX break.
- [ ] Cloud category "subscribe but keep private" — a user can save a
  reference to a cloud course as one of their local categories without
  republishing it. Needs a new client method + backend endpoint
  (`Backend.Notes.Courses/subscribe`) plus a sidebar action. Decompose
  further before implementing: (a) design subscription data model,
  (b) backend endpoint + tests, (c) frontend wiring.

#### Search

### Note preview

### Note editor

#### Markdown Editor

##### Plaintext editor

##### Markdown editor

### Editor Settings

#### Editor Preferences

## Planner

### Lerner view

### Course view

#### Course detail

### Activity view

### Planner Settings

## Portal

### Front page

### Course

### Learner

### Activity

### Portal Settings

## Backend

- [ ] I noticed that some data structure is not split cleanly by their function, e.g. The course should have a independent app folder for easy management

### MCP

## Documentation pages
