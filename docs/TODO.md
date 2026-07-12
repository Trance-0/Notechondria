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

## **Urgent** — Activity first, then agent task-execution (owner priority 2026-07-10)

Owner's current priority order: (1) the Activity surface (calendar +
tasks) fully working, (2) agents able to remote-test and to create /
manage tasks for the user over MCP, with batch work going through the
CLI. Landed in 0.1.160: `seed_agent_user`, the gateway `/mcp/` route
fix (MCP was unreachable through the Docker gateway), MCP↔REST
planner-event parity (window normalization + reopen), `days` on
`get_activity_week` + REST `include_completed`/`limit` on
`planner-events/`, baseline `initialize` instructions on both MCP
servers, upgraded tool descriptions/schemas (planner cluster +
destructive-tool warnings), and `notechondria-mcp batch`. Landed in
0.1.161: the Pages CI split (frontend / docs deploys independent) and
the `backend-tests.yml` CI leg. Standing constraints for all future
rounds: docs/AGENTS.md **Host resource budget** AND **Deployment
topology & no-local-containers rule** — this project never runs in
local Docker on a < 16 GB machine; frontend/docs deploy via GitHub
Pages, backend via Northflank on commit, suites via CI on push.

- [ ] **Activity UI verification pass (frontend).** Backend + MCP
  Activity flows are verified end-to-end; the Flutter Activity
  screens (portal `activity_week.dart`, planner todo list) have only
  been exercised by owner reports (0.1.158 fix round). Verify against
  the **deployed** Pages frontend + Northflank backend after the next
  push; collect any remaining Activity bugs into the next fix round.
- [ ] **Browser-level probe layer.** Playwright (Python) against the
  deployed Pages site (`https://trance-0.github.io/Notechondria/...`)
  for smoke flows + screenshots (headless, one browser, after
  checking `free -h`). Unblocks the storage-isolation regression test
  (F1) and gives the owner async screenshots for UI taste checks.
  Screenshots land in a gitignored `artifacts/` dir.
- [ ] **Repo `.mcp.json`** registering the CLI server (key read from
  env, never committed) so Claude Code sessions get the 41 tools
  automatically against the deployed backend.
- [ ] **Round-end verification convention.** On this host: CLI unit
  tests when `cli/` changed, plus static checks; backend Django
  tests, Flutter smoke tests, web builds, and the docs build are
  proven by CI (`backend-tests.yml` / `frontend-pages.yml` /
  `docs-pages.yml`) after the owner pushes. Probe the deployed
  handshake to confirm a backend deploy landed. Call out anything not
  run locally per LLM_CHECK — and never start project containers
  locally.

## **Urgent** — GitHub course binding & activity UX (owner request 2026-07-11)

Large multi-part owner request. Recurrence backend + MCP/CLI landed in
0.1.164; the rest below is pending. Deliver in CI-verified increments;
do not run project containers/apps locally.

### Recurring events
- [x] Backend: `recurrence_freq/interval/end_date/count` on `PlannerEvent`,
  window expansion in `calendar_week_payload`, serializer + views,
  MCP/CLI parity, tests. (0.1.164)
- [x] **Activity UI (portal):** recurrence controls in the hold-to-edit
  event dialog — default one-time; weekly/monthly/yearly; ends at a
  date OR after N occurrences. Recurring occurrences render from the
  expanded week payload. (0.1.167) — recurrence in the *create* dialog
  and planner_app parity still pending.

### Activity UI fixes (portal)
- [x] Event chip CSS: luminance-derived ink (legible in dark theme) +
  per-course palette colour variation. (0.1.167)
- [x] **Long-press / right-click** an event opens the edit dialog
  (planner events; falls back to detail sheet otherwise). (0.1.167)
- [x] **Course (category) filter** at the top of the activity view
  (portal): `_CourseFilterBar` narrows the grid + deadlines to one
  course. (0.1.169)
- [x] **ICS / subscription import feedback modal** (portal): success
  shows a bullet list of imported events, failure shows the reason.
  Backend `import_summary` on feed create. (0.1.166) — planner_app
  parity still pending.

### Course ↔ GitHub binding (backend source of truth, lazy sync)
- [x] Backend **bind / unlink** endpoints (`courses/<id>/git/` GET/PUT/
  DELETE, owner-only, `owner/name` validation), owner-only `git` field
  on `CourseSerializer`. (0.1.170)
