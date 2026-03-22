# CODEX Handoff

This file is the current engineer handoff for the Notechondria workspace. It is meant to transfer architecture decisions, deployment assumptions, product scope, and verification reality to the next engineer without relying on thread history.

## 1. Current status

- The backend is now API-first Django REST Framework. Django is kept only for REST APIs, the default admin, and static/media handling behind nginx.
- The frontend is now a Flutter app for web and desktop-style layouts. It is the primary user-facing interface.
- The Flutter codebase has been split out of the previous oversized `frontend/lib/main.dart` into reusable libraries and page modules.
- Deployment now supports separate backend and frontend Docker stacks, with Jenkins testing and deploying them in parallel.
- The current codebase has moved significantly beyond the original Django-rendered UI, but not every recent change was runtime-verified in this environment. Treat the latest handoff as source-accurate but partially execution-unverified.

## 2. Repository map

- `backend/`: Django project, DRF APIs, admin, nginx/static/media wiring, Docker assets, backend tests.
- `frontend/`: Flutter app, web container build, frontend tests, frontend nginx config.
- `deployment/`: CI/CD shell scripts for env generation, testing, deployment, and wait logic.
- `docs/`: deployment and project docs.
- `sample/`: seeded example course content and media used to bootstrap an empty database.
- `course_template/`: older course template artifacts; keep only if still useful for migration or examples.
- `CODEX.md`: this handoff file.
- `LLM_CHECK.md`: end-of-round safety checklist and accumulated pitfalls.

## 3. Backend design

### 3.1 Runtime shape

- Main Django settings live in `backend/notechondria/settings.py`.
- Test settings live in `backend/notechondria/settings_test.py`.
- API routing is centered under `backend/notechondria/api_urls.py`.
- API-specific error handling and middleware live in `backend/notechondria/api_views.py` and `backend/notechondria/middleware.py`.
- Core feature apps are `backend/creators/` and `backend/notes/`.

### 3.2 Auth and account workflow

- Authentication uses DRF token auth.
- Registration is email/password only.
- Email verification is supported.
- Password reset is supported.
- SMTP is used when configured.
- If SMTP is missing or invalid, registration and verification flows should not crash. Verification codes should fall back to server logs so an admin can recover them manually.
- The initial Django admin user is bootstrapped from env:
  - `DJANGO_SUPERUSER_USERNAME`
  - `DJANGO_SUPERUSER_EMAIL`
  - `DJANGO_SUPERUSER_PASSWORD`
- Login was broadened so env-bootstrapped admin access can work with username as well as email.

### 3.3 Notes, courses, and activity

- Notes support recent-note listing, note detail, note history, and restore flows.
- `GET /api/v1/notes/` is now authenticated-only and returns only non-deleted notes owned by the signed-in creator.
- Public course viewing is intentionally available without login.
- Notes now support soft delete via `deleted_at` plus recycle-bin list, restore, and empty-bin endpoints.
- Notes also carry `client_draft_id` so frontend local-draft sync can be idempotent.
- Course subscriptions are now first-class via `CourseSubscription`, with per-user `subscribed_at` and `last_opened_at`.
- Course ordering is backend-canonical and synced across sessions/devices, not local-only.
- Course opens, subscribes, and unsubscribes are appended to `CourseOperationLog` for ordering/audit history.
- Planner events, heatmap activity, calendar feeds, and note-edit session activity exist on the backend.
- Planner events now also support `is_completed` and `completed_at`, and the week payload exposes an urgency-sorted `deadlines` list for vertical layouts.
- The activity model has moved toward calendar events rather than a separate recent-activity feed.
- Recommendation behavior on the front page currently means public-note surfacing, not a sophisticated ranking system. Do not overstate the algorithm.

### 3.4 Sample bootstrap

- Empty-database bootstrap seeds three sample courses:
  - `Vibe Coding 101`
  - `Meaning of Work in Age of AI`
  - `Self-identity and Expression in Modern Arts`
