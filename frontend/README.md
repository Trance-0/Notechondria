# Frontend workspace

`frontend/` now contains exactly three app directories:

- `editor_app/` — offline-first markdown editor with optional sync
- `planner_app/` — course planning, module board, and calendar workflows
- `portal_app/` — online auth, cloud preferences, and router-shell orchestration

## Current app intent

### 1) `editor_app`
Primary role:
- local/offline note creation
- note list ordered by created time
- keyword search
- edit/view workflows
- local settings and sync endpoint configuration

Current runtime shape in this pass:
- boots independently
- builds independently for web
- navigation constrained to learner/settings surfaces

### 2) `planner_app`
Primary role:
- course list / project list
- module-oriented course view
- activity and calendar planning
- discussion-board-oriented course/module surfaces

Current runtime shape in this pass:
- boots independently
- builds independently for web
- navigation constrained to front/course/activity surfaces

### 3) `portal_app`
Primary role:
- online-only auth and account orchestration
- cloud preference storage
- router shell around the editor/planner workspaces
- future git-like versioning entry surface

Current runtime shape in this pass:
- boots independently
- builds independently for web
- navigation is constrained to `Portal` + `Settings`
- front page is an orchestration dashboard with launch targets for editor/planner instead of a broad integrated copy

## Local verification completed in this environment

Using a git-source Flutter install on arm64 Linux:

- `flutter test test/smoke_test.dart` passed for:
  - `frontend/editor_app`
  - `frontend/planner_app`
  - `frontend/portal_app`
- `flutter build web --release` passed for:
  - `frontend/editor_app`
  - `frontend/planner_app`
  - `frontend/portal_app`

## Important verification caveat

The old upstream root frontend test suite was **not green** before the split. In this environment, the upstream root app failed at least one widget test (`opens course note in reader dialog`) before the cleanup work. Treat this branch as a clean split starting point, not as proof that every feature contract is already fully re-separated internally.

## Environment variables

For local or CI builds, the key frontend variables are:

- `FRONTEND_API_BASE_URL` — browser-reachable API base URL, e.g. `https://example.com/api/v1`
- `FRONTEND_BACKEND_ORIGIN` — nginx proxy target for `/api`, `/admin`, `/static`, `/media`
- `NOTECHONDRIA_SHARED_NETWORK` — shared Docker network name for full-stack local deployment

Keep `FRONTEND_API_BASE_URL` absolute.

### GitHub Actions / repo secrets

The current Pages workflows can build without private secrets if the public API URL is hardcoded in source defaults, but for real deployment you should record these repository-level secrets or variables:

- `FRONTEND_API_BASE_URL`
- `FRONTEND_BACKEND_ORIGIN`

Minimal setup path:

1. Open GitHub repository settings.
2. Go to **Secrets and variables → Actions**.
3. Add `FRONTEND_API_BASE_URL` with the public API endpoint.
4. Add `FRONTEND_BACKEND_ORIGIN` with the proxy origin used by nginx/container deployments.

If you prefer checked-in local defaults for development, keep them in a non-secret env file outside git and feed them into Docker Compose or local shell exports.

## GitHub Pages workflow

GitHub Actions builds all three apps from `codex` in one combined workflow:

- `.github/workflows/frontend-pages.yml`

Deployment targets:

- `/editor/`
- `/planner/`
- `/portal/`

Important Pages runtime notes:
- builds use `--no-web-resources-cdn` so CanvasKit/web runtime assets are bundled locally instead of fetched from Google CDN
- the published bootstrap is rewritten to disable service-worker registration, reducing stale-cache breakage after bad deploys
- the site root includes a small landing page linking to all three apps

## App-local Docker assets

Each app now contains its own:

- `Dockerfile`
- `docker-compose.yml`
- `nginx/default.conf.template`

That keeps home/self-host deployment aligned with the three-app split instead of the old single frontend container.