**Locked-in architecture (owner, 2026-07-11):**
- **Auth = per-user GitHub App** (reuse the profile-sync App installation
  token to push to `Course.git_repo`). The Nesbitt-bot PAT is used ONLY
  to create the template repo and publish the standard.
- **Scheduler = lazy-on-request** (no worker/cron): flush pending courses
  during normal API traffic, row-locked against double-push.
- **Adapter, not restructure**: bind an existing docs repo (VitePress/
  Nextra/Docusaurus/GitBook) via `notechondria.course.yaml`; read/write
  **markdown only**, never touch build config/code/CI. Backend is the
  source of truth; overwrite mapped markdown only after permission.

- [x] **Course-repo adapter + format standard**: `courses/course_repo.py`
  (config + presets + parser, tested), `docs/integrations/course-repo-format.md`,
  PyYAML dep. (0.1.172)
- [x] Backend **`git_import`** endpoint (`POST courses/<id>/git/import/`
  + MCP/CLI `import_course_git`): App-token fetch → `parse_course_repo` →
  create/update notes matched by `Note.git_path`; `GIT_IMPORT` log. (0.1.173)
- [x] **Lazy-on-request sync**: course notes → markdown (adapter write
  mapping) → commit/push via the App token to `Course.git_repo`, fired
  when `git_pending_since` exceeds `git_sync_timeout_minutes` (row-locked;
  `git_last_synced_at`/`git_last_sync_error`; `GIT_SYNC` log). Overwrite
  mapped markdown only, after permission. `serialize_course_for_sync` +
  `_commit_files` + `sync_course_to_repo` + `mark_course_pending` +
  `flush_due_course_syncs`; `POST courses/<id>/git/sync/`; arm-on-edit in
  the three note-write paths; flush on the authenticated course-list
  poll; MCP/CLI `sync_course_git`. (0.1.174)
- [ ] **Multi-repo per user**: today `GithubIntegration.repo_full_name`
  is one repo; let each `Course.git_repo` push with the user's App token.
- [x] **Effective logs** on bind / unlink (`GIT_BIND`/`GIT_UNLINK`). (0.1.170)
- [x] Created the **course template repo**
  `Nesbitt-bot/notechondria-course-template` (private, `is_template`).
  (2026-07-11) — will re-seed as the *standard/reference* (config example)
  rather than a rigid layout.
- [~] **Veronica-7 migration** — adapter validated read-only against the
  real repo (211 blobs / 195 md): `infer_preset`→`vitepress`, `.vitepress/**`
  excluded, no README/TODO leakage, depth-1 → 6 index-titled modules / 193
  notes / 0 warnings, frontmatter round-trips. Validated
  `notechondria.course.yaml` + runbook: `docs/integrations/veronica-7-migration.md`.
  **Remaining (blocked here — need production + owner sign-off):** fork
  `colorful-numbers/Veronica-7` → Nesbitt-bot (bot PAT); push the config to
  the fork; **bind + import needs the GitHub Data Sync App installed on the
  fork + the production backend** (no local Django here); the **PR back to
  the original is outward-facing to a third party — confirm before opening.**
- [ ] **MDX support** (`.mdx`) — skipped in v1 (parser warns); add
  parsing + sync-write once markdown is solid.
- [ ] **Cloudflare-style repo selector/binder** UI: list of repos, each
  opens a modal to pick the course to bind + set the sync timeout.
- [x] **MCP/CLI** `get_course_git` / `set_course_git` (both servers,
  parity; shared `notes.services` logic). (0.1.171) — course *content*
  access over API key already exists (list_courses/get_course/notes
  tools).

### Cross-app plumbing
- [ ] **Developer menu** currently editor-only — embed it in **planner**
  and **portal** too; menu content depends on each app's support.
- [ ] **Experimental features** registry: add "GitHub course sync"
  alongside "import apple journal".

## Dev plan — bring every component online (fewest owner-attention rounds)

Working agreement: the owner focuses on testing and new features;
agents finish the remaining completion work in **batched autonomous
rounds**. Each round below is sized for one agent session, ends with
the harness green + a commit, and needs **zero owner input** unless an
item is tagged `[OWNER]`. All `[OWNER]` items are consolidated into
Round E so human attention is spent once, at the end.

### Round A — i18n completion sweep (no owner input)

