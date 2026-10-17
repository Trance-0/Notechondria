# Local folder storage mode (design)

Status: design only. Nothing here is implemented. Written against `main`
at VERSION 0.1.199. Citations were first pinned at `6cd1f3be` and are
re-pinned at HEAD `48988a20`. Between the two commits only
`frontend/planner_app/lib/core/calendar.dart` and
`frontend/planner_app/test/smoke_test.dart` changed, and their citations
are updated. Browser facts were re-checked on 2026-10-17 against the
sources in section 11.2. Paths are repo-root-relative. Anything not
confirmed is marked **unverified** and collected in section 11.1. Items
that need an owner decision are in section 10. Section 12 maps each
finding of design reviews 1 and 2 to the section that resolves it.

The design spans nine files, all under the 1000-line cap:

- this document: sections 1, 2.1 to 2.7, 3.1 to 3.3, 4 and 9 (summaries),
  5, and 10, with pointers for 11 and 12;
- [`local_folder_mode/modes_and_migration.md`](local_folder_mode/modes_and_migration.md):
  2.8 to 2.10 (routing by storage mode, startup, which apps use the
  folder) and 7 (migration and mode switching);
- [`local_folder_mode/storage_rules.md`](local_folder_mode/storage_rules.md):
  3.4 to 3.8 (writes and journal, delete and trash, attachments, IDs,
  rescans);
- [`local_folder_mode/feature_matrix.md`](local_folder_mode/feature_matrix.md):
  section 4;
- [`local_folder_mode/security_and_tabs.md`](local_folder_mode/security_and_tabs.md):
  section 6 (shared origin, locking, permissions);
- [`local_folder_mode/testing.md`](local_folder_mode/testing.md):
  section 8;
- [`local_folder_mode/implementation_plan.md`](local_folder_mode/implementation_plan.md):
  section 9;
- [`local_folder_mode/unverified_and_sources.md`](local_folder_mode/unverified_and_sources.md):
  section 11 (unverified items and sources);
- [`local_folder_mode/revision_log.md`](local_folder_mode/revision_log.md):
  section 12 (revision logs for design reviews 1 and 2).

Section numbers are global: a reference such as "6.2 R4" or "3.4.1"
means that section in whichever file holds it.

Owner request (intent): add an option in the login window that checks for
a qualified Chrome; if qualified, use a local folder as a pure local file
backend; support all features; the frontend reads and renders content
locally and acts only as a dashboard for local services.

## Summary

- **Qualification** is feature detection (`showDirectoryPicker`,
  `isSecureContext`, permission and iteration methods, Web Locks, not
  mobile). Brands from `navigator.userAgentData` are only a label. Native
  builds hide the option.
- **Architecture: option A.** A shared, in-page local backend implements
  the `/api/v1` routes the apps already call. It plugs in as the
  `http.Client` that `HttpClientInternalsMixin.send` operations call, so
  existing app code paths run unchanged against a folder. While an app is
  in folder mode, every request through its client is answered in the
  page. Routing follows the app's storage mode, not the request host or
  the folder's permission state, and the mode is decided synchronously
  before the first request (2.8).
- **Folder layout** extends the GitHub data-sync layout
  (`backend/creators/services/github_sync.py:11-28`): one `.md` file plus a
  `.meta.json` sidecar per note, JSON for everything else, attachments as
  real files, and a `manifest.json` with a layout version. A `.nchron`
  export carries both the v1 buckets and a verbatim copy of the folder.
- **Multi-tab safety:** every write re-reads its files from disk under an
  exclusive Web Lock, multi-file writes go through a journal, and reads
  take the lock in shared mode (6.2).
- **Feature matrix** (section 4): 44 features work fully locally (a),
  5 work by calling a third party from the browser (b), 13 need a server
  (c). One listed area (AI/LLM) has no feature today and is not counted.
- **Main risk:** the Pages origin `https://trance-0.github.io` is shared
  with other Trance-0 Pages projects (section 6.1). Same-origin code can
  reach a granted folder. v1 therefore passes no folder handle between
  tabs on any origin; each app tab opens the folder itself (6.2). A
  dedicated origin removes the other projects, but the loopback preview
  and the Docker self-host still serve uploaded `/media/` files on the
  app origin (6.1).

## 1. Qualification check in the login window

### 1.1 The login window today

- There is no modal login dialog. The shared signed-out surface is
  `AuthHub`, an inline `Card`
  (`frontend/notechondria_shared/lib/src/components/auth_dialogs.dart:49-106`).
  Only the email and password form opens as a dialog, through
  `showBlurDialog` (`auth_dialogs.dart:82-87`). The doc comment at
  `auth_dialogs.dart:30-48` lists its three CTAs: Casdoor SSO, the Casdoor
  org-login link, and the collapsed email/password fallback.
- Per-app entry points:
  - Editor: `_buildSignedOutAccount` returns `AuthHub(...)`
    (`frontend/editor_app/lib/modules/settings_build.dart:129-136`). The
    callbacks come from `_SettingsPage(...)` in
    `frontend/editor_app/lib/core/build_helpers.dart:598-612`.
  - Planner: the "Login and sync" card shows `AuthHub(` inside
    `if (!_isAuthenticated)`
    (`frontend/planner_app/lib/modules/settings.dart:442-450`), wired from
    `frontend/planner_app/lib/app_shell.dart:815-831`.
  - Portal: `_buildSignedOutAccount`
    (`frontend/portal_app/lib/modules/settings_build.dart:156-175`) shows
    `AuthHub` (`:162-167`) and a "Keep offline data after login"
    checkbox, wired from `frontend/portal_app/lib/core/build_page.dart:120-133`.
- `docs/AGENTS.md` lists `Shared.AuthDialog` (`login.submit`, ...), but no
  Dart code emits that source. Auth messages use `<App>.Auth/*` from the
  shared mixins, for example
  `frontend/notechondria_shared/lib/src/app_shell/app_shell_auth_actions_mixin.dart:31-44`.
- There is no storage-mode enum. Signed out means the token is null or empty
  (`frontend/notechondria_shared/lib/src/app_shell/app_shell_session_mixin.dart:66-75`).
  Offline mode is the boolean `offline_mode` in local settings, default
  `false` (`frontend/editor_app/lib/core/local_store.dart:147`).

### 1.2 Capability probe

A new `probeLocalFolderSupport()` returns a `LocalFolderQualification`
(`qualified`, ordered `gaps`, `browserLabel`). It runs at build time with no
user gesture and no prompt, on web builds only (1.3).

| Gap id | Check (all via `dart:js_interop`) | Why it matters |
|---|---|---|
| `noDirectoryPicker` | `window.showDirectoryPicker` is a function | The only way to obtain a user-visible folder handle |
| `insecureContext` | `window.isSecureContext == true` | The File System Access API is secure-context only (MDN, 11.2) |
| `noPermissionApi` | `queryPermission` and `requestPermission` exist on `FileSystemHandle.prototype` | Needed to re-grant a stored handle (section 6.3) |
| `noDirectoryIteration` | `values` (or `entries`) exists on `FileSystemDirectoryHandle.prototype` | Needed to scan the folder |
| `noWebLocks` | `navigator.locks` exists | Needed to serialize writes across tabs (section 6.2) |
| `mobile` | `navigator.userAgentData.mobile == true`; when `userAgentData` is absent, the UA regex `iphone\|ipad\|ipod\|android\|mobile` | v1 is desktop-only (open question Q2) |

