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

## Frontend default API behavior
- On GitHub Pages: defaults to `https://notenextra.trance-0.com/api/v1`
- On local browser full-stack deploy (`localhost` / `127.0.0.1`): defaults to same-origin `${origin}/api/v1`
- In Docker full-stack deploy: root gateway nginx routes `/api/v1` to the Django backend

## Local verification
```bash
for app in frontend/editor_app frontend/planner_app frontend/portal_app; do
  (cd "$app" && flutter test test/smoke_test.dart -r compact)
  (cd "$app" && flutter build web --release --base-href "/${app##*/_app}/" --no-web-resources-cdn)
done
```
