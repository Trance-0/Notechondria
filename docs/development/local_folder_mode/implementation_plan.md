# Local folder storage mode: phases and file plan

Part of the design in [`../local_folder_mode.md`](../local_folder_mode.md)
(section 9). Same conventions: repo-root-relative paths, line counts and
`file:line` at HEAD `48988a20` (VERSION 0.1.199). Section numbers are
global: 2.8 to 2.10 and 7 are in `modes_and_migration.md`, 3.4 to 3.8 in
`storage_rules.md`, 4 in `feature_matrix.md`, 6 in `security_and_tabs.md`,
8 in `testing.md`, 11 in `unverified_and_sources.md`, and 12 in
`revision_log.md`.
Sizes are estimates.

## 9.1 Phases

Each phase is one or more normal rounds: VERSION bump,
`docs/versions/<v>.md` plus its `docs/SUMMARY.md` entry, and the
`docs/LLM_CHECK.md` round log (`docs/AGENTS.md`, round-end convention).

An app's wiring lands in the phase that ships its sign-in option: its
`local_folder` startup step, `prepare: LocalFolderBoot.preload` in
`main.dart`, the controller and `StorageModeClient` default client in
`_NotechondriaAppState` with the `NotechondriaApp(localFolder:)` test
seam, the settings gating (including `onPing` and the GitHub card gate),
and its app-level smoke checks. An app without that wiring ignores
the shared mode key (main 2.10 rule 1), so it never calls a folder route
that does not exist yet. Within a wired app, every control whose route
arrives in a later phase or is cloud-only is gated with `cloudOnly(...)`
(`cloudOnlyAction(...)` for a required action callback), the shared
session mixin's helpers; the GitHub card is gated until Phase 5 (9.3),
and F18's template restore stays gated (T7(f)). Both gates were placed
in Phase 1 and stay inert until an app's `localFolder` is set (12.4). The
editor gets its option at the end of Phase
2, the planner and portal at the end of Phase 3. Until an app's option
ships, nothing can write the key for it, so no feature flag is needed
(AGENTS.md 1.2).

0. **Spike, nothing merged.** Resolve U1, U3, U5, U7, U10, U17, and U18
   (section 11.1) in a throwaway build on desktop Chrome.
1. **Foundation.** `FolderFs` (web, memory, stub), JS bindings with the
   per-callback zone wrappers (main 2.5), qualification, handle store,
   the pick flow (the `isSameEntry` copy check, "Choose again" with its
   `folder_id` checks and "Switch to this folder"), lock (shared and
   exclusive modes), controller (with the `opening` and `needsPick`
   states), `LocalFolderBoot` and the `runGuardedApp(prepare:)` hook,
   journal (with `expect` and the replay check), layout and index
   (chunked scans, duplicate identities), note codec, transport (the
   `opening` hold, 503 states, read and write deadlines from request
   start), `StorageModeClient` (routing and the handshake passthrough),
   router, handlers for handshake, settings (with the per-device key
   filter), session, Casdoor config, courses (delete over notes, trashed
   notes, events, and feeds), notes, and trash (with the cascade); the
   secret denylist; the `AuthHub` slot, sign-in option, status card
   (with folder counts and bytes), reconnect view, and banners. The
   startup-budget condition in `HttpClientInternalsMixin.send` and
   `disconnectFolder()` in the session mixin. Behavior-preserving fixes
   for all three apps: the multipart `_httpClient.send(request)` sites
   and the optional `pingBackend` client. Editor smoke checks at the
   client level: the editor's real `HttpNotechondriaClient` over the
   controller's `StorageModeClient` and `MemoryFolderPlatform`, inside
   `http.runWithClient`, with no app wiring, so the shell cannot yet read
   the mode key. The Chromium lock tests in
   `test/local_folder_opfs_test.dart` (8.3). Hand-written fixtures for
   these routes and Q14's backend contract test (8.4). No app wiring in
   any app. Phase 1 decisions (design review 3 T7): (a) one session-key
   table keyed by app id, `kAppSessionKeys` in `local_folder_boot.dart`;
   (b) `decideStorageMode` takes `isWeb` from the `LocalFolderPlatform`
   that `forTest` receives; (c) the session mixin reaches the controller
   through an abstract `LocalFolderController? get localFolder` that each
   shell implements (null until its wiring phase), a one-line app edit
   allowed in Phase 1; (d) the `external_edit`/`concurrent_edit` snapshot
   writer and the two-pool prune are Phase 1 (`folder_snapshots.dart`);
   (e) `.notechondria/index.json` is a derived cache with
   `schema_version` 1, `layout_version`, `folder_id`, `generated_at`, and
   per-path entries (schema in `folder_index.dart`), and any other index is
   ignored and rescanned; (f) F18 template restore answers 501 in folder
   mode and its callback is gated with `cloudOnlyAction(...)`, so the GitHub card
   is not the only gated control; (g) a granted handle without
   `manifest.json` is `error` with "Folder not opened:
   Shared.LocalFolder/scan — '<name>' has no manifest.json (<cause>) ...";
   (h) a lock wait cut short by the request deadline answers with the 2.9
   deadline message ("waiting for the folder lock"), and only a full 5 s
   wait uses R5's; (i) in `disconnected`, a GET gets "Folder data not
   loaded: Shared.LocalFolder/disconnect — '<name>' was disconnected in
   this tab; the app reloads its browser-local data instead."; (j) when
   both 3.8 checks trip on one PATCH, one `external_edit` snapshot is
   taken. Landed in 0.1.200 (the Phase 1a storage core, then Phase 1b),
   with the option hidden in every app; the differences from this text
   are listed in 12.4.