- `navigator.userAgentData.brands` is read only for `browserLabel` (for
  example "Google Chrome 1xx") in logs and the status card. It never gates
  the option, so Edge, Opera, and Brave with the API flag enabled qualify
  on capability alone. Brave ships the API behind a flag (Chrome docs,
  11.2).
- The existing `isMobileWebBrowser()`
  (`frontend/notechondria_shared/lib/src/utils/web_install_env_web.dart:13-18`)
  cannot be reused as is: it returns `false` for an installed mobile PWA
  (`:16-17`). The probe needs a plain device check.
- The picker needs transient user activation (MDN, 11.2). The order of
  gestures is fixed in 1.3. That Flutter web keeps activation through
  `onPressed` is **unverified** (U3); `file_selector` opening an
  `<input type=file>` from `onPressed` suggests it does.

### 1.3 The option and its states

`AuthHub` gains one optional slot, `Widget? localFolderOption`, rendered
between the Casdoor CTAs and the email/password expander. Each app passes
the shared `LocalFolderSignInOption` widget on web builds and `null` on
native builds. A slot keeps the shared widget generic, as
`frontend/AGENTS.md` (development rule 3) asks.

| State | What the user sees |
|---|---|
| Qualified, not connected | Enabled button "Use a local folder (no account)" and one line: "Notes, courses, and planner data are saved as files in a folder you choose. No account is needed, and none of this data is sent to the Notechondria server." |
| Qualified, a folder is already connected on this browser (2.10) | The same button, labeled "Use the connected folder '<name>'" |
| Unqualified | The same button, disabled, followed by a copyable `FeedbackText` message for the first gap and the fallback line below |
| Folder mode active | `AuthHub` is not shown (the app is in a signed-in state). Settings show a `LocalFolderStatusCard` instead (section 2.7) |
| Native build (the portal desktop build) | Nothing: the slot is `null`, so no button and no message. The qualification messages name browsers and would mislead there. Folder mode for native builds is Q11 |

Gesture order, so that each browser call that needs transient activation
is the first call of its own click handler:

1. If the shared-origin notice (6.1 mitigation 2) has not been
   acknowledged on this browser
   (`notechondria.shared.local_folder_notice_ack`), the option's
   `onPressed` only opens the notice dialog. The dialog holds the
   "Remember this folder on this browser" checkbox (6.1 mitigation 1) and
   a "Choose folder" button. That button's `onPressed` calls
   `showDirectoryPicker` before any `await`.
2. Once the notice is acknowledged (and on origins that need none), the
   option's `onPressed` calls `showDirectoryPicker` first. Every
   directory picker in the app passes
   `{id: 'notechondria-folder', mode: 'readwrite'}`, so a later "Choose
   '<name>' again" opens where the folder was chosen (MDN `id` option).
3. When the picked folder is empty, the app shows "Start empty" and
   "Start from an archive". "Start from an archive" opens the `.nchron`
   file picker as the first call of its own `onPressed`. The file picker
   is never chained after the directory picker within one gesture.
4. The reconnect view (2.9, 6.3) has two buttons, and each one's browser
   call is the first call of its `onPressed`:
   - "Reconnect '<name>'", shown when a handle exists and its grant
     expired, calls `requestPermission({mode: 'readwrite'})`;
   - "Choose '<name>' again", shown when there is no handle (session-only
     mode after every reload and in every new tab), calls
     `showDirectoryPicker({id: 'notechondria-folder', mode: 'readwrite'})`.
     Only after the picker returns does the app read the picked folder's
     `manifest.json` and check its `folder_id` (2.9).

Messages for unqualified browsers (AGENTS.md 1.8 shape; module rows in 9.4):

- `noDirectoryPicker`: "Local folder mode unavailable: Shared.LocalFolder/qualify — this browser does not provide window.showDirectoryPicker (File System Access API). Firefox and Safari do not offer it."
- `insecureContext`: "Local folder mode unavailable: Shared.LocalFolder/qualify — the page is not a secure context (window.isSecureContext is false). Open the app over https or from http://127.0.0.1."
- `noPermissionApi` / `noDirectoryIteration`: "Local folder mode unavailable: Shared.LocalFolder/qualify — this browser exposes the folder picker but not FileSystemHandle.requestPermission (or directory iteration), so a folder could not be reopened or scanned."
- `noWebLocks`: "Local folder mode unavailable: Shared.LocalFolder/qualify — navigator.locks (Web Locks API) is missing, so two tabs could corrupt the folder."
- `mobile`: "Local folder mode unavailable: Shared.LocalFolder/qualify — a mobile browser was detected (navigator.userAgentData.mobile, or the user agent when that is missing). Folder mode is desktop-only in this release."

Fallback line, shown under every message: "Keep working signed out in
browser-local mode and back up with the local-data export (.nchron), or use
the Notechondria desktop build." The desktop build exists for the portal
only (`.github/workflows/portal-release.yml:131-156`), and it stores data
through `shared_preferences`, not in a folder (folder mode for it is Q11).

### 1.4 Platform facts used by this design

Sources are listed in section 11.2. BCD is MDN browser-compat-data 8.1.6
(timestamp 2026-10-15).

| Fact | Status and source |
|---|---|
| `showDirectoryPicker`: Chrome 86, Edge 86, Opera 72, Chrome Android 132, WebView Android 132; not Firefox or Safari | Verified, BCD. The brief said "Opera 86+" and "Chrome on Android only has OPFS"; both are out of date. Chrome's own Q1 2025 post says the API reached Android in Chrome 132 |
| Picker needs a secure context and transient user activation; `mode: 'readwrite'`, `id`, `startIn` options; `AbortError` for sensitive folders | Verified, MDN `showDirectoryPicker` |
| Restricted folders, for example "core operating system folders like Windows, the macOS Library folders" | Verified, Chrome File System Access article. The home directory root being blocked is **unverified** (U4) |
| `queryPermission`/`requestPermission`: Chrome 86 desktop, Chrome Android 109; not Firefox or Safari | Verified, BCD |
| `removeEntry(name, {recursive})`, `entries`/`values`, `getFileHandle`/`getDirectoryHandle({create})`: Chrome 86, Firefox 111, Safari 15.2 | Verified, BCD and MDN `removeEntry` |
| `createWritable()` writes to a temporary file, flushed on `close()`; `keepExistingData` defaults to false; `mode: 'exclusive'` (Chrome 121) vs default `'siloed'`, where "the last writer opened has its data written" | Verified, MDN `createWritable` and BCD. Chrome's swap-file name `<name>.crswap` is **unverified** (U17) |
| Handles can be stored in IndexedDB; Chrome 122+ offers "Allow on every visit" when a stored handle calls `requestPermission()` on a later visit; installed apps persist the grant automatically; otherwise access lasts until the last tab of the origin closes | Verified, Chrome persistent-permissions post |
| Chrome also revokes a granted handle's access when the tab has been in the background for a while (the one-time-permission logic); a later `requestPermission()` on that handle can show the three-way prompt. After more than three denials or dismissals that prompt stops and the regular one shows | Verified, Chrome persistent-permissions post |
| `FileSystemObserver` shipped on desktop Chrome 133 (not Android); BCD: Chrome 133, Edge 133, Opera 118, experimental, not standards-track | Verified, Chrome 133 release notes, blink-dev Intent to Ship, BCD |
| `FileSystemHandle.move()`: Chrome 102, file handles only (directory moves unsupported) | Verified, BCD note. Overwrite behavior **unverified** (U5) |
| `FileSystemHandle.isSameEntry()`: Baseline, widely available since March 2023 | Verified, MDN `isSameEntry` |
| Web Locks: Chrome 69, Firefox 96, Safari 15.4; locks are scoped to the origin and queue across tabs; `request()` takes `mode: 'exclusive'` (default) or `'shared'` (readers-writer) and an abort `signal` usable as a timeout | Verified, BCD and MDN Web Locks. That a tab's locks are released when it closes or its renderer crashes is **unverified** (U18); the journal (3.4.1) relies on it only to let another tab roll forward |
| `navigator.userAgentData` (`brands`, `mobile`): Chrome 90; not Firefox or Safari | Verified, BCD |
| `package:web` 1.1.1 (locked in `frontend/*/pubspec.lock`, transitive) binds `getFileHandle`, `getDirectoryHandle`, `removeEntry`, `createWritable`, `isSameEntry`, `StorageManager.getDirectory`, `LockManager.request`. It does **not** bind `showDirectoryPicker`, `queryPermission`, `requestPermission`, `entries`/`values`, the `mode` member of `FileSystemCreateWritableOptions` (it has only `keepExistingData`), `Navigator.userAgentData`, or `FileSystemObserver` (its API page returns 404) | Verified against the pub.dev API pages for 1.1.1. The missing members need small `@JS` extension types (9.2 `js_bindings_web.dart`) |
| `package:web` callbacks are not bound to the current zone, unlike `dart:html`; dart.dev recommends `Zone.current.bindUnaryCallback(...)` before `.toJS` | Verified, dart.dev package:web page. Design rule in 2.5 |
| `Zone.bindUnaryCallback<R, T>` returns `ZoneUnaryCallback<R, T>` (keeps the return value); `Zone.bindUnaryCallbackGuarded<T>` returns `void Function(T)` | Verified, api.dart.dev `Zone` pages. A `void` lock callback would release the lock at once (2.5) |
| Web Locks: the lock is held until the callback's returned promise settles; a non-promise return "is wrapped in a promise that is immediately resolved", so the lock is released "in an upcoming microtask" | Verified, Web Locks spec section 2.4 note and section 4.4 ("Resolve waiting with r") |
| For web-vs-native conditional imports, Dart now recommends `dart.library.js_interop` over `dart.library.html` | Verified, dart.dev package:web migration page |

