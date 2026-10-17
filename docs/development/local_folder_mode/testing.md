# Local folder storage mode: testing strategy

Part of the design in [`../local_folder_mode.md`](../local_folder_mode.md)
(section 8). Same conventions: repo-root-relative paths, `file:line` at
HEAD `48988a20` (VERSION 0.1.199), and section numbers that refer to the
main document unless they start with 8. Sections 2.8 to 2.10 and 7 are in
[`modes_and_migration.md`](modes_and_migration.md), 3.4 to 3.8 in
[`storage_rules.md`](storage_rules.md), and 6 in
[`security_and_tabs.md`](security_and_tabs.md).

## 8.1 Layers

1. Unit tests in `frontend/notechondria_shared/test/local_folder/`:
   codecs, router, journal crash and roll-forward tests including the
   replay external-edit check (3.4.1), two-transport concurrency tests
   (6.2), ID allocation and duplicate identities (3.7), trash semantics
   and the empty-trash cascade (3.5), course delete over notes, trashed
   notes, events, and feeds (3.5), snapshot pools (3.8), recurrence and
   search ports, archive bridge, the secret denylist in both directions
   (5), the per-device settings filter (F08), the detail-sentinel check
   (2.5), `decideStorageMode` over seeded `SharedPreferences` (2.8), the
   `opening` hold and the deadlines (2.9), and the `StorageModeClient`
   routing table (2.8). The shared package's tests
   are not run by CI (`docs/AGENTS.md`, round-end convention), so anything
   that must be CI-checked also appears in a smoke test.
2. Per-app smoke tests (CI), 8.5.
3. OPFS and Web Locks integration tests in Chromium (8.3), run in a
   Docker container with the Flutter SDK and Playwright's Chromium, on a
   host with at least 16 GB RAM, and not in GitHub CI unless the owner
   adds a job (Q13). They cover what only a browser can show: that the
   `locks.request` wrapper keeps the lock for the whole operation (2.5),
   and that a throwing void listener reaches the zone's error handler.
4. Manual checks on desktop Chrome (8.6).

## 8.2 Dart-side fake

`MemoryFolderFs implements FolderFs`, with injectable failures
(`NotAllowedError`, `NotFoundError`, abort mid-write, external edit with
a new `lastModified`), `revoke()` and `grant()` to simulate a lost and
restored permission, and crash points ("throw after the n-th write").
`MemoryFolderLocks` is the matching Web Locks double, with shared and
exclusive modes and abort timeouts, shared by several transports, and a
change channel double that can delay or drop messages.
`MemoryHandleStore` holds remembered handles, and `MemoryFolderPicker`
returns a preset `MemoryFolderFs` root or throws `AbortError`, standing
in for "Choose '<name>' again". `MemoryFolderPlatform` bundles these for
`LocalFolderController.forTest(app:, boot:, platform:)`, which is what
smoke tests pass as `NotechondriaApp(localFolder: ...)` (2.7). They are
exported from a separate library,
`package:notechondria_shared/local_folder_testing.dart`, so production
code never imports them. The fake sits at the `FolderFs` level because
`package:web` types are extension types and cannot be mocked by
implementing them (dart.dev package:web page). `MemoryFolderLocks` keeps
a lock for as long as the Dart operation runs, so it cannot show the
JavaScript return-value bug of 2.5; 8.3 covers that in Chromium.

## 8.3 OPFS stand-in and Web Locks tests in Chromium

- The test file is
  `frontend/notechondria_shared/test/local_folder_opfs_test.dart`. It
  lands in Phase 1 with the web `FolderFs` and the lock wrapper, gains
  attachment-byte tests in Phase 2 and archive-bridge tests in Phase 4,
  and runs from `frontend/notechondria_shared`.
- `const bool kLocalFolderOpfsTestHook = bool.fromEnvironment('NOTECHONDRIA_TEST_OPFS_FOLDER');`
  defaults to false. Only when it is true does the web `FolderFs` take its
  root from `navigator.storage.getDirectory()` (a per-test subdirectory)
  and report permissions as granted. Run with
  `flutter test --platform chrome --dart-define=NOTECHONDRIA_TEST_OPFS_FOLDER=true test/local_folder_opfs_test.dart`.
