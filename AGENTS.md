# AGENTS Handoff

This file is the current engineer handoff for the Notechondria workspace.

## 1. Current status

- Backend remains Django + DRF.
- Jenkins is now **backend-only**.
- Frontend is no longer one tracked Flutter app under `frontend/lib/`.
- `frontend/` now contains exactly three tracked app directories:
  - `frontend/editor_app/`
  - `frontend/planner_app/`
  - `frontend/portal_app/`
- The old root frontend source tree (`frontend/lib`, `frontend/test`, `frontend/web`, `frontend/windows`, `frontend/nginx`) has been removed from tracked source.
- The older temporary `frontend/shared/` tree is also gone from tracked source.

## 2. Repository map

- `backend/`: Django project, DRF APIs, admin, Docker assets, backend tests.
- `frontend/`: three standalone Flutter frontend apps plus root docs/ignore rules.
- `deployment/`: backend CI/CD shell scripts.
- `docs/`: deployment and project docs.
- `sample/`: seeded example course content and media.
- `course_template/`: older course template artifacts.
- `AGENTS.md`: this handoff file.
- `LLM_CHECK.md`: end-of-round checklist and pitfalls.

## 3. Backend design

### 3.1 Runtime shape
- Main Django settings: `backend/notechondria/settings.py`
- Test settings: `backend/notechondria/settings_test.py`
- API routing: `backend/notechondria/api_urls.py`
- Core apps: `backend/creators/`, `backend/notes/`

### 3.2 Auth and account workflow
- DRF token auth
- email/password registration
- email verification + password reset
- env-bootstrapped admin user supported
- username or email login supported for admin access

### 3.3 Notes, courses, and activity
- authenticated notes API with recycle bin and version flows
- public course viewing without login
- planner events / activity week / calendar feed support
- course subscriptions and backend-canonical course ordering exist
- current backend is still shared across all three frontend apps

### 3.4 Local backend verification reality
Verified in this environment:
- Python dependencies install successfully with local `uv`
- Django test discovery starts and reaches database setup

Blocked in this environment:
- local `manage.py test` fails because no PostgreSQL server is available on `localhost:5432`
- Docker is not installed on this host, so container-based local backend verification was not available here

## 4. Frontend design

## 4.1 App split

### `frontend/editor_app/`
Intended role:
- offline-first markdown editor
- note list, search, edit/view modes, local settings, optional sync

Current shape in this pass:
- self-contained Flutter app directory
- own `pubspec.yaml`, `lib/`, `web/`, `windows/`, `test/`, `Dockerfile`, `docker-compose.yml`, and nginx template
- navigation constrained to learner/settings surfaces

### `frontend/planner_app/`
Intended role:
- project/course list
- module-oriented course view
- activity / calendar planning
- discussion-board-oriented planning flows

Current shape in this pass:
- self-contained Flutter app directory
- own `pubspec.yaml`, `lib/`, `web/`, `windows/`, `test/`, `Dockerfile`, `docker-compose.yml`, and nginx template
- navigation constrained to front/course/activity surfaces

### `frontend/portal_app/`
Intended role:
- online-only auth and cloud preference routing
- sync orchestration for editor/planner concepts
- future git-like versioned remote portal

Current shape in this pass:
- self-contained Flutter app directory
- own `pubspec.yaml`, `lib/`, `web/`, `windows/`, `test/`, `Dockerfile`, `docker-compose.yml`, and nginx template
- navigation is constrained to `Portal` + `Cloud Settings`
- front page is a router/orchestrator shell that launches editor/planner targets instead of acting like the full integrated copy

## 4.2 Important frontend reality
- The three apps are independently buildable now.
- The three apps are independently smoke-tested now.
- The split is currently **structural and deployable**, but not yet fully de-duplicated internally.
- There is still copied code across the app directories; deeper extraction/refinement remains future work.

## 4.3 Frontend verification completed in this environment
Using git-source Flutter on arm64 Linux:

Passed:
- `flutter test test/smoke_test.dart` in `frontend/editor_app`
- `flutter test test/smoke_test.dart` in `frontend/planner_app`
- `flutter test test/smoke_test.dart` in `frontend/portal_app`
- `flutter build web --release` in all three apps
- `flutter build web --release --base-href /editor/` in `editor_app`
- `flutter build web --release --base-href /planner/` in `planner_app`
- `flutter build web --release --base-href /portal/` in `portal_app`

Historical baseline note:
- before the split cleanup, the old upstream root frontend test suite was not green in this environment; the old widget test failed at `opens course note in reader dialog`

## 5. Deployment topology

### 5.1 Backend — Render (primary)
- Service URL: `https://notechondria.onrender.com`
- Root dir: repo root (not `backend/`)
- Build command: `pip install -r backend/requirements-render.txt`
- Start command: `bash render-deploy.sh`
- `render-deploy.sh` loads `.env` / secret files, then calls `deployment/render/scripts/render_backend_start.sh`
- The start script runs Django migrations, `bootstrap_platform`, `collectstatic`, and launches gunicorn
- `backend/requirements-render.txt` excludes heavy ML packages (torch, etc.) for free-tier compatibility
- WhiteNoise middleware serves static files (no nginx on Render)
- `DATABASE_URL` is parsed via `dj-database-url` when set; falls back to individual `POSTGRE_*` vars
- Required env vars: `DATABASE_URL`, `SECRET_KEY`, `ALLOWED_HOSTS`, `CSRF_TRUSTED_ORIGINS`

### 5.1b Backend — Docker / Jenkins (self-hosted)
- Compose file: `backend/docker-compose.yml`
- Jenkins handles backend env prep, backup, tests, and deploy
- backend deploy/test helpers live under `deployment/jenkins/scripts/`

### 5.2 Frontend
GitHub Pages workflows:
- `.github/workflows/frontend-editor-pages.yml`
- `.github/workflows/frontend-planner-pages.yml`
- `.github/workflows/frontend-portal-pages.yml`

Pages paths:
- `/editor/`
- `/planner/`
- `/portal/`

Each frontend app also has app-local container assets:
- `Dockerfile`
- `docker-compose.yml`
- `nginx/default.conf.template`

### 5.3 Environment contract
Important frontend variables:
- `FRONTEND_API_BASE_URL`
- `FRONTEND_BACKEND_ORIGIN`
- `NOTECHONDRIA_SHARED_NETWORK`

Important backend variables for Docker/Jenkins: see `deployment/jenkins/.env.example` and `deployment/jenkins/scripts/prepare_env.sh`.
Important backend variables for Render: see `deployment/render/README.md`.

## 6. Open work / caution list

- The three apps still contain duplicated Flutter source copied from the prior monolith.
- `editor_app` / `planner_app` / `portal_app` behavioral separation is only partially refined; structural separation is ahead of product-polish separation.
- Backend local verification still needs a reachable PostgreSQL service to complete full Django test runs.
- Any future PR to upstream should target `Trance-0/Notechondria:codex`, not the fork’s `main` branch.
- Do not claim full feature re-separation until learner/planner/portal code paths are more deeply specialized than just navigation slicing and app-directory isolation.
- Render free-tier `SECRET_KEY` is a placeholder; rotate before any real production traffic.
- `requirements-render.txt` must stay free of heavy ML packages (torch, etc.) for free-tier compatibility; keep those only in `requirements.txt` for self-hosted Docker builds.

## 7. Prompt recipe for the next engineer

If continuing this work, use this framing:

> Work on `Trance-0/Notechondria` using the `codex` branch as the upstream target. Keep frontend as three standalone Flutter apps under `frontend/editor_app`, `frontend/planner_app`, and `frontend/portal_app`. Keep the Jenkins pipeline full-stack with backend/frontend test and deploy branches running in parallel. Verify each app locally with Flutter before claiming success. Run backend tests with `DJANGO_SETTINGS_MODULE=notechondria.settings_test`, keep `SECRET_KEY` defined there, and avoid import-time OpenAI client initialization.