Finish every remaining string so no future round has to context-switch
back into i18n. Subsumes the per-phase remnants tracked in the i18n
section below:

- Portal settings **body** strings: personal-info form fields, the
  API-key section (`settings_sections.dart`), backend/offline +
  local-data captions, recycle-bin dialog, Casdoor connected-accounts
  copy.
- Shared `mcp_skill_section.dart` chrome (keep §1.8 diagnostic strings
  English).
- Planner Phase 2: nav, screens, dialogs.
- Closing audit: grep sweep for hardcoded user-facing literals across
  all three apps + shared; locale-switch test per app must pass.

### Round B — portal feature parity + stale-module cleanup

- Portal Settings to full parity with editor Settings (tracked as
  deferred since 0.1.18).
- Remove the stale unused modules flagged in index.md §6
  (`planner_app`/`portal_app` copies of `front.dart`, `course.dart`,
  `activity.dart`, `learner.dart` not reachable from `visibleIndices`)
  — requires the `app_shell.dart` rewrite; do it together with the
  Round C shell work to avoid touching the same file twice.

### Round C — low-depth UI pass (Apple-HIG-inspired)

Design goal from the owner: modern interaction in the Apple direction,
minimal learning effort, **low navigation depth**, no feature loss.
Concretely:

- **Design tokens in `notechondria_shared`**: one typography scale
  (large-title page headers), an 8-pt spacing grid, corner-radius and
  elevation tokens (flat surfaces, hairline dividers, blur where
  `showBlurDialog` already set the precedent), standard motion
  durations/curves. Apps consume tokens; no per-app forks.
- **Depth audit**: every core action reachable in ≤ 2 taps from the
  app's home surface. Flatten the 7-subpage settings stack into one
  scrollable grouped page with inline disclosure (search-style jump
  header), keeping deep links to sections working.
- **Direct manipulation over menus**: swipe actions on note/event list
  rows (archive, complete, delete-with-undo SnackBar), pull-to-refresh
  on every feed, keep drag-to-create (0.1.158 calendar) as the pattern
  reference.
- **Sheets over dialogs** on compact layouts: bottom sheets with
  grabbers for pickers/actions; dialogs stay on wide/desktop.
- Acceptance: harness screenshots of every main surface before/after
  for the owner's async review; smoke + locale tests green.

### Round D — cross-app information sharing

Maximize what the three little apps share, so switching apps never
loses context:

- **Same-origin single sign-in**: the F1 storage namespacing
  (0.1.127–0.1.129) isolates per-app keys; add a deliberate **shared**
  namespace for the session token + locale + theme so signing into one
  app signs into all three on the same origin (Docker/Pages deploys).
  Guard with the existing storage-isolation acceptance test once the
  Playwright layer (Urgent section) exists.
- **Cross-app deep links with context**: portal is the hub — notes
  open in editor (`/editor/#/note/<id>`), courses/deadlines in planner;
  editor/planner link back to portal surfaces. Define one shared
  route-building helper in `notechondria_shared` so link shapes never
  drift.
- **Shared workspace summary**: portal front page already gets
  `upcoming_events` + recent notes from `FrontPageApiView`; surface the
  same compact cross-module strip (next deadline, last-edited note) in
  editor and planner headers so information flows both ways. Backend
  data already exists — frontend consumption only.

### Round E — release + owner checklist (single human-attention gate)

- Editor + planner GitHub Release workflows (see Release / CI section
  below — decide tag namespacing there first).
- `[OWNER]` one consolidated checklist, prepared by the agent as a
  short doc the round before: production `SECRET_KEY` rotation
  (Render), OAuth redirect-URI registration for final hostnames,
  `MIN_FRONTEND_VERSION` floor decision, Casdoor redirect-URI list
  recording (Backend/Auth section below), PyPI publish credentials for
  `notechondria-mcp` (MCP Phase 4), and a taste-check pass over the
  Round C screenshot gallery.

## Global reusable components

### Cross-platform web shell

Survey + full design in
[`docs/development/cross_platform_plan.md`](development/cross_platform_plan.md).
F1 (storage namespacing), F2 (viewport meta), F3 (web identity), the
F4 service-worker decision, per-app icons, the in-app install hint /
durability notice, and the legacy storage-key cleanup action landed
across 0.1.127–0.1.129 — see
[`versions/0.1.127.md`](versions/0.1.127.md),
[`0.1.128.md`](versions/0.1.128.md), and
[`0.1.129.md`](versions/0.1.129.md). Remaining:

- [ ] **Storage-isolation regression test.** Script the F1 acceptance
  test (load editor then planner under one origin, assert neither
  mutates the other's namespaced keys) — Playwright against the built
  web bundles, or a `flutter drive` web run. Needs a browser-driver
  toolchain not currently set up in this environment.

### Login and account info

### Local data / storage

### App preferences

### Debug log window

## Editor

### Note view

### Note editor

### Editor Settings

## Internationalization (i18n)

Full plan + architecture in
[`docs/development/i18n_plan.md`](development/i18n_plan.md). Goal:
English (US) + Chinese (Simplified), a Language setting in each app
(shared widget), system-language default on first run. Phased:

- [x] **Phase 1 — scaffold + editor language switcher (0.1.133).**
  Shared ARB catalog + generated `AppLocalizations` in
  `notechondria_shared`, editor `MaterialApp` wired with delegates +
  `supportedLocales` + `locale`, `locale` persisted in `app_settings`
  (mirrors `theme_preset`), system-locale default, and a working
  Language row in the editor settings (System / English / 简体中文).
  Only a demonstrative string set is translated so far — the bulk of
  the editor's strings still need migrating to ARB keys (carry into a
  Phase 1b or fold into Phase 4).
- [~] **Phase 1b/1c — editor strings → ARB (in progress).** 0.1.140
  translated the editor settings surface (menu tiles + subpage titles +
  rows + caption), the shared debug-log **menu** chrome, and added the
  `AppLocalizations` delegate to planner/portal so shared widgets
  localize. 0.1.141 translated the always-visible surfaces — the
  navigation/shell (drawer + rail labels, error bar, category dialogs)
  and the home/notes feed (`learner.dart`: search hints, section
  headers, empty states, scope dropdown, composer menu, sync card, FAB
  tooltips) — and added `editor_app/test/locale_switch_test.dart`
  proving the switch renders Chinese at runtime (the mechanism was
  always sound; the gap was coverage). 0.1.142 translated the note
  viewer (the share-link preview), the note editor "More actions" menu +
  hints, and the private-note/load-error dialogs. Remaining editor
  strings (note metadata/export dialog, live-markdown paragraph
  placeholders, misc snackbars) still need migrating screen by screen.
- [~] **Phase 2/3 — planner + portal Language setting (0.1.143).**
  Both apps now have a working in-app Language picker (System / English
  / 简体中文): locale state + persistence + `MaterialApp.locale` +
  apply-immediately `_setLocale` mirror the editor; planner via the
  shared `AppPreferencesCard` (now fully localized + a new Language
  row), portal via a Language row in its preferences subpage. Locale
  tests added for both. **Remaining:** translate the rest of the planner
  / portal app strings (nav, screens, dialogs) — only the shared
  settings/preferences surface is localized so far.
- [~] **Phase 4 — remaining shared widgets (in progress).** 0.1.147
  localized the StorageUsageCard (incl. its byte-quota + suggestion
  strings), the ErrorStateView retry, the install banner (both copy
  variants + "Got it"), the onboarding-tour chrome
  (Close/Skip/Back/Next/Done), and the what's-new overlay
  (title + Skip/Got it). 0.1.148 localized the **auth surface**: the
  AuthHub (`auth_dialogs.dart` — Account, the SSO descriptions, the
  Casdoor/sign-up CTAs, the email/password expander + login dialog
  incl. its phased-status lines) and the
  `casdoor_link_challenge_dialog.dart` bind/create flow (all panes,
  field labels, actions, and form-validation errors). Also replaced a
  fragile `title == 'Login'` check in `EmailPasswordDialog` with an
  explicit `finishAutofillOnSuccess` flag so the title can localize.
  **Remaining:** `mcp_skill_section.dart` (the user-facing skill.md +
  GitHub-sync card chrome; keep its operator/diagnostic snackbar
  strings English per AGENTS.md §1.8). (Log OUTPUT lines + terminal
  command I/O stay English by design. The per-app What's-New /
  onboarding *content* registries also stay English for now — only the
  shared chrome is localized.)
- [ ] **Phase 2 — planner strings.** Translate planner UI; reuse the
  shared catalog for common strings.
