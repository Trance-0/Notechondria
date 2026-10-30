# Notechondria — Project Overview

Human-facing summary of what Notechondria is and how it runs.

- Arriving from GitHub? The repo-root [`README.md`](../README.md) has
  the elevator pitch and quick-start block; this page is the
  slightly-longer tour.
- For deep agent-facing architecture, project-specific overrides,
  and the open-work list, see [`docs/index.md`](index.md).
- For shared cross-project agent rules, see the `AGENTS.md/`
  submodule (pinned to
  [`Trance-0/AGENTS.md`](https://github.com/Trance-0/AGENTS.md)).

## What it is

Notechondria is a **three-app Flutter frontend** plus a **Django + DRF
backend** for note-taking, course planning, and offline/online
synchronization. All three frontends share the one backend over a
single versioned API surface (`/api/v1/...`).

| Component | Path | Docs |
| --- | --- | --- |
| Editor (offline-first markdown notes) | `frontend/editor_app/` | [`client/editor_app.md`](client/editor_app.md) |
| Planner (courses + calendar + activity) | `frontend/planner_app/` | [`client/planner_app.md`](client/planner_app.md) |
| Portal (public landing + full shell) | `frontend/portal_app/` | [`client/portal_app.md`](client/portal_app.md) |
| Backend (Django + DRF + Postgres) | `backend/` | [`server/backend.md`](server/backend.md) |

The three Flutter apps are independently buildable and independently
deployable.

### Storage tiers

- **Cloud**: the Django backend (PostgreSQL, R2 media), when signed in.
- **Browser-local**: `SharedPreferences` and IndexedDB in each app, for
  signed-out use and offline drafts.
- **Local folder** (desktop Chromium over https or `http://127.0.0.1`;
  editor since 0.1.201, planner and portal since 0.1.202): "Use a local
  folder (no account)" in each app's signed-out Settings makes a picked
  folder the app's storage. Notes are Markdown files with JSON sidecars;
  planner events and calendar feeds are files under `planner/`. The
  shared package's in-page backend
  (`frontend/notechondria_shared/lib/src/local_folder/`) answers the
  `/api/v1` calls, so no note or planner data goes to the server. Other
  browsers show the option disabled with the reason. Design:
  [`development/local_folder_mode.md`](development/local_folder_mode.md);
  storage summary in
  [`development/storage_model.md`](development/storage_model.md).

## How it runs

### Local development

- **Backend**: Python 3.9 (the Dockerfile pins it; PEP 604 unions are
  banned — see [`index.md §0`](index.md#0-project-specific-overrides)),
  PostgreSQL on `localhost:5432`. See
  [`development/local_dev.md`](development/local_dev.md) and
  [`development/python_environments.md`](development/python_environments.md).
- **Frontend**: Flutter per-app (editor/planner/portal). Each is a
  self-contained workspace with its own `pubspec.yaml`.
- **Web apps against the remote backend**: `scripts/local_remote_deploy.sh
  up` builds the three apps in Docker. It serves them at
  `http://127.0.0.1:9068/{portal,editor,planner}/` (loopback only) behind
  an nginx gateway that proxies `/api/` to
  `https://notechondria.trance-0.com`. Env vars: `LOCAL_GATEWAY_HOST_PORT`
  and `REMOTE_BACKEND_ORIGIN`. Images carry the repo `VERSION` as
  `APP_VERSION`, and containers restart with Docker until `down`. Hosts
  with at least 16 GB RAM only. See
  [`deployment/local_preview.md`](deployment/local_preview.md) and
  [`development/local_dev.md`](development/local_dev.md).

Bootstrap, in order:

```bash
git clone --recurse-submodules https://github.com/Trance-0/Notechondria.git
cd Notechondria
free -h && nproc && docker ps             # host budget check (docs/AGENTS.md)
scripts/local_remote_deploy.sh up         # web apps vs. the remote backend
# or, with a Flutter SDK, one app at a time:
(cd frontend/editor_app && flutter pub get && flutter run -d chrome --web-port 9060)
# backend (Python + PostgreSQL), see development/local_dev.md:
(cd backend && python -m venv .venv && . .venv/bin/activate \
  && pip install -r requirements.txt && python manage.py migrate \
  && python manage.py runserver 127.0.0.1:9090)
```

Quick smoke (all three frontend apps):

```bash
for app in frontend/editor_app frontend/planner_app frontend/portal_app; do
  (cd "$app" && flutter test test/smoke_test.dart -r compact)
done
```

### Deployment topology

Live today: the frontend and docs on GitHub Pages and the backend on
Northflank. The other paths are self-host or preview options.

- **GitHub Pages (frontend)** — live at
  <https://trance-0.github.io/Notechondria/portal/> (also `/editor/`,
  `/planner/`).
  [`.github/workflows/frontend-pages.yml`](../.github/workflows/frontend-pages.yml)
  builds all three apps on push to `main`, with repo-prefixed base hrefs
  and `APP_VERSION` set from the repo `VERSION`.
- **GitHub Pages (docs)** — live at
  <https://trance-0.github.io/Notechondria/docs/>, built by
  [`.github/workflows/docs-pages.yml`](../.github/workflows/docs-pages.yml)
  into a disjoint `gh-pages` subtree.
- **Northflank (backend)** — live at `https://notechondria.trance-0.com`
  and deploys on commit. See
  [`deployment/northflank.md`](deployment/northflank.md); template at
  repo-root `northflank.json`.
- **Render (backend only, free-tier)** — see
  [`deployment/render_free_tier.md`](deployment/render_free_tier.md).
- **Jenkins (full-stack self-hosted)** — Ubuntu installer
  `deployment/jenkins/install-jenkins.sh` (Jenkins on `127.0.0.1:8080`),
  sequential test/backup/deploy stages, and a final
  `verify_deployment.sh` gate on the gateway routes. See
  [`deployment/deploy.md`](deployment/deploy.md) and
  [`../deployment/jenkins/README.md`](../deployment/jenkins/README.md).
- **Docker (self-hosted full stack)** — root
  [`docker-compose.yml`](../docker-compose.yml).
- **Local preview (loopback)** — `scripts/local_remote_deploy.sh up`
  serves the three apps on `127.0.0.1:9068` against the Northflank
  backend. See [`deployment/local_preview.md`](deployment/local_preview.md).

### Frontend API base URL

Resolved by `_defaultApiBaseUrl()` in each app's
`lib/core/helpers.dart`. Override at build time with
`--dart-define=DEFAULT_API_URL=https://your-backend/api/v1`. When a
user edits the URL in Settings, the client calls
[`verifyHandshake`](server/backend.md#handshake) against the candidate
before committing.

### Startup when the backend is down (since 0.1.198)

Each app paints its local data first and never waits on the backend
without a bound:

- `web/index.html` shows a static copy of the splash header (no spinner)
  until Flutter's first frame, and the Flutter splash takes over in the same
  place, so there is one loading screen (since 0.1.199). The splash names
  the running step, for example `Connecting to server:
  Planner.Startup/handshake`. If the Flutter loader fails to download or
  throws, or nothing has rendered after 20s, the page shows the cause and a
  Reload button.
- Backend requests made during startup, the error banner's Retry, and its
  Work offline are capped at 10s, and later requests in the same pass fail
  fast after the first timeout. An unresponsive backend therefore ends in the
  "Cloud data not loaded: <App>.Startup/bootstrap — the server did not
  respond within 10s" banner over local data, with Work offline and Retry.
- A startup step that throws (for example a corrupt local cache) shows a
  failure screen with Retry and Continue anyway. Uncaught errors before the
  first frame, and widget build errors, render visible fallbacks instead of
  a blank page.
- Every startup step (local data, API base, handshake, session restore,
  sign-in callback, initial data) writes a `<App>.Startup/<step>` record to
  the debug log (Settings > Debug log) with its duration and, on failure,
  the cause, such as `timeout after 10s (server did not respond)` or
  `connection refused`. Messages, banners, and dialog errors are selectable
  and have a Copy button (since 0.1.199).
- The planner imports `.ics` files on the device when signed out, offline,
  or when the server is unreachable, and keeps them across reloads
  (since 0.1.199; see
  [`client/planner_app.md`](client/planner_app.md#offline-calendar-import-01199)).
  Subscribing to a calendar URL still needs a cloud session.

See the `src/startup/` section of
[`client/notechondria_shared.md`](client/notechondria_shared.md).

The separate version banner compares the build's `APP_VERSION` with the
backend handshake. A newer backend shows "A new version is available.
Refresh to update."; an older backend shows "A new version is rolling
out". A build without `APP_VERSION` reports `0.1.21` and shows a false
update banner, so every build path passes it (see
[`development/local_dev.md`](development/local_dev.md#version-stamping-and-the-version-banner)).

### Per-app OAuth redirect URIs (since 0.1.90)

When editor / planner / portal share one backend, each app needs its
own OAuth callback host. The backend now accepts a comma-separated
allow-list and chooses the matching entry by request `Origin`/`Referer`:

- `GOOGLE_AUTHORIZED_REDIRECT_URIS`
- `GITHUB_AUTHORIZED_REDIRECT_URIS`

Each URI must be pre-registered in the corresponding provider console.
The legacy single-value `GOOGLE_AUTHORIZED_REDIRECT_URI` /
`GITHUB_AUTHORIZED_REDIRECT_URI` env vars remain as a fallback.

### Per-user MCP skill (since 0.1.90)

Every authenticated user has a `Creator.mcp_skill_md` text field
editable in Settings → API settings. Its contents are returned as the
`instructions` field of the MCP `initialize` JSON-RPC response so any
agent connecting via `Bearer ntc_<key>` reads the user's import /
export playbook on connect.

### Custom note meta variables (since 0.1.90)

Notes carry a free-form JSON object on `Note.custom_meta`, surfaced in
all three apps' note metadata dialogs as an expandable
key/value list. The shared widget lives at
`notechondria_shared/lib/src/components/custom_meta_list_editor.dart`
and is exported as `CustomMetaController` + `CustomMetaListEditor`.
Custom keys round-trip to YAML frontmatter when the GitHub-sync export
runs.

### Experimental: GitHub data-sync (since 0.1.90, push pipeline wired in 0.1.93)

Per-user backup of all server-held text + metadata into a GitHub
repository the user owns. Materializes Creator profile, app settings,
MCP skill, courses, notes (incl. custom_meta), planner events, and
calendar feeds; static assets we host (avatars, attachments, cover
images) are referenced by URL only. See
[`integrations/github-sync.md`](integrations/github-sync.md) for the
full repo layout, env-var contract, and the open static-asset gap.

Once `GITHUB_DATA_SYNC_APP_*` env vars are set on the backend, every
authenticated app (editor / planner / portal) shows a "Connect to
GitHub" card in Settings → API settings. After installing the
Notechondria GitHub App, the user picks a repo from the dropdown and
clicks "Push now"; the backend signs an App JWT, exchanges it for a
short-lived installation token, and PUTs every materialized file via
the GitHub Contents API. Toggle "Include assets" before pushing
(since 0.1.94) to inline avatar / cover / attachment bytes under
`assets/...` so the clone is genuinely self-contained — subject to
50 MB per-file and 200 MB per-push caps; oversized files are
recorded in `manifest.skipped_assets` and the parent record's URL
reference is preserved unchanged. Restore is a separate stdlib-only
CLI at
[`../backend/scripts/github_sync_restore.py`](../backend/scripts/github_sync_restore.py)
(`--dry-run` and `--include-assets` supported; reruns are idempotent
via `client_draft_id`).

## Installing on a phone (web channel)

The web build is the only mobile delivery channel right now (the
release workflow's iOS archives are unsigned and need a Mac to
install). The supported path is **Add to Home Screen**:

- **iPhone (Safari)**: open the app URL, tap Share, then
  "Add to Home Screen". The installed app gets a standalone window,
  its own icon/name, and its storage is exempt from Safari's 7-day
  script-writable-storage eviction — a plain bookmark is not, so
  local-only drafts in a bookmark can be evicted after a week of
  inactivity. Signing in (cloud sync) is the durable option either
  way.
- **Android (Chrome)**: open the app URL and accept the install
  prompt (or menu > "Add to Home screen").

Since 0.1.196 the Pages builds register no service worker (the
`STRIP_SERVICE_WORKER` kill switch in `frontend-pages.yml` is on, because
this Flutter SDK deprecated its worker). Every launch fetches the current
bundle, so an installed app needs a connection to open. Data already saved
on the device stays available after it opens.

## Where to go next

- [`index.md`](index.md) — project-local agent rules (§0),
  long-form architecture, state snapshot, open-work / caution list.
- [`client/`](client/) — per-app frontend docs (editor / planner /
  portal).
- [`server/backend.md`](server/backend.md) — Django apps, models,
  views, services, handshake, middleware, deploy entrypoint.
- [`TODO.md`](TODO.md) — active work list (versioning rules inside).
- [`versions/`](versions/) — per-release changelog (`0.1.x`).
- [`api/backend_api_spec.md`](api/backend_api_spec.md) — API surface.
- [`deployment/`](deployment/) — one file per deploy target, including
  [`deployment/local_preview.md`](deployment/local_preview.md).
- [`development/ai_integration.md`](development/ai_integration.md) —
  current AI stub state and the future HTTP-microservice plan.
- [`development/cross_platform_plan.md`](development/cross_platform_plan.md)
  — progress snapshot, mobile-web findings (incl. the same-origin
  storage collision behind the multi-app auth corruption), tutorials
  design, and the phased cross-platform roadmap.
- [`operations/postgres_migration.md`](operations/postgres_migration.md)
  — backup/restore runbook.
- [`operations/local_backup_restore.md`](operations/local_backup_restore.md)
  - click-run Python backup/restore scripts for PostgreSQL and
  Cloudflare R2 using repo-root `.env`.
- [`testing/backend_test_plan.md`](testing/backend_test_plan.md).
- [`LLM_CHECK.md`](LLM_CHECK.md) — end-of-round checklist.
- [`../AGENTS.md/AGENTS.md`](../AGENTS.md/AGENTS.md) — shared
  cross-project agent contract (submodule, pinned).

Local full-stack Jenkins deployment pulls GitHub `main` on push webhooks.
PostgreSQL, Django, three apps, gateway, Casdoor and GitHub sync use a private
root `local.env` on the local build agent. See
[Jenkins runbook](../deployment/jenkins/README.md).
