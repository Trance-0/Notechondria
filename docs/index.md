# Notechondria — Long-Form Agent Handoff

Deep architectural and operational detail for Notechondria. This file is the
single source of truth for project-local agent instructions; the root
`AGENTS.md` was removed and its contents folded here. The canonical
cross-project rules live in the [`agents/`](../agents/) submodule
(pinned to [`Trance-0/AGENTS.md`](https://github.com/Trance-0/AGENTS.md)).

Read this file in order:

1. [`agents/AGENTS.md`](../agents/AGENTS.md) — shared dev contract
   (tone, scope discipline, per-stack expectations, commit rules).
2. §0 below — **project-specific overrides** that beat the shared contract
   when they conflict.
3. The rest of this file — architecture, deploy topology, open-work list.
4. [`LLM_CHECK.md`](../LLM_CHECK.md) — end-of-round checklist.
5. [`docs/readme.md`](readme.md) — human-facing summary of how the
   project works.

---

## 0. Project-specific overrides

Rules in this section **override** the shared ruleset in
[`agents/AGENTS.md`](../agents/AGENTS.md) when they conflict. Keep this
section short; deeper explanations belong in later sections.

- **Upstream target branch is `codex`, not `main`.** Any PR to upstream
  targets `Trance-0/Notechondria:codex`.
- **Frontend is three standalone Flutter apps** under
  `frontend/editor_app/`, `frontend/planner_app/`, `frontend/portal_app/`.
  Do not merge them back into a monolith.
- **Backend tests run with
  `DJANGO_SETTINGS_MODULE=notechondria.settings_test`**; that settings
  file must define a non-empty `SECRET_KEY`.
- **Vendor SDK clients (OpenAI, etc.) must initialize lazily at call
  time**, never at module import. As of 0.1.18 the OpenAI SDK is removed
  entirely — future AI goes through an external microservice over HTTP
  (see [`docs/development/ai_integration.md`](development/ai_integration.md)).
- **`backend/requirements-render.txt` stays free of heavy ML packages**
  (`torch`, `llvmlite`, `numba`, etc.) for Render free-tier compatibility.
  `backend/requirements.txt` itself is also now pruned of that stack.
- **GitHub Pages builds use the project-site base paths**
  `/Notechondria/editor/`, `/Notechondria/planner/`,
  `/Notechondria/portal/`.
- **Never assume host ports** (`80`, `443`, `8080`, `5432`, …) are free;
  verify on the target machine before assigning.
- **Target Python 3.9.** The Dockerfile pins `python:3.9.18-bullseye`,
  so do NOT use PEP 604 unions (`X | Y`) in runtime annotations — use
  `typing.Optional` / `typing.Union`. This overrides
  `agents/AGENTS.md` §4.1's "target 3.11+" default.

---

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
- `LLM_CHECK.md` — end-of-round checklist and pitfall log.
- `agents/` — git submodule pinning the canonical agent rules
  (`Trance-0/AGENTS.md`). The root `AGENTS.md` was removed; project-local
  overrides now live in §0 above.

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
