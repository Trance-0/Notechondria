# TODO

Pending version: 0.1

Here is a list of task we need to do now after testing, finishing and solve these bugs in order, and check the item from the list when you are done, ignore the checked items. The following is the list you need to follow:

1. If certain functionality in frontend involves changes in backend, add the backend function in the corresponding module and test them before implementing them in frontend, provide options for hard to implement features.
2. For testing backend, check render-mcp, the api key and database credentials is in the local `sample.test.env`, or `sample.render.env` file.
3. You may Add items to the TODO if
   - You find additional features that I described to you but is not implemented to keep them on track and let me know you get to it.
   - A big task that needs to be decomposed into smaller tasks, and test on each steps.
4. For the bug you fixed on this round, create a new `<Pending-version>.<inc-numeral>.md` in `./docs/` versions, move your finished item (delete the completed item in this file) to this new file, follow the templated defined in previous files.
5. For new features, deleted features, include the detailed descriptions update in `./docs/`
6. **Versioning rule:** On each update, increment the third digit in `./VERSION` (e.g. `0.1.8` -> `0.1.9`). The first two digits (`0.1`) are controlled by humans only — never change them. The `VERSION` file is read by `prepare_env.sh` to tag Docker images as `v<VERSION>.<BUILD_NUMBER>`.
7. Let me know any environment variables need to be updated. After all edits are done, check every test passed. COMMIT and I will push after check.
8. Always finish `**Urgent**` tasks first if exists.
9. PAUSE WHEN CREDIT LIMIT RUNS OUT BEFORE CONTINUE THE NEXT TASK

Completed rounds live in `./docs/versions/<semver>.md` — do **not**
restate them here. When a task is landed, delete its entry from this
file and add a round-log entry to the new version doc.

## Global reusable components

### Cross-platform web shell

Survey + full design landed in
[`docs/development/cross_platform_plan.md`](development/cross_platform_plan.md)
(written at 0.1.126). Finding numbers below refer to that doc.

- [ ] **Urgent — per-app storage namespacing (F1).** On GitHub Pages
  all three apps share one browser origin, and editor / planner /
  portal use identical `shared_preferences` keys
  (`notechondria.local_*`, `notechondria.session`, shared `oauth_*`
  keys in `app_shell_oauth_mixin.dart`). They overwrite each other's
  sessions, settings, drafts, and OAuth intent — the observed
  "multi app auth is corrupting" behavior on web. Prefix every key
  per app (`notechondria.editor.*` etc.), prefix the shared OAuth
  handoff keys with the launching app id, and add a one-time
  copy-style migration for legacy unprefixed keys. Acceptance test:
  log in via editor, open planner in the same browser — planner must
  not inherit or mutate editor state.
- [ ] **Viewport meta tag (F2).** All three `web/index.html` lack
  `<meta name="viewport" ...>`, so iPhone Safari renders the desktop
  layout on a ~980 px virtual viewport. Add
  `width=device-width, initial-scale=1, viewport-fit=cover` to each.
- [ ] **Web identity (F3).** Replace placeholder `"frontend"` /
  `"A new Flutter project."` in each app's `web/manifest.json`,
  `<title>`, and `apple-mobile-web-app-title` with per-app names
  (Notechondria Editor / Planner / Portal) and distinct icons so
  Safari bookmarks and Add-to-Home-Screen are tellable apart.