2. **Content.** Attachments, covers, avatar, `folderAwareImageProvider`,
   promotion-failure handling and "Copy browser attachments into the
   folder", history and snapshots (`external_edit`, `concurrent_edit`, in
   their own pool), sessions, search port, front page. Editor wiring (as
   listed above) and its app-level smoke checks. Show the option in the
   editor.
3. **Planner.** Events and recurrence, deadlines, week view, heatmap,
   calendar import, URL fetch with the CORS fallback, the
   `client_local_id` upsert, and the connect-time push of browser-local
   courses, events, and feeds with the recovery list (main 7.1). Planner
   and portal wiring (as listed above), the `sizedImageBuilder` line in
   both note viewers, the portal's `_NoteRoutePage` controller and
   reconnect view, and their smoke files. Show the option in the planner
   and portal.
4. **Interchange and multi-tab.** `.nchron` bridge (new `folder_id` on
   restore, chunked import), change channel, `FileSystemObserver` and
   focus rescans, "adopt a GitHub data-sync clone". No handle handoff
   (main 6.2).
5. **GitHub (b).** Credential store and token-based status, repos, push,
   and course repo bind and import. The GitHub card's `cloudOnly(...)`
   gate is replaced by the token-based card in folder mode.

## 9.2 New files

All under `frontend/notechondria_shared/lib/src/local_folder/` unless the
path says otherwise. Web-only files are selected with
`if (dart.library.js_interop)` against a stub, so VM tests and the native
portal build compile (dart.dev recommends this condition over
`dart.library.html`).