- [~] **Phase 3 — portal strings (nearly done).** Localized across
  0.1.154–0.1.156: front page, course browser, learner feed,
  note-metadata dialog, the block note editor, and the activity /
  week-calendar surfaces (incl. event + iCal dialogs). **Remaining:** the
  portal `settings*.dart` chrome (subpage titles, backend/API/security/
  recycle-bin page strings) — shares the editor's settings pattern.
  0.1.157 localized the settings **navigation** (menu tiles + all
  subpage app-bar titles + the preferences rows). **Final remaining:**
  the deeper settings subpage **body** strings — personal-info form
  fields, the API-key section (`settings_sections.dart`), backend/
  offline + local-data captions, recycle-bin dialog, Casdoor connected-
  accounts copy — plus the shared `mcp_skill_section.dart`.
  (0.1.154 also fixed a functional gap: portal's API base URL is now
  editable from the always-reachable Backend settings page, so a
  signed-out user can repoint the backend.)
- [ ] **Phase 4 — shared-widget + dialog sweep.** Ensure every shared
  component (auth dialogs, onboarding tour, what's-new, install
  banner, debug log, error state) is fully localized, and audit
  SnackBar/dialog strings. Keep AGENTS.md §1.8 diagnostic strings
  English for greppability; localize the user-facing consequence text.

## Planner

- [ ] Planner starter workspace currently seeds a single "Starter
  planning course" + two planning drafts on first run
  (`planner_app/lib/app_shell.dart` `_ensureStarterWorkspace`).
  Decide whether planner should have an analogous
  "Inbox / scratchpad" category instead of a premade course — or
  whether the planning-course semantics make a non-Inbox default
  the right default. Changing planner's starter default is a UX
  break, so gather feedback before touching.

## Version-update notification (landed 0.1.151–0.1.152)

Owner-confirmed **handshake-compare** approach (no GitHub polling) + a
`min_frontend_version` compat floor. Backend handshake exposes both
`version` (already) and `min_frontend_version` (env `MIN_FRONTEND_VERSION`,
empty = no floor). All three apps host a shared `VersionUpdateBanner`
that probes on boot + every 15 min and compares the built `_kAppVersion`:
backend newer → "new version available, refresh"; backend behind the
served bundle → "rolling out"; below the floor → non-dismissible "no
longer supported". Backs future mobile update prompts too. Optional
GitHub-release `latest_version` signal remains a possible follow-up.

## i18n bug fixes (landed)

- 0.1.149 fixed two reported i18n gaps: the editor's "Clear all local
  data" tile + confirm dialog, and the onboarding tour **content**
  (title/body) in all three apps — it was a `const` step list that
  couldn't read `AppLocalizations`, so only the chrome (0.1.147) had
  been localizing. Now built from `l10n`.

## Tutorials / What's New

Owner decision (0.1.127): version-update tutorials are a **UI
overlay**, not courses. The shared `showWhatsNewOverlay` +
per-app `lib/core/whats_new.dart` registries landed in 0.1.127:
on boot each app diffs its built `APP_VERSION` against the user's
`last_seen_version` (local stats for everyone; the per-app
`Creator.last_seen_versions` map for signed-in users) and shows the
missed feature cards once, with a Skip option that also marks them
seen.

**Standing convention for every future round:** when a round ships a
user-visible feature, append a `FeatureUpdate` entry (version, title,
one-to-two-sentence description, icon) to the affected app's
`lib/core/whats_new.dart` registry in the same commit as the feature.

First-run onboarding tour landed in 0.1.130 — see
[`versions/0.1.130.md`](versions/0.1.130.md). It is a **layout-agnostic
paged intro** (concept cards, not anchored coach marks): the same
content renders identically on the mobile drawer layout and the
desktop sidebar layout, sidestepping the double-authoring/fragility
that had deferred it. Shows once on first run (tracked by an
`onboarding_seen` local-stats flag), is skippable, and is re-openable
from each app's Settings ("View tutorial"). On a brand-new user's
first boot it takes priority over the What's-New / install nudges.

- [ ] **Optional: anchored coach marks (still deferred).** If a future
  round wants step-by-step pointers at specific controls, that remains
  deferred until the responsive layouts are stable — each anchored
  step would need authoring twice around the 960 px breakpoint. The
  paged tour covers onboarding without it.

## Backend

### Auth

