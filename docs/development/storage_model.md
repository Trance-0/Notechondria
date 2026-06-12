# Storage model — backend (Django) and frontend (offline)

How user data is laid out and persisted across the two halves of
Notechondria. This is the doc the URGENT TODO item asked for —
"how Django backend manage the storage of user data and how
frontend manages the storage of user data for offline local users.
The structure storage of note class, course class, and others."

Related: [`server/notes.md`](../server/notes.md),
[`server/creators.md`](../server/creators.md),
[`client/editor_app.md`](../client/editor_app.md).

## TL;DR

| Layer | Tech | Lifetime | What lives there |
| --- | --- | --- | --- |
| Backend authoritative DB | PostgreSQL via Django ORM | Forever | Source of truth: users, creators, courses, notes, blocks, attachments, planner events, calendar feeds, recycle bin, version history. |
| Backend file storage | Cloudflare R2 (cloud) or local disk (Docker dev) | Forever (R2) / volume-bound (local) | Static assets, user-uploaded media, course covers, note attachments. |
| Frontend offline | `SharedPreferences` JSON blobs (one per concern) | Until logout, manual clear, or the user clears site data | Local mirror of recently seen courses + notes, settings, draft notes, stats, cached front-page, UI logs, session token. |

The frontend never persists to a structured local DB (no `sqflite`,
no Hive). Everything is a JSON document under one of seven
`SharedPreferences` keys per app.

## Backend storage

