# Local folder storage mode: feature matrix

Part of the design in [`../local_folder_mode.md`](../local_folder_mode.md)
(section 4). Same conventions: repo-root-relative paths, `file:line` at
HEAD `48988a20` (VERSION 0.1.199; first pinned at `6cd1f3be`, and only
the planner `calendar.dart` citations moved), and section numbers that
refer to the main document unless they start with 4. Section numbers are
global: 2.8 to 2.10 and 7 are in `modes_and_migration.md`, 3.4 to 3.8 in
`storage_rules.md`, 6 in `security_and_tabs.md`, and 8 in `testing.md`. In
the Code column, a path without a directory prefix is under the named
app's or the shared package's `lib/`.

## 4.1 Routes the apps call

Enumerated from every `_uri(...)` call in the three clients plus
`verifyHandshake` and `pingBackend`. E is
`frontend/editor_app/lib/core/http_client.dart`, P is
`frontend/planner_app/lib/core/client.dart`, Po is
`frontend/portal_app/lib/core/client.dart`; numbers are the lines of the
`_uri(...)` calls (the `Uri.parse` line for the handshake).
All paths are under `/api/v1`. There are 66 distinct method and path
pairs (the JSON and multipart `PATCH /settings/` count once). `docs/api/backend_api_spec.md` is stale (it lists register,
verify-email, and session routes at `:24-31` that the backend does not
mount, and omits most routes below), so the backend route table
`backend/notechondria/api_urls.py:64-136` is the reference.

| Area | Method and path | Lines | Folder mode |
|---|---|---|---|
| Handshake, debug | `GET /handshake/`; `GET /ping/` | E:57, P:255, Po:53; `ping_backend.dart:35-38` | Local (a), answered in every folder state (2.8 rule 4); `ping` reaches the transport through the shell's `onPing` closure (2.7). The manual "Check for updates" is the only request that leaves the page (2.8 rule 3) |
| Front page | `GET /front-page/` | E:160, Po:150 | Local, own data (a) |
| Courses | `GET,POST /courses/`; `GET,PATCH,DELETE /courses/{id}/`; `POST /courses/reorder/`; `GET /courses/{id}/notes/` (Po also paged); `POST /courses/{id}/open/`; `POST /admin/template-courses/restore/` | E:169-237,517,526; P:358-420,672,681; Po:159-258,531,540 | Local (a); template restore substituted (F18) |
| Course sharing | `POST,DELETE /courses/{id}/subscribe/`; `POST /courses/{id}/subscribe-private/`; `POST /courses/{id}/transfer/` | E:488-508; P:406,653,663; Po:207,512,522 | 501 (c) |
| Course git | `PUT /courses/{id}/git/`; `POST /courses/{id}/git/import/` | Po:224,234 | GitHub API with a token (b) |
| Notes | `GET,POST /notes/`; `GET,PATCH,DELETE /notes/{id}/`; `GET /notes/uuid/{uuid}/` | E:247-345,257; P:430-510; Po:271-367,281 | Local (a); other users' notes 404 |
| Trash | `GET /notes/deleted/`; `POST /notes/{id}/restore/`; `DELETE /notes/deleted/empty/` | E:313-332; P:478-497; Po:335-354 | Local (a) |
| History | `GET /notes/{id}/history/`; `POST /notes/{id}/snapshot/`; `POST /notes/{id}/restore/{version}/` | E:357-387; P:522-552; Po:379-409 | Local (a) |
| Sessions | `POST /note-sessions/`; `PATCH /note-sessions/{id}/` | E:465,478; P:630,643; Po:489,502 | Local (a) |
| Attachments | `GET,POST /notes/{id}/attachments/`; `DELETE .../{aid}/`; the same three under `/notes/uuid/{uuid}/` | E:751-837 | Local files (a) |
| Covers | `POST,DELETE /notes/{id}/cover/` | E:852,874; P:916,938; Po:820,842 | Local files (a) |
| Planner | `GET,POST /planner-events/`; `PATCH /planner-events/{id}/`; `GET /activity/`; `GET /activity/week/` | E:887-912,396,408; P:891-955,561,573; Po:795-859,418,431 | Local (a) |
| Calendar feeds | `GET,POST /calendar-feeds/`; `PATCH,DELETE /calendar-feeds/{id}/` | E:421-455; P:586-620; Po:445-479 | Local (a); URL fetch (b) or (c) |
| Auth | `POST /auth/login/`; `POST /auth/casdoor/exchange/`, `bind/`, `link/bind/`, `link/create/`; `DELETE /auth/casdoor/unlink/`; `POST /auth/rotate-api-key/` (E, Po) | E:535-611,627; P:690-766; Po:549-633,653 | 501 (c) |
| Auth (local answers) | `GET /auth/casdoor/config/` returns `configured: false`; `GET /auth/session/`; `POST /auth/logout/` | E:547,618,697; P:702,773,782; Po:561,644,744 | Local (a). The backend has no `session` or `logout` route (`api_urls.py:64-136`); that pre-existing gap is out of scope |
| Settings | `GET,PATCH /settings/` (JSON and multipart avatar) | E:708-729; P:793,805,872; Po:755-776 | Local (a) |
| GitHub | `GET,DELETE /integrations/github/status/`; `GET .../repos/`; `POST .../callback/`; `POST .../push/` | E:639-690; P:814-865; Po:665-733 | GitHub API with a token (b); `callback` 501 (c) |

