# Local folder storage mode: storage modes, startup, and migration

Part of the design in [`../local_folder_mode.md`](../local_folder_mode.md)
(sections 2.8 to 2.10 and 7). Same conventions: repo-root-relative paths,
`file:line` at HEAD `48988a20` (VERSION 0.1.199), and section numbers that
refer to the main document unless they are 2.8 to 2.10 or start with 7.
Sections 3.4 to 3.8 are in [`storage_rules.md`](storage_rules.md),
section 6 in [`security_and_tabs.md`](security_and_tabs.md), and section 8
in [`testing.md`](testing.md).

## 2.8 Routing by storage mode

Storage mode is per app: `browserOrCloud` (today's behavior) or `folder`.
It is decided once per start, synchronously, before the root widget is
built and therefore before any request:

- `runGuardedApp` gains an optional `Future<void> Function()? prepare`,
  awaited inside its zone after `WidgetsFlutterBinding.ensureInitialized()`
  and before `launch()`
  (`frontend/notechondria_shared/lib/src/startup/startup_guard.dart:35-39`).
  Each wired app's `main` passes `prepare: LocalFolderBoot.preload`, which
  awaits `SharedPreferences.getInstance()` once and stores
  `LocalFolderBoot.snapshot`. That call loads every value into a cache
  (shared_preferences 2.5.4 `shared_preferences_legacy.dart:79-96`), and
  later reads such as `getString` are synchronous (`:129`), so the later
  `_LocalAppStore` calls reuse the same instance at no extra cost.
- `LocalFolderController.forApp(app)` (2.7) calls `decideStorageMode`,
  which returns `folder` only when the build is web, the shared key
  `notechondria.shared.storage_mode` (2.10) holds `"mode": "folder"`, and
  the app has no saved cloud session. A saved session is read exactly as
  the app's `loadSession` reads it, a value that decodes to a map with a
  non-null `token`:
  - editor: `notechondria.editor.session`, or, when that key is absent,
    the legacy `notechondria.session` that `_migrateLegacyKeys` would copy
    into it (`frontend/editor_app/lib/core/local_store.dart:50-72`,
    `:287-299`);
  - portal: `notechondria.portal.session` (`frontend/portal_app/lib/core/local_store.dart:76`);
  - planner: none, because it keeps its session in memory only
    (`frontend/planner_app/lib/core/initial_data.dart:259-260`).

  With a saved session the mode is `browserOrCloud` and 2.10 rule 2
  applies. An app without the wiring (2.10 rule 1) has no controller and
  keeps today's behavior.
- `preload` catches its own errors. If browser storage cannot be read,
  the snapshot is empty, the mode is `browserOrCloud`, and the app logs
  "Local folder not checked: <App>.Startup/local_folder — browser storage
  could not be read (<cause>); starting in browser-local or cloud mode."

In folder mode the folder state starts as `opening`, and the
`local_folder` step (2.9) opens the folder. After that the mode changes
only on Connect, Disconnect, and "Switch to this folder" (2.9). The folder
state (`opening`, `needsPick`, `needsPermission`, `scanning`, `active`,
`error`, `disconnected`) never changes routing. `StorageModeClient.send`
applies four rules:

1. **Mode `browserOrCloud`:** forward to the inner `http.Client`,
   unchanged.
2. **Mode `folder`:** hand every request to `LocalFolderTransport`,
   whatever its host, scheme, or path, except the single passthrough in
   rule 3. The transport finds the `/api/v1/` segments in the path (a base
   URL may carry a prefix, for example `https://host/notechondria/api/v1`)
   and dispatches the rest. A path without them gets a 404 with "Request
   not answered: Shared.LocalFolder.Backend/route — <METHOD> <path> is not
   an /api/v1 route, and folder mode sends nothing to the network."
3. **The one passthrough**, for the manual "Check for updates" button in
   the status card (Q9). A request goes to the inner client only when all
   of these hold:
   - it was issued inside `runCloudVersionCheck(...)`, a zone value that
     only that button's `onPressed` sets (the zone mechanism of
     `runWithStartupBudget`, `startup_budget.dart:105-127`);
   - the method is `GET`, with no body and no query string;
   - the path ends with `/api/v1/handshake/`;
   - the scheme is `https`, or `http` with a loopback host;
   - the scheme, host, port, and path prefix equal the saved
     `api_base_url`.

   The client rebuilds the request with only `Accept: application/json`,
   dropping `Authorization` and every other header. Cookies depend on the
   API base: package:http 1.6.0's `BrowserClient.withCredentials`
   defaults to false (`browser_client.dart:59`), which maps to fetch
   `credentials: 'same-origin'` (`:88`). A cross-origin API base, such as
   the Pages deployment's default, therefore gets no cookies. A
   same-origin base, which is the default on `localhost` and `127.0.0.1`
   (editor `core/helpers.dart:142-156`) and so includes the loopback
   preview, may get the origin's cookies. They carry no authority there:
   the handshake is a public GET view
   (`backend/notechondria/api_views.py:252-253`), and the API
   authenticates only by `Authorization` header (`ApiKeyAuthentication`,
   `CasdoorJWTAuthentication`, `TokenAuthentication`, no session
   authentication, `backend/notechondria/settings.py:287-304`). The
   existing 8 s handshake timeout applies outside
   startup (`frontend/editor_app/lib/core/http_client.dart:62-68`). The
   response is read only for `version` and `min_frontend_version`. Any
   other request made inside that zone still goes to the transport. Log:
   "Cloud version checked: Shared.LocalFolder/version_check — GET
   <host>/api/v1/handshake/ answered 0.1.NNN; no account data was sent."
   The automatic version polls (editor `core/settings_helpers.dart:120-139`)
   are not in that zone, so the local handshake answers them with the
   running build's version and the banner stays hidden (F46).
