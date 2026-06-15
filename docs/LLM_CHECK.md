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
- Replaced the split Pages workflows with a single combined pipeline to avoid gh-pages push races and workflow cancellation.
- Reorganized deployment into method-specific folders:
  - `deployment/jenkins/`
  - `deployment/docker/`
  - `deployment/render/`
- Moved environment samples into deployment-method folders and removed the stale root `sample.env`.
- Added root full-stack `docker-compose.yml`, root `render-deploy.sh`, and a full-stack Jenkins pipeline wired to deployment-specific helper scripts.
- Backend Docker build now copies `AGENTS.md` instead of the removed `CODEX.md`.
- `bootstrap_platform` runtime lookup now accepts `AGENTS.md` first and falls back to `CODEX.md`, fixing Jenkins test/runtime failures after the handoff rename.
- Jenkins pipeline now runs backend/frontend tests in parallel and backend/frontend deploys in parallel, then finalizes the gateway nginx.
- Jenkins test/deploy branches use `catchError(...)` so one side can continue even if the other side fails.
- `render-deploy.sh` now supports sourcing env files from Render secret files (e.g. `/etc/secrets/.env`).
- Added Render-specific backend dependency/runtime files:
  - `backend/requirements-render.txt`
  - `backend/runtime.txt`
  - `backend/.python-version`
  - root `runtime.txt`
  - root `.python-version`
- Backend `requirements.txt` no longer includes `numba` / `llvmlite`, avoiding Python 3.14 build failures in Render's default environment.
- Reproduced and passed the previous Jenkins-failing backend test locally (`HeatmapApiTests.test_admin_can_restore_template_courses_into_partial_catalog`) and the `HeatmapApiTests` suite under `settings_test`.
- Default frontend API behavior now targets `https://notechondria.trance-0.com/api/v1` on GitHub Pages and same-origin `/api/v1` on local browser full-stack deploys.
- Added a root Pages landing page so `/Notechondria/` is not a 404 while the three apps live under subpaths.
- Corrected Pages base-href handling for a GitHub **project site**: builds must use `/Notechondria/editor/`, `/Notechondria/planner/`, and `/Notechondria/portal/` rather than root-level `/editor/`, `/planner/`, `/portal/`.
- Caught and fixed an incomplete workflow patch where planner used the corrected repo-prefixed base path but editor and portal were still building with root-level base paths.
- Caught a second incomplete base-href fix where portal had been corrected but editor was still building with `/editor/`; editor must also use `/Notechondria/editor/` on GitHub project Pages.
- Updated Pages builds to bundle web resources locally (`--no-web-resources-cdn`) and rewrite the final Flutter bootstrap load call to disable service-worker registration in the published output.
- Local verification for the Pages runtime path now includes confirming the built bootstrap ends in `_flutter.loader.load({});` and uses `useLocalCanvasKit: true`.
- Added first-run offline starter workspaces so the split apps render meaningful content without backend/login prerequisites:
  - `editor_app` seeds local notes and a storage-layout example
  - `planner_app` seeds a local course, module discussion notes, and local planner events
  - `portal_app` seeds a minimal router-shell front-page payload
- Planner offline behavior now supports signed-out local planner-event creation/toggling and shows the activity board when local planner data exists.
- Re-ran local `flutter test` and `flutter build web --no-web-resources-cdn` for all three apps after the functionality patch.
- Simplified `editor_app` settings down to the requested three sections: login/sync, editor settings, and debug log.
- Simplified `planner_app` settings down to the requested three sections: login/sync, planner settings, and debug log.
- Added planner deadline ordering weights (`deadline_time_weight`, `deadline_importance_weight`) and used them in offline deadline urgency scoring.
- Added stronger widget smoke tests that assert meaningful first-run content instead of only checking for `MaterialApp`.
- Added `frontend/AGENTS.md` and refreshed `frontend/README.md` to document the three-app split for both humans and agents.
- Added backend-supported editor sync modes:
  - push `normal` keeps both local/cloud
  - push `force` clears signed-in user cloud notes, then uploads local drafts
  - pull `normal` merges remote notes into local drafts
  - pull `force` replaces local drafts with remote notes
