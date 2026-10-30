# Notechondria

Notechondria is a note-taking and course-planning system: three standalone
Flutter apps that work offline first and sync through one Django backend.

All three apps can also run with no account and no server (editor since
0.1.201, planner and portal since 0.1.202): on desktop Chromium (Chrome,
Edge), "Use a local folder (no account)" stores notes, courses, planner
events, and imported calendars as plain files in a folder the user picks,
and the page answers the API itself. Design:
[`docs/development/local_folder_mode.md`](docs/development/local_folder_mode.md).

## Components
- `frontend/editor_app/` — offline-first markdown note editor
- `frontend/planner_app/` — course/module planner and deadline tracker
- `frontend/portal_app/` — public front page and orchestration shell
- `frontend/notechondria_shared/` — shared Flutter package used by all three
- `backend/` — Django + DRF + PostgreSQL, API under `/api/v1/`
- `cli/` — stdio MCP server that talks to the REST API

## Live
- Apps (GitHub Pages):
  [portal](https://trance-0.github.io/Notechondria/portal/),
  [editor](https://trance-0.github.io/Notechondria/editor/),
  [planner](https://trance-0.github.io/Notechondria/planner/)
- Docs: <https://trance-0.github.io/Notechondria/docs/>
- Backend API (Northflank): `https://notechondria.trance-0.com/api/v1/`;
  the version probe is
  <https://notechondria.trance-0.com/api/v1/handshake/>

## Local preview against the remote backend
Builds the three web apps from this checkout in Docker and serves them on
loopback, proxying `/api/`, `/media/`, and `/static/` to the production
backend. No local backend, database, or credentials. Use a host with at
least 16 GB RAM (see `docs/AGENTS.md`, "Host resource budget").

```bash
scripts/local_remote_deploy.sh up     # build one app at a time, then start
scripts/local_remote_deploy.sh down   # stop and remove the containers
```

- `http://127.0.0.1:9068/portal/`, `/editor/`, `/planner/` (bound to
  `127.0.0.1` only)
- Builds are stamped with `VERSION`, so no false "new version" banner.
- Runbook: [`docs/deployment/local_preview.md`](docs/deployment/local_preview.md).

## Deployment methods
- GitHub Pages — frontend (`.github/workflows/frontend-pages.yml`) and docs
  (`.github/workflows/docs-pages.yml`), on push to `main`
- Northflank — backend (`northflank.json`), deploys on commit
- `deployment/jenkins/` — self-hosted full stack; Ubuntu installer
  `deployment/jenkins/install-jenkins.sh`
- `deployment/docker/` — self-hosted Docker full stack and the local
  preview gateway
- `deployment/render/` — Render backend (free tier; uses
  `backend/runtime.txt`, `backend/.python-version`,
  `backend/requirements-render.txt`)

## Docs

Full documentation site (rebuilt on every push to `main`, per
`.github/workflows/docs-pages.yml`):
**<https://trance-0.github.io/Notechondria/docs/>**.

Entry points:

- [`docs/readme.md`](docs/readme.md) — human-facing project
  overview (slightly longer version of this file).
- [`docs/index.md`](docs/index.md) — agent-facing long-form
  architecture + open-work list + project-specific overrides.
- [`docs/client/`](docs/client/) — per-app frontend docs
  (editor, planner, portal) + the shared `notechondria_shared`
  package.
- [`docs/server/`](docs/server/) — backend deep dives (overview,
  `creators`, `notes`, `mcp`).
- [`docs/deployment/`](docs/deployment/) — deploy runbooks
  (Docker-compose / Jenkins / Render / Northflank / GitHub Pages / local
  preview / Release process).
- [`docs/versions/`](docs/versions/) — per-release changelog
  (`0.1.x` series).
- [GitHub issues](https://github.com/Trance-0/Notechondria/issues) — active work list;
  [`docs/TODO.md`](docs/TODO.md) records the tracker migration.

## Frontend default API behavior
- On GitHub Pages: defaults to `https://notechondria.trance-0.com/api/v1`
- On local browser full-stack deploy (`localhost` / `127.0.0.1`): defaults to same-origin `${origin}/api/v1`
- In Docker full-stack deploy: root gateway nginx routes `/api/v1` to the Django backend
- Local web apps against the remote backend: `scripts/local_remote_deploy.sh up` serves all three on `http://127.0.0.1:9068/` (loopback only) and proxies `/api/` to `https://notechondria.trance-0.com`. Details: [`docs/development/local_dev.md`](docs/development/local_dev.md).

## Per-app OAuth redirect URIs (since 0.1.90)

- The backend matches the request `Origin` header against the
  comma-separated allow-lists below and returns the matching URI to
  whichever Flutter app calls `/api/v1/auth/oauth-config/`. Each entry
  must also be pre-registered with the OAuth provider (Google
  "Authorized redirect URIs" / GitHub OAuth App callback URL).
  - `GOOGLE_AUTHORIZED_REDIRECT_URIS=https://editor.example/,https://portal.example/,https://planner.example/`
  - `GITHUB_AUTHORIZED_REDIRECT_URIS=...same shape...`
- Legacy single-value `GOOGLE_AUTHORIZED_REDIRECT_URI` /
  `GITHUB_AUTHORIZED_REDIRECT_URI` continue to work as a fallback.

## Experimental: GitHub data-sync (since 0.1.90, push pipeline wired in 0.1.93)

- See [`docs/integrations/github-sync.md`](docs/integrations/github-sync.md)
  for the full flow + repo layout + restore steps.
- Required env: `GITHUB_DATA_SYNC_APP_NAME`,
  `GITHUB_DATA_SYNC_APP_CLIENT_ID`, `GITHUB_DATA_SYNC_APP_CLIENT_SECRET`,
  `GITHUB_DATA_SYNC_APP_PRIVATE_KEY` (single-line PEM with `\n`
  escapes), `GITHUB_DATA_SYNC_APP_INSTALL_URL`.
- The frontend exposes a "Connect to GitHub" card in Settings → API
  settings on every app. Once connected, pick a repo from the
  dropdown and hit "Push now"; the backend signs an App JWT,
  exchanges it for an installation token, and PUTs every materialized
  file via the GitHub Contents API.
- Toggle "Include assets" before pushing (since 0.1.94) to inline
  avatar / cover / attachment bytes under `assets/...` so the clone
  is self-contained. Per-file 50 MB / per-push 200 MB caps; oversized
  files are recorded in `manifest.skipped_assets`.
- Restore from a cloned backup repo via
  [`backend/scripts/github_sync_restore.py`](backend/scripts/github_sync_restore.py)
  (stdlib-only; supports `--dry-run` and `--include-assets`).

## Local verification
```bash
for app in frontend/editor_app frontend/planner_app frontend/portal_app; do
  (cd "$app" && flutter test test/smoke_test.dart -r compact)
  (cd "$app" && flutter build web --release --base-href "/$(basename "$app" _app)/" \
    --no-web-resources-cdn --dart-define=APP_VERSION="$(cat ../../VERSION)")
done
```

## Developer scripts

```english
Continue working on this project, with prompts in ./docs/TODO.md.
```

Local full-stack Jenkins deployment (PostgreSQL, Django, three apps, gateway,
Casdoor and GitHub sync) uses a private root `local.env`. See
[deployment/jenkins/README.md](deployment/jenkins/README.md).