4. **Folder states.** The transport answers `GET /handshake/` and
   `GET /ping/` from memory in every state. In `opening` it holds every
   other request until the state changes, within the request's deadline
   (2.9), and then applies this rule for the state reached. A cold portal
   `#/note/<uuid>` start, whose `_NoteRoutePage` loads in `initState`
   (`frontend/portal_app/lib/components/note_route_page.dart:33-44`), and
   the guest public-notes fetch of a cold `#/notes` start
   (`frontend/portal_app/lib/modules/learner.dart:98-110`) are held this
   way and answered from the folder. Outside `active` the transport
   answers every other route, the (b) routes included, with 503 and a
   1.8 detail:
   - `needsPick`: "Folder not open: Shared.LocalFolder/restore_handle —
     this browser keeps access to '<name>' for one page load only
     (session-only mode), so it has to be chosen again. Click Choose
     '<name>' again."
   - `needsPermission`: "Folder access lost: Shared.LocalFolder/permission
     — the browser no longer grants read and write access to '<name>'
     (NotAllowedError, or access revoked while the tab was in the
     background). Click Reconnect."
   - `scanning`: "Folder not ready: Shared.LocalFolder/scan — '<name>' is
     still being indexed (<n> of <m> entries). Try again in a moment."
   - `error`: "Folder unavailable: Shared.LocalFolder/<process> — <cause>."
     with the process and cause of the error that set the state.
   - `disconnected` (another tab disconnected the folder, 2.10): "Folder
     disconnected: Shared.LocalFolder/disconnect — '<name>' was
     disconnected in another tab. Reload to continue in browser-local
     mode." When another tab switched folders (2.9), the detail is
     "Folder switched in another tab: Shared.LocalFolder/connect — this
     browser now uses '<picked>' instead of '<name>'. Reload to open it."

   All three apps keep a failed note save as a browser-local draft
   (editor `core/note_crud.dart:136-160`, planner `core/note_crud.dart:139-158`,
   portal `core/note_crud.dart:135-150`), and Reconnect pushes those
   drafts into the folder through `applyAuthPayload`
   (`app_shell_session_mixin.dart:326-327`).

`needsPermission` is a routine state, not an edge case: Chrome revokes
access for a tab that has been in the background for a while (1.4), so a
user who switches away and back meets rule 4 regularly. Outside the app
client, only the requests named in 2.6 leave the page. The smoke check
"revoked mid-session" in 8.5 asserts that the test's recorder, which
stands in for every `http.Client()`, receives zero requests in every
non-active state.

## 2.9 Startup sequence in folder mode

The new `local_folder` step runs after `local_state` and before `config`
and the handshake (editor `frontend/editor_app/lib/core/bootstrap.dart:37-51`,
planner `frontend/planner_app/lib/core/bootstrap.dart:37-54`, portal
`frontend/portal_app/lib/core/bootstrap.dart:35-50`). It makes no network
request.

1. The storage mode is already decided (2.8). In `browserOrCloud` mode
   the step returns at once and startup is unchanged. In `folder` mode
   the folder state is `opening`.
