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

## Editor

### Note view

- [ ] Allow user to delete local category (except inbox) when no login. Do not sync anything, if they login, always pull, then merge.

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
