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

## Global reusable components

### Login and account info

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

### Editor Settings

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

### GitHub Sync

- [ ] **Push-side conflict resolution.** The Contents API PUTs in
  `creators.services.github_sync.commit_and_push` overwrite the
  remote blob unconditionally. A user editing on two devices
  between syncs can lose changes. Fetch the existing blob on each
  path, diff against the materialized payload, and surface a
  "remote changed — overwrite or merge?" prompt before writing.
  Lifted from the 0.1.94 carryover.
- [ ] **Asset rotation / pruning.** Repeated `include_assets=true`
  pushes accumulate orphan files for notes deleted client-side
  whose old `assets/notes/<uuid>/` paths still live in the remote
  tree. Add a `--prune-orphans` mode on the push pipeline that
  walks the Trees API and removes unreferenced subtrees in the
  same commit. Lifted from the 0.1.94 carryover.

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