The **only** authoritative store is the Django ORM (PostgreSQL in
production; in-memory sqlite in
[`settings_test.py`](../../backend/notechondria/settings_test.py)).
File blobs go to either Cloudflare R2 (when
`CLOUDFLARE_R2_BUCKET_NAME` is set — Render and Northflank) or a
local volume (Docker dev) — see
[`deployment/overview.md` § Cloudflare R2](../deployment/overview.md#3-cloudflare-r2-cdn).

### Account / identity

Defined in [`server/creators.md`](../server/creators.md). Wire-level
shape:

```text
auth.User (Django built-in)
  └── creators.Creator (1:1 by user_id)
        ├── creators.CreatorApiKey (1:N — hashed only)
        ├── creators.CreatorInvitation (1:N)
        └── creators.CreatorOauthIdentity (1:N — google / github)
```

`Creator` is the row everything else hangs off. Anywhere the
backend needs the "creator context" of a `request.user`, it goes
through `ensure_creator(user)` in
[`backend/notechondria/utils.py`](../../backend/notechondria/utils.py).

### Content / planning

Defined in [`server/notes.md`](../server/notes.md). Shape:

```text
creators.Creator
  ├── notes.Course (1:N) — `is_default=True` for the pinned Inbox
  │     ├── notes.CourseMedia (1:N) — covers / banners
  │     ├── notes.CourseSubscription (M:N to Creator)
  │     ├── notes.CourseOperationLog (1:N audit trail)
  │     └── notes.Note (1:N)
  │           ├── notes.NoteIndex (1:N) — block ordering
  │           │     └── notes.NoteBlock (M:N via NoteIndex)
  │           ├── notes.NoteAttachment (1:N) — uploaded files
  │           ├── notes.NoteVersion (1:N) — snapshots
  │           ├── notes.RecycleBinEntry (1:1 when deleted)
  │           └── notes.NoteActivitySession (1:N) — edit sessions
  ├── notes.HeatmapActivity (1:N) — per-day rollup
  ├── notes.PlannerEvent (1:N)
  ├── notes.CalendarFeed (1:N)
  └── notes.Tag, notes.ValidationRecord
```

Key invariants:

- Every creator has exactly one `Course` with `is_default=True` —
  the "Inbox", undeletable.
- `Note → Course` is a hard FK; deleting the course's notes goes
  through the recycle bin first. Inbox cannot be deleted.
- `NoteBlock` is M:N with `Note` via `NoteIndex(note_id,
  noteblock_id, index)` — the same block can render in multiple
  notes (transclusion). A "delete block from note" actually
  removes the `NoteIndex` row, leaving the `NoteBlock` itself
  alive.
- `NoteVersion.snapshot` is a JSON dump of the note + all blocks
  at snapshot time, used by `NoteRestoreApiView`.
- `RecycleBinEntry.restorable_until` defines when the soft-delete
  becomes hard. `DeletedNoteEmptyApiView` purges expired entries.

### File storage paths

`models.py` declares per-relation upload-path helpers:

| Helper | Resolves to |
| --- | --- |
| `note_attachment_path(instance, filename)` | `user_upload/user_<creator_user_id>/notes/note_<note_id>/<filename>` |
| `message_image_path` (gptutils, parked) | `user_upload/user_<id>/conversations/chat_<chat_id>/msg_<msg_id>_img.<ext>` |
| `message_file_path` (gptutils, parked) | `user_upload/user_<id>/conversations/chat_<chat_id>/msg_<msg_id>_file.<ext>` |

When `CLOUDFLARE_R2_BUCKET_NAME` is set, Django Storages writes to
`<bucket>/media/user_upload/...`. Otherwise to the configured
`DJANGO_PRODUCTION_MEDIA_ROOT` (`/home/mediafiles` in the Docker
image).

`collectstatic --noinput --clear` mirrors built static assets to
`<bucket>/static/` (R2) or `DJANGO_PRODUCTION_STATIC_ROOT`
(`/home/staticfiles` locally) on every container start — see
[`backend/entrypoint.sh`](../../backend/entrypoint.sh).

### Settings

User-editable settings live in two places:

- **DRF surface**: `GET/PATCH /api/v1/settings/` —
  `SettingsApiView` reads/writes the canonical record on the
  server. Includes `app_settings` JSON for client-only knobs the
  server doesn't interpret.
- **`Creator` row**: profile-level fields (`display_name`,
  `motto`, `social_link`, `avatar`, `email`, `editor_mode`,
  `theme_preset`, `theme_mode`, `api_base_url`).

The server is the source of truth when the user is signed in. The
frontend reconciles by calling `GET /api/v1/settings/` on login
and merging into the local `settings` blob (see below).

## Frontend storage

Each Flutter app has its own copy of
[`core/local_store.dart`](../../frontend/editor_app/lib/core/local_store.dart)
(planner and portal too). The class is `_LocalAppStore` and it's
the **single chokepoint** for `SharedPreferences` reads/writes —
no other file in the lib should call `SharedPreferences.getInstance()`.

### Keys

Since 0.1.127 every key carries a **per-app namespace** —
`notechondria.editor.*` / `notechondria.planner.*` /
`notechondria.portal.*`. On GitHub Pages (and any single-domain
deploy) the three apps share one browser origin, and web
`SharedPreferences` is origin-scoped localStorage, so the previous
app-agnostic `notechondria.*` keys let the apps overwrite each
other's settings, drafts, and session state. `_migrateLegacyKeys`
copies any old unprefixed value into the app's namespace once
(copy, not move — each app migrates independently; the stale legacy
keys are left behind for now). The shared OAuth handoff keys
(`oauth_redirect_uri` / `oauth_invitation_code` / `oauth_intent` in
`app_shell_oauth_mixin.dart`) carry the same prefix.

Seven JSON blobs per app, plus the session record (key names below
shown for the editor; substitute the app id):

| Key | Type | Default factory | What it holds |
| --- | --- | --- | --- |
| `notechondria.editor.local_settings` | `Map<String, dynamic>` | `defaultSettings()` | Local mirror of `/api/v1/settings/`: `theme_preset`, `theme_mode`, `api_base_url`, `updated_at`, `log_preferences`. |
| `notechondria.editor.local_drafts` | `List<Map<String, dynamic>>` | `[]` | Notes the user typed while offline; sync flow pushes them to `/api/v1/notes/` after login. |
| `notechondria.editor.local_courses` | `List<Map<String, dynamic>>` | `[]` | Locally created courses (pre-sync) plus the cached list of remote courses. The Inbox is created locally if no session exists. |
| `notechondria.editor.local_stats` | `Map<String, dynamic>` | `defaultStats()` | Counters: `local_drafts_created`, `local_drafts_synced`, `local_courses_created`, `local_courses_synced`, `avatar_updates`, `settings_saves`, `logs_copied`, `cache_clears`, `local_data_clears`, `sync_failures`, `last_sync_at`. Since 0.1.127 also `last_seen_version` (What's-New overlay stamp). |
| `notechondria.editor.local_cache` | `Map<String, dynamic>` | `defaultCache()` | Last-seen server payloads for offline render: `front_page` (cached `/api/v1/front-page/` response), `courses` (cached `/api/v1/courses/`), `activity` (cached planner data), `updated_at`. |
| `notechondria.editor.local_logs` | `List<String>` | `[]` | UI log lines surfaced in the debug drawer. |
| `notechondria.editor.session` | `Map<String, dynamic>?` | `null` | After login: `{token, user, saved_at}`. Cleared on logout. The token is plaintext — same security posture as any web app's localStorage token. Editor-only; planner/portal don't persist the token. |

All values are JSON-serialized via `dart:convert`. Decoding tolerates
malformed values by falling back to the defaults (see
`_decodeMap`/`_decodeList` in `local_store.dart`).

### Lifecycle

1. **Boot** — `app_shell.dart::_loadLocalState` calls
   `_LocalAppStore.load()`, which reads all seven blobs in one
   pass. Then `_httpClient.updateBaseUrl(_localSettings['api_base_url'])`
   pre-points the API client at the persisted backend.
2. **Login** — `LoginApiView` returns `{token, user}`; the app
   calls `_LocalAppStore.saveSession(token, user)`. A subsequent
   `GET /api/v1/settings/` reconciles `_localSettings` with the
   server, then `_persistLocalSettings()` writes it back.
3. **Settings save** — `_handleUpdateSettings` (in
   [`app_shell.dart`](../../frontend/editor_app/lib/app_shell.dart))
   reads form values, runs `verifyHandshake(nextApiBase)` if the
   API URL changed (see [handshake](../server/backend.md#handshake)),
   then `_applyLocalAppSettings({...})` mutates `_localSettings`
   and `_persistLocalSettings()` flushes to disk. If signed in,
   the same payload is PATCHed to `/api/v1/settings/` for the
   server-side mirror.
4. **Offline create** — drafts and locally-created courses go
   into `notechondria.local_drafts` /
   `notechondria.local_courses` immediately. Sync flow on login
   pushes them up.
5. **Sync** — `_syncAllLocalData` walks the unsynced drafts/
   courses, posts each, and on success increments
   `local_drafts_synced` / `local_courses_synced`.
6. **Logout** — `_LocalAppStore` clears the session blob; other
   blobs are kept so the user's local-only work survives.
7. **"Clear local data"** — wipes all seven blobs back to
   defaults.

### Important: drafts vs cache

`local_drafts` is **content the user created that hasn't been
sent to the server yet**. Don't conflate with `local_cache`,
which is **server payloads cached for offline display**. Sync
empties `local_drafts` (after pushing); refresh refills
`local_cache`.

## Cross-frontend / cross-backend correspondence

| Frontend blob | Server source of truth | Reconciliation point |
| --- | --- | --- |
| `local_settings` | `Creator` row + `app_settings` JSON | `GET /api/v1/settings/` on login + `PATCH /api/v1/settings/` on save. |
| `local_drafts` | `notes.Note` rows | `POST /api/v1/notes/` per draft, then drop from blob. |
| `local_courses` | `notes.Course` rows | `POST /api/v1/courses/` per locally-created course; `GET /api/v1/courses/` populates the cached read-side. |
| `local_cache.front_page` | `FrontPageApiView` payload | `GET /api/v1/front-page/` on boot + manual refresh. |
| `local_cache.courses` | `notes.Course` list | Same. |
| `local_cache.activity` | Activity / planner endpoints | Same. |
| `session.token` | `authtoken.Token` row | `LoginApiView` mints it; `LogoutApiView` revokes it server-side. |

## Known issues to be aware of

- **Token expiry / "Invalid token"** — the frontend's "offline
  fallback: Invalid token" message fires when a stored DRF token
  is rejected by the server (revoked, deleted, or signed by a
  different `SECRET_KEY`). The current behavior is to fall back to
  offline mode silently, which can mask the underlying issue. The
  right fix is to surface a "session expired — please sign in
  again" prompt and clear `notechondria.session`.
- **No server-side mirror of drafts** — once a draft is in
  `local_drafts`, it's only on that device until sync. Users who
  log in from a second device do **not** see in-progress drafts.
- **Frontend never deletes stale cache entries** — `local_cache`
  grows monotonically until "Clear local data" is invoked or the
  user clears site data. For long-lived sessions this is fine
  (each cache entry is small JSON), but it's worth knowing.
- **`gptutils` tables stay** — even though the AI app is stubbed
  ([`development/ai_integration.md`](ai_integration.md)), its
  tables (`gptutils_conversation`, `gptutils_message`) remain in
  the database via the existing migrations. Future external AI
  service can reuse them.