- Bootstrap also creates a demo creator account named `CodeX` and logs the generated credentials during bootstrap.
- Source material comes from `sample/` plus repository content such as `CODEX.md`.
- Bootstrap logic lives under `backend/notes/management/commands/bootstrap_platform.py`.
- Sample course metadata now lives in per-course directories under `sample/<slug>/course.json` with matching media assets in `sample/<slug>/media/`.
- Bootstrap was hardened so missing optional sample assets should not crash the app.

### 3.5 Static, media, nginx, and startup rules

- nginx is the static/media origin in both debug-like and production-like container paths.
- Shared volume targets are:
  - static: `/home/staticfiles`
  - media: `/home/mediafiles`
- `backend/entrypoint.sh` is responsible for:
  - database readiness
  - migrations
  - superuser bootstrap
  - `collectstatic --clear`
  - startup verification that required admin and DRF assets really exist in the shared static directory
- `backend/docker-compose.yml` healthchecks depend on those static assets existing before the stack is treated as healthy.
- This was added because earlier runs could appear "up" while admin and browsable DRF assets were still 404ing through nginx.

## 4. Frontend design

### 4.1 Code organization

- Thin entrypoint: `frontend/lib/main.dart`
- Shared shell/state: `frontend/lib/app_shell.dart`
- Shared helpers: `frontend/lib/core/`
- Reusable widgets: `frontend/lib/components/`
- Page modules:
  - `frontend/lib/modules/front.dart`
  - `frontend/lib/modules/learner.dart`
  - `frontend/lib/modules/course.dart`
  - `frontend/lib/modules/activity.dart`
  - `frontend/lib/modules/settings.dart`

### 4.2 Layout model

- Narrow screens use bottom navigation.
- Wide or horizontal screens use a left sidebar.
- The wide layout should keep icon and label on the same row, with Settings anchored lower-left.

### 4.3 Product behavior currently intended

- Front page:
  - public course material access
  - auto-advancing course carousel seeded with three demo courses
  - public-note recommendation surface rendered as a blog-style feed
  - authenticated heatmap for progress and plans
- Learner:
  - signed-out local drafts and signed-in cloud notes are distinct surfaces
  - local drafts remain local until manually synced after login
  - recent notes as the primary signed-in surface
  - search/filtering, with backend keyword+fuzzy search for cloud notes and local fuzzy filtering for drafts
  - dialog-based note reading instead of a permanent full-note pane
  - note creation, import/export, autosave, and version history
  - editor-mode switching with plain, preview, and block modes
  - delete-to-recycle-bin support
- Course:
  - subscribed courses are primary
  - unsubscribed courses render as preview cards with metadata and subscribe actions
  - wide-layout course ordering comes from backend-synced `last_opened_at`
- Activity:
  - horizontal layouts keep the week calendar
  - vertical layouts use a Canvas-style urgency-sorted deadline list with completion checkboxes
  - planner events, imported/subscribed iCal data, and note-edit session events
- Settings:
  - compact auth dialogs for sign up, verify, login, forgot password
  - server profile fields for username/email/motto/social/editor mode/avatar
  - local app settings for theme preset, theme mode, and API base URL, mirrored to the server profile with timestamps on login
  - recycle bin, local stats, and one-click frontend log copy
  - frontend/API debug surfaces

### 4.4 Recent frontend implementation notes

- Text selection/copy support was added, but an early global `SelectionArea` placement caused overlay crashes. Selection handling was then moved deeper into page content.
- The Flutter client now tries to defend against HTML error pages being decoded as JSON by surfacing request/response debug information in the UI.
- Local default API behavior is meant to target `http://localhost:9080/api/v1`.
- The standalone web build also accepts `FRONTEND_API_BASE_URL`.
- The standalone frontend container now defaults `FRONTEND_API_BASE_URL` to `/api/v1` and relies on frontend nginx to proxy `/api/`, `/admin/`, `/static/`, and `/media/` to `FRONTEND_BACKEND_ORIGIN`.
- Imported markdown documents should leave description empty rather than copying the entire document body into the description field.
- The learner add action should stay compact: icon-first, tooltip on hover, long-press import on supported platforms.
- Local drafts are persisted with `shared_preferences` in `frontend/lib/core/local_store.dart`.
- Avatar/media URLs should be resolved through `_resolveRemoteUrl(...)` because some backend media references can arrive as relative paths or malformed `file:///media/...` values.
- Note-session creation/update must be treated as best-effort; editor open should not be blocked by a failed note-session API call.

