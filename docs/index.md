# Notechondria — Long-Form Agent Handoff

Deep architectural and operational detail for Notechondria. This file was
migrated from the repo-root `AGENTS.md`; the root `AGENTS.md` now points at
the shared agent-rules submodule (`.agents/`) plus this file.

Read [`docs/readme.md`](readme.md) first for a human-facing overview.

---

## 1. Current status

- Backend remains Django + DRF.
- Jenkins is full-stack (backend + frontend test/deploy in parallel), but the
  backend-only pipeline under `deployment/jenkins/` is also supported.
- Frontend is no longer one Flutter app; it is three tracked apps under
  `frontend/`:
  - `frontend/editor_app/`
  - `frontend/planner_app/`
  - `frontend/portal_app/`
- The old root frontend source tree (`frontend/lib`, `frontend/test`,
  `frontend/web`, `frontend/windows`, `frontend/nginx`) has been removed
  from tracked source.
- The older temporary `frontend/shared/` tree is also gone from tracked
  source.

## 2. Repository map

- `backend/` — Django project, DRF APIs, admin, Docker assets, backend tests.
- `frontend/` — three standalone Flutter frontend apps plus root docs/ignore
  rules.
- `deployment/` — backend + frontend CI/CD shell scripts, organized per
  deploy target (`jenkins/`, `docker/`, `render/`).
- `docs/` — this directory; deployment, development, operations, API, and
  per-version notes.
- `sample/` — seeded example course content and media.
- `course_template/` — older course template artifacts.
- `AGENTS.md` (root) — thin pointer; rules inherited from the `.agents/`
  submodule (`Trance-0/AGENTS.md`).
- `LLM_CHECK.md` — end-of-round checklist and pitfall log.
- `.agents/` — git submodule pinning the canonical agent rules.

## 3. Backend design

### 3.1 Runtime shape

- Main Django settings: `backend/notechondria/settings.py`
- Test settings: `backend/notechondria/settings_test.py`
- API routing: `backend/notechondria/api_urls.py`
- Core apps: `backend/creators/`, `backend/notes/`

### 3.2 Auth and account workflow

- DRF token auth.
- Email/password registration.
- Email verification + password reset.
- Env-bootstrapped admin user supported.
- Username or email login supported for admin access.

### 3.3 Notes, courses, and activity

- Authenticated notes API with recycle bin and version flows.
- Public course viewing without login.
- Planner events / activity week / calendar feed support.
- Course subscriptions and backend-canonical course ordering.
- Current backend is still shared across all three frontend apps.

### 3.4 Local backend verification reality

Verified in the current environment:

- Python dependencies install successfully with local `uv`.
- Django test discovery starts and reaches database setup.

Blocked in the current environment:

- `manage.py test` fails because no PostgreSQL server is available on
  `localhost:5432`.
- Docker is not installed on this host, so container-based local backend
  verification was not available here.

## 4. Frontend design

### 4.1 App split

#### `frontend/editor_app/`

Role: offline-first markdown editor — note list, search, edit/view modes,
local settings, optional sync.

Shape: self-contained Flutter app directory with its own `pubspec.yaml`,
`lib/`, `web/`, `windows/`, `test/`, `Dockerfile`, `docker-compose.yml`, and
nginx template. Navigation is constrained to learner/settings surfaces.

#### `frontend/planner_app/`

Role: project/course list, module-oriented course view, activity / calendar
planning, discussion-board-oriented planning flows.

Shape: self-contained Flutter app directory with its own `pubspec.yaml`,
`lib/`, `web/`, `windows/`, `test/`, `Dockerfile`, `docker-compose.yml`, and
nginx template. Navigation is constrained to front/course/activity surfaces.

#### `frontend/portal_app/`

Role: online-only auth and cloud preference routing; sync orchestration for
editor/planner concepts; future git-like versioned remote portal.

Shape: self-contained Flutter app directory, `Portal + Cloud Settings`
navigation only. The front page is a router/orchestrator shell that
launches editor/planner targets instead of acting like a full integrated
copy.

### 4.2 Important frontend reality

- The three apps are independently buildable.
- The three apps are independently smoke-tested.
- The split is currently **structural and deployable**, not yet fully
  de-duplicated internally.
- There is still copied code across the app directories; deeper
  extraction/refinement remains future work.

### 4.3 Frontend verification completed in this environment

Using git-source Flutter on arm64 Linux. Passed:

- `flutter test test/smoke_test.dart` in each of `editor_app`,
  `planner_app`, `portal_app`.
