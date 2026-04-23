# Notechondria

Notechondria is split into three standalone Flutter frontends plus one Django backend.

## Frontends
- `frontend/editor_app/` — offline-first note editor
- `frontend/planner_app/` — course/module planner and deadline tracker
- `frontend/portal_app/` — orchestration shell

## Backend
- `backend/` — Django + DRF + PostgreSQL

## Root files
Only essential root files are kept here:
- `README.md`
- `Jenkinsfile`
- `docker-compose.yml`
- `render-deploy.sh`

## Render runtime note
Render should use the backend runtime files:
- `backend/runtime.txt`
- `backend/.python-version`
- `backend/requirements-render.txt`

## Deployment methods
- `deployment/jenkins/` — full-stack Jenkins deployment
- `deployment/docker/` — local/self-hosted Docker full stack
- `deployment/render/` — Render backend + GitHub Pages frontend

## Docs

Full documentation site (rebuilt on every push to `main`, per
`.github/workflows/frontend-pages.yml`):
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
  (Docker-compose / Render / Northflank / GitHub Pages / Release
  process).
- [`docs/versions/`](docs/versions/) — per-release changelog
  (`0.1.x` series).
- [`docs/TODO.md`](docs/TODO.md) — active work list.

## Frontend default API behavior
- On GitHub Pages: defaults to `https://notechondria.trance-0.com/api/v1`
- On local browser full-stack deploy (`localhost` / `127.0.0.1`): defaults to same-origin `${origin}/api/v1`
- In Docker full-stack deploy: root gateway nginx routes `/api/v1` to the Django backend

## Local verification
```bash
for app in frontend/editor_app frontend/planner_app frontend/portal_app; do
  (cd "$app" && flutter test test/smoke_test.dart -r compact)
  (cd "$app" && flutter build web --release --base-href "/${app##*/_app}/" --no-web-resources-cdn)
done
```

## Developer scripts

```english
Continue working on this project, with prompts in ./docs/TODO.md.
```
