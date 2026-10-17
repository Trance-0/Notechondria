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
  before commit (0.1.18). Since 0.1.199 the import also works offline;
  see [Offline calendar import](#offline-calendar-import-01199).
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
| `core/local_store.dart` | Same local-store shape; persists planner-specific settings (deadline weights) and, since 0.1.199, calendars imported on this device (`notechondria.planner.local_calendar_feeds`). |
| `core/calendar.dart` | Calendar feed actions: iCal import (cloud or local), URL subscribe (cloud only), refresh, toggle, delete. |
| `core/local_calendar.dart` | Since 0.1.199: stores imported calendars locally and places their events on the activity week (`_withLocalCalendarEvents`). |
| `core/bootstrap.dart` | Cold start. Since 0.1.199 each step logs `Planner.Startup/<step>` records with durations (see the shared package's `startupStep`). |
| `components/` | Shared UI + splash. |
| `modules/activity.dart` | Activity view: heatmap, event list, and the "Calendar this week" list in the vertical board. |
| `modules/activity_calendar.dart` | ics/zip import review dialog and the calendar subscription dialog (errors render inline and copyable). |
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

### Offline calendar import (0.1.199)

Import iCal no longer needs a cloud session or a reachable backend.

1. The file (`.ics`, or the first `.ics` inside a `.zip`) is read and parsed
   on the device by the shared `parseIcalEvents`
   (`notechondria_shared/lib/src/utils/ical_events.dart`). The review
   dialog shows the same count that is imported. A file with no readable
   `DTSTART` stays in the dialog with an inline, copyable message:
   `Calendar not imported: Planner.Sync.Calendar/parse — "<file>" has no
   VEVENT entries with a readable DTSTART.`
2. Signed in and online, the import is unchanged: POST to
   `/api/v1/calendar-feeds/` (`Planner.Sync.Calendar/push`).
3. Signed out, in offline mode, or when that upload fails, the calendar is
   saved on the device instead: `Calendar saved on this device:
   Planner.Sync.Calendar/import — "<title>" (<n> events) is stored locally
   because <reason>; it is not uploaded to the cloud.` After a failed
   upload, `<reason>` is `the cloud upload failed (<cause>)` and the
   SnackBar is shown as a warning (10s instead of 6s); the dialog still
   closes because the calendar was imported.
4. Local calendars live in `notechondria.planner.local_calendar_feeds`
   (their own bucket, so "Clear cached data" and a signed-in reload keep
   them). Each record uses the local-archive `calendar_feeds.json` shape
   with `is_local_feed: true`, `source_file`, and the parsed `events`
   (`uid`, `title`, `description`, `starts_at`, `ends_at`, `all_day`).
   Re-importing a calendar with the same title replaces the earlier local
   copy. "Clear local data" removes them; `.nchron` export and restore carry
   them.
5. Their events appear on the activity week (`kind: 'calendar'`) and in the
   "Calendar this week" list of the vertical board, which the signed-out
   view always uses. The offline week now follows week navigation.

Limitations: RRULE is not expanded (a recurring event imports its first
occurrence), `TZID=` times are read as device-local time, and local
calendars are not uploaded after a later sign-in (tracked in
[`../TODO.md`](../TODO.md#planner)).

**Subscribe by URL stays cloud-only.** The server downloads the feed
(`read_calendar_feed` in `backend/notes/services.py`); a browser cannot
fetch another site's `.ics` cross-origin, and the project does not proxy it.
Signed out or offline, the subscribe dialog says so inline:
`Calendar not subscribed: Planner.Sync.Calendar/subscribe — subscribing by
URL needs a cloud session because the server downloads the feed; ... Sign
in, or download the .ics file and use Import iCal, which works offline.`

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
