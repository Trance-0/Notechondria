# Editor app (`frontend/editor_app/`)

Offline-first markdown note editor. One of three standalone Flutter apps
that share the same Notechondria backend.

Related: [planner_app](planner_app.md), [portal_app](portal_app.md),
[server/backend.md](../server/backend.md).

## Role

- Offline-capable authoring surface: notes, folders, tags, attachments.
- Local persistence via `shared_preferences` + filesystem under
  `SharedPreferences`-managed keys, so the app boots without network.
- Long-lived archive client, not the archive authority. The app should
  treat durable user writing as portable files first: GitHub-flavored
  Markdown for prose, JSON/frontmatter for structured metadata, and
  normal media files beside the entry. App databases, cloud sync, and
  importers are adapters around that portable shape.
- Optional cloud sync to Django when the user is signed in and the API
  base URL passes the [handshake check](../server/backend.md#handshake).
- Settings surface handles auth (login, register, OAuth with Google and
  GitHub), API base URL, API key rotation, change-email, change-password,
  identity-code verification, and theme.

## Portable diary format goal

The editor's compatibility target is a boring folder format that can be
read without Notechondria:

```text
journal/
  2026/
    2026-05-22/
      entry.md
      metadata.json
      media/
        IMG_001.heic
        voice.m4a
```

`entry.md` renders as GitHub-flavored Markdown. Metadata belongs in
YAML frontmatter and/or `metadata.json` so geodata, place names, weather,
mood, tags, source app, media pointers, created/updated timestamps, and
sync provenance remain structured instead of buried in prose. The format
can support modern post/blog structure beyond simple Markdown, but should
avoid opaque document containers such as DOCX or PDF as the canonical
storage layer.

Importer priority is one-way into local state first, with cloud sync
remaining an explicit later user action. Apple Journal, GitJournal,
Joplin, Obsidian, Day One, ZIP, JSONL, Git/WebDAV/S3/R2, and local
folder flows should all map into or out of this same Markdown/JSON/media
archive shape rather than becoming separate sources of truth.

The first Apple Journal importer phase is ZIP-only because Flutter web
can reliably read one selected archive, while recursive folder reads
need a desktop-only `dart:io` path. Settings -> Developer -> Import
Apple Journal ZIP parses Markdown/JSON entries, stores referenced media
in `LocalAttachmentStore`, writes GFM/frontmatter drafts into an
existing or new local category, logs each import stage in the Debug log,
and leaves cloud sync paused until the user explicitly runs Push local
-> cloud.

Note URLs use `#/notes/<uuid>` so the copied link and the browser URL
match the viewed note. Public UUID links render read-only when opened
cold; private links keep the URL in place and show a sign-in prompt
instead of redirecting back to the editor root.

Legacy owned categories named `Inbox` are handled as a user-directed
data migration. After a clean signed-in load, the editor offers to move
their notes into a new category or remove the old category property so
the notes fall into the uncategorized bucket. The backend already
preserves notes on category deletion via `course_id = NULL`, so this
flow does not require a schema migration.

## Shape

Self-contained Flutter workspace with its own
`pubspec.yaml`, `lib/`, `web/`, `windows/`, `test/`, `Dockerfile`,
`docker-compose.yml`, and `nginx/default.conf.template`. Navigation is
constrained to `Learner / Settings` surfaces.

### Library layout

`frontend/editor_app/lib/` is a single Dart library (`part of
notechondria_frontend`) split across these files:

| File | Responsibility |
| --- | --- |
| `main.dart` | Library declaration, top-level `main()`, launches `NotechondriaApp` with `visibleIndices` for this app. |
| `app_shell.dart` | The root widget + state: bootstraps local store, runs the settings-save flow, drives theme + API base URL, owns `_localSettings`, `_localDrafts`, `_localCourses`, `_localStats`, `_localCache`. Most feature logic now lives in `core/*.dart` extensions to keep the shell under the hard 1000-line ceiling. |
| `core/client.dart` | `NotechondriaClient` interface and `HttpNotechondriaClient` HTTP implementation; holds the base URL, `verifyHandshake`, token auth, debug snapshots. |
| `core/helpers.dart` | `_defaultApiBaseUrl`, `_kDefaultApiUrl` (compile-time via `--dart-define=DEFAULT_API_URL=...`), `_slugifyLocalText`, date helpers. |
| `core/local_store.dart` | `_LocalAppStore.load/save*` — every SharedPreferences key the app persists (settings, drafts, courses, stats, cache, UI logs, session token). |
| `core/url_strategy.dart` / `url_strategy_web.dart` | Path-URL strategy for web; conditional import keeps non-web builds pure Dart. |
| `components/` | Shared UI: `navigation.dart`, `avatar.dart`, `debug_widgets.dart`, `error_state.dart`, `note_viewer.dart`, `splash_screen.dart` (Krebs-cycle animation). |
| `modules/` | Feature screens: `learner.dart` (note list + editor), `settings.dart` (full account surface), plus stale copies of `front.dart`, `course.dart`, `activity.dart` that aren't on this app's nav but still compile. |

### Local store

`_LocalAppStore` in `core/local_store.dart` is the one place
SharedPreferences reads/writes happen. Keys:

- `settings` → `{api_base_url, theme_preset, theme_mode,
  log_preferences, updated_at}` and related.
- `drafts` → unsynced note drafts.
- `courses` → cached course list.
- `stats` → local counters (settings saves, sync count).
- `cache` → `{front_page, courses}` snapshots used for offline renders.
- `logs` → UI logs surfaced in the debug drawer.
- `session` → `{token, user}` after login, cleared on logout.

### Local folder mode (0.1.201)

On desktop Chromium over https or `http://127.0.0.1`, signed-out
Settings shows "Use a local folder (no account)". The picked folder
becomes the editor's storage: `HttpNotechondriaClient` runs over the
`LocalFolderController`'s `StorageModeClient`, and the shared in-page
backend answers every `/api/v1` call from files in the folder (notes,
categories, trash, history, snapshots, attachments, covers, avatar,
sessions, search, front page, heatmap). Only "Check for updates" reaches
the saved server, with no token. Firefox, Safari, and mobile show the
option disabled with the 1.8 reason.

- Wiring: `core/local_folder_connect.dart` (the `Editor.Startup/local_folder`
  step, the folder session and connect-time move of browser drafts, the
  verification rescan, the reconnect view, the status card);
  `cloudOnly` gates on the cloud-only Settings controls;
  `folderAwareImageProvider` for `nc-folder:` images.
- Tests: `test/local_folder_smoke.dart` (registered from
  `smoke_test.dart`, so CI runs it).
- Design: [`development/local_folder_mode.md`](../development/local_folder_mode.md);
  open items in [`TODO.md`](../TODO.md).

## API client contract

`HttpNotechondriaClient` talks to `<base>/api/v1/...`. See
[server/backend.md](../server/backend.md) for the endpoint list and
response shapes.

Key entry points:

- `updateBaseUrl(String)` — mutate the in-memory base URL without
  re-instantiating the client. Called when Settings persists a URL
  change or when `_loadLocalState` boots a saved value.
- `verifyHandshake(String)` — probes `<candidate>/handshake/`; see
  [handshake](../server/backend.md#handshake). Settings-save refuses
  to commit a URL that fails this check.
- `login / register / verifyEmail / oauth...` — auth surface.
- `getFrontPage / getCourses / getCourseNotes / getNote / updateNote`
  — read/write data.

- `subscribePrivateCourse` saves a foreign cloud course as a private
  sidebar subscription without changing ownership or republishing it.

## Build and deploy

- Local dev: `flutter run -d chrome` from `frontend/editor_app/`.
- Smoke test: `flutter test test/smoke_test.dart -r compact`.
- GitHub Pages: built by
  [`.github/workflows/frontend-pages.yml`](../../.github/workflows/frontend-pages.yml)
  with `--base-href "/Notechondria/editor/" --no-web-resources-cdn`.
- Self-hosted Docker: app-local `Dockerfile` + `docker-compose.yml`,
  joined to the `NOTECHONDRIA_SHARED_NETWORK` so it resolves the
  backend by its compose alias.

## Known drift and open work

See [index.md §6 "Open work / caution list"](../index.md#6-open-work--caution-list).
In particular:

- `app_shell.dart` remains above the 500-LOC target but below the
  hard 1000-line ceiling from `AGENTS.md/AGENTS.md` section 1.6.
- Stale modules `front.dart`, `course.dart`, `activity.dart`,
  `learner.dart` that this app's `visibleIndices` doesn't use still
  compile — deleting them needs the `app_shell.dart` mixin refactor.