- `flutter build web --release` in all three apps.
- `flutter build web --release --base-href /editor/` / `/planner/` /
  `/portal/` in the matching app.

Historical baseline note: before the split cleanup, the old upstream root
frontend test suite was not green in this environment; the old widget test
failed at `opens course note in reader dialog`.

## 5. Deployment topology

### 5.1 Backend — Render (primary)

- Service URL: `https://notechondria.onrender.com`
- Root dir: repo root (not `backend/`)
- Build command: `pip install -r backend/requirements-render.txt`
- Start command: `bash render-deploy.sh`
- `render-deploy.sh` loads `.env` / secret files, then calls
  `deployment/render/scripts/render_backend_start.sh`.
- The start script runs Django migrations, `bootstrap_platform`,
  `collectstatic`, and launches gunicorn.
- `backend/requirements-render.txt` excludes heavy ML packages (torch, etc.)
  for free-tier compatibility.
- WhiteNoise middleware serves static files (no nginx on Render).
- `DATABASE_URL` is parsed via `dj-database-url` when set; falls back to
  individual `POSTGRE_*` vars.
- Required env vars: `DATABASE_URL`, `SECRET_KEY`, `ALLOWED_HOSTS`,
  `CSRF_TRUSTED_ORIGINS`.

### 5.1b Backend — Docker / Jenkins (self-hosted)

- Compose file: `backend/docker-compose.yml`.
- Jenkins handles backend env prep, backup, tests, and deploy.
- Backend deploy/test helpers live under `deployment/jenkins/scripts/`.

### 5.2 Frontend — GitHub Pages

Workflows:

- `.github/workflows/frontend-editor-pages.yml`
- `.github/workflows/frontend-planner-pages.yml`
- `.github/workflows/frontend-portal-pages.yml`

Pages paths (GitHub **project site**, prefix with repo name):

- `/Notechondria/editor/`
- `/Notechondria/planner/`
- `/Notechondria/portal/`

Each frontend app also has app-local container assets: `Dockerfile`,
`docker-compose.yml`, `nginx/default.conf.template`.

### 5.3 Environment contract

Frontend:

- `FRONTEND_API_BASE_URL` — absolute browser-facing URL; never a
  slash-prefixed route (Git Bash on Windows can path-convert `/api/v1` into a
  broken `C:/Program Files/Git/api/v1` Docker build argument).
- `FRONTEND_BACKEND_ORIGIN`
- `NOTECHONDRIA_SHARED_NETWORK`

Backend:

- Docker/Jenkins: `deployment/jenkins/.env.example` +
  `deployment/jenkins/scripts/prepare_env.sh`.
- Render: `deployment/render/README.md`.

## 6. Open work / caution list

- The three apps still contain duplicated Flutter source copied from the
  prior monolith.
- `editor_app` / `planner_app` / `portal_app` behavioral separation is only
  partially refined; structural separation is ahead of product-polish
  separation.
- Backend local verification still needs a reachable PostgreSQL service to
  complete full Django test runs.
- Any future PR to upstream should target `Trance-0/Notechondria:codex`, not
  the fork's `main` branch.
- Do not claim full feature re-separation until learner/planner/portal code
  paths are more deeply specialized than navigation slicing and
  app-directory isolation.
- Render free-tier `SECRET_KEY` is a placeholder; rotate before any real
  production traffic.
- `requirements-render.txt` must stay free of heavy ML packages (torch,
  etc.) for free-tier compatibility; keep those only in `requirements.txt`
  for self-hosted Docker builds.
- `portal_app` and `planner_app` still contain stale modules (`front.dart`,
  `course.dart`, `activity.dart`, `learner.dart`) that their `visibleIndices`
  don't use; removing these requires rewriting their `app_shell.dart`.
- `editor_app/app_shell.dart` (~2481 lines) and `client.dart` (~812 lines)
  remain above the 500-line target; further splits would need mixin-based
  architecture changes.

## 7. Prompt recipe for the next engineer

If continuing this work, use this framing:

> Work on `Trance-0/Notechondria` using the `codex` branch as the upstream
> target. Keep frontend as three standalone Flutter apps under
> `frontend/editor_app`, `frontend/planner_app`, and `frontend/portal_app`.
> Keep the Jenkins pipeline full-stack with backend/frontend test and deploy
> branches running in parallel. Verify each app locally with Flutter before
> claiming success. Run backend tests with
> `DJANGO_SETTINGS_MODULE=notechondria.settings_test`, keep `SECRET_KEY`
> defined there, and avoid import-time OpenAI client initialization.