- [ ] **Casdoor migration — remaining phases 4–5 only.** Phases 1–3
  of [`docs/integrations/casdoor-migration.md`](integrations/casdoor-migration.md)
  landed across 0.1.95–0.1.101 (JWT auth class, `Creator.casdoor_sub`,
  exchange/bind/unlink endpoints, shared `AuthHub` + OAuth mixin,
  link-challenge flow in 0.1.118, OIDC profile refresh in 0.1.119;
  the `Session` model was dropped in 0.1.106). Still open:
  4. Retire the remaining legacy auth endpoints. Owner decision
     (0.1.127): the email/password fallback login is **permanent**
     (Casdoor-outage escape hatch) and now auto-syncs the Casdoor
     password into the local hash — see
     [`versions/0.1.127.md`](versions/0.1.127.md). Everything else
     legacy can go.
  5. Cleanup: delete dead serializers / templates / helpers listed in
     the survey, and add a status header to
     `integrations/casdoor-migration.md` marking phases 1–3 DONE so
     future rounds stop re-planning them.
- [ ] **Casdoor password-hash claim is scrubbed (watch upstream).**
  The owner configured the application's Token Format (JWT-Custom,
  RS256, token fields Password / Password salt / Password type), but
  live tokens from auth.trance-0.com carry an **empty** `password`
  claim value (`passwordType` says `bcrypt`; verified 2026-06-12) —
  current Casdoor scrubs the hash server-side. The claims-sync path
  in `backend/creators/casdoor_password.py` is implemented and
  dormant; it activates automatically if a Casdoor upgrade starts
  emitting the hash. Until then the ROPC grant at fallback-login
  time covers the sync. Re-test after Casdoor upgrades.
- [ ] **Document the final Casdoor redirect-URI list.** The owner
  completed the app config on `auth.trance-0.com` (0.1.127). Record
  the registered redirect URIs and token-format settings (JWT-Custom,
  RS256, Password / Password salt / Password type token fields) in
  `integrations/casdoor-setup.md` so the config is reproducible.
- [ ] **MCP API keys stay app-internal.** Casdoor is NOT in the
  per-request hot path for MCP — the `Bearer ntc_<key>` scheme keeps
  using `creators.authentication.ApiKeyAuthentication` and the
  `/api/v1/auth/rotate-api-key/` endpoint. Document this in
  `docs/server/mcp.md` as part of the cutover round.

### MCP

**Standalone CLI MCP server** — proposal + owner decisions in
[`docs/integrations/mcp-cli-migration.md`](integrations/mcp-cli-migration.md).
Keep BOTH `/mcp/` (in-backend, HTTP) and the CLI (stdio); separate
endpoints, shared `ntc_` auth (one key per user); CLI in `cli/`
(Python, independent program). **Parity rule: every new MCP tool lands
in both `backend/mcp/tools.py` and `cli/notechondria_mcp/tools.py`.**

- [x] **Phase 2 — CLI skeleton (0.1.138).** Runnable `cli/`
  program: config, backend client, stdio JSON-RPC server, a
  representative tool subset, unit tests.
- [x] **Phase 1 — backend API gap audit (0.1.145).** Audited all 41
  MCP tools in `backend/mcp/tools.py` against `/api/v1/`: every tool
  operation (incl. the flagged note versions/sessions, heatmap,
  activity-week, calendar feeds, and course unsubscribe) has a REST
  equivalent — **no gaps, no new endpoints needed.** Rewrote
  `docs/server/mcp.md`: corrected the auth header to
  `Authorization: Bearer ntc_<secret>` (was `ApiKey nch_live_…`), the
  tool count to 41 (was 21) with an accurate categorized list + a
  tool→endpoint coverage table, the test count to 51 (was 39), and
  added the MCP⇄CLI parity rule.
- [x] **Phase 3 — full tool parity (0.1.146).** All 41 tools from
  `backend/mcp/tools.py` are now in `cli/notechondria_mcp/tools.py` with
  matching names + schemas (name-set diff asserted identical). Filled
  the one audit gap: added a filtered `GET` to `note-sessions/` (was
  POST-only) so `list_note_sessions` works over REST.
- [ ] **Phase 4 — distribute.** Publish `notechondria-mcp` to PyPI;
  document agent-host config.
- [ ] **Phase 5 (deferred).** Cutover/deletion of `backend/mcp/` —
  not until further notice (both servers kept for now).

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
