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
| `app_shell.dart` | The root widget + state: bootstraps local store, runs the settings-save flow, drives theme + API base URL, owns `_localSettings`, `_localDrafts`, `_localCourses`, `_localStats`, `_localCache`. ~2500 LOC — split candidates noted in [index.md §6](../index.md). |
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

- `app_shell.dart` is ~2500 LOC and `client.dart` is ~812 LOC — both
  above the 500-LOC target from `AGENTS.md/AGENTS.md` §1.5.
- Stale modules `front.dart`, `course.dart`, `activity.dart`,
  `learner.dart` that this app's `visibleIndices` doesn't use still
  compile — deleting them needs the `app_shell.dart` mixin refactor.
