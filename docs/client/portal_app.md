# Portal app (`frontend/portal_app/`)

Orchestration shell: public front page + module-level access to all
five Notechondria modules. One of three standalone Flutter apps that
share the same backend.

Related: [editor_app](editor_app.md), [planner_app](planner_app.md),
[server/backend.md](../server/backend.md).

## Role

- Public-facing landing page (no login required): recommended/public
  courses carousel, contribution heatmap, recent-notes discovery list.
  Powered by the backend's
  [`FrontPageApiView`](../server/backend.md#notes-api) at
  `GET /api/v1/front-page/` (anonymous-friendly).
- Full five-module sidebar since 0.1.18: `Front page`, `Learner`,
  `Course`, `Activity`, `Settings`. Unlike editor/planner (which limit
  `visibleIndices`), the portal surfaces all five so a signed-in user
  can reach any feature without swapping apps.
- Pages project-site root redirects here:
  `https://trance-0.github.io/Notechondria/` → `/Notechondria/portal/`
  via the meta-refresh index shipped by
  [`.github/workflows/frontend-pages.yml`](../../.github/workflows/frontend-pages.yml).

## Shape

Self-contained Flutter workspace with its own `pubspec.yaml`, `lib/`,
`web/`, `windows/`, `test/`, `Dockerfile`, `docker-compose.yml`, and
nginx template.

### Library layout

Same `part of notechondria_frontend` pattern as the other two apps:

| File | Responsibility |
| --- | --- |
| `main.dart` | Launches `NotechondriaApp` with `visibleIndices: [0,1,2,3,4]` — all five modules on. |
| `app_shell.dart` | Root widget + state. Same Settings-save flow + handshake guard as the other apps, plus a compact AppBar title that mirrors the current module's `_titles` entry. |
| `core/client.dart` | `HttpNotechondriaClient` with `verifyHandshake`. |
| `core/helpers.dart` | Compile-time API base default. |
| `core/local_store.dart` | Same SharedPreferences shape. |
| `components/splash_screen.dart` | Krebs-cycle splash with `widget.appTitle` overlay. |
| `modules/front.dart` | Public front page: carousel of public courses, heatmap (if logged in), recent public notes. |
| `modules/learner.dart` | Learner view (embeds editor's shape). |
| `modules/course.dart` | Course view (embeds planner's shape). |
| `modules/activity.dart` | Activity view (embeds planner's shape). |
| `modules/settings.dart` | Portal Settings (partial parity with editor — see "Known drift"). |

### Smoke test

`test/smoke_test.dart` boots `app.main()` and asserts `find.text('Front
page')` is present (matches both the compact AppBar title and the
navigation destination label after the 0.1.18 rewrite).

## API client contract

Same `HttpNotechondriaClient` contract as the other two apps — see
[editor_app.md#api-client-contract](editor_app.md#api-client-contract).
Portal-specific calls:

- `getFrontPage()` → the combined payload served by the backend
  `FrontPageApiView`: `{default_course, carousel_courses,
  recent_notes, recommended_notes, collections, heatmap?,
  upcoming_events?}`.
- Auth flow is shared (login, register, OAuth, verify, rotate key,
  change email/password).

## Build and deploy

- Local: `flutter run -d chrome` from `frontend/portal_app/`.
- Smoke test: `flutter test test/smoke_test.dart -r compact`.
- GitHub Pages: same `frontend-pages.yml` workflow, base-href
  `/Notechondria/portal/`. Root `/Notechondria/` meta-refreshes here.
- Self-hosted Docker: app-local compose routes `location = /` through
  the gateway nginx `return 302 /portal/`.

## Known drift

See [index.md §6](../index.md#6-open-work--caution-list). Portal-specific:

- Portal Settings feature parity with editor Settings is partial. The
  sidebar visibility and core surfaces exist; full API-key rotation,
  change-password with identity code, change-email, and config
  download still need porting from
  [`editor_app/lib/modules/settings.dart`](../../frontend/editor_app/lib/modules/settings.dart)
  into
  [`portal_app/lib/modules/settings.dart`](../../frontend/portal_app/lib/modules/settings.dart)
  — tracked as deferred in
  [versions/0.1.18.md](../versions/0.1.18.md).