Correction to the brief: `storage_estimate_web.dart` does not use
`package:web`. It imports `dart:html`
(`frontend/notechondria_shared/lib/src/utils/storage_estimate_web.dart:1-2`),
selected by `if (dart.library.html)`
(`frontend/notechondria_shared/lib/src/components/storage_usage_card.dart:5-6`).
Every web file in the repo uses `dart:html` today. The new module follows
the shape of that file (one stub plus one web file selected by a conditional
import, best-effort calls that never throw past the boundary) but uses
`package:web` and `dart:js_interop`, because `dart:html` has no File System
Access bindings and is deprecated. That requires adding `web` as a direct
dependency of `frontend/notechondria_shared/pubspec.yaml`.

## 2. Architecture

### 2.1 Seams that exist today

- `HttpClientInternalsMixin.send(method, uri, operation, {requestBytes})`
  (`frontend/notechondria_shared/lib/src/http/http_client_internals_mixin.dart:105-175`)
  logs `<App>.HTTP/request|response|slow|request_failed`, applies the
  startup budget, and returns the raw `http.Response`. `decode`
  (`:186`) turns it into JSON or throws a shaped error. A `detail` that
  already contains "—" is passed through verbatim (`:320-321`).
- The `operation` closures call the injected `http.Client`: editor
  `frontend/editor_app/lib/core/http_client_internals.dart:28-78`, planner
  `frontend/planner_app/lib/core/http_client_internals.dart:22-72`, portal
  `frontend/portal_app/lib/core/http_client_internals.dart:22-90` (plus `_put`).
- Each app builds `HttpNotechondriaClient({http.Client? httpClient})` with
  `httpClient ?? http.Client()` (`frontend/editor_app/lib/core/http_client.dart:7-9`,
  `frontend/planner_app/lib/core/client.dart:209-211`,
  `frontend/portal_app/lib/core/client.dart:7-9`). The root
  `_NotechondriaAppState` (not `AppShell`) caches one instance,
  `widget.client ?? HttpNotechondriaClient()`
  (`frontend/editor_app/lib/app_shell.dart:52-53`,
  `frontend/planner_app/lib/app_shell.dart:38-39`,
  `frontend/portal_app/lib/app_shell.dart:38-39`).
- The smoke tests already swap the transport:
  `HttpNotechondriaClient(httpClient: MockClient(backend.handle))`
  (`frontend/editor_app/test/smoke_test.dart:50-57`).
- Bypasses of the injected client:
  - Multipart uploads call `request.send()`, which creates its own
    `Client()` (package:http `BaseRequest.send` docs). There are 8 sites:
    editor `http_client.dart:740,775,825,863`, planner `client.dart:883,927`,
    portal `client.dart:787,831`.
  - `pingBackend` calls top-level `http.get`
    (`frontend/notechondria_shared/lib/src/utils/ping_backend.dart:24-38`).
  - Browser navigations: the Casdoor redirect, the GitHub App install popup
    (`frontend/notechondria_shared/lib/src/components/mcp_skill_section.dart:417`),
    and `Image.network` for media URLs (section 3.6).

So the real seam is the `http.Client` behind `send()`. Implementing an
`http.BaseClient` there keeps `send()` logging, the startup budget, and
`decode()` unchanged.

### 2.2 Options

- **A. Route-level local backend (chosen).** A shared
  `LocalFolderTransport extends http.BaseClient` decodes each request
  (JSON or `http.MultipartRequest`), dispatches `(method, path)` to
  handlers that implement the `/api/v1` contract over the folder, and
  returns JSON responses with the backend's shapes and status codes.
- **B. Storage adapter under each app's local store.** Keep the apps in
  signed-out or offline mode and replace the SharedPreferences backing of
  each `_LocalAppStore` (for example `frontend/editor_app/lib/core/local_store.dart:33-139`)
  and `AppShellLocalPersistMixin`
  (`frontend/notechondria_shared/lib/src/app_shell/app_shell_local_persist_mixin.dart:46-92`)
  with folder files.
- A'. Dart-interface variant of A: implement each app's
  `NotechondriaClient` directly (`frontend/editor_app/lib/core/client.dart:6`,
  `frontend/planner_app/lib/core/client.dart:4`,
  `frontend/portal_app/lib/core/client_base.dart:4`). Rejected: the three
  interfaces differ, so this needs three implementations, and it skips the
  HTTP logging and decode path.
- C. Host the local backend in a SharedWorker so one process serves all
  tabs. Rejected for v1: it needs a separate dart2js entrypoint and a
  shared script path in the Pages tree (a CI change). Web Locks give the
  needed write serialization without it.
- D. A localhost daemon speaking `/api/v1`. Not designed here (no network
  listener by default); see section 2.6 and Q1.

### 2.3 Comparison

