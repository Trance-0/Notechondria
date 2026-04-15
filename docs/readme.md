# Notechondria — Project Overview

Human-facing summary of what Notechondria is and how it runs. For deep
agent-facing architecture, project-specific overrides, and the
open-work list, see [`docs/index.md`](index.md). For the shared
cross-project agent rules, see the `AGENTS.md/` submodule (pinned to
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

## How it runs

### Local development

- **Backend**: Python 3.9 (the Dockerfile pins it; PEP 604 unions are
  banned — see [`index.md §0`](index.md#0-project-specific-overrides)),
  PostgreSQL on `localhost:5432`. See
  [`development/local_dev.md`](development/local_dev.md) and
  [`development/python_environments.md`](development/python_environments.md).
- **Frontend**: Flutter per-app (editor/planner/portal). Each is a
  self-contained workspace with its own `pubspec.yaml`.

Quick smoke (all three frontend apps):

```bash
for app in frontend/editor_app frontend/planner_app frontend/portal_app; do
  (cd "$app" && flutter test test/smoke_test.dart -r compact)
done
```

### Deployment topology

Five supported paths, each with its own folder under `deployment/`:

- **Render (backend only, free-tier)** — see
  [`deployment/render_free_tier.md`](deployment/render_free_tier.md).
- **Northflank (backend only)** — see
  [`deployment/northflank.md`](deployment/northflank.md). Template at
  repo-root `northflank.json`.
- **Jenkins (full-stack self-hosted)** — see
  [`deployment/deploy.md`](deployment/deploy.md).
- **Docker (local/self-hosted full stack)** — root
  [`docker-compose.yml`](../docker-compose.yml).
- **GitHub Pages (frontend only)** — one workflow under
  [`.github/workflows/frontend-pages.yml`](../.github/workflows/frontend-pages.yml)
  builds all three apps. Base-hrefs are repo-prefixed
  (`/Notechondria/editor/`, `/Notechondria/planner/`,
  `/Notechondria/portal/`).

### Frontend API base URL

Resolved by `_defaultApiBaseUrl()` in each app's
`lib/core/helpers.dart`. Override at build time with
`--dart-define=DEFAULT_API_URL=https://your-backend/api/v1`. When a
user edits the URL in Settings, the client calls
[`verifyHandshake`](server/backend.md#handshake) against the candidate
before committing.

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
- [`deployment/`](deployment/) — one file per deploy target.
- [`development/ai_integration.md`](development/ai_integration.md) —
  current AI stub state and the future HTTP-microservice plan.
- [`operations/postgres_migration.md`](operations/postgres_migration.md)
  — backup/restore runbook.
- [`testing/backend_test_plan.md`](testing/backend_test_plan.md).
- [`../LLM_CHECK.md`](../LLM_CHECK.md) — end-of-round checklist.
- [`../AGENTS.md/AGENTS.md`](../AGENTS.md/AGENTS.md) — shared
  cross-project agent contract (submodule, pinned).
