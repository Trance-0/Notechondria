# GitHub Pages frontend deployment

This project deploys the three frontend apps to GitHub Pages from one workflow.

## Workflow
- `.github/workflows/frontend-pages.yml`

## Required repository secrets or variables
- `FRONTEND_API_BASE_URL` = `https://notenextra.trance-0.com/api/v1`
- `FRONTEND_BACKEND_ORIGIN` = `https://notenextra.trance-0.com`

## Required GitHub repository settings
Merging workflow files alone may not be enough in the upstream repo. Check:

1. **Actions enabled** for the repository
2. **Workflow permissions** set to **Read and write permissions**
3. **Pages enabled** and publishing from `gh-pages`
4. If required by the repo policy, approve first-time workflows in the Actions UI

## Notes
- This is a GitHub **project site**, so each app must build with a repo-prefixed base href:
  - `/Notechondria/editor/`
  - `/Notechondria/planner/`
  - `/Notechondria/portal/`
- Builds use `--no-web-resources-cdn` so runtime assets are bundled locally.
