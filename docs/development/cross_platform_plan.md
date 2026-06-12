# Cross-Platform Reliability and Tutorials Plan

> **Status update (0.1.127).** Phase A and most of Phase B landed:
> F1 per-app storage namespacing + legacy-key migration, F2 viewport
> meta, F3 web identity (icons still stock Flutter), and the F4
> service-worker decision — workers are **re-enabled** on Pages with
> an update toast in each `web/index.html` and a
> `STRIP_SERVICE_WORKER` repository-variable kill switch in
> `frontend-pages.yml`. Section 3's course-based tutorial design was
> **rejected by the owner** in favor of a version-gated What's-New
> overlay (shipped 0.1.127; see `docs/TODO.md` "Tutorials / What's
> New" for the standing registry convention). Owner decisions on §6:
> service worker = option 3; email/password fallback = keep
> permanently, now auto-synced against Casdoor (ROPC at fallback
> login; JWT hash claims dormant because Casdoor scrubs the
> `password` value); Casdoor config at auth.trance-0.com = done.
> Remaining open items are tracked in `docs/TODO.md`.

Status snapshot and forward plan, written at 0.1.126. Covers: where the
project stands today, what breaks on mobile web (iOS Safari is the only
mobile channel currently in use), the root cause of the multi-app auth
corruption, the tutorials-integration design, and a phased roadmap.

Owner context this plan is written for:

- The owner uses the apps **purely online via Safari bookmarks on
  iPhone** plus desktop browsers. There is no Apple computer available,
  so **the web build is the iOS delivery channel** for the foreseeable
  future — unsigned iOS archives in the release workflow cannot be
  side-loaded without a Mac. Native compile polish is explicitly out of
  scope for now.
- Casdoor is live at `auth.trance-0.com`; multi-app auth misbehaves
  ("corrupting") and is under investigation. Section 3 names the root
  cause found during this survey.

---

## 1. Current progress snapshot (as of 0.1.125)

What demonstrably works:

- **Three standalone Flutter apps** (`frontend/editor_app`,
  `frontend/planner_app`, `frontend/portal_app`) sharing
  `frontend/notechondria_shared`, all passing smoke tests and
  `flutter build web` with repo-prefixed base-hrefs.
- **Offline-first local model**: every app seeds a starter workspace on
  first run (`lib/core/local_starter.dart` in each app), persists state
  through `lib/core/local_store.dart` (web: `localStorage` via
  `shared_preferences`), and stores attachment bytes in IndexedDB
  (`notechondria_shared/lib/src/utils/local_attachment_store_web.dart`).
- **Casdoor auth is the primary surface** and is much further along than
  `docs/TODO.md` suggested before this round: phases 1–3 of
  [`integrations/casdoor-migration.md`](../integrations/casdoor-migration.md)
  landed across 0.1.95–0.1.101 (JWT auth class
  `backend/creators/casdoor_auth.py`, `Creator.casdoor_sub`,
  exchange/bind/unlink endpoints, shared `AuthHub` + OAuth mixin in the
  frontend, gitea-style link challenge in 0.1.118, OIDC profile refresh
  in 0.1.119). The legacy `Session` model was dropped in 0.1.106; an
  email/password fallback login was restored in 0.1.111 for Casdoor
  outages. Remaining: phases 4–5 (legacy endpoint retirement + cleanup).
- **Backend**: Django + DRF on Python 3.11 Docker base (0.1.115),
  deployable to Render / Northflank / Jenkins / Docker; GitHub data-sync
  push pipeline with asset bundling; MCP server with per-user API keys
  and per-user skill instructions; click-run backup/restore scripts
  (0.1.122).
- **Responsive layout** is genuinely implemented: a 960 px
  `LayoutBuilder` breakpoint switches sidebar ↔ drawer in all three apps
  (`editor_app/lib/app_shell.dart:476`, `planner_app/lib/app_shell.dart:423`,
  `portal_app/lib/app_shell.dart:419`), with `SafeArea` wrapping and no
  hover-only or keyboard-only interactions.

What is documented but stale:

- `docs/TODO.md` still listed the Casdoor migration as a future "next
  major" item; corrected this round.
- No `docs/client/*.md` page mentions mobile, Safari, or PWA behavior;
  this file is now the canonical place for that.

---

## 2. Mobile web findings (prioritized)

### F1 — URGENT: same-origin storage collision corrupts auth and data

**This is the most likely root cause of the "multi app auth is
corrupting" symptom.**

On GitHub Pages (and on any single-domain full-stack deploy where nginx
serves the three apps under one hostname), editor, planner, and portal
all live on **one browser origin** — only the path differs
(`/Notechondria/editor/`, `/Notechondria/planner/`,
`/Notechondria/portal/`). Web storage is **origin-scoped, not
path-scoped**, and all three apps use identical keys:

- `notechondria.local_settings`, `notechondria.local_drafts`,
  `notechondria.local_courses`, `notechondria.local_stats`,
  `notechondria.local_cache`, `notechondria.local_logs`,
  `notechondria.session`, trash keys — duplicated verbatim in
  `editor_app/lib/core/local_store.dart:32`,
  `planner_app/lib/core/local_store.dart:29`, and
  `portal_app/lib/core/local_store.dart:26`.
- OAuth handoff keys `oauth_redirect_uri`, `oauth_invitation_code`,
  `oauth_intent` in
  `notechondria_shared/lib/src/app_shell/app_shell_oauth_mixin.dart:196-198`.
- IndexedDB database `notechondria_attachments`
  (`local_attachment_store_web.dart:8`).

Consequences observed/expected on web:

- Logging in inside one app rewrites `notechondria.session` /
  `local_settings` for all three; opening another app then boots with
  the other app's settings blob, a token it may interpret differently,
  or a profile that doesn't match its cache — i.e. "auth corruption".
- Planner's starter-workspace seeding can fire against an empty-looking
  `local_courses` key and clobber editor categories (and vice versa),
  because each app deserializes the shared key with its own schema.
- An OAuth flow started in app A and a login started in app B race on
  `oauth_intent`; the Casdoor callback can complete with the wrong
  intent (`bind` vs `register`/`login`).

Desktop and mobile **native** builds are unaffected (per-app
preference stores), which is why this only shows up in the
browser-bookmark usage pattern.

**Fix (design shift):** introduce a per-app storage namespace, e.g.
`notechondria.editor.*` / `notechondria.planner.*` /
`notechondria.portal.*`, defined once (constant in each app, or an
`appId` parameter the shared mixins accept) and applied to:

1. every `local_store.dart` key in the three apps,
2. the shared `oauth_*` keys (prefix with the launching app's id —
   this also makes the callback race impossible),
3. optionally the IndexedDB name (attachments are keyed by
   note/attachment UUID, so cross-app sharing is *probably* benign;
   decide explicitly and document rather than leave it implicit).

Plus a one-time migration on boot: if legacy unprefixed keys exist and
the app-scoped keys do not, **copy** (do not move) legacy values into
the app's namespace, then mark the legacy keys migrated; the editor —
as the primary data-bearing app — should be the only app allowed to
delete the legacy keys after all three have stamped their migration
flag. Simpler acceptable variant: copy-and-leave-forever, with a
"Clear legacy shared storage" maintenance action in Developer settings.

### F2 — P0: missing `viewport` meta tag in all three `web/index.html`

`frontend/*/web/index.html` (all three apps) has **no**
`<meta name="viewport" ...>`. Without it, iPhone Safari lays the page
out on a ~980 px virtual viewport and scales it down: tiny text, wrong
breakpoint (the app renders the ≥960 px *desktop* sidebar layout on a
phone), broken pinch behavior, and an unstable keyboard/insets
experience. This single missing line is likely the largest share of
"the page feels broken on mobile".

Fix in each app's `web/index.html` `<head>`:

```html
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
```

(`viewport-fit=cover` lets `SafeArea` handle the iPhone notch/home
indicator correctly in standalone mode.)

### F3 — P0: placeholder web identity ("frontend" / "A new Flutter project")

All three `web/manifest.json` files say `"name": "frontend"`,
`"description": "A new Flutter project."`; `index.html` has
`<title>frontend</title>` and
`<meta name="apple-mobile-web-app-title" content="frontend">`, and the
icons are the stock Flutter logo. A Safari bookmark or Add-to-Home-Screen
therefore shows "frontend" with the Flutter icon for every app, and the
three apps are indistinguishable on a home screen.

Fix per app: title/name "Notechondria Editor" / "Notechondria Planner"
/ "Notechondria Portal" (short_name "Editor" / "Planner" / "Portal"),
real descriptions, distinct icons (even a colored letter glyph is
enough), and consider `"orientation": "any"` instead of
`portrait-primary` for tablet/desktop installs.

### F4 — P1: no offline launch on web + Safari 7-day storage eviction

Two related risks for the bookmark-on-iPhone usage pattern:

1. **Service worker registration is deliberately disabled** in
   published Pages builds (`.github/workflows/frontend-pages.yml`
   rewrites the bootstrap to `_flutter.loader.load({});` and deletes
   `flutter_service_worker.js`) to avoid the stale-cache incidents
   documented in [`deployment/deploy.md`](../deployment/deploy.md).
   Consequence: the "offline-first" apps cannot even *launch* without
   network on web — airplane mode or a flaky connection yields a blank
   page, despite all the local-draft infrastructure underneath.
2. **Safari ITP caps script-writable storage at 7 days** for sites the
   user hasn't interacted with: `localStorage` (all drafts, settings,
   session) and IndexedDB (attachments) can be evicted wholesale if the
   bookmark isn't opened for a week. A signed-out user who drafted
   notes locally and came back after a vacation loses everything.

