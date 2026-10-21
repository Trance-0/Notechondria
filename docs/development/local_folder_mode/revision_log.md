# Local folder storage mode: revision logs

Part of the design in [`../local_folder_mode.md`](../local_folder_mode.md)
(section 12). Same conventions: repo-root-relative paths, `file:line` at
HEAD `48988a20` (VERSION 0.1.199). Section numbers are global. 1, 2.1 to 2.7, 3.1 to 3.3, 5, and 10 are in
the main document; 2.8 to 2.10 and 7 in
[`modes_and_migration.md`](modes_and_migration.md); 3.4 to 3.8 in
[`storage_rules.md`](storage_rules.md); 4 in
[`feature_matrix.md`](feature_matrix.md); 6 in
[`security_and_tabs.md`](security_and_tabs.md); 8 in
[`testing.md`](testing.md); 9 in
[`implementation_plan.md`](implementation_plan.md); and 11 in
[`unverified_and_sources.md`](unverified_and_sources.md). Section 12 moved here
from the main document in revision 2, together with section 11 (now in
`unverified_and_sources.md`), so that the main document stays under the
1000-line cap (AGENTS.md 1.6).

## 12.1 Revision log (design review 1)

Review: `.agents/tasks/design-review.json` and `.agents/tasks/design-review.md`
(verdict CHANGES_REQUESTED). This table is kept as written at revision 1.
Where revision 2 changed a resolution, 12.2 says so: the zone binding of
L3 (N2), the bound claim of M3 (N8), and the dedicated-origin handoff of
M10 (N4).

| ID | Resolution | Sections |
|---|---|---|
| H1 | Route by storage mode for any host; transport answers 503 outside `active`; `.invalid` override dropped; one unauthenticated handshake passthrough; revoked-mid-session smoke check | 2.5, 2.6, 2.7, 2.8, 6.3, 8.5 |
| M1 | A live cloud session wins with a 1.8 notice; `disconnectFolder()` never ends a cloud session; precedence smoke check | 2.7, 2.10, 8.5, Q5 |
| M2 | Each app honors the key from the phase that ships its option; cross-tab and Phase 2 display rules | 2.10, 9.1 |
| M3 | Index fast path and splash re-arm; local requests outside the budget, 5 s lock wait and 8 s read deadline; needsPermission pass and out-of-budget Reconnect; folder wording | 2.7, 2.9, 6.2 R5, 8.5 |
| M4 | Roll-forward under the exclusive lock with re-check, removals last, op-id order; shared-lock reads resolve journals first; crash and concurrent tests | 3.4.1, 6.2 R1 R3, 6.4 |
| M5 | Every write re-reads its files and counters from disk under the lock; cache is read-only; chunked holds; two-transport tests | 3.7, 6.2 R2 R4, 8.1 |
| M6 | Duplicate UUID and ID rule with log line; counters above the max seen; adopt keeps unique ids; new `folder_id` on restore; `isSameEntry` copy check | 3.2, 3.3, 3.7 |
| M7 | Planner and portal viewers pass the folder-aware image builder; smoke check | 3.6, 8.5, F31 |
| M8 | Empty trash removes history, assets, and sessions and nulls comment links; delete privatizes comments; both journaled | 3.5 |
| M9 | Courses pushed first with id map; `client_local_id` insert-if-absent; pushed copies move to a 30-day recovery list | 7.1, 3.2, Q18 |
| M10 | Handle handoff off on `*.github.io`; added to the residual risk | 6.1, 6.2 |
| L1 | Re-pinned to `48988a20`: planner `calendar.dart:123-192`, `:195-211`, `:213-227`; planner smoke test 767 lines; F12 create guard `api.py:774-800` | header, 8.5, F12, F41, F42, 9.3 |
| L2 | `session rejected:` added to the sentinel list and to the planned `docs/AGENTS.md` update | 2.5, 9.4 |
| L3 | Binding gaps extended (`mode`, `userAgentData`, `FileSystemObserver`); callbacks bound to the controller's zone | 1.4, 2.5, 9.2 |
| L4 | Whole-key, case-insensitive denylist with suffixes, `path` and `*_path` exempt, two-direction test | 5 |
| L5 | U8, U11, U15 closed; 12-version bound stated; Q10, Q15, Q16 recorded as D1 to D3 | 3.8, 10.2, 11.1 |
| L6 | Folder session and GitHub token messages reshaped to 1.8 | 2.7, 5 |
| L7 | Settings call sites and other missing files added with deltas; planner `app_shell.dart` and editor `build_helpers.dart` stay under 1000; OPFS tests in a container on 16 GB+ hosts | 2.7, 8.1, 8.3, 9.3, Q13 |
| L8 | Picker called from the notice's own button; archive picker has its own button | 1.3, 7.2 |
| L9 | 7.3 reworded around recoverable moves; promotion failures keep `local://` links with a retry action | 3.6, 7.1, 7.3 |
| L10 | `*.crswap` ignored everywhere; background auto-revocation made a routine path | 1.4, 3.1, 3.4, 3.8, 6.3 |
| L11 | F04 message added; F63 startup-image row (a); option hidden on native builds | 1.3, F04, F63 |

