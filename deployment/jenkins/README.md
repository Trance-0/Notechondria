# Jenkins full-stack deployment

This target uses Jenkins to test and deploy the full stack:
- Django backend
- PostgreSQL database
- backend nginx
- editor frontend
- planner frontend
- portal frontend
- root gateway nginx

## Files
- `scripts/` — Jenkins helper scripts
- `.env.example` — environment example for Jenkins-injected values

## Pipeline shape
1. prepare environment
2. backup database
3. run tests in parallel:
   - backend tests
   - frontend tests
4. deploy in parallel:
   - backend deploy
   - frontend deploy
5. bring up gateway nginx

## Notes
- Backend Docker build now copies `AGENTS.md`, not the removed `CODEX.md`.
- Frontend deploy uses the same three app directories used by GitHub Pages.