## 5. Deployment topology

### 5.1 Backend stack

- Compose file: `backend/docker-compose.yml`
- Host-facing ports by default:
  - nginx/app gateway: `9080` via `APP_HOST_PORT`
  - direct Django app: `9090` via `BACKEND_HOST_PORT`
  - postgres: `9032` via `DB_HOST_PORT`
- The backend stack includes:
  - `app`
  - `db`
  - `nginx`

### 5.2 Frontend stack

- Compose file: `frontend/docker-compose.yml`
- Docker build file: `frontend/Dockerfile`
- Frontend web container is exposed by default on `9060` via `FRONTEND_HOST_PORT`, and also on `8080` via `FRONTEND_FLUTTER_HOST_PORT`.
- The frontend container builds Flutter web and serves the built output with nginx.
- Flutter build steps run as root inside the build image because the preinstalled SDK under `/sdks/flutter` must be able to update its cache during `flutter pub get` and `flutter build web`.
- Frontend nginx proxies `/api/`, `/admin/`, `/static/`, and `/media/` to `FRONTEND_BACKEND_ORIGIN`, while `/` serves the compiled Flutter `build/web` bundle.

### 5.3 Jenkins pipeline

- `Jenkinsfile` runs:
  - env preparation
  - database backup
  - backend/frontend tests in parallel
  - backend/frontend deploy in parallel
- Deployment and test helpers live under `deployment/scripts/`.
- Important scripts:
  - `prepare_env.sh`
  - `backup_postgres.sh`
  - `test_backend.sh`
  - `test_frontend.sh`
  - `deploy_backend.sh`
  - `deploy_frontend.sh`
  - `wait_for_stack.sh`
  - `wait_for_frontend.sh`
  - `ensure_db_ready.sh`

### 5.4 Environment contract

Key env variables currently expected by the stack:

- Django and backend:
  - `DJANGO_SECRET_KEY`
  - `DJANGO_DEBUG`
  - `DJANGO_ALLOWED_HOSTS`
  - `DJANGO_ALLOWED_HOSTS_COMPOSE`
  - `DJANGO_CSRF_TRUSTED_ORIGINS`
  - `DJANGO_LOG_LEVEL`
  - `DJANGO_LOG_FILE_NAME`
  - `DJANGO_SUPERUSER_USERNAME`
  - `DJANGO_SUPERUSER_EMAIL`
  - `DJANGO_SUPERUSER_PASSWORD`
- Database:
  - `POSTGRE_USERNAME`
  - `POSTGRE_PASSWORD`
  - `POSTGRE_HOST`
  - `POSTGRE_PORT`
  - `POSTGRE_DB`
  - `DB_AUTO_REINIT_IF_MISMATCH`
- Ports:
  - `APP_HOST_PORT`
  - `BACKEND_HOST_PORT`
  - `FRONTEND_HOST_PORT`
  - `FRONTEND_FLUTTER_HOST_PORT`
  - `DB_HOST_PORT`
- Static/media:
  - `PRODUCTION_STATIC_ROOT`
  - `PRODUCTION_MEDIA_ROOT`
- SMTP and verification:
  - `SMTP_HOST`
  - `SMTP_PORT`
  - `SMTP_USERNAME`
  - `SMTP_PASSWORD`
  - `SMTP_USE_TLS`
  - `SMTP_USE_SSL`
  - `SMTP_FROM_EMAIL`
  - `EMAIL_VERIFICATION_TTL_HOURS`
  - `FRONTEND_VERIFY_URL`
- Frontend:
  - `FRONTEND_API_BASE_URL`
  - `FRONTEND_BACKEND_ORIGIN`
  - `FRONTEND_IMAGE`