Mitigations, in recommended order:

1. **Promote Add-to-Home-Screen as the supported iOS channel** (after
   F2/F3 land, it is actually pleasant). Home-screen web apps get their
   own storage partition and are not subject to the 7-day ITP eviction
   in practice; they also get a standalone window and an app icon. Add
   a short "Install on iPhone/Android" section to `docs/readme.md` and
   a one-time dismissible hint card in the apps when
   `display-mode: browser` is detected on a mobile UA.
2. **Make signed-in sync the durability story** and say so in the UI:
   the existing push/pull sync plus GitHub data-sync already cover
   durable storage; surface a gentle "local-only data can be evicted by
   the browser — sign in to keep it" notice in Settings when the user
   has local drafts and no session.
3. **Reconsider the service-worker ban** (decision item, not a
   foregone conclusion): Flutter's generated service worker is
   content-hash versioned, so the historical stale-shell pain is
   recoverable (worst case one stale load, fixed on next reload).
   Options:
   - keep disabled (status quo: zero offline launch, zero cache risk);
   - re-enable as built (offline launch works; accept one-reload
     staleness after deploys);
   - re-enable plus an in-app "new version available — reload" toast
     wired to the service-worker update event (best UX, small JS shim
     in `index.html`).
   Recommendation: option 3, trialed on one app (portal) for a release
   before rolling out, with the rewrite-to-disable kept in the workflow
   behind a flag as the kill switch.

