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
- [ ] **Phase 3 — portal strings.** Translate portal UI.
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
