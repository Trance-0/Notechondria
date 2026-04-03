# LLM_CHECK

Use this checklist at the end of each modification round.

## Common mistakes seen in prior rounds

1. Claiming UI capture work without a runnable Flutter toolchain.
2. Adding docs or scripts without checking that file paths still match the current repo layout.
3. Writing pipeline and shell scripts whose argument order does not actually line up.
4. Leaving visible text encoding artifacts in UI copy.
5. Reporting success without clearly separating verified work from unverified work.
6. Expanding scope without checking whether there were already user changes in the worktree.
7. Assuming a host port such as `80`, `443`, `8080`, or any other port is free without first confirming it on the target machine; you do not know the host machine state, so never assign host ports on assumption.

## Round-end checklist

- Confirm every command or test reported as passed was actually run in the current environment.
- Confirm every command or test not run is called out explicitly with the reason.
- Confirm docs reference current paths such as `backend/`, `frontend/`, `docs/`, and `deployment/`.
- Confirm `CODEX.md` was updated when the round materially changed architecture, product scope, or the prompt recipe needed to recreate the project.
- Confirm CI files and scripts agree on invocation syntax and environment variable names.
- Confirm UI strings are plain, intentional, and free of mojibake or placeholder artifacts.
- Confirm `.gitignore` ignores local junk without hiding required tracked source files.
- Confirm no unrelated user changes were reverted.
- Confirm every host port assignment was explicitly verified for the target machine instead of assuming a common port is available; you have no knowledge of host port availability until it is checked.

## Current round log