| Criterion | A: local `/api/v1` | B: store adapter |
|---|---|---|
| Coverage of "all features" | Every storage-backed feature already has a cloud code path; implementing the route covers it in all three apps at once | Only what offline mode covers today: drafts, local courses, local events, local calendar feeds, local trash. History, sessions, attachments list/delete, covers, heatmap, activity week, and server search have no offline path. Planner offline events are not even pushed today (`docs/TODO.md:406-410`) |
| Size of change | One new shared module (about 8,500 lines in about 46 files, section 9.2) plus small per-app edits | Many small edits in every `if (!signedIn \|\| offline)` branch of three apps, plus new offline implementations for each missing feature, triplicated |
| Testability | Pure Dart. The router can be driven through `MockClient`-style injection and an in-memory filesystem in VM tests, the same way the smoke tests run today | Needs widget-level tests per app per feature |
| Contract drift with the backend | Real risk: handlers must mirror serializer shapes, validation, and rules such as upsert by `client_draft_id` (`backend/notes/api.py:1399-1420`). Mitigated by fixtures (section 8.4) | Low drift with the backend, but drift between three app copies |
| Multi-tab safety | One choke point; every request takes the folder lock in the right mode | Writes are spread across per-app persisters |
| Human-readable folder | Layout is free; it follows the server data model | Tends to mirror the bucket JSON (`drafts.json` as one file) unless a mapping layer is added, which recreates A |

### 2.4 Decision

Choose **A**. It is the only option that reaches every storage-backed
feature without rewriting three apps' offline branches, it has a single
place to enforce locking and atomic writes, and it can be tested in the VM
with the injection the smoke tests already use. The cost is contract
drift, which section 8.4 contains with recorded response fixtures. Design
review 1 did not find A unsound; its routing finding (H1) is fixed in 2.8.

### 2.5 Components and request flow

New shared module `frontend/notechondria_shared/lib/src/local_folder/`:

- `FolderFs`: a small interface (`readText`, `readBytes`, `writeText`,
  `writeBytes`, `list`, `stat`, `remove`). Implementations: the web
  File System Access backend, an in-memory fake for tests, and a stub for
  non-web builds.