- Images:
  - `APP_IMAGE`
  - `NGINX_IMAGE`

See `sample.env` and `deployment/scripts/prepare_env.sh` for the current authoritative defaults.

## 6. Verification reality

What was confirmed in this environment:

- The repository layout and file split are present as described.
- `dart format --set-exit-if-changed frontend/lib frontend/test` completed successfully in recent rounds.
- Documentation, env defaults, Dockerfiles, Jenkinsfile, and deployment scripts were updated to match the current stack shape.

What was not reliably verified in this environment:

- Full backend Django test execution from the host.
- Docker-backed backend runtime validation.
- Full Flutter test and build completion.
- `dart analyze` completion.

Why verification was limited here:

- The available local `python.exe` resolves to the Windows Store shim rather than a usable interpreter for direct backend runs.
- Docker daemon access was denied in this environment, so containerized backend verification could not be completed.
- Flutter tooling was partially usable for formatting, but longer runs such as `flutter test`, `flutter build web`, and `dart analyze` were blocked by timeout or Windows process-permission issues.

Do not tell the next engineer that the whole stack is fully green. The safe statement is: current source structure is updated to the intended design, but runtime verification must be rerun in a working Docker + Flutter environment.

## 7. Open risks and handoff watchlist

- Reconfirm backend static serving after a clean rebuild. Earlier nginx 404s for Django admin and DRF assets were a real issue and were only recently hardened.
- Reconfirm the standalone frontend Docker build and Jenkins frontend test stage after the non-root Dockerfile adjustments.
- Reconfirm Flutter runtime behavior on both Chrome and Windows after the module split and settings/theme fixes.
- Some advanced product goals are still rough or partial:
  - offline-first local cache and sync are not a finished system
  - block editing is not yet a polished Notion-level editor
  - avatar upload/crop/reposition is not a finished flow
  - recommendation logic is still basic
- If the next round touches frontend routing or API paths, recheck CORS and JSON error responses together. Earlier failures came from mismatched assumptions across Flutter, nginx, and Django.

## 8. Practical rebuild and recovery order

Use this order when continuing the project:

1. Start from `sample.env` and generate a deploy env with `deployment/scripts/prepare_env.sh` if needed.
2. Rebuild and verify the backend stack first:
   - migrations
   - admin bootstrap
   - sample bootstrap
   - collected static assets through nginx
   - backend tests
3. Rebuild and verify the standalone frontend web container.
4. Run Flutter locally against `http://localhost:9080/api/v1`.
5. Recheck public course viewing, auth dialogs, learner note flows, activity calendar flows, and settings/API-debug flows.
6. Only after local validation, trust Jenkins parallel test/deploy stages as the automation path.

## 9. AI continuation prompt

If an AI engineer needs to continue this project with minimal thread context, use a prompt close to this:

```text
Inspect the existing Notechondria repository and preserve user changes.
Treat the current architecture as an API-first Django REST Framework backend plus a modular Flutter frontend.

Continue from the current state rather than rebuilding from zero:
- Django should serve REST APIs, default admin, and nginx-served static/media only.
- Flutter is the primary user-facing app and is organized into a thin main entrypoint, shared core/components, and page modules for front, learner, course, activity, and settings.
- Keep public course viewing available without login.
- Keep auth centered in Settings using compact dialog flows.
- Keep backend/frontend deployment separate, with Dockerized backend and standalone Dockerized Flutter web frontend.
- Preserve env-driven ports, SMTP fallback-to-log behavior, admin bootstrap, seeded sample course content, and Jenkins parallel backend/frontend test+deploy stages.
- When changing the project shape, update CODEX.md and LLM_CHECK.md.
- State clearly what you actually verified versus what you could not verify.
```

## 10. Round-end rules

Every substantial round should end with:

1. Targeted source or doc edits that match the current repo structure.
2. A clear statement of what was actually run and what was blocked.
3. An `LLM_CHECK.md` pass against the new changes.
4. A `CODEX.md` update whenever architecture, deployment shape, or the safest continuation prompt changes materially.