- [ ] **Offline / install story (F4).** Decide the service-worker
  question (currently force-disabled in `frontend-pages.yml`, so web
  builds cannot launch offline at all): keep disabled, or trial
  re-enable on portal with an update toast and a workflow kill
  switch. Independent of that decision: add Add-to-Home-Screen
  guidance for iOS (mitigates Safari's 7-day storage eviction) and a
  "local-only data can be evicted — sign in to keep it" notice when
  local drafts exist without a session.

### Login and account info

### App preferences

### Debug log window

## Editor

### Note view

### Note editor

### Editor Settings

## Planner

- [ ] Planner starter workspace currently seeds a single "Starter
  planning course" + two planning drafts on first run
  (`planner_app/lib/app_shell.dart` `_ensureStarterWorkspace`).
  Decide whether planner should have an analogous
  "Inbox / scratchpad" category instead of a premade course — or
  whether the planning-course semantics make a non-Inbox default
  the right default. Changing planner's starter default is a UX
  break, so gather feedback before touching.

## Tutorials

Design rationale in
[`docs/development/cross_platform_plan.md §3`](development/cross_platform_plan.md):
tutorials ship as ordinary public courses (reuses course / public-note
/ subscription infra, renders responsively on every platform), not as
in-app overlay tours.

- [ ] **Tutorial course content + seeding (backend).** Author
  `getting-started`, `editor-basics`, and `planner-basics` courses
  under `sample/` following the existing `course.json` + markdown
  convention, and add an idempotent `seed_tutorials` management
  command that publishes them as admin-owned public courses on a
  non-empty database (`bootstrap_platform` only runs on empty DBs).
  Screenshots should be captured at a narrow viewport so phone users
  see their own layout.
- [ ] **Tutorial surfacing (frontend).** Portal front page gets a
  "Start here" pinned collection; editor and planner get a
  "Help & tutorials" row in Settings deep-linking into the tutorial
  course; extend the seeded welcome notes in each app's
  `lib/core/local_starter.dart` to link there. No overlay-tour
  framework — the 960 px breakpoint would force double-authoring of
  every step.

## Backend

### Auth

- [ ] **Casdoor migration — remaining phases 4–5 only.** Phases 1–3
  of [`docs/integrations/casdoor-migration.md`](integrations/casdoor-migration.md)
  landed across 0.1.95–0.1.101 (JWT auth class, `Creator.casdoor_sub`,
  exchange/bind/unlink endpoints, shared `AuthHub` + OAuth mixin,
  link-challenge flow in 0.1.118, OIDC profile refresh in 0.1.119;
  the `Session` model was dropped in 0.1.106). Still open:
  4. Retire the remaining legacy auth endpoints. Owner decision
     needed: keep the 0.1.111 email/password fallback as a permanent
     Casdoor-outage escape hatch, or remove it too.
  5. Cleanup: delete dead serializers / templates / helpers listed in
     the survey, and add a status header to
     `integrations/casdoor-migration.md` marking phases 1–3 DONE so
     future rounds stop re-planning them.
- [ ] **OAuth callback app routing (cross_platform_plan F5).**
  `backend/notechondria/api_views.py` `oauth_callback` redirects every
  same-tab flow to a single `FRONTEND_ORIGIN` plus a hardcoded
  `/Notechondria/editor/` path, so GitHub App installs and legacy
  provider flows started from planner / portal land in the editor.
  Carry the originating app through the `state` parameter (suffix
  `_editor` / `_planner` / `_portal`, mirroring the `_bind`
  convention) and map it back to the right app path on return.
- [ ] **Casdoor redirect-URI audit (cross_platform_plan F6).** Verify
  the app config on `auth.trance-0.com` lists every redirect URI the
  SPAs can present (`Uri.base` minus query): the three Pages paths
  under `https://trance-0.github.io/Notechondria/...`, any
  custom-domain equivalents, and local-dev `http://localhost:<port>/`
  entries — and that backend `CSRF_TRUSTED_ORIGINS` /
  `FRONTEND_ORIGIN` envs match. Document the final list in
  `integrations/casdoor-setup.md`.
- [ ] **MCP API keys stay app-internal.** Casdoor is NOT in the
  per-request hot path for MCP — the `Bearer ntc_<key>` scheme keeps
  using `creators.authentication.ApiKeyAuthentication` and the
  `/api/v1/auth/rotate-api-key/` endpoint. Document this in
  `docs/server/mcp.md` as part of the cutover round.

### MCP

### GitHub Sync

- [ ] **Push-side conflict resolution.** The Contents API PUTs in
  `creators.services.github_sync.commit_and_push` overwrite the
  remote blob unconditionally. A user editing on two devices
  between syncs can lose changes. Fetch the existing blob on each
  path, diff against the materialized payload, and surface a
  "remote changed — overwrite or merge?" prompt before writing.
  Lifted from the 0.1.94 carryover.
- [ ] **Asset rotation / pruning.** Repeated `include_assets=true`
  pushes accumulate orphan files for notes deleted client-side
  whose old `assets/notes/<uuid>/` paths still live in the remote
  tree. Add a `--prune-orphans` mode on the push pipeline that
  walks the Trees API and removes unreferenced subtrees in the
  same commit. Lifted from the 0.1.94 carryover.

## Release / CI

- [ ] **Editor + planner GitHub Release workflows.** 0.1.68
  documented the existing `portal-release.yml` workflow in
  [`docs/deployment/release.md`](deployment/release.md). The
  same shape is needed for `editor_app` and `planner_app`.
  Decide tag namespacing before duplicating: a plain `v0.1.68`
  push would fire all three workflows and they'd race to
  publish/update the same GitHub Release. Proposals:
  - `ve0.1.68` → editor, `vp0.1.68` → planner, `v0.1.68` →
    portal. Each workflow filters on its own tag prefix.
  - OR fold all three into a single `frontend-release.yml`
    with a per-app matrix leg and a single publish job at the
    end (attaches all 18 archives to one release). Cleaner
    artefact discovery, harder matrix.
  - Windows code signing is still open — see
    [release.md #not yet automated](deployment/release.md#not-yet-automated).

## Documentation pages