- `LocalFolderController` (a `ChangeNotifier`): the app's storage mode
  (`browserOrCloud` or `folder`, decided before the first request, 2.8)
  and, separately, the folder state (`opening`, `needsPick`,
  `needsPermission`, `scanning`, `active`, `error`, `disconnected`). It
  owns the handle, the permission checks, the in-memory index (a read
  cache only, 6.2 R2), the lock, the change channel, and the app's
  `StorageModeClient` (`httpClient`, created on first use over
  `http.Client()`).
  - Owner. There is one controller per app instance. `_NotechondriaAppState`
    creates it as a `late final` field next to `_client` (editor
    `app_shell.dart:52-53`, planner `:38-39`, portal `:38-39`) and passes
    it to `AppShell` and, in the portal, to `_NoteRoutePage`
    (`frontend/portal_app/lib/components/note_route_page.dart:11-23`),
    which uses the client outside any `AppShell`. `AppShell` does not
    create it: the client is built before any shell exists, and the
    portal builds one shell per route (`portal app_shell.dart:92-105`,
    `:161`). Wiring is in 2.7.
  - Zone binding. The controller is created during the root widget's
    first build, inside `runGuardedApp`'s zone and before `_bootstrapApp`
    enters a startup budget, and captures `Zone.current` then.
    `package:web` does not bind callbacks to a zone (1.4), so every Dart
    function passed to JavaScript is bound before `.toJS`. The wrapper
    depends on what JavaScript does with the return value (table in 9.2):
    - Void listeners (`BroadcastChannel` messages, `FileSystemObserver`,
      `focus`, `visibilitychange`) use the captured zone's
      `bindUnaryCallbackGuarded` (`bindBinaryCallbackGuarded` for the
      observer's two arguments). An exception then reaches
      `runGuardedApp`'s handler, and a refresh fired later never runs
      inside a startup budget.
    - The `locks.request` callback must return the operation's promise.
      The browser holds the lock until that promise settles, and when the
      callback returns a non-promise it releases the lock "in an upcoming
      microtask" (Web Locks spec, section 2.4 note). A guarded wrapper
      returns `void Function(T)` (api.dart.dev), which JavaScript sees as
      `undefined`, so it would release every lock before the operation's
      first `await`, and the bug would compile silently. The callback is
      therefore bound with the non-guarded
      `Zone.current.bindUnaryCallback<JSPromise<JSAny?>, Lock?>`, in the
      zone of the request that asked for the lock, because it continues
      that request. Its body runs the operation inside a try/catch,
      completes the caller's `Completer` with the result or the error,
      and returns that block's `Future<void>` as `.toJS`. The promise
      therefore always resolves, and the lock is released exactly when
      the operation ends.
    - Lock-wait timeouts use `AbortSignal.timeout(ms)` (bound in
      `package:web` 1.1.1), which takes no Dart callback.

    Chromium tests for the lock wrapper are in 8.3; the VM fakes cannot
    show this bug.
- `LocalFolderTransport extends http.BaseClient`: request decode, the
  folder lock (shared for GET, exclusive otherwise, 6.2 R1), dispatch,
  response encode. Responses carry `content-type: application/json` and
  `x-notechondria-backend: local-folder`. While the folder state is
  `opening` it holds requests; outside `active` it answers 503 (2.8
  rule 4). Deadlines run from request start (2.9).
- `LocalBackendRouter` and handlers per area (notes, trash, courses,
  planner, calendar, attachments, settings and auth, GitHub).
- `StorageModeClient extends http.BaseClient`: routes by storage mode
  (2.8). The (b) handlers make their third-party calls (GitHub, calendar
  URLs) through a separate plain `http.Client` owned by the transport.

Flow: UI action, app method (for example `createNote`), `_post`,
`send()` (logging), `_httpClient.post`, `StorageModeClient`,
`LocalFolderTransport`, router, handler, `FolderFs`, JSON response,
`decode()`, back to the unchanged app code.

Unsupported routes (class (c), section 4) answer HTTP 501 with
`{"detail": "<section 1.8 message>"}`. Folder errors use 501
(unsupported) or 503 (folder unavailable) and never 401 or 403. The
transport ignores the `Authorization` value, because the folder has one
user, so no route answers 401. Every detail contains "—", so
`shapedErrorMessage` passes it through verbatim
(`http_client_internals_mixin.dart:320-321`). No detail may contain any of
the four substrings the session-rejection detectors count:

- the three `docs/AGENTS.md` sentinels, `invalid token`,
  `authentication credentials were not provided`, and `token_not_valid`;
- `session rejected:`, which `shapedErrorMessage` prefixes onto every 401
  body without an em-dash (`:323-324`).

The detectors are editor `frontend/editor_app/lib/core/initial_data.dart:279-290`,
planner `frontend/planner_app/lib/core/initial_data.dart:261-267`, and
portal `frontend/portal_app/lib/core/initial_data.dart:269-275`. Two hits
in one load clear the session, so a stray 401 in folder mode would sign
the user out. A unit test checks every folder detail string against the
four substrings.

### 2.6 How "dashboard for local services" is met

The local backend is the service. It owns IDs, validation, trash, history,
recurrence expansion, search ranking, and activity aggregation, which are
the same responsibilities the Django backend has. The UI keeps calling the
same `/api/v1` contract and only reads and renders responses.

In folder mode no note, course, planner, profile, or settings data goes to
the Notechondria server: every request through the app's HTTP client is
answered in the page (2.8). The requests that still leave the page carry
no folder data: the manual "Check for updates" handshake (2.8 rule 3);
the browser's own loads of absolute `https` image URLs that a note body
or an adopted profile already contains (F32); and the portal's startup
image when the user set it to a remote URL, a per-device preference
(`frontend/portal_app/lib/components/custom_splash_overlay.dart:67-79`,
F63). Class (b) calls go straight to the named third party (GitHub, a
calendar host).

The service lives inside each app's page rather than in a separate
process. Because it speaks the backend contract, the same router could
later run in a localhost daemon or in the desktop build, with the UI
pointed at it through the existing API base URL setting. Whether the owner
meant such a separate process is open question Q1. This design does not
open any network listener.

### 2.7 Changes outside the new module

- Default client and controller, in `_NotechondriaAppState` (editor
  `app_shell.dart:52-53`, planner `:38-39`, portal `:38-39`):

  ```dart
  late final LocalFolderController _localFolder =
      widget.localFolder ?? LocalFolderController.forApp('portal'); // or 'editor', 'planner'
  late final NotechondriaClient _client = widget.client ??
      HttpNotechondriaClient(httpClient: _localFolder.httpClient);
  ```

  - `LocalFolderController.forApp` takes the storage mode from
    `LocalFolderBoot.snapshot` (2.8). Without a snapshot (today's widget
    tests) or on a native build, the mode is `browserOrCloud`.
  - `NotechondriaApp` gains `LocalFolderController? localFolder`, the
    app-level test seam. Folder smoke tests pass a controller built over
    `MemoryFolderPlatform` (8.2) and no `client`, so the production line
    above runs in tests and its inner `http.Client()` resolves to the
    test's recorder (8.5).
  - `_localFolder` goes to `AppShell(localFolder: ...)` (editor `:94`,
    planner `:82`, portal `_buildShell` at `:92-105`) and to the portal's
    `_NoteRoutePage(localFolder: ...)` (`:121`).
  - `main.dart` passes `prepare: LocalFolderBoot.preload` to
    `runGuardedApp` (2.8).

  Each app gets these lines in the phase that ships its option (2.10).
- Portal note route. `_NoteRoutePage` listens to the controller. In
  folder mode, while the folder state is `needsPick`, `needsPermission`,
  or `error`, it shows `LocalFolderReconnectView` instead of its error
  text. When the state becomes `active` and no note is shown, it calls
  `_load()` again (`components/note_route_page.dart:33-53`). A cold
  `#/note/<uuid>` start therefore renders the folder note once the folder
  opens, even when the user has to choose it again first.
- Multipart: replace `request.send()` with `_httpClient.send(request)` at
  the 8 sites in 2.1 (one line each), so uploads reach the transport and
  test clients.
- No base-URL override. The first draft set the base URL to
  `https://local-folder.invalid/api/v1` in folder mode as a fail-closed
  backstop. That is dropped, because it could not hold:
  `_loadInitialData`, `_applyLocalAppSettings`, and `_loadLocalState`
  reset the base URL from `_localSettings['api_base_url']` on every load
  (editor `core/initial_data.dart:19-21`, `core/settings_helpers.dart:50-52`,
  `core/load_local_state.dart:56-58`; planner `:10`, `:39`, `:53`; portal
  `:10`, `:39`, `:50`); `applyAuthPayload` runs both of the first two
  (`app_shell_session_mixin.dart:301-316`); and RFC 6761 only says
  resolvers SHOULD fail `.invalid` names, while an explicit HTTP proxy
  still receives the request. Routing by storage mode (2.8) ignores the
  host, so every `updateBaseUrl` caller can keep pointing the client at
  the saved cloud URL without effect. That saved URL is what the manual
  update check uses.
- Startup budget. `HttpClientInternalsMixin.send` (`:120-124`) applies the
  startup budget only to requests that the `StorageModeClient` sends to
  the network. It asks through a small `LocalRoutingClient` interface
  (`routesLocally(method, uri)`). Requests answered in the page are not
  network calls, so the `frontend/AGENTS.md` rule that startup network
  calls run inside the budget still holds. The transport bounds waiting
  for local requests itself (2.9), but not a disk that stalls inside a
  hold, so this exemption is required, not a convenience.
- `pingBackend` (`ping_backend.dart:24-38`) takes an optional
  `http.Client`. Its three callers pass only `widget.apiBaseUrl`, so
  today `ping` always calls top-level `http.get`: editor
  `modules/settings_build.dart:326`, planner `modules/settings.dart:645`,
  portal `modules/settings.dart:475`. Each `_SettingsPage` gains
  `Future<PingResult> Function()? onPing`, and the call becomes
  `onPing: widget.onPing ?? () => pingBackend(widget.apiBaseUrl)`. The
  shell passes `onPing: () => pingBackend(<api base>, client: widget.localFolder.httpClient)`
  where it builds `_SettingsPage(...)`. `ping` then goes through
  `StorageModeClient`: the local backend answers it in folder mode, and
  the network does otherwise, as today.
- Startup: a `local_folder` step, described in 2.9.
- In folder mode `offline_mode` is ignored and its switches are disabled
  (`frontend/editor_app/lib/modules/settings_pages.dart:254-268`, the
  shared `AppPreferencesCard` `offlineMode` parameter at
  `frontend/notechondria_shared/lib/src/settings/app_preferences_card.dart:50-51`)
  by passing `onOfflineModeChanged: null` (9.3). The learner pages get
  `offlineMode: false` (editor `core/build_helpers.dart:595`, planner
  `app_shell.dart:770`, portal `core/build_page.dart:63`). Offline mode
  would only stop local reads.
- `_persistLocalCache` is skipped in folder mode. Caching folder payloads
  in localStorage duplicates data into a 5 MiB per-origin quota (MDN storage
  quotas) that all apps on the origin share.
- Settings, signed-in block: a shared `LocalFolderStatusCard` (folder name,
  permission state, last scan, folder file counts and bytes from the index
  (F48), Rescan, Reconnect or Choose again, Export, Check
  for updates, Disconnect, and a collapsed "Cloud-only features" list with
  the class (c) messages) replaces the profile/Casdoor/API-key rows. The
  class (c) controls are disabled by passing null callbacks where
  `_SettingsPage(...)` is built: editor `core/build_helpers.dart:599-627`
  and `:746`, planner `app_shell.dart:814-858`, portal
  `core/build_page.dart:119-176`. The settings pages already hide or
  disable a control whose callback is null (editor
  `modules/settings_pages.dart:245`, portal `modules/settings_pages.dart:185`
  and `:649`). So the portal's `settings_pages.dart` (1029 lines, already
  over the cap) does not change, and the planner's `settings.dart` (936
  lines) grows by about 5 lines, the one-line card insert plus the
  `onPing` field (9.3); the card itself lives in the shared package.
- `app_shell_session_mixin.dart`:
  - `_reconcileLocalDataOwner` must not stamp `local_data_owner` for the
    folder payload (it carries `is_local_folder: true`), otherwise a later
    cloud sign-in would treat the browser-local data as foreign
    (`app_shell_session_mixin.dart:404`).
  - `persistSession` is skipped for it, so the editor and portal never
    restore a folder session from localStorage; startup derives it from
    the mode key (2.9).
  - The "Signed in as" message (`:348`) becomes, after a connect,
    "Folder session started: Shared.LocalFolder/pick — using '<name>'; no
    account is used and no data is sent to the Notechondria server." At
    startup it is "Folder session started: Shared.LocalFolder/restore_handle
    — reopened '<name>' from this browser."
  - A new `disconnectFolder()` serves Disconnect (2.10). It clears the
    in-memory folder token before the storage mode switches (2.10 rule 4),
    so no request carrying `Token local-folder` can reach the network.
    `logout()` (`:357-388`) delegates to it when the profile has
    `is_local_folder: true`, so a folder session never reaches
    `authClient.logout` or `clearPersistedSession()` (`:361`, `:378`).

### 2.8 to 2.10 Storage modes, startup, and which apps use the folder

