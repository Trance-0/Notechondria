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

## Bugs

- [ ] Replicate the 0.1.20 editor_app bug fixes (invalid-token
  session-clear + bind-without-token short-circuit) into planner_app
  and portal_app. Their `app_shell.dart` files inline the same flow
  as editor's but were not touched this round.

- [ ] **Note share / deep-link redirect failure.** User-reported: the
  note-share URL doesn't resolve when opened in a fresh tab.
  Investigation path (`editor_app/lib/app_shell.dart`):
  `_parseNoteUuidFromUrl` reads the fragment after `#`; `_bootstrapApp`
  calls `_openNoteByUuid` AFTER `_loadInitialData`. Possible causes:
  (a) the URL fragment regex is case-insensitive but may not match
  when the shared link carries a trailing slash or query string;
  (b) `_handleOAuthCallback` already does `browserReplaceState` and
  strips the fragment when handling `?code=` / `?state=` — check if
  it's stripping the note fragment before the deep-link parser runs;
  (c) for a private note opened without a session, the UUID endpoint
  returns 403 but the error message is just stuffed into
  `_errorMessage` without a clear "sign in to view" prompt.
  Add a regression test that exercises
  `https://host/#/notes/<uuid>` cold-start with and without session.

- [ ] **Category ownership UI mismatch.** Backend's
  `DELETE /courses/<id>/` correctly returns 403 for non-owners
  (`backend/notes/api.py:690`). The editor sidebar calls
  `_deleteCategory` unconditionally and surfaces the 403 as a raw
  error. Fix: when `course['is_owned'] == false`, the sidebar
  long-press / right-click menu should show **Unsubscribe** (calls
  `DELETE /courses/<id>/subscription/`) instead of **Delete**. The
  existing `_promptEditCategory` → `_EditCategoryDialog` action list
  needs a third branch. Backend already supports both paths:
  `CourseSubscribeApiView` for subscribe/unsubscribe,
  `CourseDetailApiView` for owner delete. Local courses (negative
  id) keep the current delete semantics.

## Global reusable components

### Start up animations

- [ ] Completing: mobile view cross-fade gap. On narrow layouts the
  incoming metabolite skeletal formula currently fades in only after
  the previous one has already faded out, producing a perceptible
  blank moment. Spec: neither formula should fully fade away between
  steps — the new one must start emerging before the old one has
  fully receded. Tune cross-fade overlap in `_drawSkeletalFormula`
  step-boundary logic (`_KrebsCyclePainter.paint`).

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

### App preferences

- [ ] **Offline-mode toggle** in the shared `AppPreferencesCard`
  (`frontend/notechondria_shared/lib/src/settings/app_preferences_card.dart`)
  so it shows up in all three apps. A single boolean `offline_mode`
  persisted into `_LocalAppStore._settingsKey`
  (`local_settings['offline_mode']`). When enabled:
  - `_bootstrapApp` skips the remote front-page / courses / notes
    fetches in `_loadInitialData` and immediately renders from
    `_localCache`. Target: reduce first-paint time to < 500 ms.
  - Public-notes list fetching in `_LearnerPage` switches to lazy:
    pulled only when the user explicitly taps a "Load public notes"
    button. Signed-in personal notes are still pulled on demand
    when the user selects them.
  - Category auto-sync from cloud is gated: `_loadInitialData`
    continues to hit `/courses/` only if `offline_mode` is false or
    the user is currently authenticated.
  - The debug log emits `Editor.Sync.Settings/offline_mode` on
    toggle with the consequence / cause shape.
  - Touches: shared `AppPreferencesCard` (new toggle row),
    `_LocalAppStore.defaultSettings()` to seed `false`, all three
    `_bootstrapApp` / `_loadInitialData` to respect the flag.

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

- [ ] Move the editor-mode selector out of the top bar and into the
  "..." (details) menu button. Clicking "..." should show a dropdown
  with two options: **Edit note meta** (current details behavior)
  and **Switch editor** (small picker: `P` plain text, `G` live
  markdown). Remove the top-bar dropdown completely and widen the
  title field. Touches `editor_app/lib/modules/note_editor.dart`
  and the inlined editors in planner/portal
  `modules/learner.dart`.

- [ ] **Attachment CDN rework** (user-reported). Current behavior
  writes base64 data URIs inline and queues raw bytes in
  `metadata_json['queued_attachments']` as base64. Spec:
  - **Local first.** On pick, write the file bytes to app-local
    storage under `attachments/<note-uuid>/<safe-filename>` and
    embed a `local://<note-uuid>/<safe-filename>` URL into the
    markdown. Preview widget (flutter_markdown) renders
    `local://` via a custom image builder that reads the bytes
    from that storage.
  - **No base64 in markdown body.** Keep only a compact pointer.
  - **Storage backend:**
    - Web: IndexedDB (via `idb_shim` or hand-rolled). 20 MB per
      attachment stays, but add a total-budget check (~200 MB)
      because browsers evict heavy origins.
    - Native: `path_provider` `getApplicationSupportDirectory`.
    - A shared `LocalAttachmentStore` helper in
      `notechondria_shared/lib/src/utils/local_attachment_store.dart`
      hides the platform split.
  - **Upload on sync.** `_promoteQueuedAttachments` reads the
    local file (no more base64 decode step) and streams it through
    `client.uploadNoteAttachment`. On success, rewrite the markdown
    from `local://...` to the CDN URL and delete the local blob.
  - **Preview from attachments list.** Add an "Attachments" section
    under the editor toolbar listing every embedded attachment
    (local + remote) with filename, size, a preview thumbnail for
    images, and a delete button. Today there's no such list at
    all.
  - **Filename sanitization** — the same rules as
    `local_archive.dart::_sanitize`: slashes → `_`, control bytes
    stripped, deterministic `-<index>` on collision.
  - **Migration shim.** Existing drafts carry base64 in
    `metadata_json['queued_attachments']`. On load, migrate each
    such entry to the local file store one-time and rewrite the
    body references.
  - Split into at least three commits: (1) shared
    `LocalAttachmentStore` + migration shim + tests;
    (2) editor wiring (upload flow, preview list, sync promotion);
    (3) planner + portal.

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

- [ ] I noticed that some data structure is not split cleanly by
  their function, e.g. The course should have a independent app
  folder for easy management.

- [ ] **Attachment CDN server-side.** Currently uploads go to a
  single path. Consider keying by `note.uuid` at the URL level
  (`/notes/<uuid>/attachments/<filename>`) so the frontend can
  invalidate / sync without passing integer ids. Align with the
  frontend `local://<note-uuid>/<safe-filename>` scheme in the
  attachment-CDN rework above.

### MCP

## Documentation pages