- Lock tests, over the real `navigator.locks` and the production
  `folder_lock_web.dart` wrapper:
  - two overlapping exclusive requests on one name, the first awaiting
    several timers (about 200 ms in total) before it returns: the second
    starts only after the first returns, and `navigator.locks.query()`
    taken during the first lists one `held` and one `pending` request;
  - an operation that throws: the caller receives the error, and a
    following request on the same name is granted at once, with nothing
    left in `query().held`;
  - two shared holds overlap, and an exclusive request waits for both;
  - a lock wait longer than its `AbortSignal.timeout` (shortened for the
    test) fails with the folder-lock message (6.2 R5);
  - a throwing `BroadcastChannel` listener reaches the zone's error
    handler.

  The first two fail if the grant callback is bound with a guarded
  (`void`) wrapper, so they are the regression test for 2.5.
- Where it runs: in a Docker container with the Flutter SDK (the version
  CI pins) and Playwright's Chromium, with `CHROME_EXECUTABLE` pointing at
  that Chromium. `docs/AGENTS.md` allows Flutter containers only on hosts
  with at least 16 GB RAM, so the run follows its host resource budget:
  measure `free -h` and `nproc` first, cap the container
  (`docker run --rm --memory=6g --cpus=2 ...`), wrap the test in
  `timeout 1200`, run one container at a time, and kill it after 5
  minutes without output. Fallback if it runs out of memory or hangs: run
  only the VM tests and the manual checks in 8.6, and say so in the
  round summary. GitHub CI does not run these tests unless the owner adds
  a Chrome job (Q13).
- Unreachable in production: the flag is a compile-time constant, and the
  release builds pass only `APP_VERSION`
  (`.github/workflows/frontend-pages.yml:63,73,83`,
  `.github/workflows/portal-release.yml:134-156`), so the compiler drops
  the branch. An optional CI guard greps each built `main.dart.js` for the
  hook's marker string (Q13).
- How OPFS handles answer `queryPermission` is **unverified** (U10); the
  hook does not depend on it.

## 8.4 Contract fixtures (drift control)

One sanitized backend response per (a) and (b) route lives in
`frontend/notechondria_shared/test/fixtures/api_v1/`, and a unit test
asserts that the local router returns the same keys and JSON types for
the same request.

- **Phase 1 fixtures are hand-written.** No host available to this work
  can run the backend: `docs/AGENTS.md` bans local containers below 16 GB
  RAM, and the host Python is 3.14 against 3.11-era pins. Each fixture is
  built from the serializer or payload helper that renders its route:
  `backend/notes/api.py` (`NoteSummarySerializer` `:344`,
  `NoteDetailSerializer` `:423`, `CourseSerializer` `:450`,
  `NoteVersionSerializer` `:573`, `CalendarFeedSerializer` `:631`),
  `backend/creators/api.py` (the settings representation at `:395-428`),
  and the payload helpers in `backend/notes/services.py` (for example
  `note_session_payload` `:367`). Each one is checked against the
  assertions in `backend/notes/tests.py` and `backend/creators/tests.py`.
  A `_source` key names the serializer and the backend test it was
  checked against; the comparison ignores keys that start with `_`.
- **Q14's backend test is the CI recorder.** `backend/notes/test_api_contract.py`
  runs in `backend-tests.yml` (`python manage.py test`). It seeds one
  creator's data, calls each fixture's route with the Django test client,
  and fails when a key or JSON type differs from the committed fixture.
  It also writes every live response under
  `backend/build/contract_responses/`, which an `actions/upload-artifact`
  step publishes, so a fixture can be refreshed from CI without a local
  backend. The fixture directory joins the workflow's `paths:` filter
  (`.github/workflows/backend-tests.yml:15-18`), so a fixture-only change
  runs the test.
- **Routes the backend does not have** (`GET /auth/session/`,
  `POST /auth/logout/`, Q17) get no recorder. Their shapes come from the
  client code that parses them. `_restoreSession` reads `authenticated`
  and passes the whole map to `applyAuthPayload` (editor
  `core/auth_flows.dart:174-177`, portal `core/bootstrap.dart:325-328`),
  which reads `token` and `user` (`app_shell_session_mixin.dart:181-182`).
  The session fixture is therefore `{"authenticated": true, "token":
  "<the request's token>", "user": {<the GET /settings/ profile keys>,
  "is_local_folder": true}}`. Logout's response is decoded and discarded
  (editor `core/http_client.dart:695-704`), so its fixture is `{}`.

## 8.5 Smoke-test checks