These sections are in
[`local_folder_mode/modes_and_migration.md`](local_folder_mode/modes_and_migration.md):

- 2.8 routing by storage mode: the mode is decided synchronously before
  the first request, from preloaded `SharedPreferences`; in folder mode
  every request through the app client is answered in the page, whatever
  its host; the transport holds requests while the folder is `opening`
  and answers 503 with a 1.8 detail in the other non-`active` states; the
  one passthrough is an unauthenticated `GET /handshake/` for "Check for
  updates";
- 2.9 the `local_folder` startup step: index fast path, splash re-arm,
  the pending paths that complete the pass ("Reconnect" for an expired
  grant, "Choose again" with `folder_id` checks when there is no handle),
  Reconnect outside the startup budget, deadlines measured from request
  start, and folder wording;
- 2.10 which apps use the folder: per-phase opt-in, cloud-session
  precedence, `disconnectFolder()` and its order, and what other tabs
  show.

## 3. Folder layout

### 3.1 Tree

The layout is a superset of the GitHub data-sync layout
(`backend/creators/services/github_sync.py:11-28`,
`docs/integrations/github-sync.md:39-62`), which already follows the
portable-archive rule in `docs/client/editor_app.md:14-18,50-53`
(Markdown for prose, JSON/frontmatter for metadata, media as normal files;
"local folder flows" are listed there as an adapter of the same shape).

```
<chosen folder>/
├── manifest.json               required; see 3.2
├── README.md                   written once at init; never parsed
├── profile/
│   ├── creator.json            same keys as github_sync._profile_files (:116-158)
│   ├── settings.json           {app_settings, app_settings_updated_at}
│   └── skill.md                MCP skill text
├── courses/
│   └── <slug>.json             one per course (github_sync._course_files :160-181, plus color_hue)
├── notes/
│   ├── <stem>.md               YAML frontmatter + Markdown body
│   └── <stem>.meta.json        sidecar: ids, metadata_json, custom_meta, client_draft_id, ...
├── history/
│   └── <note-uuid-hex>/
│       ├── index.json          versions: id, reason, label, created_at
│       └── <version-id>.md     snapshot body
├── planner/
│   ├── events.json             planner events (shape of services.planner_event_payload :182)
│   ├── feeds.json              calendar feeds without raw_ical
│   ├── feeds/<feed-id>.ics     raw iCal of imported or last-fetched feeds
│   ├── sessions.json           note study sessions
│   └── heatmap.json            per-day activity counts
├── assets/
│   ├── avatar.<ext>
│   └── notes/<note-uuid-hex>/
│       ├── cover.<ext>
│       ├── attachments.json    id, uuid, filename, content_type, size_bytes, created_at
│       └── attachments/<sanitized original filename>
├── recycle_bin.json            pointer list, as in the GitHub layout
├── trash/
│   └── notes/<stem>.md + <stem>.meta.json   (sidecar carries deleted_at)
└── .notechondria/
    ├── index.json              derived cache; safe to delete
    ├── import.json             progress of an unfinished archive import (6.2 R4)
    └── journal/<op-id>.json    write-ahead records for multi-file operations (3.4.1)
```

- `<stem>` is `<note-uuid-hex>` for notes the app creates, the same name
  `github_sync._note_files` uses (`:184-242`). Notes added by hand with any
  file name are adopted: the app writes a sidecar next to the file and
  never renames it. Two files that claim one UUID are handled in 3.7.
- Attachments keep their original (sanitized) file names so a user can
  find them in a file manager. The GitHub layout uses
  `attachments/<attachment-uuid>.<ext>` (`github_sync.py:282-286`); the
  GitHub push in folder mode maps names, and the backend restore script
  does not restore assets anyway (`backend/scripts/github_sync_restore.py:21-24`).
- Chrome's write swap files (`<name>.crswap`, 3.4) can appear next to any
  file while it is written. Nothing in the app reads, counts, exports, or
  deletes them.
- Debug logs and per-device preferences (theme, locale, API base URL, the
  portal startup image) stay in browser storage. They describe the
  device, not the data (decision D2, section 10). The folder settings
  handler drops these keys from every `PATCH /settings/` and never
  returns them, so the reused settings push cannot write the cloud API
  URL into `profile/settings.json` (F08).

### 3.2 File formats

- `manifest.json`:
  `{"format": "notechondria-folder", "layout_version": 1, "folder_id": "<uuid>", "created_at": "<RFC 3339>", "created_by_app_version": "0.1.NNN", "id_counters": {"course": 0, "note": 0, "version": 0, "session": 0, "event": 0, "feed": 0, "attachment": 0}, "github_sync_schema_version": 1}`,
  plus `restored_from_folder_id` after a `.nchron` restore (3.3). Each
  counter holds the last ID issued; the rules are in 3.7.
  The app refuses a folder whose `layout_version` is newer than it
  supports: "Folder not opened: Shared.LocalFolder/scan — manifest.json
  layout_version 2 is newer than this build supports (1). Update the app."
- Note `.md`: frontmatter keys follow `github_sync._note_files`
  (`title`, `uuid`, `course_slug`, `is_public`, `editor_mode`,
  `last_edit`, `date_created`) using the same quoted-scalar subset it
  writes. On read, `title`, `course_slug`, `is_public`, and the body are
  authoritative, so a user can edit them in any editor. Other keys are
  regenerated on write. Custom meta is read from the sidecar only, because
  `github_sync` spreads custom keys into the frontmatter after the system
  keys (`:200-209`) and a custom key could shadow a system key.
- Note `.meta.json`: `schema_version`, `id`, `uuid`, `sharing_id`,
  `metadata_json`, `custom_meta`, `client_draft_id`, `note_type`,
  `source_note_uuid`, `cover_image_url` (the sidecar fields of
  `github_sync.py:224-241`), plus `description`, `word_count`, and the
  `md_size` and `md_last_modified` seen at the last write (used in 3.8).
- `planner/events.json` and `planner/feeds.json` records may carry
  `client_local_id`, the browser-local ID they were pushed from (7.1).
- Every JSON file carries `schema_version: 1`, as `github_sync` does.
- Markdown links to attachments are stored on disk as relative paths
  (`../assets/notes/<hex>/attachments/<name>`), so the file renders in
  ordinary Markdown viewers. The note codec rewrites them to the
  `nc-folder:` scheme on read and back on write (3.6).

### 3.3 Interchange with `.nchron` (export format v1) and GitHub sync

The v1 archive is a dump of `_LocalAppStore` buckets
(`docs/export_format_v1.md:8-29`; writer
`frontend/notechondria_shared/lib/src/utils/local_archive.dart:135-246`).
The folder is shaped like the server data instead. Two rules make them
interchangeable:

1. **Folder to `.nchron`.** The export writes the normal v1 bucket files,
   derived from the folder (`drafts.json` holds every live note as a local
   draft with `client_draft_id = fld_<uuid-hex>`, `courses.json` the
   courses, `planner_events.json` and `calendar_feeds.json` the planner
   data, `attachments/<client-id>/<file>` the bytes). It also adds an
   optional `folder/` subtree with a verbatim copy of the folder, minus
   `.notechondria/` and `*.crswap`. `readLocalArchive` builds a name map
   and looks up only known entries (`local_archive.dart:273-275`), so v1
   readers ignore `folder/`, and `docs/export_format_v1.md:39-43` allows
   extra optional files without a version bump (decision D3). The copy
   repeats attachment bytes that the v1 `attachments/` entries already
   hold, so attachment-heavy archives are about twice as large.