### F5 — P1: backend OAuth callback hardcodes the editor app

`backend/notechondria/api_views.py:394-399` resolves redirects with a
single global `FRONTEND_ORIGIN` env var and a hardcoded
`frontend_path = "/Notechondria/editor/"`. Any flow that round-trips
through `oauth_callback` (GitHub App install, legacy provider logins,
same-tab fallbacks) dumps planner/portal users into the editor, where —
combined with F1 — the editor then rewrites the shared storage keys.
The Casdoor login flow itself is unaffected (the SPA passes its own
`Uri.base` as `redirect_uri`), which is why corruption looks
intermittent.

Fix: carry the originating app through `state` (e.g. suffix
`_editor` / `_planner` / `_portal`, mirroring the existing `_bind`
convention) and map it to the right path on return; keep
`FRONTEND_ORIGIN` for the origin only. Until that lands, expect GitHub
App installs initiated from planner/portal to end in the editor.

### F6 — P2: stale auth docs and Casdoor config drift

- `docs/TODO.md`'s Casdoor entry described the migration as not started
  (fixed this round — now tracks only phases 4–5).
- [`integrations/casdoor-migration.md`](../integrations/casdoor-migration.md)
  should get a status header pointing at the landed phases so future
  agents stop re-planning phase 2/3.
- Casdoor app config at `auth.trance-0.com` must list **every**
  `redirect_uri` the apps can present. The SPA sends
  `Uri.base` minus query string, so the full set is (adjust hostnames
  to actual deploys):
  - `https://trance-0.github.io/Notechondria/editor/`
  - `https://trance-0.github.io/Notechondria/planner/`
  - `https://trance-0.github.io/Notechondria/portal/`
  - custom-domain equivalents if the apps are served there, and
  - `http://localhost:<port>/` entries used during development.
  A missing entry produces Casdoor-side `redirect_uri` rejections that
  present in-app as failed logins on exactly one app — worth
  re-auditing while debugging the corruption, since it compounds F1.
  Keep the matching backend env list (`CSRF_TRUSTED_ORIGINS`,
  `FRONTEND_ORIGIN`) in sync; the union logic in
  `backend/notechondria/settings.py:119-141` only protects the
  auto-detected hosts.

### F7 — P2: existing tracked gaps (unchanged, for completeness)

Already tracked in `docs/TODO.md` and carried forward: GitHub-sync
push-side conflict resolution and asset pruning; editor + planner
release workflows (tag-namespace decision pending); planner starter
default; `app_shell.dart` size; stale planner/portal modules.

---

## 3. Tutorials integration design

Goal: teach new users the editor/planner/portal basics, on every
platform, without building a second content system.

### Options considered

- **A. Tutorials as ordinary public courses (content-first).** Author
  tutorial content as markdown notes inside one or more public
  "Tutorials" courses, seeded server-side exactly like the existing
  sample courses (`backend/notes/management/commands/bootstrap_platform.py`
  already seeds three demo courses from `sample/`). Clients need almost
  nothing new: public-note pull, course subscription, and the portal
  front page already exist. A "Help & tutorials" entry in each app's
  Settings (and the portal front page) deep-links into the course.
