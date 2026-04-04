# Notechondria Frontends

This directory contains three standalone Flutter apps:

- `editor_app/` — offline-first text editor and note workspace
- `planner_app/` — course/module planner and deadline tracker
- `portal_app/` — auth/orchestration shell that routes into the other apps

## Modules by app

### editor_app
Primary behavior:
- note list
- note metadata editing
- markdown import/export
- note editor with three modes:
  - plain text
  - dynamic markdown
  - block editor
- editor-focused settings:
  - login/sync
  - editor defaults/theme
  - debug log

### planner_app
Primary behavior:
- course view
- module discussion roots and local note comments
- deadline tracker / activity view
- offline planner events
- planner-focused settings:
  - login/sync
  - deadline ordering weights + theme
  - debug log

### portal_app
Primary behavior:
- auth/orchestration shell
- launch links into editor/planner workspaces
- cloud-oriented settings surface

## Deployment

Frontend GitHub Pages deploys all three apps from one workflow:
- `.github/workflows/frontend-pages.yml`

GitHub Pages project-site paths:
- `/Notechondria/editor/`
- `/Notechondria/planner/`
- `/Notechondria/portal/`

Pages runtime choices:
- local bundled web runtime assets (`--no-web-resources-cdn`)
- disabled published service-worker bootstrap
- root landing page links to all three apps
- default API target on Pages: `https://notechondria.trance-0.com/api/v1`

On local full-stack browser deploys (`localhost` / `127.0.0.1`), the apps default to same-origin `/api/v1`.

## Verification

Run from `frontend/`:

```bash
for app in editor_app planner_app portal_app; do
  (cd "$app" && flutter test test/smoke_test.dart -r compact)
  (cd "$app" && flutter build web --release --base-href "/${app%_app}/" --no-web-resources-cdn)
done
```