2. **`.nchron` to folder.** If `folder/` is present, restore it verbatim
   into an empty folder (lossless round trip), with one exception: the
   restore writes a new `folder_id` and keeps the original as
   `restored_from_folder_id`. A restored folder therefore never shares a
   lock name or a remembered-handle key with its source (3.7). Otherwise
   map buckets to records the way the post-login push does (section 7.1).
   Either way the import runs in chunks and writes `manifest.json` last
   (6.2 R4).

So folder, zip, folder is lossless; browser-local, zip, folder keeps
everything browser-local mode has; folder, zip, browser-local keeps notes,
courses, and planner data but drops history and sessions, which
browser-local mode does not model. Attachments on that last path are U16:
the base64-to-`LocalAttachmentStore` move runs once per browser
(`frontend/editor_app/lib/core/local_persist.dart:51-55`), so imported
bytes may stay in the localStorage drafts bucket.

Because the folder is a superset of the GitHub data-sync layout, a cloned
data-sync repository can be opened as a folder (Phase 4 "adopt" action,
ID rules in 3.7), and the folder can be pushed to GitHub with the same
layout (feature F49).

Two doc-versus-code differences in `docs/export_format_v1.md` should be
fixed when the bridge lands: the collision suffix is `__$i` in code
(`local_archive.dart:179`) but `-<index>` in the doc (`:96`), and the doc
says import first wipes local state (`:151-152`) while the editor import only
replaces six buckets (`frontend/editor_app/lib/core/local_archive_io.dart:178-200`).

### 3.4 to 3.8 Storage rules

These sections are in
[`local_folder_mode/storage_rules.md`](local_folder_mode/storage_rules.md):

- 3.4 writes: replace-on-close, swap files, and the write-ahead journal
  with its roll-forward rules and crash tests (3.4.1);
- 3.5 delete and trash semantics matched to the backend, including the
  empty-trash cascade and comment privatization;
- 3.6 attachments and media: the `nc-folder:` scheme, the folder-aware
  image provider and builder (including the planner and portal note
  viewers), and promotion failures;
- 3.7 IDs: counters, duplicate identities, adopt, and folder identity;
- 3.8 index, external and concurrent edits, retention, and rescans.

## 4. Feature matrix

The full matrix is in
[`local_folder_mode/feature_matrix.md`](local_folder_mode/feature_matrix.md):
4.1 lists the 66 method and path pairs the apps call with their
folder-mode handling, 4.2 classifies 63 features (F01 to F63), and 4.3
gives the counts. Result: 44 features work fully locally (a), 5 call a
third party from the browser (b: F32 remote images, F42 CORS-enabled
calendar URLs, F49 GitHub data-sync push, F51 course repo bind and import,
F52 course repo sync), and 13 need a server (c: F01 Casdoor SSO, F02
email/password login, F03 account linking, F04 registration and reset,
F16 course subscriptions, F17 course transfer, F26 cross-user search, F28
other users' shared notes, F29 public sharing, F43 calendar URLs without
CORS, F45 public discovery, F50 GitHub App install, F53 MCP endpoint).
F55 (AI/LLM) has no feature today and is not counted. Every (c) has a
server-held secret, server-held accounts, cross-user or public data, or a
connection the browser cannot make as its cause; none is a limit of the
folder. Every (c) row has a 1.8 message and a fallback.

## 5. Secrets

- Credentials are never written to the folder, to a `.nchron` export, or
  to logs. The folder may sit in a cloud-synced directory, and an archive
  is a file users share. `local_archive.dart` strips nothing itself; its
  comment makes stripping the caller's job (`local_archive.dart:67-68`).
- The folder bridge (9.2) applies a key denylist to every JSON object it
  exports (the v1 buckets and the `folder/` copy), to the GitHub push, and
  to every write under `profile/`. Matching rule: keys are compared
  case-insensitively as whole keys, never as substrings.
  - Stripped: the exact keys `token`, `pat`, `secret`, `password`,
    `passphrase`, `authorization`, `cookie`, `credential`, `credentials`,
    `api_key`, and `apikey`, and any key ending in `_token`, `_secret`,
    `_password`, or `_key`. The suffixes cover `access_token`,
    `refresh_token`, `github_token`, `client_secret`, and `private_key`.
  - Exempt: `path` and any key ending in `_path`. `.nchron` attachment
    pointers use `path` (`local_archive.dart:350-355`), and app data also
    uses `source_path` and `git_path`.
  - Test, both directions: a fixture with every key the bridge writes
    today plus the stripped list, nested at several depths. Every
    stripped key must be gone, and `path`, `source_path`, `git_path`,
    `patch`, `pattern`, `tokens_used`, and `keyboard_layout` must
    survive. A new benign key that ends in `_key` fails the test and must
    be added to an explicit exempt list.
- The only (b) features that need a credential are F49, F51, and F52, which
  use a GitHub fine-grained personal access token. F32 and F42 need none.
  F55 does not exist; a future LLM key would use the same store.
- How the user supplies it: in folder mode the GitHub card shows a token
  field and a link to GitHub's fine-grained token page, with the scope the
  App uses today (one repository, Contents read and write, Metadata read;
  `docs/integrations/github-sync.md:33-37`). The token is checked with one
  `GET https://api.github.com/user` before it is kept. Log lines name the
  outcome and never the token, its prefix, or its length:
  - "GitHub token stored for this session: Shared.LocalFolder.GitHub/token
    — GET https://api.github.com/user accepted it as '<login>'; it is kept
    in memory only." (or "remembered on this browser" with the opt-in)
  - "GitHub token not stored: Shared.LocalFolder.GitHub/token — GET
    https://api.github.com/user answered <status>."
  - "GitHub push unavailable: Shared.LocalFolder.GitHub/token — no
    fine-grained token is set for this session; paste one in the GitHub
    card."
- Where it lives (owner decision Q6):

| Option | Exposure | Cost |
|---|---|---|
| Memory only (recommended default) | Gone on reload; reachable by same-origin script only while the page runs | Re-enter once per session |
| "Remember on this browser": IndexedDB record through `Shared.Credentials` | Readable by any same-origin page (6.1), the same exposure today's cloud session token has in localStorage (`frontend/editor_app/lib/core/local_store.dart:275-285`) | None |
| Remembered and encrypted with a passphrase (WebCrypto PBKDF2 and AES-GCM) | Protects the stored copy at rest; does not stop a same-origin script that hooks the running page | Passphrase prompt each session |
| Desktop build with an OS keychain plugin | Outside the browser | Only with Q11 |

## 6. Security and multi-tab behavior

This section is in
[`local_folder_mode/security_and_tabs.md`](local_folder_mode/security_and_tabs.md):

- 6.1 the shared Pages origin: assessment, mitigations (including no
  handle handoff in v1 on any origin), and the residual risk, which on
  the loopback preview and the Docker self-host includes same-origin
  `/media/` uploads;
- 6.2 one folder for three apps: how each tab opens the folder without a
  handoff, lock rules R1 to R5 (lock modes, read-modify-write from disk,
  journals before reads, bounded holds and chunking, bounded waits), the
  change channel, and the two-transport tests;
