# Notechondria — Project Overview

Human-facing summary of what Notechondria is and how it runs. For deep
agent-facing architecture, state, and pitfall notes see
[`docs/index.md`](index.md).

## What it is

Notechondria is a three-app Flutter frontend plus a Django + DRF backend for
note-taking, course planning, and offline/online synchronization.

- **Editor app** (`frontend/editor_app/`) — offline-first markdown note editor
  with optional cloud sync.
- **Planner app** (`frontend/planner_app/`) — course/module planner with
  deadline tracking, calendar, and discussion-oriented planning flows.
- **Portal app** (`frontend/portal_app/`) — orchestration shell that routes
  authenticated users to editor/planner and handles cloud preferences.
- **Backend** (`backend/`) — Django + DRF + PostgreSQL, providing auth,
  notes, courses, planner events, subscriptions, and recycle bin.

The three Flutter apps are independently buildable and independently
deployable. They share the same backend.

## How it runs

### Local development

- **Backend**: Python 3.11+ with `uv`/`pip`, requires PostgreSQL on
  `localhost:5432`. See [`docs/development/local_dev.md`](development/local_dev.md)
  and [`docs/development/python_environments.md`](development/python_environments.md).
- **Frontend**: Flutter (git-source on Linux, installed SDK on
  macOS/Windows). Each app is a self-contained Flutter workspace; build and
  test per-app.

Quick smoke (all three frontend apps):

```bash
for app in frontend/editor_app frontend/planner_app frontend/portal_app; do
  (cd "$app" && flutter test test/smoke_test.dart -r compact)
  (cd "$app" && flutter build web --release \
     --base-href "/Notechondria/${app##*/_}/" --no-web-resources-cdn)
done
```

### Deployment topology

Four supported paths, each with its own folder under `deployment/`:

- **Render (backend)** — `deployment/render/`. Free-tier friendly:
  `backend/requirements-render.txt` excludes heavy ML deps, WhiteNoise serves
  static assets, `DATABASE_URL` is parsed via `dj-database-url`. See
  [`docs/deployment/render_free_tier.md`](deployment/render_free_tier.md).
- **Jenkins (full-stack self-hosted)** — `deployment/jenkins/`. Backend and
  frontend test and deploy stages run in parallel; `deployment/jenkins/scripts/`
  holds the helpers. See [`docs/deployment/deploy.md`](deployment/deploy.md).
- **Docker (local/self-hosted full stack)** — `deployment/docker/`. Root
  `docker-compose.yml` composes backend + three frontend apps behind a
  gateway nginx that routes `/api/v1` to Django.
- **GitHub Pages (frontend only)** — one workflow per app under
  `.github/workflows/`. Base-hrefs are repo-prefixed
  (`/Notechondria/editor/`, `/Notechondria/planner/`,
  `/Notechondria/portal/`) because this is a GitHub project site.
- **Northflank** — `deployment/northflank.json` +
  [`docs/deployment/northflank.md`](deployment/northflank.md).

### Frontend default API base

- GitHub Pages → `https://notechondria.trance-0.com/api/v1`
- `localhost` / `127.0.0.1` → same-origin `${origin}/api/v1`
- Docker full-stack → gateway nginx routes `/api/v1` to the backend

## Where to go next

- [`docs/index.md`](index.md) — long-form architecture, state snapshot,
  open-work / caution list, prompt recipe for continuing agent work.
- [`docs/TASKS.md`](TASKS.md) — active task list (versioning rules inside).
- [`docs/versions/`](versions/) — per-release changelog (`0.1.x`).
- [`docs/api/backend_api_spec.md`](api/backend_api_spec.md) — backend API
  surface.
- [`docs/operations/postgres_migration.md`](operations/postgres_migration.md)
  — backup/restore workflow.
- [`docs/testing/backend_test_plan.md`](testing/backend_test_plan.md) —
  backend test plan.
- [`../LLM_CHECK.md`](../LLM_CHECK.md) — end-of-round checklist.
- [`../AGENTS.md`](../AGENTS.md) — agent rules (inherited via the
  `Trance-0/AGENTS.md` submodule at `.agents/`).