2. Restore the handle. With "Remember this folder" on, it comes from the
   IndexedDB record (6.2), and the step calls
   `queryPermission({mode: 'readwrite'})`. In session-only mode, the
   default on `*.github.io` (Q3), the handle lives only in page memory, so
   after every reload and in every newly opened app tab there is none and
   the step goes to step 4b. A missing record in remembered mode is
   treated the same way.
3. `granted`: read `manifest.json`, roll forward leftover journals under
   the exclusive lock (3.4.1), and load `.notechondria/index.json`. When
   the index exists and matches the layout version, the controller is
   `active` at once, and a verification rescan (3.8) runs after the
   startup pass, outside the budget zone; if anything changed, the UI
   refreshes through the change path (6.2). Note overwrites stay safe
   meanwhile, because every write re-checks the file on disk (3.8).
   Without a usable index the step scans in place (state `scanning`) and
   reports progress at least every 2 s on the splash status ("Reading
   folder '<name>': 1,200 of 5,000 entries"). The step then calls
   `applyAuthPayload` with the local payload, as `session_restore` does
   for a saved cloud session (`frontend/editor_app/lib/core/auth_flows.dart:168-177`).
4. The folder is pending. The step completes without waiting for a
   click, in either case below. The pass continues with the folder
   pending: the handshake is answered locally (2.8 rule 4), and
   `session_restore`, `oauth_callback`, and `initial_data` are skipped.
   The pass ends with the splash hidden and `LocalFolderReconnectView`
   shown in place of the shell (6.3); held requests get the 503 of the
   new state.
   - a. `prompt` on a restored handle (expired or auto-revoked grant):
     the state is `needsPermission`, and the view offers "Reconnect
     '<name>'".
   - b. No handle: the state is `needsPick`, and the view offers "Choose
     '<name>' again".
5. `denied`, `NotFoundError`, or a newer `layout_version`: the controller
   enters `error`, and the reconnect view shows the matching message from
   6.3 or 3.2. For `denied` and `NotFoundError` it also offers "Choose
   '<name>' again".

In folder mode, `session_restore` is skipped, because the folder session
comes from step 3. `oauth_callback` is skipped too; a leftover `?code=`
logs "Sign-in not completed: <App>.Startup/oauth_callback — this app is in
folder mode; disconnect the folder to sign in to the cloud." `config` logs
"API base resolved: <App>.Startup/config — folder mode; requests are
answered in the page (the saved URL <url> is used only by Check for
updates)."

**Splash.** The 12 s force-hide (`kBackendStartupTimeout + 2s`, editor
`core/bootstrap.dart:25-32`, planner `:26-27`, portal `:24-25`) stays as
the safety net. Each progress report from the step re-arms it for another
12 s, so a long first scan keeps its progress visible. If the step
reports nothing for 12 s, the timer hides the splash as it does today.

**Reconnect (a handle exists).** The "Reconnect '<name>'" button calls
`requestPermission({mode: 'readwrite'})` first in its `onPressed` (1.3).
On `granted` it runs step 3, including `applyAuthPayload`. That runs in
the gesture's zone, outside any startup budget (`runWithStartupBudget`
is zone-scoped, `startup_budget.dart:105-127`), so a slow folder cannot
trip the budget or make later requests skip as "Cloud data not loaded".
A mid-session reconnect uses the same path; the handle is still in page
memory then, in session-only mode too.

**Choose again (no handle).** The "Choose '<name>' again" button calls
`showDirectoryPicker({id: 'notechondria-folder', mode: 'readwrite'})`
before any `await` in its `onPressed` (1.3). The fixed `id` makes the
picker open where it was last used with that `id` (MDN). The picker
includes Chrome's grant for `readwrite`; when the user closes it or
declines the grant it throws `AbortError` (MDN). Only after it returns
does the app read the picked folder's `manifest.json`, in the same
gesture zone and outside any startup budget:

- **Same `folder_id` as the shared key:** the copy check of 3.7 runs, the
  handle is kept in page memory (and in IndexedDB when "Remember this
  folder" is on), and step 3 runs, including `applyAuthPayload`.
- **No `manifest.json`** (an empty folder, or any folder that is not a
  Notechondria folder): the app writes nothing to it and shows "Folder
  not opened: Shared.LocalFolder/pick — '<picked>' has no manifest.json,
  so it is not '<name>'. Choose '<name>', or use browser-local mode and
  connect a new folder from the sign-in screen." Starting a new folder is
  a separate, explicit Connect, so a mis-click cannot make the data look
  lost.
- **A different `folder_id`** (another Notechondria folder): refused by
  default with "Folder not opened: Shared.LocalFolder/pick — '<picked>'
  is a different Notechondria folder (folder_id <8 hex>) from '<name>'
  (<8 hex>), which this browser uses. Choose '<name>', or switch this
  browser to '<picked>'." The message comes with a "Switch to this
  folder" button. Switching:
  1. writes the shared key with the new `folder_id`, `folder_name`,
     `connected_by`, and `connected_at`;
  2. deletes the old folder's remembered-handle record and, with
     "Remember this folder" on, stores the new one;
  3. posts `{op: "switch", folder_id}` on the change channel (6.2). Other
     tabs in folder mode enter `disconnected` with the switch detail of
     2.8 rule 4; tabs in browser-local mode show the connect banner of
     2.10 rule 5;
  4. runs step 3, and then the push of 2.10 rule 3, because this is the
     app's first start in that folder.
- **A newer `layout_version`:** the 3.2 message.
- **`AbortError`:** the view stays as it was, and the app logs at INFO
  "Folder not chosen: Shared.LocalFolder/pick — the picker closed without
  a folder (AbortError)."

**Cost.** In session-only mode each app asks once per page load: after
every reload and in every newly opened app tab, because v1 passes no
handle between tabs (6.2). With "Remember this folder" on, a restored
handle takes the Reconnect path instead. A second app tab then usually
needs no prompt at all while another tab of the origin holds the grant,
because the grant belongs to the origin (6.1).

**Bounds.** Local requests do not use the startup budget (2.7). The
transport also bounds each request, measured from the moment
`LocalFolderTransport.send` receives it:

- Every lock wait is at most 5 s (6.2 R5) and never longer than the time
  left before the request's deadline. Each wait gets its own
  `AbortSignal.timeout(min(5 s, time left))`.
- **Read deadline:** 8 s for a GET. It covers the hold in `opening` (2.8
  rule 4), every lock wait (the shared lock and, on the R3 path, the
  exclusive lock for roll-forward and the shared lock again), the
  roll-forward itself, and the handler. At the deadline the GET answers
  503 with "Folder data not loaded: Shared.LocalFolder.Backend/route —
  GET <path> took more than 8 s (<cause>)." The cause is "folder still
  opening", "waiting for the folder lock", or "folder reads stalled".
- **Write deadline:** 7 s for a write to start, that is, to write its
  journal record (3.4.1 step 2) or, for a single-file write, to open the
  writable. It covers the same waits as a read. A write that misses it
  has changed nothing and answers 503 with "Change not saved:
  Shared.LocalFolder.Backend/route — <METHOD> <path> could not start
  within 7 s (<cause>)." All three apps keep such a failed save as a
  browser-local draft (2.8). A write that has started runs to the end,
  because stopping it would only leave work for roll-forward. R4 caps
  that hold at a 2 s target and 50 file writes, so a write normally
  answers within about 9 s.

These deadlines bound waiting. They do not bound a disk that stalls
inside a hold, for example a `close()` that never returns. That is why
the startup-budget exemption in 2.7 is still needed: the deadlines alone
do not keep every local request under the 10 s budget.

**Wording.** In folder mode the later steps use folder wording. The
handshake step's splash label reads "Opening folder backend" instead of
"Connecting to server". The `initial_data` step's label reads "Reading
folder '<name>'", and its failure consequence is "Folder data not loaded"
instead of "Cloud data not loaded" (editor `core/bootstrap.dart:89-96`,
and the matching planner and portal steps). `_initialDataOutcome` says
"every folder request answered" instead of "every cloud request
answered" (editor `core/bootstrap.dart:182-196`, planner `:171-185`,
portal `:173-187`).

## 2.10 Which apps use the folder

The connection is recorded once per browser in
`notechondria.shared.storage_mode`, in `shared_preferences`, which on web
is origin-wide localStorage:
`{"mode": "folder", "folder_id", "folder_name", "connected_by", "connected_at"}`.
Sessions are per app (`notechondria.<app>.*`; editor
`core/local_store.dart:33-47` explains the prefixes). The editor and the
portal persist their cloud session (`:275-285`); the planner keeps it in
memory only (`frontend/planner_app/lib/core/initial_data.dart:259-260`).

1. **Per-phase opt-in.** An app honors the key only from the phase that
   ships its own option (9.1): the editor from Phase 2, the planner and
   portal from Phase 3. Before that the app has no `local_folder` step and
   ignores the key, so it never calls folder routes its phase lacks.