Resolved differently from the review's literal wording:

- M4 asked that GET handlers skip paths named by a pending journal. Here
  GET handlers take the lock in shared mode, so they never see an
  operation in progress, and a crash-left journal is rolled forward
  before the read. Skipping applies only when that roll-forward fails
  (6.2 R3). This is stricter than skipping and needs no per-path filter
  in the common case.
- M3 offered a shorter lock wait or running local requests outside the
  budget. The design does both: a one-condition change in `send()` keeps
  local requests out of the budget, and the 5 s lock wait and 8 s read
  deadline keep the bound below 10 s even without that change (2.7, 2.9).
  (Revision 2 withdrew the "even without that change" part; see N8.)
- M6 suggested dropping or remapping server IDs on adopt. Adopt keeps
  them, because a clone holds one account's IDs, which are already unique
  per kind; counters are raised above them, and any real collision falls
  under the duplicate rule (3.7).

## 12.2 Revision log (design review 2)

Review: `.agents/tasks/design-review-2.json` and
`.agents/tasks/design-review-2.md` (verdict CHANGES_REQUESTED: 4 MEDIUM,
12 LOW; H1 and M10 of review 1 partially resolved). Each finding was
checked against the code at `48988a20` before it was resolved.

| ID | Resolution | Sections |
|---|---|---|
| N1 | The mode is decided synchronously before the first widget is built: `runGuardedApp(prepare:)` preloads `SharedPreferences`, and `decideStorageMode` picks folder when the shared key is set and the app has no saved cloud session (same keys as `loadSession`). In folder mode the state starts as `opening`, and the transport holds requests until the folder settles, within the request deadline. One controller owner, `_NotechondriaAppState`, next to `_client`; passed to `AppShell` and the portal's `_NoteRoutePage`, which shows the reconnect view and reloads on `active`. Test seam `NotechondriaApp(localFolder: ...)` over `MemoryFolderPlatform`. Portal smoke check for cold `/note/<uuid>` and `/notes` starts with zero recorder requests and the folder note rendered | 2.5, 2.7, 2.8, 2.9, 8.2, 8.5, 9.1, 9.2, 9.3 |
| N2 | The `locks.request` callback is bound with the non-guarded `Zone.current.bindUnaryCallback<JSPromise<JSAny?>, Lock?>`, runs the operation in a try/catch, and returns its promise; guarded wrappers only for void listeners; wrapper table per callback; Chromium tests in `local_folder_opfs_test.dart` (overlap serializes, a throwing operation releases the lock); manual `navigator.locks.query()` check. Web Locks spec 2.4 note and the Zone signatures re-checked | 2.5, 8.1, 8.3, 8.6, 9.2, 11.2 |
| N3 | New folder state `needsPick` for the no-handle case. "Choose '<name>' again" calls `showDirectoryPicker({id: 'notechondria-folder', mode: 'readwrite'})` first, then checks `folder_id`. A different `folder_id` is refused with a 1.8 message and a "Switch to this folder" action that rewrites the shared key and posts `{op: "switch"}`; a folder without `manifest.json` is refused and left untouched; cancel stays. "Reconnect" keeps `requestPermission` for a restored handle. Cost corrected to once per page load per app in session-only mode. Smoke and manual checks added | 1.3, 2.8, 2.9, 6.1, 6.3, 8.5, 8.6, Q3 |
| N4 | The `BroadcastChannel` handle handoff is dropped from v1 on every origin; each app tab picks or re-grants by itself (a remembered handle often needs no prompt while another tab holds the origin's grant). The 6.2 rationale is corrected, and the residual risk names same-origin `/media/` uploads on the loopback preview and the Docker self-host. Handoff work removed from Phase 4; U13 is no longer needed | 6.1, 6.2, 8.6, 9.1, 9.2, 9.4, Q4, Q19, 11.1 |
| N5 | App-level smoke checks run inside `http.runWithClient(body, () => recorder)` with a recorder that fails on any request but the passthrough, so `request.send()` and top-level `http.*` calls are caught; an `HttpOverrides.global` backstop catches `dart:io` clients created outside the zone | 8.5 |
| N6 | The three `pingBackend` call sites are listed. Each `_SettingsPage` gains `onPing`, and the shell passes a closure over the controller's `StorageModeClient` | 2.7, 9.3 |
| N7 | Reworded: no cookies on a cross-origin API base; on a same-origin base (localhost, 127.0.0.1, the loopback preview) the browser may send the origin's cookies, which carry no authority for the public handshake, since the API authenticates only by header | 2.8 rule 3 |
| N8 | Every deadline runs from request start. The 8 s read deadline covers the `opening` hold, every lock wait including the R3 re-locks, and roll-forward. A 7 s write deadline applies until the write starts. The "even if reverted" claim is withdrawn: the deadlines bound waiting, not a disk that stalls inside a hold | 2.9, 6.2 R5 |
| N9 | Theme stays per device (D2). F08 now syncs `app_settings` minus per-device keys, and the folder settings handler drops `api_base_url`, `theme_preset`, `theme_mode`, `locale`, `offline_mode`, `log_preferences`, the startup-image keys, and `keep_offline_data_on_login` from every `PATCH /settings/` and never returns them | 3.1, F08, D2, 9.2 |
| N10 | Course delete also sets `course_id: null` in `planner/events.json` and `planner/feeds.json` and covers `trash/notes/`, matching the backend's `SET_NULL` on notes, events, and feeds | 3.5, 6.2 R4 |
| N11 | Folder-only snapshot reasons (`external_edit`, `concurrent_edit`) form their own pool with its own 12-version cap, so they never prune a version the backend rule would keep | 3.8 |
| N12 | Folder counts and bytes move to `LocalFolderStatusCard`; `StorageUsageCard` and the portal's `settings_pages.dart` (1029 lines) are unchanged | F48, 3.4, 9.3 |
| N13 | `githubSyncCardBuilder` is wrapped in `_cloudOnly(...)` at the three build sites until Phase 5; with a null builder no GitHub status request is sent | 9.1, 9.3, F49 |
| N14 | `Portal.Sync.Events` row added to 9.4 (the portal already emits `create`, `toggle`, and `edit` without a row) | 9.4 |
| N15 | Journal records carry the pre-op size and `lastModified` (`expect`) of every note body they write or remove; a replay that finds a body matching neither `expect` nor the journaled text saves it as an `external_edit` snapshot first, once per record | 3.4.1 |
| N16 | Fixtures are hand-written in Phase 1 from the serializers and backend tests, with a `_source` key; Q14's backend test is the CI recorder and uploads live responses. The `/auth/session/` shape is derived from `_restoreSession` and `applyAuthPayload` parsing. `frontend/notechondria_shared/test/local_folder_opfs_test.dart` lands in Phase 1. 7.1 sets the in-memory token before the course push. The copy check needs no permission for `isSameEntry` and asks before probing a remembered handle without a grant. `disconnectFolder()` moves the state to `disconnected` and clears the token before the mode switches | 2.10, 3.7, 7.1, 8.3, 8.4, 8.5, 9.2, Q14 |

Resolved differently from the review's literal wording:

- N1 offered a `pending` mode or a synchronous decision. The design uses
  both parts: the mode is decided synchronously, and a separate folder
  state, `opening`, holds requests while the folder is opened. Holding
  (instead of answering 503) is what lets a cold portal deep link render
  the folder note.
- N8 offered a write deadline or dropping the claim. The design adds the
  deadline and also narrows the claim, because a started write cannot be
  cut off safely.
- N11 offered an exemption or coalescing. The design uses separate pools,
  which keeps every automatic snapshot up to its own cap and needs no
  timing rule.
- N15 suggested comparing the body with the pre-op sidecar. The record
  stores the expected size and `lastModified` instead, because a crash
  after step 3's sidecar writes leaves the new sidecar on disk.
- N2 named `Zone.current`; the design binds the lock callback in the zone
  of the request that asked for the lock, which is `Zone.current` at the
  call, and keeps the controller's captured zone for void listeners only.

Also changed while verifying:

- Sections 11 and 12 moved out of the main document into
  `unverified_and_sources.md` and this file, because the revision would
  otherwise have taken the main document past 1000 lines. Nothing was
  deleted; the main document keeps a pointer for each.
- 6.3's "denied" row said the folder becomes "Disconnected", while 2.9
  step 5 said `error`. Both now say `error`, with "Choose '<name>' again"
  and "Use browser-local mode instead".
- The connect, disconnect, and switch messages of the change channel
  move to Phase 1, because the 2.10 rule 5 banners and the 2.9 switch
  notice need them before Phase 4's change messages.
- 9.2's totals are recomputed from the table: about 8,500 shared library
  lines in 46 files (the review summed revision 1's table to about 7,900
  against a stated 7,500).
- 9.3's fallback range for the planner's `case 3:` settings builder is
  corrected to `app_shell.dart:813-927`; the `_SettingsPage(...)` call
  runs to `:927`, past `githubSyncCardBuilder` at `:897`.
- U18 is narrowed to the renderer-crash case: release on tab close is
  specified (Web Locks spec, section 2.6).
- 3.5 records a known difference found while checking N10: the backend's
  heatmap rows reference the note (`HeatmapActivity.note_id`, `CASCADE`,
  `backend/planner/models.py:81-84`), so empty trash lowers its heatmap,
  while the folder's per-day counts do not change.
- Two notes from the review that were not findings: 2.6 now names the
  portal's remote startup image as a request that leaves the page, and
  2.9's folder wording covers the `_initialDataOutcome` log line.

## 12.3 Design review 3, resolved in Phase 1a

Review: `.agents/tasks/design-review-3.json` and
`.agents/tasks/design-review-3.md` (verdict APPROVED, LOW findings T1 to
T8). T1 (Phase 3), T2 (Phase 2), and T4 (Phase 2) stay with their phases.

| ID | Resolution | Where |
|---|---|---|
| T3 | `remember` stored in the shared key, default off on every origin known today; second `needsPick` wording for a missing record; checkbox placement and "Use the connected folder" routing stated | 1.3, 2.8 rule 4, 2.10; `local_folder_boot.dart`, `handle_store.dart`, `folder_messages.dart` |
| T5 | IndexedDB callbacks added to the zone-wrapper table, guarded, with the `onupgradeneeded` exception | 9.2; `handle_store_web.dart` |
| T6 | `flutter test test/local_folder/` runs in `frontend-pages.yml` | 8.1 |
| T7 | (a) to (j) decided in one list | 9.1 Phase 1; (a, b, d, e, g, h, i, j) coded in Phase 1a, (c, f) land with the app wiring and handlers |
| T8 | U18 row, the "mode changes" sentence, and the `backend-tests.yml:16-19` citations | 1.4, 2.8, 8.4, 9.3 |

Phase 1a code review (`.agents/tasks/phase1a-review.json`, P1A-1 to
P1A-6), resolved in the same phase:

| ID | Resolution | Where |
|---|---|---|
| P1A-1 | The replay's `external_edit` snapshot is numbered above the counters the record journals, so it never shares an id with a version the record issued | 3.4.1; `folder_journal.dart`, `folder_snapshots.dart` |
| P1A-2 | Wrong-typed fields in hand-edited sidecars, course files, history indexes, and the manifest read as absent | 3.8; `note_codec.dart`, `folder_index.dart`, `folder_snapshots.dart`, `folder_layout.dart` |
| P1A-3 | The scan's counter raise and identity fixes take the R3 path when roll-forward fails | 3.4.1, 6.2 R3; `folder_scanner.dart`, `folder_identity.dart` |
| P1A-4 | Unreadable records are deleted (now stated); a newer `schema_version` stays and fails roll-forward | 3.4.1; `folder_journal.dart` |
| P1A-5 | `scrubSessionSentinels` on every assembled detail; the 1b transport applies it to handler details too | 2.5; `folder_messages.dart`, `local_folder_controller.dart` |
| P1A-6 | The per-app connect row no longer lists session keys (T7(a)) | 9.2 |

## 12.4 Phase 1b (0.1.200): where the code differs from the design

Phase 1b landed the transport, `StorageModeClient`, router, the Phase 1
handlers, the fixtures and Q14's recorder, the three widgets, and the
plumbing. Where the code and the earlier text disagreed, the code was
kept and the design text changed in the same commit:

| Item | Code (0.1.200) | Where |
|---|---|---|
| T7(c) | Every shell implements `LocalFolderController? get localFolder => null`; the session mixin carries `disconnectFolder()`, the `logout()` guard, the folder session messages, and the skipped `persistSession` and owner stamp | 2.7, 9.1; `app_shell_session_mixin.dart`, three `app_shell.dart` |
| T7(f) and the GitHub gate | The gates are `cloudOnly(...)` and `cloudOnlyAction(...)` on the shared session mixin, not a per-app `_cloudOnly(...)`, and they land in Phase 1 at the three build sites, inert while `localFolder` is null. `onRestoreTemplateCourses` is a required callback whose portal reader is the 1029-line `settings_pages.dart`, so `cloudOnlyAction` keeps the button and answers the 501 message without a request instead of passing null | 9.1, 9.3; editor `core/build_helpers.dart`, planner `app_shell.dart`, portal `core/build_page.dart` |
| New file | `handlers/records.dart`: course, note, profile, and recycle-bin records and the serializer-shaped payloads the four handler files share | 9.2 |
| Passthrough | `runCloudVersionCheck(apiBaseUrl, body)` carries the saved cloud URL as the zone value, because the transport does not know the app's settings; `checkCloudVersion` is the status card's call | 2.8 rule 3; `storage_mode_client.dart` |
| Route details | 501 and 404 details go through `scrubRouteDetail`, which also breaks the editor deep-link markers (`permission`, `forbidden`, `not authenticated`, ` 403 `, `403:`), because they interpolate the request path (T2) | 2.5; `folder_messages.dart`, `router.dart` |
| P1A review LOW | `scrubSessionSentinels` folds each character with `toLowerCase`, as the detectors do, so U+212A KELVIN SIGN no longer slips past it | 2.5; `folder_messages.dart` |
| Errors | Only `NotAllowedError` and a root `NotFoundError` change the folder state (`needsPermission`, `error`); any other `FolderFs` failure of one request answers 500 and leaves the folder open | 2.8 rule 4; `transport.dart` |
| Search | Phase 1 `q` is a substring match with title hits first, and `sort=popular` sorts as `newest`; the `note_search_score` port stays in Phase 2 | F25; `handlers/notes.dart` |
| Course open | F15 answers 200 for the folder's own course with `last_opened_at` in the course file; the backend answers 404 without a subscription, so the route has no fixture | F15; `handlers/courses.dart` |
| Empty trash | One trashed note per chunk (R4 allows batching while the hold stays under 2 s) | 6.2 R4; `handlers/trash.dart` |
| Handshake | `capabilities` keeps the backend's keys; `planner`, `calendar_feeds`, `attachments`, and `mcp` are 0 until their phases | F46; `handlers/auth_settings.dart` |
| UI text | The option, status card, and reconnect view use English constants; the ARB rows of 9.3 move to Phase 2, when the editor shows the option, because `flutter gen-l10n` fails on the existing `activityWeightN` placeholder (`docs/TODO.md`). The status card has no Export and the option no "Start from an archive" until the Phase 4 bridge | 9.3; `components/local_folder_*.dart` |
| Fixtures | Each fixture holds `_source`, `_setup` (`empty`, `course_and_note`, `trashed_note`), the request with `{course_id}`, `{note_id}`, `{note_uuid}` placeholders, `status`, and `body`; `_folder_omits` lists dotted key paths the folder leaves out (F08), and `_backend_route: false` marks session and logout (Q17) | 8.4 |

## 12.5 Phase 1 review follow-ups (after 0.1.200, before Phase 2)

The Phase 1b review (`.agents/tasks/phase1b-review.json`, P1B-1 to
P1B-5) and the open item of the 1a review (P1A-7), resolved before Phase
2 shows the option. The option is still hidden, so no app changes.

| ID | Resolution | Where |
|---|---|---|
| P1B-1 | Handlers locate notes through the in-memory index and re-read only the note they serve or rewrite. Index `schema_version` 2 adds a `summary` to note body and sidecar entries (the fields of the backend's note summary), so the list routes read no note file; a search reads only the bodies its title and description miss, 32 at a time. The list routes, and any lookup that misses, first list `notes/` (and `trash/notes/`) and index only the files the index lacks. This tab's writes update the in-memory index from the text they wrote and a fresh stat, and reach `index.json` through the coalesced flush of L2A-1 below. Chromium, 2,000 notes on OPFS: a single-note GET took 27 ms (21 ms hold) and a PATCH 59 ms (56 ms hold); 0.1.200 answered the same GET with the 8 s deadline's 503 after an 11 s hold. A search took 1.3 s, so it passes the 2 s hold target near 3,000 notes (Phase 2 search port, `docs/development/local_folder_mode/deferred.md`) | 3.8, 6.2 R2 R4, 8.3; `folder_index.dart`, `handlers/lookup.dart`, `handlers/{records,notes,courses,trash}.dart`, `transport.dart`, `local_folder_controller.dart` |
| P1B-2 | `checkCloudVersion` treats an answer carrying `x-notechondria-backend: local-folder` as not checked: "Cloud version not checked: Shared.LocalFolder/version_check — folder mode sends the update check only to an https URL or a loopback http URL, so GET <host>/api/v1/handshake/ was answered in this page and nothing was sent." | 2.8 rule 3; `storage_mode_client.dart`, `folder_messages.dart` |
| P1B-3 | Write lookups of notes and courses ignore the skip set of a failed roll-forward (`lookupSkip`), so `commit` and `writeText` answer `writeBlockedByJournal` instead of a 404 or a second note for the same `client_draft_id` | 6.2 R3; `handlers/lookup.dart`, `handlers/notes.dart`, `handlers/courses.dart` |
| P1B-4 | The transport passes every 404 and 501 detail, router or handler, through `scrubRouteDetail` | 2.5; `transport.dart` |
| P1B-5 | Tests for the session mixin's folder branches (`applyAuthPayload`, the `logout()` guard, `disconnectFolder()`, `cloudOnly`, `cloudOnlyAction`), a throwing `prepare`, the write-start deadline, and the transport-level R3 path | 8.1; `test/local_folder/app_wiring_test.dart`, `transport_test.dart` |
| P1A-7 | Closed in 0.1.200 by the per-character fold (12.4); the review's `invalid to\u212Aen` case is now in `messages_test.dart`. The scrub now resumes at the second character of a match instead of after the whole match, so overlapping sentinels ("invalid token_not_valid") are all broken | 2.5; `folder_messages.dart` |

The review of these changes (`.agents/tasks/review-2a.json`, L2A-1 to
L2A-7) found that the index, now the source of list rows, was trusted
where it could be out of date. Its fixes:

| ID | Resolution | Where |
|---|---|---|
| L2A-1 | `index.json` follows this tab's writes: `flushIndex` writes the in-memory index under the exclusive lock one second after the first write of a burst (`kIndexFlushDelay`), so a reload starts from them and permanently deleted notes leave the file; a failed write logs "Folder index not saved: Shared.LocalFolder/write — ..." and is retried after the next write. Startup still goes `active` on the stored index (2.9), but its note body and sidecar entries start unverified: the first listing that meets one stats the file and reads it again only when its size or `lastModified` changed, and course payloads run that listing too. Chromium, 2,000 OPFS notes: the first list after an open from `index.json` held the lock 1,733 ms (later lists 92 ms), the flush 113 ms | 3.8, 6.2 R1; `local_folder_controller.dart`, `handlers/lookup.dart`, `handlers/courses.dart`, `folder_index.dart`, `transport.dart`, `router.dart` |
| L2A-2 | A rescan records the index changes this tab makes while it runs and applies them to its entries in its final exclusive hold, before `index.json` is written, and again for changes made after that hold | 3.8; `local_folder_controller.dart`, `folder_scanner.dart`, `folder_index.dart` |
| L2A-3 | A re-read note whose sidecar id, UUID, or summary fields differ from its entry gets a fresh sidecar entry (one stat, only on a difference), so another tab's description edit reaches the list and a renumbered id is found once the old id is asked for | 3.7, 3.8; `handlers/lookup.dart` |
| L2A-4 | Note delete selects comments by `source_note_uuid` only and checks `is_public` on disk | 3.5, 6.2 R2; `handlers/notes.dart` |
| L2A-5 | Course delete stats every note body (500 per hold) before it selects by `course_slug`, and indexes again each body that changed. Chromium, 2,000 notes: 11 holds, the longest 217 ms, 969 ms in all | 3.5, 6.2 R2 R4; `handlers/courses.dart`, `handlers/lookup.dart` |
| L2A-6 | Not bounded yet: the first list after an open and a listing that finds many new files run in one hold. Measured 1,733 ms for 2,000 stored notes and 626 ms for 300 new ones, so about 2,300 stored notes or 900 new files pass the 2 s target. Read batches of 128 instead of 32 changed little (1,615 ms). Tracked in `docs/development/local_folder_mode/deferred.md` for Phase 4's paged rescans | 6.2 R4; `docs/development/local_folder_mode/deferred.md` |
| L2A-7 | The Chromium timing test asserts every timed step's hold against `kFolderLockHoldTarget`; testing.md 8.3 names the numbers that are only printed | 8.3; `test/local_folder_opfs_timing_test.dart` |


## 12.6 Phase 2 shared content routes: where the code differs from the design

Phase 2 added the shared routes the editor needs before it shows the
option: attachments (id and uuid routes), covers, the avatar, history,
snapshots, version restore, study sessions, the `note_search_score` port,
the front page, and the heatmap, plus `folderAwareImageProvider` and
`folderAwareSvg`. Deferred items are in
`docs/development/local_folder_mode/deferred.md` ("Deferred from Phase 2").

| Item | Code | Where |
|---|---|---|
| Image provider | `folderAwareImageProvider(url, folder:)` returns `FolderImage` (bytes read through the controller's `FolderFs`, decoded as `MemoryImage` decodes) for `nc-folder:` and `NetworkImage` otherwise; `folderAwareSvg` uses `SvgPicture.memory` or `SvgPicture.network` (T4). Only paths under `assets/` are read; a `?v=` query is dropped from the path and kept in the cache key. `flutter_svg` becomes a direct dependency of the shared package (the three apps already had it) | 3.6, 9.2; `utils/folder_aware_image.dart`, `pubspec.yaml` |
| Upload writes | `LocalHandlerContext.writeBytes` writes an attachment, cover, or avatar file (replace-on-close, 3.4) before the journaled JSON that names it, so an interruption leaves at most an unreferenced file | 3.4.1, 3.6; `router.dart`, `transport.dart`, `handlers/attachments.dart` |
| Attachment names | Stored names keep letters, digits, `.`, `_`, and `-` (others become `_`), lose a leading dot, are capped at 120 characters, and get `-2`, `-3` on a clash; `attachments.json` also keeps `original_filename`, which the payload answers. Size caps are the backend's: 20 MB per attachment, 5 MB per cover; the avatar, which has no backend cap, uses 20 MB | 3.6; `handlers/attachments.dart` |
| Covers and avatar | `assets/notes/<hex>/cover.<ext>` and `assets/avatar.<ext>`; the stored URL carries `?v=<ms>` so a replaced file is not served from the image cache, and a replaced file with another extension is removed in the same journal record. The backend also bumps `last_edit` on a cover change; the folder leaves the note body alone | 3.6, F09, F34 |
| History | `GET /notes/{id}/history/` lists both retention pools, newest first (at most 24 entries); the backend answers its 12 newest. Each index entry also keeps the sidecar's `description` and `metadata_json`, so a restore brings them back; a folder-only snapshot has neither, and the note keeps its own | 3.8, F23; `handlers/history_sessions.dart`, `folder_snapshots.dart` |
| Sessions | `planner/sessions.json` records carry `note_uuid` besides `note_id`, so empty trash finds them; `course_id` is derived from the note when answering. `GET /note-sessions/` (filter `note_id`, `limit` up to 200) is answered too | 3.5, F24 |
| Search | `q` ranks with the `note_search_score` port and `SequenceMatcher.ratio` (autojunk on, no junk elements), so fuzzy hits ("n1" for "n17") now match as in the backend. Every score needs the note content, so a search reads every body (Phase 1 read only those the title and description missed). Parity is checked against CPython 3.9 `difflib` values to 1e-12 | F25, U12; `search_score.dart`, `handlers/notes.dart` |
| Heatmap | `planner/heatmap.json` is `{"schema_version": 1, "days": {"YYYY-MM-DD": {"created_notes": n, "peak_words": m}}}`, written in the create journal record of each new note with a word count above 0 (content, else description, else title, as `note_word_count` counts the blocks). Draft upserts are edits, which `build_heatmap_payload` does not count. The day is the device's local day | F38, 3.5; `handlers/activity.dart`, `handlers/notes.dart` |
| Front page | Carousel and collections: the folder's courses that hold at least one live note (the backend: at least one public note), in course order, at most 6; recent and recommended notes: every live note by `last_edit` (D1); `upcoming_events` from `planner/events.json` without `client_local_id`. `GET /heatmap/` (182 days each way) is answered too | F44; `handlers/activity.dart` |
| Handshake | `capabilities.attachments` is 1 | F46; `handlers/auth_settings.dart` |
| Fixtures | 14 new fixtures. Setups `note_with_attachment`, `note_with_snapshot`, and `note_with_session` add `{attachment_id}`, `{version_id}`, `{session_id}`; a request with `files` (field to `filename`, `content_type`, `base64`) is sent as multipart with its `fields`, by both the Dart test and `backend/notes/test_api_contract.py` | 8.4; `test/fixtures/api_v1/` |


## 12.7 Hardening round (0.1.203): index cache extracted

The first follow-up of the section A hardening round in
`next_phase.md` (deferred item L2A2-5). A pure refactor with no
behaviour change.

| Item | Code | Where |
|---|---|---|
| L2A2-5 | The in-memory index cache moved out of `local_folder_controller.dart` into a new `FolderIndexCache` in `lf/folder_index_cache.dart`: the index state (`_index`, the unverified set, the scan-time change log, the flush timer and dirty flag, scan progress) and its methods (`setIndex`, `scan`, the scanner factory, `isUnverified`, `updateIndex`, the coalesced `_scheduleFlush`, `flushIndex`). The class is controller-free like `folder_index.dart`, reading the controller's live folder, record, lock name, and `active` state through accessor callbacks as `FolderScanner` takes its collaborators, and calling back into `notifyListeners`. The controller keeps thin `index`/`progress`/`isUnverified`/`updateIndex`/`flushIndex`/`rescan` delegators, so the transport, the router `RouteContext`, the handlers, and the tests are unchanged; `kIndexFlushDelay` moved with the cache and is re-exported from the controller file. The controller dropped from 892 to 788 lines | 3.8, L2A-1, L2A-2, 6.2 R1 R2 R4; `local_folder_controller.dart`, `folder_index_cache.dart` |