- Added a user-scoped backend notes bulk-clear action at `DELETE /api/v1/notes/mine/` for force-push behavior.
- Replaced the planner app's generic front page with a planner-specific dashboard centered on course calendars and upcoming deadlines.
- Added a reminder that `settings_test` must define a non-empty `SECRET_KEY`; otherwise session/messages/request tests fail before reaching application logic.
- Added a reminder that OpenAI/GPT clients must be initialized lazily at call time rather than module import time, or unrelated tests and URL imports can fail without `OPENAI_API_KEY`.
- Re-verified all three apps locally after the planner-home replacement.
- Updated frontend ignore rules to apply recursively so nested Flutter app build output does not pollute the repo.
- Local Django verification now reaches real test discovery/install using `uv`, but still stops at PostgreSQL connection setup because no local database server is present on this host.
- Specialized `portal_app` toward option B: router-shell/orchestrator behavior, `Portal + Settings` navigation only, and launch cards for editor/planner targets instead of retaining the broad integrated copy.
- Removed stale modules from `editor_app`: deleted `front.dart`, `course.dart`, `activity.dart` and their `part` directives; these modules are not used by the editor (visibleIndices: [1, 4]).
- Rewrote `editor_app/app_shell.dart`: sidebar now shows note categories (courses) instead of "Learner View" navigation; compact view uses a three-dot `PopupMenuButton` in the app bar instead of a bottom `NavigationBar`; removed all activity/planner/calendar state and methods; added `_selectedCategoryId`, `_allCategories`, `_buildConfigFileContent()`, `_downloadConfigFile()`.
- Cleaned up unused declarations in `editor_app/app_shell.dart`: removed `_destinations`, `_selectedNavIndex`, `_handleVisibleDestinationSelected`, `_showCompactPageHeader`, `_openNoteViewer`, `_createLocalCourse`.
- Rewrote `editor_app/settings.dart`: removed section numbering ("1.", "2.", "3."); added `onDownloadConfig` parameter; migrated user profile fields (avatar, username, email, motto, social link) into the "Login and sync" section; added "Configuration" section with config file download and maintenance actions; simplified "Debug log" to only show recent UI logs with copy button (removed `_ApiDebugCard` verbose display).
- Simplified `portal_app/settings.dart`: removed "Stats" section and `_StatChip` widget; replaced "API debug" + "Frontend logs" sections with a single "Debug log" card showing only recent UI logs.
- Simplified `planner_app/settings.dart`: removed section numbering ("1.", "2.", "3."); replaced verbose `_ApiDebugCard` in debug section with simplified UI-only log view.
- Split large `editor_app` files: `learner.dart` (1493 lines) split into `learner.dart` (563), `note_editor.dart` (707), `note_metadata.dart` (225); auth dialogs extracted from `settings.dart` (1135) into `components/auth_dialogs.dart` (456), leaving `settings.dart` at 683.
- `app_shell.dart` (2481) and `client.dart` (812) remain above the 500-line target; `app_shell.dart` is a single stateful class and `client.dart` is an interface+implementation pair — splitting further requires mixin-based architecture changes.
- All three frontend apps (`editor_app`, `planner_app`, `portal_app`) verified with `flutter build web --no-tree-shake-icons` after changes.
- Portal and planner apps still contain stale modules (`front.dart`, `course.dart`, `activity.dart`, `learner.dart`) that their `visibleIndices` don't use; removing these requires rewriting their respective `app_shell.dart` files (same scale as the editor_app rewrite).
- Added source-filter chips to the shared Debug log card and threaded structured `EditorLogSink` callbacks through editor learner/editor/attachment widgets so module-routed UI events no longer land with an empty source.
- Fixed the editor smoke-test regression where signed-out first-run local drafts were seeded but hidden behind the public-note scope.
- Documented the Editor app's portable archive goal: GitHub-flavored Markdown for prose, JSON/frontmatter for metadata, and normal media files as the durable storage shape.
- Paused Apple Journal import implementation pending the folder-vs-ZIP picker decision: Flutter web can reliably import ZIP files, while recursive selected-folder reads require a desktop-only path.
- Refreshed `frontend/editor_app/pubspec.lock` so the editor web build resolves the shared package's `idb_shim` transitive dependency; editor smoke test and editor web build pass.
- Added four click-run root `scripts/` Python backup/restore tools: PostgreSQL tar backup/restore via `pg_dump`/`pg_restore`, and Cloudflare R2 tar backup/restore via stdlib SigV4 requests that read root `.env`.
- Completed the Editor TODO items: private cloud-category subscriptions now have backend model/API/client/sidebar support, and Settings has an experimental Apple Journal ZIP importer that creates local drafts/categories with sync paused until manual push.
- Added tracked `.gitignore` entries for `scripts/db_backup/` and `scripts/r2_backup/`; removed the project-local docs rule that previously forbade `.gitignore` edits.
- Fast-forwarded `main` to the completed feature branch and added the project-specific branch rule: work directly on `main` unless the owner explicitly names another branch; other branches are backup / provenance branches.
- 0.1.126 (docs-only): surveyed mobile-web compatibility and produced `docs/development/cross_platform_plan.md`. Root-caused the "multi app auth corrupting" symptom: on GitHub Pages all three apps share one origin and use identical `shared_preferences` keys (`notechondria.local_*`, `notechondria.session`, unprefixed `oauth_*`), so they overwrite each other's sessions and drafts; fix tracked as Urgent in `docs/TODO.md` (per-app key namespacing + copy migration). Also recorded: missing viewport meta in all three `web/index.html`, placeholder web identity ("frontend"), no offline launch on Pages (service worker force-disabled) + Safari 7-day ITP eviction risk, and `oauth_callback` hardcoding the editor path. Rewrote the stale Casdoor TODO entry (phases 1-3 already landed in 0.1.95-0.1.101; only 4-5 remain) and added a tutorials-as-public-courses plan. No code changed, so no Flutter/Django test runs this round.
- 0.1.127: implemented the three owner decisions (service worker re-enabled with update toast + STRIP_SERVICE_WORKER kill switch; What's-New overlay replacing course-based tutorials, with Creator.last_seen_versions tracking; permanent email/password fallback with Casdoor password auto-sync). Fixed the Urgent same-origin storage collision (per-app `notechondria.<app>.*` namespacing + copy migration, OAuth handoff keys included). Live-verified Casdoor ROPC against auth.trance-0.com; found the IdP scrubs the `password` claim (claims-sync path dormant, documented in TODO). Repaired pre-existing failures: 3 stale CasdoorAuthTests (asserted pre-0.1.118 auto-link/auto-provision and pre-0.1.109 signin URL) and 14 NoteAttachmentByUuidApiTests (still used session login dropped at cutover) — both verified failing on unmodified HEAD via worktree before touching. Refreshed planner/portal pubspec.lock (idb_shim resolution; their web builds were broken the same way 0.1.123 fixed for editor). Verified: full backend suite OK (169 tests, Django 4.2.10 venv, settings_test); flutter analyze 0 errors x3; smoke tests pass x3; web builds pass x3 with viewport/title/service-worker spot-checked in built output. Reminder: building with --base-href under Git Bash on Windows needs MSYS_NO_PATHCONV=1 or the path gets rewritten to C:/Program Files/Git/...
- 0.1.128: ported the index repo reaction simulator to Dart (`notechondria_shared/lib/src/reaction_simulator/`, TCA preset + CPK palette, hardcoded 128 particles / energy N(250000,60000)) and made it the splash backdrop, deleting the 840-line `splash_painter.dart`. Dart port over JS embedding because the splash ships in native desktop/mobile builds. Porting pitfall caught by tests: JS for..of tolerates appending to the iterated array (upstream `_ripen` spawns products mid-loop); Dart iterators throw ConcurrentModificationError — iterate a snapshot. Completed the TODO OAuth-callback app-routing item (`state` suffix `_editor|_planner|_portal` -> per-app redirect path; SPA appends `state=app_<id>` to the GitHub App install URL). Owner authorized the `.gitignore` shared-lib negation. Added the "Installing on a phone" docs section. Verified: shared + 3-app analyze 0 errors, all flutter suites pass, 3 web builds pass, full backend suite OK.
- 0.1.129: closed the remaining Cross-platform web shell TODO items except the browser-driver regression test. Generated distinct per-app icons (editor teal E, planner indigo P, portal amber N) at 192/512/maskable + favicon via Pillow (offline, not a runtime dep) and matched manifest theme/background colors to each hue. Added a shared one-time dismissible MaterialBanner (`maybeShowInstallBanner`) nudging mobile-web users to Add to Home Screen, with risk-adaptive copy (signed-out + local drafts -> durability warning); gated by `isMobileWebBrowser()` via a conditional-import probe (web-only, no-op on native/desktop/installed-PWA/flutter-test). Added an editor Settings>Developer "Clear legacy shared storage" action (`_LocalAppStore.clearLegacyKeys`) that removes the pre-0.1.127 unprefixed keys the namespacing migration leaves behind; global to the origin so it clears all three apps. Pitfall: `navigator.standalone` is not in dart:html Navigator and `dart:js_util` did not resolve in the conditional-import analysis context — read it via a `dynamic` cast instead. Verified: analyze 0 errors x4, all flutter suites pass, 3 web builds pass with icons/manifest colors confirmed in output. No backend changes.
- 0.1.130: built the first-run onboarding tour (remaining Tutorials TODO). Chose a layout-agnostic paged intro (concept cards via shared `showOnboardingTour` / `TourStep`) over anchored coach marks, which had deferred the item — coach marks need authoring twice around the 960px breakpoint and break on refactors; the paged tour renders identically on mobile/desktop and needs no per-breakpoint authoring. Per-app `lib/core/onboarding.dart` registries + `_maybeShowOnboarding` (first-run, `onboarding_seen` flag) / `_replayOnboarding` (Settings "View tutorial"). On first boot the tour suppresses the What's-New/install nudges that boot so a new user sees one overlay. Plumbed `onReplayTour` through each settings widget (planner via shared AppPreferencesCard). Pitfall: a Python `.replace` template left doubled `{{`/`}}` braces in the generated onboarding.dart (template was written for `.format`) — caught by analyze, fixed by unescaping. Verified: analyze 0 errors x4, shared suite + 4 new tour tests pass, 3 app smoke tests pass with the tour firing on first boot, 3 web builds pass. No backend changes.
- 0.1.131: fixed the duplicate-Inbox bug. Root cause: pre-0.1.120 builds created real "Inbox" Course rows (is_default=True); 0.1.120 made the uncategorized bucket a client-only render of course_id IS NULL notes, but legacy rows linger and the 0.1.125 migration PROMPT let users dismiss it forever. Fix: backend `cleanup_inbox_courses` mgmt command (courses app) deletes owned "Inbox" courses, reparenting notes to NULL (Note.course_id is SET_NULL so no loss); --dry-run/--limit; 6 tests. Frontend editor: replaced the dismissable prompt with silent auto-migration (`_autoMigrateLegacyInbox` -> `_mergeInboxIntoUncategorized`), removed the dead remove-vs-rename dialog + decision class. Verified no current code path creates an Inbox course. Backend full suite 179 OK, editor analyze 0 errors, smoke + web build pass. Operator must run `python manage.py cleanup_inbox_courses` once on the live DB (runbook: docs/operations/inbox_cleanup.md). Also: started i18n with a plan doc (docs/development/i18n_plan.md) per owner request (en_US + zh_CN, language setting, system default, phased).
- 0.1.132: i18n planning doc (docs/development/i18n_plan.md). Decision: single shared gen-l10n catalog in notechondria_shared with synthetic-package:false + exported AppLocalizations (avoids per-app ARB duplication); locale rides app_settings (system|en|zh, no backend change); system default via null locale + supportedLocales clamp; Language dropdown in shared AppPreferencesCard (editor/portal hand-roll their own); keep AGENTS.md 1.8 diagnostic strings English, localize user-facing consequence only. Phased: editor first, then planner, portal, shared-widget sweep.
- 0.1.133: i18n Phase 1. Validated shared-package gen-l10n: in Flutter 3.38 `synthetic-package` is deprecated/no-op and `output-dir: lib/src/l10n` writes importable Dart that the barrel exports (one catalog for all apps — no per-app ARB duplication). Editor wired end-to-end: MaterialApp delegates/supportedLocales/locale, locale persisted in app_settings mirroring theme_preset, applied via _applyLocalAppSettings (fires new onLocaleChanged), system default for free (null locale -> device clamp), and a Language row (System/English/简体中文) in editor settings that localizes live via AppLocalizations. Only a demo string set translated; bulk editor strings are Phase 1b. Planner/portal untouched but still build against the updated shared package (verified: analyze 0 errors shared+editor, editor smoke, 3 web builds all pass). Gotcha: localizing SHARED widgets would break planner/portal until they also wire the AppLocalizations delegate — so Phase 1 localized only editor-context strings.
- 0.1.134: fixed planner Activity view being sign-in-only. Root cause: the signed-out else branch in planner initial_data._loadInitialData set plannerEvents=const [] and activityWeek=null, wiping the locally-seeded/cached data loaded at boot. Fix: keep the local plannerEvents and rebuild the board via _buildOfflineActivityWeek(); also made _loadActivityWeek rebuild offline when signed out instead of early-returning. Cloud-only data (calendar feeds, recycle bin, cloud notes) still cleared. Verified planner analyze 0 errors + smoke + web build.
- 0.1.135: MCP->CLI migration proposal (docs/integrations/mcp-cli-migration.md). Surveyed backend/mcp: /mcp/ JSON-RPC endpoint, ~44 tools calling Django ORM directly, Bearer ntc_ auth, skill.md served in initialize. Proposal: standalone notechondria-mcp CLI (Python mcp SDK) calling /api/v1/ with the ntc_ key; backend stays source of truth. Additive backend changes only (expose mcp_skill_md over API, audit /api/v1 tool coverage). 5 phases ending in deleting backend/mcp/. Flagged stale auth header (ApiKey nch_live vs Bearer ntc_) in docs/server/mcp.md. Docs-only.
- 0.1.136: Local-data storage visualization (editor first). Backend: /api/v1/handshake/ now returns storage:{backend,label} from STORAGES[default][BACKEND] (cloudflare-r2 vs local-disk); 4 handshake tests. Shared: StorageUsageCard (backend host + storage arch, total used, browser quota+free via navigator.storage.estimate web helper, per-bucket breakdown bars, low-storage suggestions) + conditional-import readStorageEstimate. Editor: HandshakeResult.storageLabel + verifyHandshake on the interface; _LocalAppStore.bucketSizes() (utf8 byte sizes per bucket, session key excluded); _StorageUsageSection gathers bucketSizes + LocalAttachmentStore.totalBytes() + handshake arch probe and renders the card atop the Local data subpage. Planner/portal reuse the shared card as follow-up. Verified: backend suite OK, analyze 0 errors shared+editor, editor smoke, 3 web builds.
- 0.1.137: ran the Inbox DB fix on the LIVE db from this local session (DATABASE_URL from repo-root .env, DJANGO_SETTINGS_MODULE=notechondria.settings; needed psycopg2-binary in backend/.venv). The owned-only sweep found nothing, but a read-only audit found 1 ORPHANED ownerless Inbox course (id=19 slug=inbox-7, 0 notes, 1 subscription) rendering as a duplicate for the subscriber. Added --include-ownerless flag to cleanup_inbox_courses (default still owned-only), test it, ran --dry-run then applied: 0 Inbox courses remain (3 total, was 4). Lesson: a creator-deleted (SET_NULL) Inbox placeholder keeps its subscriptions and shows as a duplicate; the owned-only default missed it.
- 0.1.138: started the MCP->CLI migration (Phase 2). New cli/ Python program (independent of backend/): config (env or ~/.notechondria/config.json), requests client (Bearer ntc_ key), tool registry mirroring backend/mcp/tools.py (notes CRUD, courses, planner events), stdio JSON-RPC 2.0 server (initialize fetches mcp_skill_md as instructions, tools/list, tools/call, ping), __main__ with check+serve, README, 10 unit tests (no network/no MCP SDK, all pass). No backend change needed: ntc_ keys already auth every /api/v1 endpoint and /api/v1/settings/ already returns mcp_skill_md. Owner decisions locked: keep both servers (shared ntc_ auth, 1 key/user), cli/ dir, Python, keep /mcp/ for now. Added the MCP<->CLI parity rule to docs/index.md §0 (every new tool in both servers). Transport hand-rolled (no SDK dep) so it is testable now; can adopt the official mcp SDK later.
