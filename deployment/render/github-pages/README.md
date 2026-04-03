# GitHub Pages frontend deployment

This project deploys the three frontend apps to GitHub Pages from one workflow.

## Workflow
- `.github/workflows/frontend-pages.yml`

## Required repository secrets or variables
- `FRONTEND_API_BASE_URL` = `https://notenextra.trance-0.com/api/v1`
- `FRONTEND_BACKEND_ORIGIN` = `https://notenextra.trance-0.com`

## Notes
- This is a GitHub **project site**, so each app must build with a repo-prefixed base href:
  - `/Notechondria/editor/`
  - `/Notechondria/planner/`
  - `/Notechondria/portal/`
- Builds use `--no-web-resources-cdn` so runtime assets are bundled locally.