2. **A live cloud session wins.** If the app holds a saved cloud session
   at startup (editor, portal), `decideStorageMode` returns
   `browserOrCloud` (2.8) and the app restores that session as today. It
   shows once per start, and the
   status card repeats: "Local folder not used: <App>.Startup/local_folder
   — this app is signed in to the Notechondria cloud as '<user>', which
   takes precedence over the folder '<name>' connected on this browser.
   Sign out here to use the folder." If `session_restore` then clears the
   session, the signed-out `AuthHub` offers "Use the connected folder
   '<name>'" (1.3).
3. **Otherwise the app uses the folder.** On its first start in a given
   folder, the app pushes its own browser-local data in (7.1) and records
   `notechondria.<app>.folder_pushed = <folder_id>`.
4. **Disconnect never ends a cloud session.** Disconnect calls
   `disconnectFolder()`, not `logout()`. Its steps run in this order, so
   that no request carrying `Token local-folder` can reach the inner
   client:
   1. The folder state becomes `disconnected`. Routing stays in folder
      mode, so a request already queued or still issued (a pending
      autosave, for example) gets a 503, here with "Change not saved:
      Shared.LocalFolder/disconnect — '<name>' was disconnected in this
      tab; the change stays in this browser.", and the app keeps a failed
      save as a browser-local draft.
   2. The app clears its in-memory folder token and profile. A save that
      fires after this finds no token and takes the signed-out path.
   3. The app clears the shared key and the remembered-handle record and
      posts `{op: "disconnect"}` on the change channel (6.2).
   4. Only then does the storage mode switch to `browserOrCloud`, and the
      app reloads browser-local data.

   It never calls `authClient.logout`, never calls
   `clearPersistedSession()`, and never touches another app's keys. A
   folder-mode app has no cloud session of its own (rule 2), so nothing
   is lost.
5. **What a running tab shows when another tab changes the connection:**
   - this tab in browser-local mode, folder connected elsewhere: a banner
     "Folder connected in another tab: Shared.LocalFolder/connect —
     '<name>' is now this browser's storage. Reload to use it; this tab's
     browser-local data will be copied in."
   - this tab in folder mode, folder disconnected elsewhere: the folder
     state becomes `disconnected`, requests answer 503 (2.8 rule 4), and
     a banner shows that message.
   - this tab in folder mode, another tab chose "Switch to this folder"
     (2.9): the same, with the switch detail of 2.8 rule 4.
   - this tab holds a cloud session: nothing changes except the status
     card line from rule 2.
   - in Phase 2 the planner and portal do not read the key and keep their
     own browser-local or cloud data. The editor's status card says
     "Folder used by the editor only: Shared.LocalFolder/connect — the
     planner and portal do not support folder mode in this release and
     keep their own data."

The smoke checks in 8.5 cover rules 2 and 4, including the order in
rule 4.

## 7. Migration and mode switching

### 7.1 Browser-local data into a folder

These steps run on the first connect and on the first start of each other
app in that folder (2.10 rule 3), so each app moves its own browser-local
data once per folder.

1. First connect only: the folder is picked, the manifest written or
   validated, and the index built.
2. **Courses first.** Before this step the app sets its in-memory token
   to `local-folder`, with no profile and no `persistSession`, because
   each app's `_syncLocalCourse` throws "Local course not synced" without
   a token (editor `core/local_course_builders.dart:75-76`, planner
   `:94-101`, portal `:102-103`). Step 4's `applyAuthPayload` then sets
   the same token together with the profile. The app pushes its
   browser-local courses through the
   app client with the local token, reusing its `_syncLocalCourse`
   (planner `frontend/planner_app/lib/core/local_course_builders.dart:92-138`;
   loop in `core/maintenance_actions.dart:91-115`). Each push upserts on
   `client_course_id` (3.7) and returns the folder course;
   `_syncLocalCourse` already remaps drafts to it (`:107-115`) and moves
   the local course into the browser-local recycle bin (`:120`). The step
   records `local course id → folder course id` for step 3.
