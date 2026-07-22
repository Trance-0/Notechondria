# TODO — working agreements

> **Open work now lives in [GitHub Issues](https://github.com/Trance-0/Notechondria/issues).**
> The 26 unfinished items from this file were migrated there on 2026-07-19
> (labelled `todo-import`, plus an `area:*` label per component) so each one
> has its own status, discussion thread, and close event.
>
> Browse by area:
> [activity](https://github.com/Trance-0/Notechondria/issues?q=is%3Aissue+is%3Aopen+label%3Aarea%3Aactivity) ·
> [calendar](https://github.com/Trance-0/Notechondria/issues?q=is%3Aissue+is%3Aopen+label%3Aarea%3Acalendar) ·
> [backend](https://github.com/Trance-0/Notechondria/issues?q=is%3Aissue+is%3Aopen+label%3Aarea%3Abackend) ·
> [auth](https://github.com/Trance-0/Notechondria/issues?q=is%3Aissue+is%3Aopen+label%3Aarea%3Aauth) ·
> [mcp](https://github.com/Trance-0/Notechondria/issues?q=is%3Aissue+is%3Aopen+label%3Aarea%3Amcp) ·
> [i18n](https://github.com/Trance-0/Notechondria/issues?q=is%3Aissue+is%3Aopen+label%3Aarea%3Ai18n) ·
> [github-sync](https://github.com/Trance-0/Notechondria/issues?q=is%3Aissue+is%3Aopen+label%3Aarea%3Agithub-sync)
>
> **New work goes straight to an Issue, not to this file.** If you do add
> `- [ ]` items here, `python3 scripts/todo_to_issues.py --dry-run` previews
> them and `--create` files the new ones (existing titles are skipped, so
> it is safe to re-run).
>
> What stays here: the standing working agreements below, and the
> per-section record of what already shipped (`- [x]` with the version that
> landed it). Full round write-ups live in `docs/versions/`.

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
- [x] **Effective logs** on bind / unlink (`GIT_BIND`/`GIT_UNLINK`). (0.1.170)
- [x] Created the **course template repo**
  `Nesbitt-bot/notechondria-course-template` (private, `is_template`).
  (2026-07-11) — will re-seed as the *standard/reference* (config example)
  rather than a rigid layout.
- [x] **Veronica-7 migration** — DONE on production (2026-07-12). Forked
  → `Nesbitt-bot/Veronica-7`, added `notechondria.course.yaml`, App
  installed (installation `146096524`), course **#22** bound, imported
  (193 notes / 6 modules / 0 warnings, idempotent), sync verified (one
  atomic commit, byte-faithful round-trip), lazy sync enabled, and the
  config PR opened upstream: `colorful-numbers/Veronica-7#1`. Runbook:
  `docs/integrations/veronica-7-migration.md`.
- [x] **GitHub App binding over MCP/CLI**: `github_app_status` /
  `connect_github_app` / `list_github_repos` (both servers, parity 45→48;
  shared `github_sync.list_installation_repositories`). Lets an agent
  install-check → link installation id → confirm repo reach before
  `set_course_git` + `import_course_git`. (0.1.175)
- [x] **Sync atomicity/timeout** (found running the real Veronica-7
  migration): `_commit_files` did one Contents-API PUT per file → 193
  commits, 503 after 120s, partial/non-atomic push. Rewrote to a single
  Git Data API commit (tree on `base_tree` → commit → ref), short-circuit
  when nothing changed. (0.1.176)
- [x] **Expose `git_path`** on `NoteDetailSerializer` so the git-import
  mapping is inspectable over the API. (0.1.176)
- [x] **Imported-note order** — `Note.sort_order` (migration 0022) set on
  import from the adapter's module/note ordering; course notes list by
  `("sort_order", "-last_edit")` so native notes keep recency. (0.1.188)
- [x] **Lost module grouping on import** — `Note.module` stores the
  adapter's module label and the course view groups by it. (0.1.178)
- [x] **`pending_since` armed on bind even when `sync_enabled=false`** —
  the debounce is armed only when sync is enabled (cleared when off), so
  the git payload no longer advertises a stuck pending sync. (0.1.188)

### Calendar / course feature batch (remaining after 0.1.178)

Foundations shipped in 0.1.178 (`Course.color_hue`, `Note.module`, event
payload `course`, module grouping #4, HSV event colours #6-core). Remaining
items — several are interaction/architecture-heavy and want a local Flutter
build to validate:

- [x] **#5 Event detail + course selector** — course dropdown in the
  create + edit dialogs (portal 0.1.181, planner 0.1.183; default Inbox)
  and the detail dialog shows course + importance alongside the time.
- [x] **#6 Hue setting button** on the calendar filter row — opens the
  course-edit modal for the selected course; disabled with a tooltip on
  "All courses". (0.1.180, both apps)
- [x] **#3 Lazy course loading** — first page (10) loads with the course,
  a loading bar gates the view (no placeholder content), and further pages
  infinite-scroll in at 20/page. Backend gained real `limit/offset`
  pagination. (0.1.185)
- [x] **#2 Ctrl+scroll time-axis zoom** — the handler existed since
  0.1.163; the browser's page-zoom was swallowing ctrl+wheel. Fixed by
  `preventDefault()` on ctrl/meta wheel in `web/index.html`. (0.1.181)
- [x] **Shareable per-note browser URLs** (bug 8, part 2) — DONE 0.1.179
  for the portal: `#/note/<uuid>` routed page (+ unique URLs for every tab
  and `#/courses/<slug>`), backend read access extended to active course
  subscribers. Remaining below: route
  `/c/<course-slug>/<note-name>` deep-links to a note and updates the URL
  as notes open, so links are shareable/back-navigable. Foundation exists
  (`Note.name` unique per course, 0.1.177; in-course link resolution in the
  viewer). Needs a Navigator-2.0 / `url_strategy` migration of
  `portal_app` `app_shell` — do it with a local Flutter build to validate
  (the portal is a single `MaterialApp(home:)` today with a stub URL
  strategy). Also port link-following to the learner editor preview and add
  `name` to the MCP/CLI note payloads.
- [x] **MCP/CLI** `get_course_git` / `set_course_git` (both servers,
  parity; shared `notes.services` logic). (0.1.171) — course *content*
  access over API key already exists (list_courses/get_course/notes
  tools).

### Cross-app plumbing

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

## Planner


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


## Backend

### Auth


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

### GitHub Sync


## Release / CI


## Documentation pages