Outside `/api/v1`: media bytes under `/media/` (rendered with
`Image.network`, replaced per 3.6), `/mcp/` (external agents only,
`backend/mcp/views.py:1-7`), the Casdoor redirect, and the GitHub App
install popup and its `/auth/github/callback` page
(`backend/notechondria/urls.py:23`).

## 4.2 Features

Class (a) works fully locally, (b) calls a third party directly from the
browser, (c) needs a server. Each (c) row gives the cause, the section 1.8
message the UI shows (and the route returns as a 501 `detail`), and the
fallback. "Cloud mode" means disconnecting the folder and signing in.

| ID | Feature | Apps | Code | Class | Folder-mode behavior |
|---|---|---|---|---|---|
| F01 | Casdoor SSO sign-in and "Sign up via Casdoor" | all | `auth_dialogs.dart:30-48`; `/auth/casdoor/config/`, `exchange/` (`app_shell_oauth_mixin.dart:355`) | (c) | The code exchange uses `CASDOOR_CLIENT_SECRET`, held only by the server (`backend/creators/casdoor_auth.py:72`, `backend/notechondria/settings.py:479`). Hidden. Message: "Cloud sign-in unavailable in folder mode: Shared.LocalFolder.Backend/unsupported — Casdoor sign-in needs the Notechondria server, which holds the OAuth client secret. Disconnect the folder to sign in." |
| F02 | Email/password login | all | `POST /auth/login/` | (c) | Accounts are server records. Hidden; same message with "email/password sign-in" |
| F03 | Casdoor bind, link challenge, unlink | all | `app_shell_oauth_mixin.dart:108,113,319`; `DELETE /auth/casdoor/unlink/` | (c) | Server account linking. Hidden; same message with "account linking" |
| F04 | Registration, verification, password reset | all | owned by Casdoor (`auth_client.dart:7-11`) | (c) | Accounts are created and recovered by Casdoor for the Notechondria server. Hidden in folder mode. Shown when a Casdoor sign-up or reset redirect returns to an app in folder mode (`oauth_callback` is skipped, 2.9) and in the status card's "Cloud-only features" list: "Account not created: Shared.LocalFolder.Backend/unsupported — registration, verification, and password reset are Casdoor flows for Notechondria cloud accounts, and a local folder needs no account. Disconnect the folder to register or reset a password." Fallback: cloud mode |
| F05 | Session restore and logout | E, Po persist the session; P keeps it in memory | `/auth/session/`, `/auth/logout/`; `app_shell_session_mixin.dart:357` | (a) | The folder session is derived from the stored mode at startup (2.9); logout means "Disconnect folder", which calls `disconnectFolder()` and never clears a cloud session (2.10 rule 4) |
| F06 | "Use a local folder (no account)" | all | new (section 1) | (a) | New |
| F07 | Profile fields (username, email, motto, social link) | all | `frontend/editor_app/lib/core/settings_actions.dart:210-229` | (a) | `profile/creator.json` |
| F08 | Synced preferences (`app_settings` without per-device keys, editor mode, planner deadline weights, `last_seen_versions`) | all | editor `settings_actions.dart:165-176`; `backend/creators/api.py:400-428` | (a) | `profile/settings.json`. Theme, locale, API base URL, offline mode, log preferences, and the portal startup image are per device in folder mode (decision D2) and stay in browser storage. The folder settings handler drops `api_base_url`, `theme_preset`, `theme_mode`, `locale`, `offline_mode`, `log_preferences`, `splash_image_url`, `splash_image_local`, and `keep_offline_data_on_login`, both at the top level and inside `app_settings`, from every `PATCH /settings/` (JSON and multipart), and omits them from `GET /settings/`. Omitting them (not sending null) keeps the device values, because `applyLocalAppSettings` merges with `{..._localSettings, ...settings}` (editor `core/settings_helpers.dart:43-49`). This matters because the reused code pushes them: `applyAuthPayload` sends `theme_*` and `api_base_url` (`app_shell_session_mixin.dart:242-248`), and so does the planner's settings save (`planner core/settings_actions.dart:128-142`). A unit test sends every per-device key and finds none in the file or the response |
| F09 | Avatar upload and display | all | `PATCH /settings/` multipart; `components/avatar.dart` | (a) | `assets/avatar.<ext>`, `nc-folder:` URL |
| F10 | API base URL setting and its handshake check | all | editor `settings_actions.dart:62-64`; `verifyHandshake` | (a) | The local handshake answers; the field is read-only while the folder is connected and keeps the saved cloud URL, which only "Check for updates" uses (2.8) |
| F11 | Offline-mode switch | all | `frontend/editor_app/lib/core/settings_helpers.dart:82-94` | (a) | Ignored and disabled through `onOfflineModeChanged: null` (2.7) |
| F12 | Course create, rename, icon, color, delete | all (delete: E) | `/courses/`, `/courses/{id}/` | (a) | `courses/<slug>.json`; delete per 3.5; titles case-insensitively unique per owner, as the backend's create and upsert guard enforces (`backend/notes/api.py:774-800`; the transfer guard at `:1007-1010` repeats it) |
| F13 | Course reorder | E | `POST /courses/reorder/` | (a) | `sort_order` fields, one journaled write |
| F14 | Course notes list and paging | all | `GET /courses/{id}/notes/` | (a) | From the index |
| F15 | Course "opened" marker | all | `POST /courses/{id}/open/` | (a) | Field in the course file |
| F16 | Subscribe, unsubscribe, private subscribe | all | `/courses/{id}/subscribe/`, `subscribe-private/` | (c) | Reads other users' courses on the server. "Course not subscribed: Shared.LocalFolder.Backend/unsupported — subscribing reads another user's course from the Notechondria server; a local folder holds only your data." Fallback: cloud mode |
| F17 | Course transfer to another author | P, Po | `POST /courses/{id}/transfer/` | (c) | Needs the other user's account. "Course not transferred: Shared.LocalFolder.Backend/unsupported — the recipient's account lives on the Notechondria server." Fallback: export the course, move it to the cloud, transfer there |
| F18 | Restore template or starter courses | all | `POST /admin/template-courses/restore/`; `_restoreLocalStarterTemplate` (`frontend/editor_app/lib/core/maintenance_actions.dart:291`) | (a) | Substituted: writes the bundled local starter content (`core/local_starter.dart` per app), not the server's `bootstrap_platform` sample catalog (`backend/notes/api.py:1968-1995`) |
| F19 | Legacy Inbox migration | E | `frontend/editor_app/lib/core/inbox_migration.dart:4-19` | (a) | Runs against folder courses; harmless no-op on new folders |
| F20 | Note create, edit, save, delete to trash | all | `/notes/`, `/notes/{id}/`; editor `note_crud.dart:13,88` | (a) | 3.2, 3.5 |
| F21 | Editor modes, metadata dialog, custom meta, `is_public` flag | all | `modules/note_metadata.dart`; `components/custom_meta_list_editor.dart` | (a) | Stored; `is_public` has no effect until the note is in the cloud (F29) |
| F22 | Trash list, restore, empty | all | editor `maintenance_actions.dart:12,51,74` | (a) | 3.5, including the empty-trash cascade over history, assets, and sessions |
| F23 | History, snapshot, restore version | all | editor `note_crud.dart:310,316,325`; `backend/notes/services.py:324-356` | (a) | `history/`; port `prune_recent_versions`, which keeps the 12 newest versions (`services.py:339-344`, 3.8) |
| F24 | Study sessions | all | `core/note_sessions.dart` | (a) | `planner/sessions.json` |
| F25 | Search and filters over own notes (`q`, scope personal/private, sort, window, course) | all | `GET /notes/?…`; `backend/notes/api.py:254-274,1313-1358` | (a) | Port `note_search_score`; it uses Python `SequenceMatcher`, so ranking parity needs a faithful port (U12) |
| F26 | Search with `scope=all` or `public` | E, Po | `backend/notes/api.py:1332-1340` | (c) | Other users' public notes are on the server. Returns own notes only and logs "Public notes not searched: Shared.LocalFolder.Backend/search — other users' public notes live on the Notechondria server; showing this folder's notes only." |
| F27 | Deep link to an own note `/notes/<uuid>` | E, Po | `frontend/editor_app/lib/core/auth_flows.dart:1-10`; `GET /notes/uuid/{uuid}/` | (a) | Resolved from the index |
| F28 | Open someone else's shared note link | E, Po | `NoteByUuidApiView` is `AllowAny` (`backend/notes/api.py:1622-1625`) | (c) | "Note not found in folder: Shared.LocalFolder.Backend/notes — <uuid> is not in this folder; shared links of other users open from the Notechondria server." Fallback: open the link in cloud mode |
| F29 | Public sharing (others can read `is_public` notes) | all | `note_is_public` (`backend/notes/api.py:80-87`) | (c) | Needs hosting. "Note not shared publicly: Shared.LocalFolder.Backend/unsupported — public links need the Notechondria server to host the note; the public flag is saved and applies if the note moves to the cloud." Fallback: export the note as Markdown and share the file |
| F30 | Browser-local drafts, draft sync, pull conflict diff | all | `core/draft_sync.dart`; `note_conflict_diff.dart` | (a) | Drafts push into the folder (7.1); the diff also serves external edits (3.8) |
| F31 | Markdown, math, `<details>`, local images | all | `frontend/editor_app/lib/core/helpers.dart:290-312`; `components/note_viewer.dart` | (a) | Already client-side (`flutter_markdown`, `flutter_math_fork`). The planner and portal note viewers (`components/note_viewer.dart:116`, `:122`) gain `sizedImageBuilder` so `nc-folder:` images render (3.6) |
| F32 | Remote images embedded by URL | all | `Image.network` fallback in editor `helpers.dart:309` | (b) | Unchanged from today: the browser fetches from the image host, and CanvasKit needs that host to send CORS headers |
| F33 | Attachments (id and uuid routes), queued attachment promotion | E | editor `note_crud.dart:164-275` | (a) | 3.6; a failed promotion keeps its `local://` link and a retry action (3.6) |
| F34 | Cover image upload and clear | all | `/notes/{id}/cover/`; `note_cover_image.dart:53` | (a) | `assets/notes/<hex>/cover.<ext>` |
| F35 | Planner events, completion toggle, recurrence | P, Po | `/planner-events/`; `backend/notes/services.py:182-307` | (a) | `planner/events.json`, with `client_local_id` on pushed browser-local events (7.1); port the recurrence expansion (`services.py:215-278`) |
| F36 | Deadline feed | P, Po | `GET /activity/` | (a) | Port `planner_deadline_payload` (`services.py:294`) |
| F37 | Week and calendar views | P, Po | `GET /activity/week/`; `calendar_week_payload` (`services.py:748`) | (a) | Merge events, sessions, and stored feed events locally |
| F38 | Heatmap | Po | front-page payload; `build_heatmap_payload` (`services.py:112`); `record_note_activity` (`:99`) | (a) | `planner/heatmap.json`, updated on note save |
| F39 | Deadline weights | P | `frontend/planner_app/lib/core/settings_actions.dart:14-15` | (a) | Already local |
| F40 | Import an `.ics` file | P | `frontend/planner_app/lib/core/calendar.dart:35-110` | (a) | Signed-in path posts `raw_ical` (`calendar.dart:73-76`) to the local backend; stored in `planner/feeds/` |
| F41 | Toggle, edit, delete a feed | P, Po | `/calendar-feeds/{id}/`; planner `calendar.dart:195-211` (toggle), `:213-227` (delete) | (a) | Local |
| F42 | Subscribe or refresh a feed by URL, host sends CORS headers | P, Po | planner `calendar.dart:123-192` posts `source_url` | (b) | The local backend fetches the URL from the browser (port `normalize_calendar_url`, `services.py:399`) and caches the body in `planner/feeds/<id>.ics`; refresh on demand and on focus |
| F43 | Subscribe or refresh by URL, host without CORS (Google public calendars verified, 11.2) | P, Po | server fetch `read_calendar_feed` (`backend/notes/services.py:538-565`) | (c) | The browser cannot read a cross-origin response without `Access-Control-Allow-Origin`. "Calendar not subscribed: Shared.LocalFolder.Backend/calendar.fetch — <host> does not allow browser downloads (no Access-Control-Allow-Origin header). Download the .ics file and use Import iCal, or subscribe in cloud mode." A proxy is Q8 |
| F44 | Front page from own data (courses, recent notes, heatmap, upcoming events) | Po (E also calls it) | `GET /front-page/`; `backend/notes/api.py:647-716` | (a) | Built from the folder; includes private notes, since only the user sees it (decision D1) |
| F45 | Public discovery: other users' public courses and notes, other users' course pages | Po, E | `FrontPageApiView` (`backend/notes/api.py:647-716`); non-owner filter (`:1255-1260`) | (c) | Cross-user data. The front page shows a one-line note: "Public notes not shown: Shared.LocalFolder.Backend/front_page — other users' public notes live on the Notechondria server." Fallback: cloud mode |
| F46 | Handshake and version-update banner | all | shared `components/version_update_banner.dart:21-92`; editor `settings_helpers.dart:120-139` | (a) | The local handshake returns `service: notechondria-backend` and `api_version: v1` (both required, editor `http_client.dart:98-108`), the running build's version (so the banner stays hidden), and `storage.label` "Local folder: <name>". The status card's "Check for updates" sends the one passthrough request (2.8 rule 3, Q9) |
| F47 | Debug log and terminal (`ls`, `cd`, `pwd`, `ping`, `clear`, `help`) | all | `components/debug_log.dart:314-358` | (a) | `ping` reports the local backend (2.7) |
| F48 | Storage usage card | all | `components/storage_usage_card.dart:19-40` (host, `storageArchLabel`, browser buckets, attachment bytes) | (a) | Unchanged card: it keeps showing this browser's buckets, and its `storageArchLabel` line reads "Local folder: <name>" from the local handshake (F46). The folder's file counts and bytes, from the index and ignoring `*.crswap` swap files (3.4), appear in `LocalFolderStatusCard` (2.7) instead, so the portal's `modules/settings_pages.dart` (1029 lines, builds the card at `:793`) is not edited |
| F49 | GitHub data-sync push, status, repo list, disconnect | all | `GithubSyncExperimentalCard` (`mcp_skill_section.dart:173`); `/integrations/github/*` | (b) | Calls `api.github.com` with a user-supplied fine-grained token. CORS verified (11.2). Pushes the folder tree in the GitHub layout. Until Phase 5 the card builder is wrapped in `cloudOnly(...)` (the shared session mixin's gate, 12.4) in folder mode, so no GitHub status request is sent before its handler exists (9.3) |
| F50 | GitHub App install popup and callback | all | `mcp_skill_section.dart:417`; `POST /integrations/github/callback/` | (c) | The installation token is minted with the App private key (`backend/creators/services/github_sync.py:503-600`; `settings.py:464-468`). "GitHub App connection unavailable in folder mode: Shared.LocalFolder.GitHub/token — installing the Notechondria GitHub App needs the server's App private key. Paste a fine-grained personal access token instead." Fallback: F49 |
| F51 | Course to GitHub repo bind and import | Po | `PUT /courses/{id}/git/`, `POST .../git/import/` | (b) | GitHub contents API with the same token |
| F52 | Course repo sync after edits | server-side today | `mark_course_pending`, `flush_due_course_syncs` (`backend/courses/git_service.py`) | (b) | Manual "Push course" and an optional debounced push from the browser |
| F53 | MCP endpoint for agents and API-key rotation | E, Po | `backend/mcp/views.py:1-7`; `POST /auth/rotate-api-key/` | (c) | Agents connect to a server URL; a web page cannot accept connections. "MCP access unavailable in folder mode: Shared.LocalFolder.Backend/unsupported — agents connect to an MCP server URL, and a web page cannot accept incoming connections. Your skill.md is still saved in the folder." Fallback: cloud mode; a local daemon is Q1 |
| F54 | MCP skill.md editor | all | `components/mcp_skill_section.dart:17`; `PATCH /settings/` `mcp_skill_md` | (a) | `profile/skill.md` |
| F55 | AI/LLM features | none | no frontend route; `backend/gptutils/gpt_request_parser.py:1-47` raises `NotImplementedError`; `docs/development/ai_integration.md:8-21` | not counted | Nothing to port. A future LLM call would be (b) with a user key (section 5) |
| F56 | `.nchron` export and import | all | shared `utils/local_archive.dart`; editor `core/local_archive_io.dart:17,95` | (a) | 3.3 |
| F57 | Markdown and zip note import/export | E | editor `note_crud.dart:345,374,467` | (a) | Unchanged |
| F58 | Apple Journal import | E | `core/apple_journal_import.dart:33` | (a) | Notes are created through the normal create path |
| F59 | Clear local data, copy logs, clear legacy storage | all | editor `maintenance_actions.dart:225,266,342` | (a) | Browser storage only; never touches the folder |
| F60 | Onboarding tour, what's new overlay | all | `components/onboarding_tour.dart`; `components/whats_new_overlay.dart` | (a) | Seen versions in `profile/settings.json` |
| F61 | Splash reaction simulator | all | `reaction_simulator/reaction_simulator.dart` | (a) | Client-only |
| F62 | Mobile install banner | E, Po | `components/install_banner.dart:24-61` | (a) | Never shown in folder mode, which is desktop-only |
| F63 | Custom startup (splash) image, uploaded or by URL | Po | `frontend/portal_app/lib/app_shell.dart:646-648`; `modules/settings_pages.dart:453-498`; `components/custom_splash_overlay.dart:67-79` | (a) | A per-device preference (decision D2): the URL or `local://app-splash/startup-image` stays in `_localSettings`, and uploaded bytes stay in `LocalAttachmentStore`. Never written to the folder, because it renders before any folder is open (3.6) |

## 4.3 Counts and justification of (c)

- (a): 44. (b): 5 (F32, F42, F49, F51, F52). (c): 13 (F01, F02, F03,
  F04, F16, F17, F26, F28, F29, F43, F45, F50, F53). Not counted: F55.
  Total 62 counted features out of F01 to F63.
- Every (c) falls in one of four causes: a server-held secret (F01, F03,
  F50), server-held accounts (F02, F04, F17), data of other users or
  public hosting (F16, F26, F28, F29, F45), or a connection the browser
  cannot make (F43 cross-origin read, F53 inbound connection). None is a
  storage limitation of the folder.