3. **Events and feeds** (planner and portal). These are `is_local_event`
   events (planner `frontend/planner_app/lib/core/planner_builders.dart:5-29`),
   `is_local_feed` feeds (`frontend/planner_app/lib/core/local_calendar.dart:34`),
   and portal events with `local-<micros>` IDs
   (`frontend/portal_app/lib/core/settings_actions.dart:216-228`).
   - Each is pushed with `course_id` rewritten through the step-2 map. A
     negative `course_id` without a mapping becomes null, and the push
     logs "Planner event course dropped: <App>.Sync.Events/push —
     '<title>' referred to local category <id>, which was not copied into
     the folder; the event is uncategorized."
   - Each carries `client_local_id = "<app>:<local id>"`. The folder
     backend upserts on it: it inserts when the key is new, and when the
     key exists it returns the existing folder record unchanged. A repeat
     push (a reconnect, or the planner and then the portal) therefore
     never duplicates a record and never overwrites edits made in the
     folder. The cloud backend has no such key
     (`PlannerEventListCreateApiView.post` creates unconditionally,
     `backend/notes/api.py:2161-2175`), so this applies to the folder
     backend only.
   - After the folder confirms a record, the browser-local copy leaves
     the visible local list and moves to a per-app recovery list
     `notechondria.<app>.pushed_to_folder` (`{folder_id, pushed_at,
     events, feeds}`), pruned after 30 days like the local recycle bin
     (`frontend/editor_app/lib/core/local_store.dart:136-139`). It has to
     leave the visible list, because the portal renders local events next
     to backend events (`frontend/portal_app/lib/core/build_page.dart:97`)
     and would show each pushed event twice. Disconnect offers "Restore
     <n> planner items pushed on <date>", which moves them back.
   - Without this step a signed-in load replaces `_plannerEvents` and
     `_persistLocalCache` overwrites the local ones (`docs/TODO.md:406-410`).
     Whether the same push should also run for cloud sign-in (closing
     those TODO items) is a separate decision.
4. The app calls `applyAuthPayload({'token': 'local-folder', 'user': {..., 'is_local_folder': true}})`.
   That flow reads `/settings/`, runs `loadInitialData`, and then pushes
   local courses (none are left after step 2) and drafts
   (`app_shell_session_mixin.dart:326-327`). The draft pushes upsert by
   `client_draft_id` (3.7), so a repeat is harmless, and they promote
   queued `local://` attachments into the folder
   (`frontend/editor_app/lib/core/note_crud.dart:192-275`); a failed
   promotion keeps its `local://` link (3.6).
5. After a successful push each app moves the draft into its browser-local
   recycle bin for 30 days (`frontend/editor_app/lib/core/local_trash.dart:3-12`,
   TTL at `core/local_store.dart:139`). The status card says: "Browser
   data moved: Shared.LocalFolder/connect — <n> drafts and <m> planner
   items from this browser are now in '<name>'; this browser keeps
   recoverable copies for 30 days (local recycle bin, and Disconnect →
   Restore)."

Portal's "clear drafts" choice runs only after a fresh OAuth sign-in
(`frontend/portal_app/lib/core/bootstrap.dart:89-91`), so connecting a
folder never clears drafts.

### 7.2 Archives

- `.nchron` into a folder: offered when connecting an empty folder,
  through its own "Start from an archive" button whose `onPressed` opens
  the file picker (1.3). Rules in 3.3; the import is chunked (6.2 R4).
- Folder out to `.nchron`: the existing export action, which reads the
  folder in folder mode (3.3), with the secret denylist (5).

### 7.3 Switching modes without data loss

The three stores are independent: cloud (server), browser-local
(localStorage and the `notechondria_attachments` IndexedDB), and folder
(disk). Switching changes which store the app reads. No switch deletes
another store's data without keeping a recoverable copy. Connecting makes
two moves, both recoverable in this browser for 30 days: browser-local
drafts go to the local recycle bin, and pushed planner items go to the
recovery list (7.1 steps 3 and 5). "Disconnect" forgets the handle and
the remembered record, leaves the folder untouched, and never ends a
cloud session (2.10 rule 4). Data otherwise moves only by explicit,
idempotent pushes. The connect-time moves are owner question Q18.

| From, to | How | Status |
|---|---|---|
| browser-local, folder | Connect (7.1) | v1 |
| folder, browser-local | Disconnect; optionally restore the pushed planner items (7.1) and import the folder's `.nchron` | v1 |
| cloud, folder | Sign out of the cloud in that app (2.10 rule 2), connect the folder. Copying cloud data in: push GitHub data-sync, clone, open the clone (Phase 4 "adopt") | v1 manual; in-app copy is a follow-up |
| folder, cloud | Interim: export `.nchron`, import it in browser-local mode, sign in; the post-login push uploads notes and courses (not history, sessions, events, or feeds). Or run `backend/scripts/github_sync_restore.py` on the folder (layout-compatible; needs an `ntc_` key; assets are not restored, `:21-24`) | Full-fidelity "move to cloud" is a follow-up (Q12) |