- Fixed Jenkins deploy invocation to pass `project_dir` and `env_path` in the order required by `deployment/scripts/deploy_backend.sh`.
- Fixed a visible separator encoding issue in the Flutter front page subtitle.
- Made the selected course stateful across course, learner, and activity views.
- Expanded Flutter widget coverage for course selection flow.
- Added `CODEX.md` and updated repo links.
- Backend verification was blocked because the available `python.exe` resolves to the Windows Store shim rather than a runnable interpreter.
- Flutter verification was attempted through the installed `flutter.bat`, but the command did not complete within the allotted timeout in this environment.
- Switched Jenkins backup and test execution to Docker-native scripts so the host no longer needs `pg_dump` or `python`.
- Fixed Docker deployment mismatches: compose stack naming, separate `db` service usage, database name wiring, and app env injection.
- Re-truncated the sample deployment secret to `dwMlZWVt...jpZOJG2z` after it had previously been written too broadly.
- Updated the backup step to skip cleanly on first deployment when the database role/database does not exist yet, instead of failing the whole pipeline.
- Added a reminder that any tool referenced by container scripts, such as `nc` in `entrypoint.sh`, must be installed in the image build.
- Added a reminder that container wait logic must have an explicit timeout, and internal Compose service connections should use service names like `db` rather than host-local addresses.
- Added a reminder that standalone frontend and backend Docker stacks must share an explicit Docker network for service-to-service proxying; do not point container-to-container traffic at host `localhost` or `host.docker.internal` unless that routing was actually verified on the target machine.
- Switched Jenkins env loading to Environment Injector style variables rendered by `prepare_env.sh`, so the pipeline no longer depends on a secret-file credential being wired correctly.
- Removed shell `source` parsing from the backup script because Environment Injector values can contain spaces, which breaks naive `.env` sourcing.
- Documented that public-repo Pipeline SCM jobs should not keep unnecessary Git credentials attached in Jenkins job configuration.
- Fixed the test stage so `settings_test` no longer depends on the production entrypoint or a live postgres container.
- Added a database preflight for deploys and an optional `DB_AUTO_REINIT_IF_MISMATCH=True` path for disposable environments with mismatched persistent postgres volumes.
- Added a reminder that containerized test commands should set `DJANGO_SETTINGS_MODULE` and `PYTHONPATH` explicitly when import resolution is environment-sensitive.
- Removed the Compose volume that masked `/home/notechondria`, because mounting over the image code directory can create stale or missing-package failures that look like random import bugs.
- Added a reminder that filesystem paths used by Django settings, especially log directories, must match the directories created in the image or be created at runtime before logging initializes.
- Added a reminder that code should not assume runtime assets live under `STATIC_ROOT` unless `collectstatic` has definitely run; source static fallbacks need to exist for debug/test paths.
- Separated host-exposed ports from fixed in-container service ports so the stack can avoid occupied host ports without breaking in-stack routing.
- Added a reminder that optional Django apps must be guarded consistently in both `INSTALLED_APPS` and URL includes, otherwise boot can fail on missing modules that are not actually required for deployment.
- Added a reminder that every package referenced by `INSTALLED_APPS` must exist in `backend/requirements.txt`, and fresh CI builds should not rely on cached images when debugging dependency drift.
- Added a reminder that Django URL includes must be guarded consistently with optional `INSTALLED_APPS` entries, or tests and deploys can fail even after settings remove those apps.
- Added a reminder that CI image rebuilds should use `--pull --no-cache` when the goal is to eliminate stale dependency and base-image state during Jenkins debugging.
- Added a reminder that Docker service networking must never be tied to `DEBUG`; database host resolution should come from env (`POSTGRE_HOST=db` in Compose), not a `localhost` fallback triggered by debug mode.
- Added a reminder that database preflight checks must verify the same TCP username/password path the app uses, not just local-socket readiness from inside the postgres container.
- Added a reminder that material project-shape changes must be recorded in `CODEX.md`, including how to prompt an AI run to recreate the new shape.
- Reworked the Flutter learner flow so recent notes stay primary, note reading happens in dialogs, and the markdown preview is explicitly scrollable to avoid overflow regressions.
- Added inline LaTeX markdown rendering, week-calendar activity views, note-session calendar events, theme/API-base settings, and frontend/API debug surfaces.
- Split the oversized Flutter `main.dart` into a thin entrypoint, shared `core/` and `components/` libraries, plus dedicated `front`, `learner`, `course`, `activity`, and `settings` module files.
- Fixed the week-activity calendar test to use a current-week iCal event instead of a stale hard-coded date, and broadened iCal datetime parsing to accept both second-level and minute-level timestamps.
- Added standalone frontend Docker build/deploy files plus Jenkins parallel backend/frontend test and deploy stages, and extended deployment env generation with frontend/admin/SMTP variables needed by the current stack shape.
- Hardened backend static serving so deploy readiness now depends on Django admin and DRF assets actually existing in the shared `/home/staticfiles` volume before nginx is treated as healthy.
- Backend verification remained blocked in this environment because only the Windows Store `python.exe` shim is present and Docker daemon access is denied.
- Flutter static verification succeeded only at the `dart format` parsing level; `dart analyze` still fails here with a Windows access-denied error while spawning `dartaotruntime.exe`.
- Added backend models and APIs for synced course subscriptions/order (`CourseSubscription`, `CourseOperationLog`), note recycle bin, idempotent `client_draft_id` sync, planner completion state, and creator app-settings mirroring.
- Reworked the Flutter shell toward distinct signed-out local drafts vs signed-in cloud notes, backend-synced course ordering, recycle-bin management, avatar upload, local stats, and local app-settings persistence.
- Replaced the front page hero with a carousel-oriented surface and richer public-note cards, rewired course/activity/settings modules to the new backend payload shape, and added one-click frontend log copy plus stats UI.
- Updated backend tests for auth-only notes, recycle bin flows, client-draft idempotency, course subscription/open ordering, planner completion filtering, and creator app-settings mirror responses.
- Fixed two follow-up CI failures by returning `count` from the recycle-bin empty endpoint and marking `/sdks/flutter` as a Git safe directory inside the frontend Docker build before `flutter pub get`.
- Changed the frontend Docker build back to a non-root user and explicitly granted that user ownership of `/sdks/flutter`, `/app`, and `/home/frontend` so Flutter can update its cache without the root warning or the earlier `engine.stamp` permission failure.
- Removed the extra frontend host-port mapping and standardized the standalone frontend back onto `FRONTEND_HOST_PORT=9060`; do not assume ports like `8080`, `80`, or `443` are unused on an unknown host.
- Added real sample directories and cover metadata for `meaning-of-work-in-age-of-ai` and `self-identity-and-expression-in-modern-arts`, and updated bootstrap to load each course from `sample/<slug>/course.json`.
- Fixed a Flutter null-safety compile break in `frontend/lib/app_shell.dart` by separating local-draft saves from authenticated cloud-note saves before calling `updateNote(...)`.
- Fixed Flutter widget-test timeouts caused by the 30-second front-page carousel timer by disabling auto-slide under test bindings and making `widget_test.dart` use bounded pumps instead of `pumpAndSettle()`.
- Split Jenkins into independent backend and frontend release tracks so frontend failures no longer block backend deployment; frontend failures now mark the build unstable instead.
- Verification is still incomplete in this environment: `flutter analyze` and `dart analyze` both timed out here, so the latest Flutter integration should be treated as source-updated but not execution-verified.
- Fixed a Dart parse/type break in `frontend/lib/app_shell.dart` by avoiding null-aware map indexing directly inside ternary branches when updating local fallback profile values.
- Hardened backend deployment against Windows-host path leakage by normalizing `PRODUCTION_STATIC_ROOT` and `PRODUCTION_MEDIA_ROOT` in both `prepare_env.sh` and the backend entrypoint before migrations and `collectstatic`.
- Made backend deploy explicitly rerun `migrate --noinput`, `bootstrap_platform`, and `collectstatic --noinput --clear` after the new app container becomes healthy, then wait for stack health again so Jenkins deploys verify the final runtime state.
- Hardened seeded course asset lookup to search multiple runtime sample roots, including `/home/sample`, and changed the backend Dockerfile to copy `sample/` into `/home/sample/` explicitly.
- Normalized the frontend deployment contract around `FRONTEND_API_BASE_URL` as an absolute browser-facing URL instead of a slash-prefixed route, because Git Bash on Windows can path-convert `/api/v1` into a broken `C:/Program Files/Git/api/v1` Docker build argument.
- Frontend deploy/test scripts now explicitly unset shell overrides such as `FRONTEND_API_BASE_URL` and disable MSYS path conversion for Docker commands so Jenkins-host environment variables cannot silently override the normalized `.env.deploy` value during build.
- Reset the fork `codex` branch back to `upstream/codex` and preserved the earlier misfire state on a backup branch before restarting the split work.
- Installed Flutter from git source on arm64 Linux and used that toolchain successfully for local smoke tests and web builds.
- Replaced the tracked root frontend monolith with exactly three tracked app directories: `frontend/editor_app`, `frontend/planner_app`, and `frontend/portal_app`.
- Added app-local `Dockerfile`, `docker-compose.yml`, and nginx template files for all three frontend apps.
- Added GitHub Pages workflows that build/test/deploy the three frontend apps independently from the `codex` branch.
- Updated frontend ignore rules to apply recursively so nested Flutter app build output does not pollute the repo.
- Local Django verification now reaches real test discovery/install using `uv`, but still stops at PostgreSQL connection setup because no local database server is present on this host.