- 6.3 permission revoked (including Chrome's background auto-revocation),
  no handle in session-only mode, folder moved or deleted;
- 6.4 rescans and external edits.

## 7. Migration and mode switching

This section is in
[`local_folder_mode/modes_and_migration.md`](local_folder_mode/modes_and_migration.md):

- 7.1 browser-local data into a folder, per app and once per folder:
  courses first with a course-ID map, events and feeds with a
  `client_local_id` insert-if-absent upsert, then drafts through
  `applyAuthPayload`; pushed browser copies stay recoverable for 30 days;
- 7.2 archives, with their own picker button;
- 7.3 switching modes without data loss.

## 8. Testing strategy

This section is in
[`local_folder_mode/testing.md`](local_folder_mode/testing.md):

- 8.1 layers: unit tests (journal crash tests, two-transport concurrency,
  duplicate identities, denylist, detail sentinels, routing table), CI
  smoke tests, OPFS and Web Locks tests in a Playwright/Chromium
  container on a host with at least 16 GB RAM (not GitHub CI unless the
  owner adds a job, Q13), and manual checks;
- 8.2 the `MemoryFolderFs`, `MemoryFolderLocks`, and `MemoryFolderPlatform`
  fakes;
- 8.3 the compile-time OPFS test hook, the lock tests, and where they run;
- 8.4 contract fixtures: hand-written in Phase 1, checked in CI by Q14's
  backend test;
- 8.5 smoke checks, all inside `http.runWithClient` with a failing
  recorder: "revoked mid-session" (zero requests reach the recorder),
  the passthrough, startup bounds, cold portal deep links, "Choose
  again", cloud-session precedence, Disconnect order, and folder images
  in the planner and portal viewers;
- 8.6 manual owner checks on desktop Chrome.

## 9. Implementation phases and file plan

See [`local_folder_mode/implementation_plan.md`](local_folder_mode/implementation_plan.md):
9.1 phases 0 to 5 (spike, foundation, content, planner, interchange and
multi-tab, GitHub), 9.2 about 46 new shared files totaling about 8,500
library lines (largest about 400) with `dart.library.js_interop`
conditional imports so VM tests and the native portal build compile, and
the zone wrapper for each JavaScript callback, 9.3 changed files
with their current sizes against the 1000-line cap, 9.4 the new
`docs/AGENTS.md` rows (`Shared.LocalFolder`, `Shared.LocalFolder.Backend`,
`Shared.LocalFolder.Archive`, `Shared.LocalFolder.GitHub`,
`Shared.Credentials`, `Portal.Sync.Events`, plus a `local_folder` startup
process) and the
`session rejected:` sentinel, and 9.5 the docs to update. No app honors
the shared mode key or shows the option before its routes exist: the
editor from Phase 2, the planner and portal from Phase 3 (2.10 rule 1).
Within a wired app, the GitHub card stays gated until Phase 5.

## 10. Open questions and decisions

### 10.1 Open questions for the owner

Each has a recommended default that the design assumes until answered.

| # | Question | Recommended default |
|---|---|---|
| Q1 | Did "dashboard for local services" mean a separate local service process (a localhost daemon) rather than an in-page backend? | In-page backend (this design). The router speaks `/api/v1`, so a daemon or the desktop build can host it later; no network listener now |
| Q2 | Chrome on Android has had the File System Access API since 132 (BCD; Chrome Q1 2025 post). Keep mobile excluded? | Exclude in v1; Android picker and permission behavior is untested (U14) and `FileSystemObserver` is desktop-only |
| Q3 | On `*.github.io`, persist the folder handle in IndexedDB? | Session only, with an unchecked "Remember this folder" opt-in and the warning in 6.1. Cost: each app asks for the folder once per page load, through "Choose '<name>' again" (2.9) |
| Q4 | Serve the apps from a dedicated origin (custom domain for the Notechondria Pages site)? | Recommended; needs DNS and a base-href change in `frontend-pages.yml`, so it is a separate round. It removes the other Pages projects from the origin; uploaded `/media/` files share an origin only where the app and the backend do, as on the loopback preview and the self-host (6.1, Q19) |
| Q5 | One folder shared by editor, planner, and portal, with an app's live cloud session taking precedence over it (2.10)? | Shared; a live cloud session wins and the app shows the notice |
| Q6 | Where do credentials for (b) features live? | Memory only, opt-in "remember on this browser" (section 5) |
| Q7 | Is a user-supplied fine-grained token acceptable for GitHub in folder mode? | Yes; the GitHub App flow stays cloud-only (F50) |
| Q8 | Add an anonymous backend proxy for calendar URLs without CORS? | No; it reintroduces the server and an open fetch proxy. Use file import |
| Q9 | Version banner in folder mode? | Hidden; a manual "Check for updates" in the status card sends one unauthenticated `GET /handshake/` to the saved cloud URL (2.8 rule 3) |
| Q11 | Folder mode for the native desktop build through `dart:io` (it would also fetch calendar URLs without CORS)? | Follow-up after v1; until then the option is hidden on native builds (1.3) |
| Q12 | Full-fidelity "move folder to cloud"? | Follow-up; interim paths in 7.3 |
| Q13 | Add a CI step that fails if the OPFS test-hook marker is in a release bundle, and a Chrome-platform test job? | Add the grep guard. No Chrome job: OPFS tests run in the Playwright/Chromium container on a host with at least 16 GB RAM (8.3) |
| Q14 | Add a backend test that checks the contract fixtures against the live serializers? | Yes, in Phase 1: it fails on a key or JSON-type difference and uploads the live responses as a CI artifact, so fixtures can be refreshed without a local backend (8.4) |
| Q17 | The apps call `GET /auth/session/` and `POST /auth/logout/`, which the backend does not route (`backend/notechondria/api_urls.py:64-136`). Intended? | Out of scope here; the folder backend answers both. Track separately |
| Q18 | Connecting moves this browser's drafts into the 30-day local recycle bin and its pushed planner items into a 30-day recovery list (7.1). Keep, or leave browser copies visible? | Keep the moves; visible copies would show every pushed portal event twice (`frontend/portal_app/lib/core/build_page.dart:97`) |
| Q19 | On origins that serve both the apps and backend `/media/` (the loopback preview, the Docker self-host), serve uploads so they cannot run as same-origin pages (another host, `Content-Disposition: attachment`, or `Content-Security-Policy: sandbox`)? | Track as separate backend hardening; it also protects the cloud session token the editor and portal keep in localStorage today (6.1) |

### 10.2 Decisions (formerly questions)

| # | Decision | Basis |
|---|---|---|
| D1 (was Q10) | The folder front page includes private notes | It is the user's own dashboard (F44) |
| D2 (was Q15) | Debug logs and per-device preferences (theme, locale, API base URL, portal startup image) stay in browser storage, not the folder. Theme is per device in folder mode, so F08 syncs `app_settings` without these keys | They describe the device, not the data (3.1, F08, F63) |
| D3 (was Q16) | `.nchron` gains the optional `folder/` subtree without a format bump | `docs/export_format_v1.md:39-43` allows extra optional files; cost: attachment bytes appear twice (3.3) |

## 11. Unverified items and sources

Section 11 is in
[`local_folder_mode/unverified_and_sources.md`](local_folder_mode/unverified_and_sources.md):
11.1 lists every item marked **unverified** (U1 to U18, with the ones
closed or no longer needed), and 11.2 the sources checked on 2026-10-17,
including the package archives and specs read for revision 2.

## 12. Revision logs

Section 12 is in
[`local_folder_mode/revision_log.md`](local_folder_mode/revision_log.md),
so that this document stays under the 1000-line cap:

- 12.1 design review 1 (H1, M1 to M10, L1 to L11), kept as written at
  revision 1;
- 12.2 design review 2 (N1 to N16), one line per finding, the items
  resolved differently from the review's wording, and the other changes
  made while verifying.