| File | Purpose | Lines | Phase |
|---|---|---|---|
| `folder_fs.dart` | `FolderFs` interface and error types | 90 | 1 |
| `folder_fs_stub.dart` | Non-web stub; every call reports "unsupported" | 30 | 1 |
| `folder_fs_web.dart` | File System Access implementation over `package:web` | 320 | 1 |
| `js_bindings_web.dart` | `@JS` extension types for what `package:web` 1.1.1 lacks: `showDirectoryPicker`, `queryPermission`, `requestPermission`, async `values()`, the `mode` member of the `createWritable` options, `Navigator.userAgentData`, and `FileSystemObserver`; plus the two zone helpers of main 2.5, `bindListener` (guarded, for void listeners) and `bindLockCallback` (non-guarded, returns the operation's promise) | 170 | 1 |
| `folder_fs_memory.dart` | In-memory fake with injectable failures, `revoke()`/`grant()`, and crash points | 200 | 1 |
| `memory_platform.dart` | `MemoryHandleStore`, `MemoryFolderPicker`, and the `MemoryFolderPlatform` bundle for `LocalFolderController.forTest` (8.2) | 120 | 1 |
| `qualification.dart`, `qualification_web.dart` | Probe and gap messages (main 1.2, 1.3) | 70 + 90 | 1 |
| `handle_store.dart`, `handle_store_web.dart` | Remembered handle in IndexedDB via `package:web`, since `idb_shim` storing a raw JS handle is **unverified** (U2) | 20 + 110 | 1 |
| `folder_pick_flow.dart` | "Choose again": the `folder_id` checks, the two refusals, and "Switch to this folder" (2.9); the copy check with `isSameEntry` and the remembered-handle probe (3.7) | 200 | 1 |
| `folder_lock.dart`, `folder_lock_web.dart` | Web Locks wrapper: shared and exclusive modes, `AbortSignal.timeout(min(5 s, time left))`, the grant callback through `bindLockCallback`, handling of the released promise, hold-time logging; in-process `MemoryFolderLocks` for tests (6.2) | 80 + 140 | 1 |
| `local_folder_boot.dart` | `LocalFolderBoot.preload` for `runGuardedApp(prepare:)`, the snapshot, and `decideStorageMode` with each app's session keys (2.8) | 90 | 1 |
| `local_folder_controller.dart` | Storage mode, folder state machine (including `opening` and `needsPick`), connect, reconnect, choose again, switch, disconnect in the order of 2.10 rule 4, scan scheduling, captured zone, `httpClient` (the app's `StorageModeClient`), the busy line, "Use the connected folder", the remember choice, the in-memory index updates, the unverified entries of a stored index, the changes made during a scan, and the coalesced `index.json` flush (12.5) | 892 | 1 |
| `folder_layout.dart` | Paths, manifest, ID counters and their raises | 180 | 1 |
| `folder_journal.dart`, `folder_journal_record.dart` | Write-ahead records with `expect`, ordered apply, removals last, roll-forward with re-check and the replay external-edit check (3.4.1); the record format and op ids are in their own file, re-exported | 230 | 1 |
| `note_codec.dart` | Frontmatter, sidecar, link rewriting | 260 | 1 |
| `folder_index.dart` | Read-only cache, `.notechondria/index.json` (schema 2: note summary fields, 12.5), the entries of note bodies and sidecars, `withChanges` and `IndexChangeLog` for the in-memory updates (12.5) | 501 | 1 |
| `transport.dart` | `LocalFolderTransport extends http.BaseClient`: JSON and multipart decode, lock mode per method, the `opening` hold, 503 states, read and write deadlines from request start (2.9), `scrubSessionSentinels` on every detail it assembles and `scrubRouteDetail` on every 404 and 501 (2.5, 12.5), the in-memory index entries of each write, binary writes for uploads (12.6), response; only lost access changes the folder state (12.4) | 382 | 1 |
| `storage_mode_client.dart` | `StorageModeClient` and `LocalRoutingClient`: mode routing and the handshake passthrough (2.8), `runCloudVersionCheck(apiBaseUrl, body)` carrying the saved URL, and `checkCloudVersion` for the status card, which counts a handshake this page answered as not checked (12.5) | 183 | 1 |
| `secret_denylist.dart` | Whole-key denylist with suffixes and `*_path` exemption (main 5) | 50 | 1 |
| `router.dart` | `(method, path)` table, `/api/v1/` segment matching, and the 501/404 fallbacks, whose details pass `scrubRouteDetail` (sentinels and the editor's deep-link markers, T2); the handler context interface, with the index and its unverified entries | 313 | 1 |
| `handlers/records.dart` | Course, note, profile, and recycle-bin records, `IndexedNote`, and the serializer-shaped payloads the handler files share (12.4, 12.5) | 431 | 1 |
| `handlers/lookup.dart` | Index-backed note lookups with one re-read each, the listing refresh for notes the index lacks and for stored entries not yet compared with the disk, the sidecar check on re-read, the body re-stat of course delete, the write lookups' skip rule, batched reads (6.2 R2, R3; 12.5) | 220 | 1 |
| `handlers/auth_settings.dart` | Handshake, settings with the per-device key filter (F08) and the multipart avatar (F09, 12.6), session (shape in 8.4), logout, Casdoor config | 248 | 1-2 |
| `handlers/courses.dart` | Course routes; chunked course delete over notes, trashed notes, events, and feeds, after a stat of every note body (3.5, 12.5) | 318 | 1 |
| `handlers/notes.dart` | Note and uuid routes, the 3.8 snapshot check (T7(j)), comment privatization on delete, the `note_search_score` ranking and the heatmap row of each created note (12.6) | 410 | 1-2 |
| `handlers/trash.dart` | Trash list, restore, empty trash with the cascade (3.5) | 147 | 1 |
| `handlers/history_sessions.dart` | History, snapshots, version restore with a `before_restore` snapshot, sessions (list, start, update), retention in two pools (3.8) | 304 | 2 |
| `handlers/attachments.dart` | Attachments (id and uuid routes), covers, the avatar file, file-name sanitizing, the backend's size caps (3.6, 12.6) | 298 | 2 |
| `search_score.dart` | Port of `note_search_score` including a `SequenceMatcher` ratio (autojunk on, no junk), checked against CPython `difflib` values (12.6) | 123 | 2 |
| `handlers/activity.dart` | Front page and heatmap (Phase 2, 12.6); week view (Phase 3) | 174 | 2-3 |
| `handlers/planner.dart` | Events, recurrence, deadlines, `client_local_id` upsert | 400 | 3 |
| `handlers/calendar.dart` | Feeds, iCal storage, URL fetch, URL normalization, `client_local_id` upsert | 280 | 3 |
| `pushed_items_store.dart` | Per-app 30-day recovery list for pushed planner items (main 7.1) | 80 | 3 |
| `folder_archive_bridge.dart` | Folder and `.nchron` in both directions, new `folder_id` on restore, chunked import | 340 | 4 |
| `change_channel.dart`, `change_channel_web.dart` | `BroadcastChannel`: the connect, disconnect, and switch messages (Phase 1, for the 2.10 rule 5 banners and the 2.9 switch notice), then change messages, `FileSystemObserver`, and focus rescans (Phase 4). No handle handoff (6.2) | 20 + 190 | 1, 4 |
| `github_token_client.dart`, `handlers/github.dart` | `api.github.com` calls and the GitHub routes | 260 + 220 | 5 |
| `credential_store.dart`, `credential_store_web.dart` | Memory and opt-in IndexedDB credential store | 80 + 90 | 5 |
| `../components/local_folder_sign_in_option.dart` | Option widget for `AuthHub`, notice dialog, gesture order (main 1.3); English text until Phase 2 (12.4) | 265 | 1 |
| `../components/local_folder_status_card.dart` | Settings card: folder counts and bytes (F48), Rescan, Reconnect, Check for updates, Disconnect, cloud-only list, busy and precedence lines; Export with the Phase 4 bridge | 244 | 1, 4 |
| `../components/local_folder_reconnect_view.dart` | Startup reconnect view with "Reconnect" and "Choose again", the refusal messages with "Switch to this folder", and the one-line banners (main 2.10 rule 5) | 245 | 1 |
| `../utils/folder_aware_image.dart` | `folderAwareImageProvider` (`FolderImage` for `nc-folder:`, `NetworkImage` otherwise) and `folderAwareSvg` (`SvgPicture.memory` or `.network`, T4); reads only under `assets/`. Adds `flutter_svg` to the shared pubspec (12.6) | 265 | 2 |
| `folder_snapshots.dart` | History index, the snapshot writer (its plans also serve the Phase 2 snapshot and restore routes), and the two-pool prune (3.8), moved into Phase 1 by T7(d) | 277 | 1 |
| `folder_identity.dart`, `folder_scanner.dart` | The scan of `folder_index.dart`, split out: duplicate identities and adoption as journaled fixes (3.7), and the paged scan with the R4 re-check | 334 + 269 | 1 |
| `folder_messages.dart` | Every 1.8 message of the module, the session-sentinel check, `scrubSessionSentinels`, and `scrubRouteDetail` (2.5) | 514 | 1 |
| `local_folder_platform.dart` | `LocalFolderPlatform` and `FolderPicker`, the seam `forTest` and the web check use (T7(b)); `folder_fs_stub.dart` stubs the whole platform, so one conditional import pair serves fs, picker, handle store, locks, channel, and probe | 46 | 1 |
| `frontend/notechondria_shared/lib/local_folder_testing.dart` | Exports the memory fakes for tests only | 15 | 1 |
| `frontend/{editor,planner,portal}_app/lib/core/local_folder_connect.dart` | Per-app startup step, precedence, connect push (token set before the course push, main 7.1); the callback gate is the shared mixin's `cloudOnly(...)` (12.4) | 90, 180, 160 | 2, 3, 3 |
| `frontend/notechondria_shared/test/local_folder/*.dart` | Unit tests incl. `folder_journal_test.dart` and `concurrency_test.dart`, each file under 500 lines | 1,700 total | 1-5 |
| `frontend/notechondria_shared/test/local_folder_opfs_test.dart` | Chromium OPFS and Web Locks tests (8.3); run in the 16 GB container, not in CI | 300 | 1, 2, 4 |
| `frontend/notechondria_shared/test/local_folder_opfs_timing_test.dart` | Chromium timing check over 2,000 OPFS notes (8.3, 12.5); same container, not in CI | 230 | 1 |
| `frontend/notechondria_shared/test/fixtures/api_v1/*.json` | Hand-written from the serializers, each with `_source` (8.4) | n/a | 1-3 |
| `backend/notes/test_api_contract.py` | Q14's CI recorder: compares each fixture with the live response and writes the responses for the artifact (8.4) | 200 | 1 |
| `frontend/{editor,planner,portal}_app/test/local_folder_smoke.dart` | Smoke checks inside `http.runWithClient` (main 8.5) | 260 each | 1-3 |

Shared library code totals about 8,500 lines in 46 files, of which about
335 are the test fakes and their export; the three per-app connect files
add about 430. The largest file is about 400 lines.

Zone wrapper per JavaScript callback (main 2.5):

| Callback | File | Wrapper | Why |
|---|---|---|---|
| `navigator.locks.request` grant callback | `folder_lock_web.dart` | `Zone.current.bindUnaryCallback<JSPromise<JSAny?>, Lock?>` (non-guarded), in the requesting zone; the body runs the operation in a try/catch, completes the caller's `Completer`, and returns that `Future<void>` as `.toJS` | The lock is held until the returned promise settles; a `void` return releases it in an upcoming microtask (Web Locks spec 2.4) |
| `BroadcastChannel` `onmessage` (changes, connect, disconnect, switch) | `change_channel_web.dart` | the captured zone's `bindUnaryCallbackGuarded<MessageEvent>` | Void listener; an error reaches `runGuardedApp`, and a refresh never runs in a startup budget |
| `FileSystemObserver` callback | `change_channel_web.dart` | the captured zone's `bindBinaryCallbackGuarded` (records, observer) | Void listener with two arguments |
| `focus` and `visibilitychange` listeners | `change_channel_web.dart` | the captured zone's `bindUnaryCallbackGuarded<Event>` | Void listeners |
| Lock-wait timeout | `folder_lock_web.dart` | none: `AbortSignal.timeout(ms)` | No Dart callback |
| Picker, permission, and file promises | `folder_fs_web.dart`, `folder_pick_flow.dart` | none: `JSPromise.toDart`, awaited in Dart | The continuation is a Dart future, already bound to the awaiting zone |
| IndexedDB request `onsuccess`, `onerror`, `onupgradeneeded`; transaction `oncomplete`, `onerror`, `onabort` (T5) | `handle_store_web.dart` (Phase 1), `credential_store_web.dart` (Phase 5) | the captured zone's `bindUnaryCallbackGuarded<Event>` (`bindListener`) | Void listeners. Bodies only complete a `Completer`, except `onupgradeneeded`, which creates the object store synchronously, because the upgrade transaction is active only while that event is dispatched |

## 9.3 Changed files

Current sizes matter because of the 1000-line cap (AGENTS.md 1.6).

| File (current lines) | Change | Net |
|---|---|---|
| `frontend/notechondria_shared/pubspec.yaml` | Add `web: ^1.1.1` as a direct dependency (locked transitively today), and raise the SDK floor to `>=3.4.0` so the hand-written bindings can use extension types (`web` 1.1.1 itself needs `^3.4.0`; the lock already resolves Dart `>=3.10.3`) | +1, 1 changed |
| `frontend/notechondria_shared/lib/notechondria_shared.dart` (123) | Exports after the `local_attachment_store` block (`:57-62`) | +14 |
| `frontend/notechondria_shared/lib/src/components/auth_dialogs.dart` (444) | `localFolderOption` slot | +15 |
| `frontend/notechondria_shared/lib/src/http/http_client_internals_mixin.dart` (407) | Skip the startup budget for requests a `LocalRoutingClient` answers locally (`:120-124`, main 2.7) | +6 |
| `frontend/notechondria_shared/lib/src/app_shell/app_shell_session_mixin.dart` (451) | Folder payload: skip the owner stamp and `persistSession`, the 1.8 folder-session messages, `disconnectFolder()`, and the `logout()` guard (main 2.7) | +40 |
| `frontend/notechondria_shared/lib/src/utils/ping_backend.dart` (76) | Optional `http.Client` | +5 |
| `frontend/notechondria_shared/lib/src/startup/startup_guard.dart` (202) | Optional `prepare` callback, awaited inside the zone after `ensureInitialized()` and the error handlers, and before `launch()` (`:25-40`, main 2.8); done in 0.1.200, unused until an app's wiring | +8 |
| `frontend/notechondria_shared/lib/src/components/note_cover_image.dart` (205) | Use `folderAwareImageProvider` at `:53` | +2 |
| `frontend/notechondria_shared/lib/l10n/app_en.arb` (694), `app_zh.arb` (554) | About 45 strings each; moved to Phase 2, when the editor shows the option (12.4) | +90 each |
| `frontend/editor_app/lib/app_shell.dart` (824), `frontend/planner_app/lib/app_shell.dart` (932), `frontend/portal_app/lib/app_shell.dart` (882) | Controller owner (main 2.5, 2.7): `NotechondriaApp.localFolder`; in `_NotechondriaAppState` the `_localFolder` field next to `_client` and the `_client` default over `_localFolder.httpClient` (editor `:52-53`, planner `:38-39`, portal `:38-39`); `AppShell.localFolder`, passed at `home: AppShell(` (editor `:94`, planner `:82`) and in the portal's `_buildShell` (`:92-105`); portal only: `_NoteRoutePage(localFolder: ...)` at `:121`. Phase 1 (0.1.200) added only `LocalFolderController? get localFolder => null` to each `_AppShellState` (T7(c), +3 each) | +9 each (portal +10) |
| `frontend/planner_app/lib/app_shell.dart` (932, same file) | Folder gating where the pages are built: `offlineMode: false` for the learner page (`:770`), and in `_SettingsPage(...)` (`:814` onward) the Casdoor, login, API-key, and pull-cloud callbacks (`:814-858`) and `onOfflineModeChanged` (`:858`) wrapped in `cloudOnly(...)`, with the folder Disconnect passed as `onLogout`; `githubSyncCardBuilder` (`:897`) wrapped in `cloudOnly(...)` until Phase 5; `onPing` passed (main 2.7). Done in Phase 1, inert: the GitHub builder and `onRestoreTemplateCourses: cloudOnlyAction(...)` (T7(f)) | +12 |
| `frontend/editor_app/lib/core/build_helpers.dart` (855) | The same gating: learner `offlineMode` at `:595`, `_SettingsPage(...)` callbacks at `:599-627`, `onOfflineModeChanged` at `:746`, `githubSyncCardBuilder` at `:696` (until Phase 5), `onPing`. Done in Phase 1, inert: the GitHub builder and the template restore | +14 |
| `frontend/portal_app/lib/core/build_page.dart` (277) | The same gating: learner `offlineMode` at `:63`, `_SettingsPage(...)` at `:119-176` (`onOfflineModeChanged` at `:163`), `githubSyncCardBuilder` at `:240` (until Phase 5), `onPing`. Done in Phase 1, inert: the GitHub builder and the template restore | +14 |
| `_SettingsPage` in editor `frontend/editor_app/lib/modules/settings.dart` (827), planner `frontend/planner_app/lib/modules/settings.dart` (936), portal `frontend/portal_app/lib/modules/settings.dart` (788) | `Future<PingResult> Function()? onPing` field and parameter; the ping call sites (editor `modules/settings_build.dart:326`, planner `modules/settings.dart:645`, portal `modules/settings.dart:475`) become `onPing: widget.onPing ?? () => pingBackend(widget.apiBaseUrl)` | +2 each; call sites 0 |
| `frontend/portal_app/lib/components/note_route_page.dart` (121) | `localFolder` parameter, a listener, `LocalFolderReconnectView` while the folder is pending, and `_load()` again on `active` (main 2.7) | +15 |
| `frontend/editor_app/lib/core/http_client.dart` (918), `frontend/planner_app/lib/core/client.dart` (961), `frontend/portal_app/lib/core/client.dart` (865) | `_httpClient.send(request)` at the multipart sites; done in 0.1.200 | 0 |
| `frontend/*/lib/core/bootstrap.dart` (285, 244, 366) | The `local_folder` step, splash re-arm on progress, skipped steps in folder mode, folder labels (main 2.9) | +25 each |
| `frontend/*/lib/main.dart` (93, 78, 84) | `part 'core/local_folder_connect.dart';` and `prepare: LocalFolderBoot.preload` in `runGuardedApp(...)` | +2 each |
| `frontend/*/lib/core/initial_data.dart` (339, 314, 325) | Treat `offline_mode` as false in folder mode | +3 each |
| `frontend/*/lib/core/local_persist.dart` (91, 28, 27) | Skip `_persistLocalCache` in folder mode | +2 each |
| `frontend/*/lib/core/helpers.dart` (954, 466, 510), `frontend/*/lib/components/avatar.dart` (161, 92, 110), `frontend/editor_app/lib/modules/settings_build.dart` (455), `frontend/portal_app/lib/modules/settings_build.dart` (515) | `folderAwareImageProvider` at the sites in main 3.6 | +1 to +2 each |
| `frontend/planner_app/lib/components/note_viewer.dart` (138), `frontend/portal_app/lib/components/note_viewer.dart` (154) | `sizedImageBuilder: _localAttachmentImageBuilder` on `MarkdownBody` (`:116`, `:122`) | +1 each |
| Settings entry points: editor `settings_build.dart:129-136`, planner `settings.dart:445-450` (936), portal `settings_build.dart:162-167` | Pass `localFolderOption`; insert the status card | +3 each |
| `frontend/*/test/smoke_test.dart` (244, 767, 314) | Call `registerLocalFolderSmokeTests()`; the editor's since 0.1.200 | +2 each |
| `.github/workflows/backend-tests.yml` | Add the fixture directory to `paths:` (`:16-19`) and an `actions/upload-artifact` step for `backend/build/contract_responses/` (main 8.4); done in 0.1.200 | +6 |

GitHub card gate (until Phase 5). The three build sites pass
`githubSyncCardBuilder: _token != null ? () => GithubSyncExperimentalCard(...) : null`,
and in folder mode `_token` is `local-folder`, so without the gate the
card would load `/integrations/github/status/` in `initState`
(`frontend/notechondria_shared/lib/src/components/mcp_skill_section.dart:249-252`)
and show a 501 before Phase 5 adds the handler. With the builder wrapped
in `cloudOnly(...)`, it is null in folder mode: the editor and planner
fall back to the callback-less card (`modules/settings_pages.dart:787-788`,
`modules/settings.dart:528-529`), whose `_refreshStatus` returns without
a request (`mcp_skill_section.dart:267-271`), and the portal omits the
card (`modules/settings_pages.dart:711`).

Files near the cap:

- `frontend/planner_app/lib/app_shell.dart`: 932 + 9 + 12 = about 953,
  under the cap; 937 after Phase 1. The gate helpers `cloudOnly(...)` and
  `cloudOnlyAction(...)` live in the shared session mixin, not in
  `app_shell.dart`. If the
  implementing round finds the gating needs more lines, it moves the
  `case 3:` `_SettingsPage(...)` builder (`:813-927`) into a new
  `frontend/planner_app/lib/core/settings_page_builder.dart` part in the
  same round, as the editor (`core/build_helpers.dart`) and portal
  (`core/build_page.dart`) already keep theirs outside `app_shell.dart`.
- `frontend/editor_app/lib/core/build_helpers.dart`: 855 + 14 = about 869.
- `frontend/editor_app/lib/core/helpers.dart`: 954 + 2 = about 956.
- `frontend/planner_app/lib/core/client.dart` (961) and
  `frontend/editor_app/lib/core/http_client.dart` (918): line-neutral.
- `frontend/planner_app/lib/modules/settings.dart`: 936 + 3 + 2 = 941.

Files to leave alone: `frontend/portal_app/lib/modules/settings_pages.dart`
(1029 lines, already over the cap; any edit would force a split in the
same round; its switches already go inert on a null callback, `:185`,
`:649`; it builds `StorageUsageCard` at `:793` and omits a null GitHub
card builder at `:711`, so neither the F48 counts nor the GitHub card
gate touch it), `frontend/notechondria_shared/lib/src/components/storage_usage_card.dart`
(the folder counts go to the status card, F48),
`frontend/portal_app/lib/components/custom_splash_overlay.dart`
(the startup image is never an `nc-folder:` URL, main 3.6),
`frontend/editor_app/lib/modules/learner.dart` (962), and the generated
`frontend/notechondria_shared/lib/src/l10n/app_localizations.dart`
(3247 lines; regenerated from the ARB files, already over the cap).

## 9.4 New `docs/AGENTS.md` module rows and sentinel

| Module (dotted) | Surface | Example processes |
|---|---|---|
| `Shared.LocalFolder` | `notechondria_shared` local-folder controller: qualification, picker, permissions, handle store, scan, lock, change channel | `qualify`, `pick`, `connect`, `permission`, `restore_handle`, `scan`, `rescan`, `observe`, `lock`, `read`, `write`, `journal`, `version_check`, `disconnect` |
| `Shared.LocalFolder.Backend` | In-page `/api/v1` implementation (`LocalFolderTransport`, router, handlers) | `route`, `unsupported`, `notes`, `courses`, `planner`, `calendar.fetch`, `attachments`, `settings`, `search`, `front_page` |
| `Shared.LocalFolder.Archive` | Folder and `.nchron` bridge | `import`, `export`, `validate` |
| `Shared.LocalFolder.GitHub` | Token-based GitHub calls from the browser | `token`, `repos`, `push`, `course_import` |
| `Shared.Credentials` | In-browser store for (b) credentials | `store`, `load`, `clear` |
| `Portal.Sync.Events` | portal planner-event sync (`core/settings_actions.dart`, `core/maintenance_actions.dart`) and the connect-time push (main 7.1) | `create`, `toggle`, `edit`, `push` |

Also:

- Add `local_folder` to the processes of the
  `Editor.Startup / Planner.Startup / Portal.Startup` row.
- Add `session rejected:` to the preserved parser sentinels next to
  `invalid token`, `authentication credentials were not provided`, and
  `token_not_valid`. All three detectors count it (editor
  `frontend/editor_app/lib/core/initial_data.dart:284`, planner
  `frontend/planner_app/lib/core/initial_data.dart:266`, portal
  `frontend/portal_app/lib/core/initial_data.dart:274`), and
  `shapedErrorMessage` produces it for every 401 without an em-dash
  (`frontend/notechondria_shared/lib/src/http/http_client_internals_mixin.dart:323-324`).
  No folder message may contain any of the four (main 2.5).
- `Portal.Sync.Events` is already emitted without a row: `create`
  (`frontend/portal_app/lib/core/settings_actions.dart:259`, `:265`),
  `toggle` (`core/maintenance_actions.dart:334-351`), and `edit`
  (`:378-391`). Main 7.1 adds `push`. The planner's 7.1 lines use the
  existing `Planner.Sync.Events` row.
- Two existing gaps in the table, noticed while writing this:
  `Shared.LocalArchive/read` is emitted
  (`frontend/notechondria_shared/lib/src/utils/local_archive.dart:258-296`)
  but has no row, and `Shared.AuthDialog` has a row but no emitter.

## 9.5 Docs to update in the implementing rounds

- `docs/AGENTS.md`: rows and the sentinel above.
- `docs/SUMMARY.md`: entries for this design and its eight parts, next to
  the other `development/` entries (`:38-44`).
- `docs/development/storage_model.md`: add the folder tier to the TL;DR
  table and the frontend storage section.
- `docs/export_format_v1.md`: document the optional `folder/` subtree and
  fix the two doc-versus-code differences (main 3.3).
- `docs/integrations/github-sync.md`: the token path in folder mode and the
  shared layout.
- `docs/deployment/local_preview.md`: recommend the loopback origin for
  folder mode.
- `docs/api/backend_api_spec.md`: refresh against
  `backend/notechondria/api_urls.py`, since the fixtures and handlers treat
  it as the contract (Q14).
- `README.md`, `docs/readme.md`, `frontend/AGENTS.md` ("Current shape"):
  a new storage tier is a material change (AGENTS.md 2.6).
- `docs/TODO.md`: track phases and the planner push items it already lists
  (`docs/TODO.md:400-410`).
- `docs/versions/<v>.md` and `docs/LLM_CHECK.md` each round.