- **B. In-app interactive tours (coach marks / overlays).** Highest
  polish, but every tour step must be authored **twice** because the
  960 px breakpoint swaps drawer/sidebar layouts, it breaks whenever a
  screen is refactored, and it needs a tour framework dependency. High
  ongoing cost for three apps.
- **C. Docs-site tutorials (mdBook).** Cheapest, already deployed, but
  lives outside the app and reads as developer docs, not user help.

### Recommendation: A now, B never (for v0.1), C as the long tail

1. **Author tutorial courses under `sample/`** (one per app:
   `editor-basics`, `planner-basics`, plus a shared
   `getting-started`), following the existing `course.json` + markdown
   convention so `bootstrap_platform` (or a new idempotent
   `seed_tutorials` management command that can run on a non-empty DB)
   publishes them as public courses owned by the admin user. Media
   (screenshots/GIFs) ride along via the existing course-media path.
   Authoring screenshots of the *mobile* layout matters: take them at a
   narrow viewport so phone users see their own UI.
2. **Surface them in-app**:
   - portal front page: a "Start here" collection pinned via the
     existing carousel/collections payload;
   - editor + planner: a "Help & tutorials" row in Settings and an
     entry in the starter-workspace welcome note (the seeded welcome
     drafts in `lib/core/local_starter.dart` already exist — link from
     there, works signed-out and offline once pulled).
3. **Keep the starter workspaces as the "tutorial step zero"** — they
   are already the de-facto onboarding and they work offline. Extend
   the welcome note text rather than adding overlay tours.
4. Defer any interactive tour until the responsive layouts are stable
   and a real user-confusion signal exists.

Mobile compatibility of this design is inherent: tutorial content is
just notes, rendered by the same responsive note viewer on every
platform; no per-platform tutorial code exists to drift.

---

## 4. Phased roadmap

Each phase is independently shippable and ordered by user-visible risk.

**Phase A — stop the corruption (urgent, small diffs)**
1. Per-app storage namespacing + legacy-key migration (F1).
2. Viewport meta in all three `index.html` (F2).
3. Casdoor redirect-URI audit at `auth.trance-0.com` + env sync (F6).

**Phase B — make the web channel feel intentional**
4. Web identity: titles, manifests, icons per app (F3).
5. OAuth callback app-routing via `state` suffix (F5).
6. Add-to-Home-Screen guidance (docs + dismissible in-app hint) and the
   "sign in to keep local data" durability notice (F4 items 1–2).
7. Service-worker decision and, if approved, portal-first trial with
   update toast + workflow kill switch (F4 item 3).

**Phase C — tutorials**
8. `getting-started` / `editor-basics` / `planner-basics` courses in
   `sample/` + idempotent seeding command.
9. Portal "Start here" collection; Settings "Help & tutorials" rows;
   welcome-note links.

**Phase D — auth debt retirement (Casdoor phases 4–5)**
10. Disable remaining legacy auth endpoints (keep the 0.1.111
    email/password fallback only if the owner wants the Casdoor-outage
    escape hatch; otherwise it goes too).
11. Delete dead serializers/templates/models per the survey in
    `integrations/casdoor-migration.md`; refresh that doc's status
    header.

---

## 5. Cross-platform test matrix (manual, until automated)

Run after each Phase A/B change, on the published Pages build:

| Surface | Checks |
| --- | --- |
| iPhone Safari (bookmark) | correct breakpoint (drawer layout), text scale, login via Casdoor, draft survives reload, keyboard does not cover editor caret |
| iPhone Add-to-Home-Screen | standalone window, app name/icon correct, login round-trip returns to the standalone app, notch/`SafeArea` |
| Android Chrome | same as Safari row + install prompt |
| Desktop Chrome/Edge/Firefox | wide layout, second app in another tab does not log out / mutate the first (F1 regression check) |
| Two apps, same browser | log in via editor, open planner: planner must NOT inherit/overwrite editor state (the F1 acceptance test) |
| Offline (after SW decision) | airplane mode relaunch behavior matches the documented expectation |

Smoke-level automation candidates: a Playwright (or `flutter drive`
web) script that loads editor then planner under one origin and asserts
storage isolation; this is the only regression in the matrix that is
both high-value and easy to script.

---

## 6. Decisions needed from the owner

1. **Service worker**: keep disabled, or trial re-enable on portal with
   the update-toast pattern? (Section 2, F4.)
2. **Legacy email/password fallback**: keep as permanent Casdoor-outage
   escape hatch, or retire in Phase D?
3. **IndexedDB attachment store**: keep shared across the three apps
   (content-addressed, probably safe) or namespace it with the rest?
4. **Tutorial authoring language/tone** and whether tutorial courses
   should be auto-subscribed for new users or opt-in from the portal.