CI runs only `test/smoke_test.dart` per app
(`.github/workflows/frontend-pages.yml:59,69,79`). Each app adds
`test/local_folder_smoke.dart` with `registerLocalFolderSmokeTests()`,
called from `smoke_test.dart`'s `main`, so the CI file grows by two lines
(planner's is already 767 lines).

- **Harness.** Each folder-mode check boots
  `NotechondriaApp(localFolder: LocalFolderController.forTest(...))` over
  `MemoryFolderPlatform` (8.2) with no `client`, so the production
  default-client line runs (2.7). The whole test body, including
  `pumpWidget` and every `pump`, runs inside
  `http.runWithClient(body, () => recorder)` (package:http 1.6.0
  `client.dart:228`). `recorder` is a `BaseClient` that records every
  request and fails the test on any request outside the passthrough
  check below. The precedence check, which starts in cloud mode on
  purpose, uses the smoke tests' existing fake backend
  (`MockClient(backend.handle)`) as the zone client instead. `Client()` returns the zone's client first
  (`client.dart:42`), so the recorder is what `StorageModeClient`'s inner
  client, a multipart `request.send()` (`base_request.dart:141`), and a
  top-level `http.get` (`http.dart:168`) all receive: a missed multipart
  site or a stray `http.*` call fails the test instead of escaping it.
  package:http warns that Flutter does not guarantee which zone runs a
  callback (`client.dart:219-226`), so `setUp` also sets
  `HttpOverrides.global` to an override whose `createHttpClient` fails
  the test (restored in `tearDown`); a `dart:io` client created outside
  the zone fails too. Timing checks run on the test's fake clock.
- **Phases.** The editor file lands in Phase 1 with client-level checks
  (`HttpNotechondriaClient(httpClient: controller.httpClient)` built
  inside the same zone) and gains the app-level checks in Phase 2; the
  planner and portal files land in Phase 3.

- Editor: create a note and find `notes/<hex>.md` with frontmatter and a
  sidecar; edit, delete to `trash/notes/`, restore; upload an attachment
  and get an `nc-folder:` URL; take a snapshot; empty trash and find no
  `history/<hex>/` or `assets/notes/<hex>/` left.
- Planner: a weekly event yields occurrences in `/activity/week/`; an
  `.ics` import lands in `planner/feeds/`; an event created signed out,
  with a local course, is present after connect with the folder course
  ID; a second connect push leaves one copy (7.1).
- Portal: the front page renders from folder data; course reorder
  persists; a `.nchron` export has the v1 buckets and `folder/`; local
  events pushed at connect appear once.
- Planner and portal: a note whose body has
  `![x](nc-folder:///assets/notes/<hex>/attachments/a.png)` renders in the
  note viewer as an `Image` with a memory provider and without the
  "failed to load" text (3.6).
- All, revoked mid-session (2.8): open a note, call `memoryFs.revoke()`,
  then save the note (PATCH with content), upload an attachment
  (multipart), run `_loadInitialData`, apply settings (which calls
  `updateBaseUrl` with the cloud URL), run the version probe, and run
  `ping`. Assert that the recorder holds zero requests, that
  each failed request carried the `needsPermission` detail, that the save
  became a browser-local draft, and that the token is still the folder
  token (no session clearing). Repeat with the folder state forced to
  `needsPick`, `scanning`, `error`, and `disconnected`.
- All, passthrough: inside `runCloudVersionCheck`, one
  `GET /api/v1/handshake/` reaches the recorder with no
  `Authorization` header; a `PATCH /api/v1/notes/1/` made inside the same
  zone does not.
- All, startup bounds (2.9): with another transport holding the lock for
  7 s, startup completes, the waiting request gets the 5 s folder lock
  message, and no "Cloud data not loaded" text appears. A start with the
  permission at `prompt` shows the reconnect view and sends no shell
  request. A GET that meets a leftover journal while another transport
  holds the lock answers by its 8 s deadline from request start, across
  the R3 re-locks.
- Portal, cold deep links (2.8 rule 4): with a folder that holds note U
  and an index, the app starts at `/note/<U>` (through
  `tester.binding.platformDispatcher.defaultRouteNameTestValue`).
  `_NoteRoutePage` renders U's title and body, and the recorder holds
  zero requests. A cold start at `/notes` shows the folder's notes in the
  learner tab after the guest fetch, again with zero requests. Repeated
  at `/note/<U>` with no remembered handle, the route page shows the
  reconnect view; after `MemoryFolderPicker` returns the same folder, U
  renders.
- All, choose again (2.9): with no remembered handle, startup shows
  "Choose '<name>' again" and sends no request. `MemoryFolderPicker` then
  returns, in separate runs: the same folder, and the app reaches
  `active`; a folder with another `folder_id`, and the refusal appears
  with the shared key unchanged, after which "Switch to this folder"
  rewrites the key and the change-channel double receives
  `{op: "switch"}`; an empty folder, and the refusal appears with the
  folder still empty; `AbortError`, and the view stays.
- Editor and portal, precedence (2.10): with a saved cloud session in
  `notechondria.<app>.session` and the shared key set to a folder, both
  seeded through `SharedPreferences.setMockInitialValues` before
  `LocalFolderBoot.preload()` so that `decideStorageMode` runs, the
  app starts in cloud mode (its session check reaches the fake backend),
  shows the "Local folder not used" notice, and
  keeps the session. In folder mode with another app's session key
  seeded, Disconnect leaves that key byte-identical and the recorder
  holds no request (no `/auth/logout/`).
- All, Disconnect order (2.10 rule 4): with a note edit pending,
  Disconnect; the edit is kept as a browser-local draft, and the recorder
  holds zero requests, so no request carried `Token local-folder` after
  the mode switched.
- All: an injected unqualified probe shows the option disabled with the
  `noDirectoryPicker` message.

## 8.6 Manual owner checks on desktop Chrome

1. Pages origin: the option is enabled; Firefox shows it disabled with the
   message.
2. Connect an empty folder; the notice's "Choose folder" opens the
   picker; the files appear in the OS file manager.
3. Non-empty folder without a manifest asks for confirmation; a system
   folder is refused by Chrome.
4. Create, edit, delete, restore, and empty trash; check files on disk,
   including that `history/` and `assets/` of the deleted note are gone.
5. Edit a note's `.md` in another editor; the app shows the change after
   focus, and history holds an `external_edit` snapshot.
6. Editor, planner, and portal open in three tabs; save in two at once;
   no file is corrupted.
7. Close all tabs and reopen. With "Remember this folder" on: "Reconnect
   '<name>'" appears (and "Allow on every visit"). With it off, the
   default on `https://trance-0.github.io`: "Choose '<name>' again"
   appears, the picker opens at the folder's location, and choosing the
   folder resumes with every note present.
8. Remove access from the address-bar icon mid-edit, and separately leave
   the tab in the background until Chrome revokes access; in both cases
   the edit survives as a draft and syncs after Reconnect.
9. Move or rename the folder; the not-found message appears; re-pick works.
10. Attachments, covers, and the avatar render, also in the planner and
    portal note viewers.
11. `.ics` import; URL subscribe to a Google calendar shows the CORS
    message; a CORS-enabled feed works.
12. `.nchron` export, then import into a new empty folder: identical tree
    except a new `folder_id`.
13. GitHub push with a fine-grained token; the token is in no file or log.
14. Same flow at `http://127.0.0.1:9068`. With "Remember this folder" on,
    a second app opened in a new tab opens the folder without a prompt
    while the first tab is still open; with it off, each app asks once
    per page load, on this origin as on `https://trance-0.github.io`. No
    tab ever receives a handle from another tab.
15. Copy a note file and, separately, the whole folder in the file
    manager: the copied note gets its own UUID after a rescan, and
    picking the copied folder offers its own identity (3.7).
16. Session-only, wrong folder: after a reload, "Choose '<name>' again",
    then pick a different Notechondria folder. The refusal names both
    folders and nothing changes on disk. "Switch to this folder" opens
    it, and an open planner tab shows the "Folder switched in another
    tab" banner. Picking an empty folder shows the refusal and leaves the
    folder empty in the file manager.
17. Locks: open the editor and the planner on one folder. In the editor,
    empty a trash of 100 or more notes, and while the status card shows
    "Folder busy", save a note in the planner and run
    `await navigator.locks.query()` in the planner's DevTools console:
    `held` lists `notechondria.local_folder.<folder_id>` once, as
    `exclusive`, and the planner's request is under `pending`; the save
    completes after the chunk. Then remove folder access from the
    address bar during an editor save: within a second,
    `navigator.locks.query()` shows nothing held, and after Reconnect the
    planner's next save succeeds.
