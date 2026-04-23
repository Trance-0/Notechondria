# Planner app (`frontend/planner_app/`)

Course / learner / activity planner. One of three standalone Flutter
apps that share the same Notechondria backend.

Related: [editor_app](editor_app.md), [portal_app](portal_app.md),
[server/backend.md](../server/backend.md).

## Role

- Course-oriented view: list courses the user owns or has subscribed
  to; open a course and see its notes grouped into expandable folders
  (introduced in 0.1.18, Learner view).
- Activity view: planner events + calendar feed imports. Supports
  RFC-5545 iCalendar (`.ics`) and zip bundles, confirmed through a
  preview dialog (event count, first/last dates, first five samples)
  before commit (0.1.18).
- Calendar subscription: paste a Google Calendar share URL or an
  iCal secret address; the backend normalizes it (see
  [`normalize_calendar_url`](../server/backend.md#notes-services) in
  `notes/services.py`) and re-fetches periodically with a Notechondria
  User-Agent.
- Settings surface covers theme, API base URL (with handshake check),
  deadline-ordering weights (time vs. importance), and offline
  preferences.

## Shape

Self-contained Flutter workspace with its own `pubspec.yaml`, `lib/`,
`web/`, `windows/`, `test/`, `Dockerfile`, `docker-compose.yml`, and
nginx template. Navigation includes four modules: `Front`, `Course`,
`Activity`, `Settings` (app_shell indexes them 0/1/2/3).

### Library layout

`frontend/planner_app/lib/` is a single Dart library (`part of
notechondria_frontend`) with the same core/components/modules split as
the editor app:

| File | Responsibility |
| --- | --- |
| `main.dart` | Library declaration, launches `NotechondriaApp` with `visibleIndices` for the planner. |
| `app_shell.dart` | Root widget + state. Contains the Settings-save flow that now calls `verifyHandshake` before switching API URL. |
| `core/client.dart` | Same `HttpNotechondriaClient` pattern as the editor. Contains `verifyHandshake`. |
| `core/helpers.dart` | `_defaultApiBaseUrl` with the same compile-time override. |
| `core/local_store.dart` | Same local-store shape; persists planner-specific settings (deadline weights). |
| `components/` | Shared UI + splash. |
| `modules/activity.dart` | Activity view: ics/zip import dialog, calendar subscription UI, heatmap, event list. |
| `modules/learner.dart` | Learner view: course-folder grouped note list. |
| `modules/course.dart` | Course detail view. |
| `modules/settings.dart` | Planner Settings (4-module sidebar, deadline weights). |

### Calendar subscription flow

1. User pastes a URL into the Activity view's subscribe dialog.
2. Frontend POSTs to `/api/v1/calendar-feeds/` with `source_url`.
3. Backend's `CalendarFeedListCreateApiView.post` calls
   `normalize_calendar_url(url)` in `notes/services.py`:
   - Google Calendar `embed?src=<id>` → canonical `.ics`
   - Google Calendar `?cid=<base64>` → canonical `.ics` (with repad)
   - Direct `.ics` and non-Google URLs pass through unchanged
4. Background fetch uses `urllib.request.Request` with
   `User-Agent: Notechondria/0.1 (+calendar-feed)`.

## API client contract

Same `HttpNotechondriaClient` surface as the editor app — see
[editor_app.md#api-client-contract](editor_app.md#api-client-contract).
Planner-specific calls:

- `getPlannerEvents / createPlannerEvent / updatePlannerEvent`
- `getCalendarFeeds / createCalendarFeed / deleteCalendarFeed`
- `importIcsZip(bytes)` — staging endpoint that returns a preview
  payload before the confirm dialog commits events.

## Build and deploy

- Local: `flutter run -d chrome` from `frontend/planner_app/`.
- Smoke test: `flutter test test/smoke_test.dart -r compact`.
- GitHub Pages: same `frontend-pages.yml` workflow, base-href
  `/Notechondria/planner/`.
- Self-hosted Docker: app-local compose joins
  `NOTECHONDRIA_SHARED_NETWORK`; nginx routes `/api/v1` to the
  backend alias.

## Known drift

See [index.md §6](../index.md#6-open-work--caution-list). Planner-specific:

- Planner Settings feature parity with editor Settings (API key
  rotation, change-password with identity code, config download)
  was partially delivered — the sidebar entry is live, the full
  surface is deferred.
