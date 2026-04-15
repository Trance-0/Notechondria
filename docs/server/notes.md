# `notes` app

Path: [`backend/notes/`](../../backend/notes/).
Responsibility: notes, courses (folders), planner events, calendar
feeds, recycle bin, attachments, activity heatmap, version history.

Index: [`server/backend.md`](backend.md).
Related: [`creators`](creators.md), [`mcp`](mcp.md),
[storage model](../development/storage_model.md).

## Models (`notes/models.py`)

| Model | Key fields | Role |
| --- | --- | --- |
| `Course` | `creator_id` (FK), `title`, `description`, `is_default`, `is_public`, `slug`, `cover_image`, `icon`, `sort_order`, `client_course_id` | A folder/category. `is_default=True` flags the pinned "Inbox" — undeletable, every user has exactly one. |
| `CourseMedia` | `course_id` (FK), `file`, `kind` | Cover/banner uploads attached to a course. |
| `CourseSubscription` | `creator_id`, `course_id`, `is_active`, `subscribed_at` | Many-to-many with payload: which creators are subscribed to which (public) courses. |
| `CourseOperationLog` | `creator_id`, `course_id`, `op`, `payload`, `at` | Audit trail for course mutations. |
| `Note` | `course_id` (FK), `creator_id` (FK), `title`, `slug`, `uuid`, `is_public`, `visibility`, `last_edit`, `deleted_at`, `parent_note_id` (FK, nullable) | The unit of content. Reachable by `<int:note_id>` or `<uuid:note_uuid>`. `parent_note_id` lets a note be a comment on another. |
| `NoteBlock` | `block_type` (TEXT/TITLE/IMAGE/CODE/...), `text`, `args` (JSON), `image`, `file` | Atomic content blob inside a note. Free-floating (multiple notes can render the same block via `NoteIndex`). |
| `NoteIndex` | `note_id` (FK), `noteblock_id` (FK), `index` | Ordering table: which blocks belong to which note, in what order. The same `NoteBlock` can appear in multiple notes (transclusion). |
| `NoteAttachment` | `note_id` (FK), `file`, `original_filename`, `file_size`, `content_type`, `date_created` | File uploads on a note. Storage path via `note_attachment_path(instance, filename)` → `user_upload/user_<id>/notes/note_<id>/<filename>`. |
| `NoteVersion` | `note_id` (FK), `snapshot` (JSON), `created_at`, `creator_id` | Frozen snapshots for rollback. |
| `RecycleBinEntry` | `note_id` (FK), `creator_id`, `deleted_at`, `restorable_until` | Soft-delete tracker. |
| `NoteActivitySession` | `note_id`, `creator_id`, `started_at`, `ended_at`, `keystrokes` | Per-edit-session attribution → feeds `HeatmapActivity`. |
| `HeatmapActivity` | `creator_id`, `date`, `count`, `weight` | Per-day rollup for the contribution heatmap. |
| `PlannerEvent` | `creator_id`, `title`, `event_date`, `is_completed`, `importance`, `source_feed_id` (FK, nullable) | A scheduled task or imported calendar event. |
| `CalendarFeed` | `creator_id`, `source_url`, `display_name`, `last_fetched_at`, `is_active` | Subscribed iCal URL. `source_url` is normalized via `normalize_calendar_url(...)` on create. |
| `Tag`, `ValidationRecord` | various | Classification + audit. Not yet exposed via the API surface. |

`NoteBlockTypeChoices` enumerates allowed `block_type` values:
TEXT, TITLE, IMAGE, CODE, etc. — see the model file for the full
list.

## Services (`notes/services.py`)

Pure helpers. No request-cycle binding.

- `normalize_calendar_url(url)` — rewrites Google Calendar share
  URLs to canonical `.ics`. Handles `embed?src=<id>` and
  `?cid=<base64>` (with repad). Direct `.ics` and non-Google URLs
  pass through unchanged.
- `read_calendar_feed(url)` — fetches with `User-Agent:
  Notechondria/0.1 (+calendar-feed)` and `Accept:
  text/calendar, */*;q=0.1` headers. Returns the raw text body.
- `parse_ical_datetime(value)` — best-effort RFC-5545 datetime
  parser used by both the import preview and the periodic feed
  refresh.
- `seed_inbox_and_welcome_note(creator) -> Optional[Note]` —
  idempotent. Creates the default `Inbox` Course (if missing) and
  a welcome Note with TITLE + TEXT blocks (if Inbox is empty).
  Late-imports `django.utils.text.slugify` and
  `notechondria.utils.generate_unique_id` to avoid circular
  imports. Called by `VerifyEmailApiView.post` and
  `_get_or_create_oauth_user` in [`creators/api.py`](creators.md).

## API surface (`notes/api.py`)

Mounted under `/api/v1/...` by
[`api_urls.py`](../../backend/notechondria/api_urls.py).

### Front page + health

| Method | Path | View | Auth |
| --- | --- | --- | --- |
| GET | `/api/v1/health/` | `FrontPageApiView.health` | AllowAny |
| GET | `/api/v1/front-page/` | `FrontPageApiView.get` | AllowAny (gates extra payload on auth) |

Example `front-page` response (anonymous viewer):

```json
{
  "default_course": {"id": 1, "title": "Vibe Coding 101", "...": "..."},
  "carousel_courses": [
    {"id": 1, "title": "Vibe Coding 101", "is_subscribed": false, "...": "..."},
    {"id": 2, "title": "Meaning of Work in Age of AI", "...": "..."}
  ],
  "recent_notes": [
    {"id": 28, "title": "First note", "course_id": 1, "last_edit": "2026-04-12T22:36:27Z"}
  ],
  "recommended_notes": ["..."],
  "collections": ["..."]
}
```

When the request is authenticated the response also includes
`heatmap` and `upcoming_events` keys.

### Courses

| Method | Path | View |
| --- | --- | --- |
| GET / POST | `/api/v1/courses/` | `CourseListApiView` |
| POST | `/api/v1/courses/reorder/` | `CourseReorderApiView` |
| GET / PATCH / DELETE | `/api/v1/courses/<int:course_id>/` | `CourseDetailApiView` |
| GET | `/api/v1/courses/<int:course_id>/notes/` | `CourseNotesApiView` |
| POST / DELETE | `/api/v1/courses/<int:course_id>/subscribe/` | `CourseSubscribeApiView` |
| POST | `/api/v1/courses/<int:course_id>/open/` | `CourseOpenApiView` |
| POST | `/api/v1/admin/template-courses/restore/` | `TemplateCourseRestoreApiView` (admin) |

Example `GET /api/v1/courses/`:

```json
[
  {
    "id": 1,
    "title": "Vibe Coding 101",
    "is_default": false,
    "is_public": true,
    "subscriber_count": 4,
    "is_subscribed": true,
    "icon": "code",
    "sort_order": 1
  },
  {"id": 2, "title": "Inbox", "is_default": true, "is_public": false, "...": "..."}
]
```

DELETE on a course where `is_default=True` returns 400 — Inbox
is undeletable. The frontend hides the delete affordance for
default courses (editor 0.1.x change).

### Notes

| Method | Path | View |
| --- | --- | --- |
| GET / POST | `/api/v1/notes/` | `NoteListCreateApiView` |
| GET | `/api/v1/notes/deleted/` | `DeletedNoteListApiView` |
| POST | `/api/v1/notes/deleted/empty/` | `DeletedNoteEmptyApiView` |
| GET | `/api/v1/notes/uuid/<uuid:note_uuid>/` | `NoteByUuidApiView` |
| GET / PATCH / DELETE | `/api/v1/notes/<int:note_id>/` | `NoteDetailApiView` |
| POST | `/api/v1/notes/<int:note_id>/restore/` | `DeletedNoteRestoreApiView` |
| GET | `/api/v1/notes/<int:note_id>/history/` | `NoteHistoryApiView` |
| POST | `/api/v1/notes/<int:note_id>/snapshot/` | `NoteSnapshotApiView` |
| POST | `/api/v1/notes/<int:note_id>/restore/<int:version_id>/` | `NoteRestoreApiView` |
| GET / POST | `/api/v1/notes/<int:note_id>/blocks/` | `NoteBlocksApiView` |
| POST | `/api/v1/notes/<int:note_id>/reorder/` | `ReorderBlocksApiView` |
| GET / PATCH / DELETE | `/api/v1/blocks/<int:block_id>/` | `SingleBlockApiView` |
| GET / POST | `/api/v1/notes/<int:note_id>/attachments/` | `NoteAttachmentApiView` |
| GET / DELETE | `/api/v1/notes/<int:note_id>/attachments/<int:attachment_id>/` | `NoteAttachmentDetailApiView` |

Example `GET /api/v1/notes/27/`:

```json
{
  "id": 27,
  "uuid": "1f8d6c4a-...",
  "title": "First note",
  "course_id": 1,
  "is_public": true,
  "visibility": "public",
  "last_edit": "2026-04-12T22:36:27Z",
  "deleted_at": null,
  "blocks": [
    {"id": 401, "block_type": "TITLE", "text": "First note"},
    {"id": 402, "block_type": "TEXT",  "text": "Welcome to Notechondria."}
  ]
}
```

### Activity, heatmap, calendar feeds, planner events

| Method | Path | View |
| --- | --- | --- |
| GET / POST | `/api/v1/activity/` | `ActivityApiView` |
| GET | `/api/v1/activity/week/` | `ActivityWeekApiView` |
| GET | `/api/v1/heatmap/` | `HeatmapApiView` |
| GET / POST | `/api/v1/calendar-feeds/` | `CalendarFeedListCreateApiView` (POST runs `normalize_calendar_url`) |
| GET / PATCH / DELETE | `/api/v1/calendar-feeds/<int:feed_id>/` | `CalendarFeedDetailApiView` |
| GET / POST | `/api/v1/planner-events/` | `PlannerEventListCreateApiView` |
| GET / PATCH / DELETE | `/api/v1/planner-events/<int:event_id>/` | `PlannerEventDetailApiView` |
| GET / POST | `/api/v1/note-sessions/` | `NoteSessionListCreateApiView` |
| GET / PATCH / DELETE | `/api/v1/note-sessions/<int:session_id>/` | `NoteSessionDetailApiView` |

Example `GET /api/v1/heatmap/`:

```json
{
  "weeks": [
    {"week_start": "2026-03-30", "days": [
      {"date": "2026-03-30", "count": 4, "weight": 0.6},
      {"date": "2026-03-31", "count": 0, "weight": 0.0}
    ]},
    "..."
  ]
}
```

Example `POST /api/v1/calendar-feeds/`:

```json
{
  "source_url": "https://calendar.google.com/calendar/embed?src=abc%40group.calendar.google.com",
  "display_name": "Class schedule"
}
```

The backend rewrites `source_url` to
`https://calendar.google.com/calendar/ical/abc%40group.calendar.google.com/public/basic.ics`
before saving.

## Management commands

`notes/management/commands/bootstrap_platform.py`:

- Idempotent. Run on every container start by
  [`backend/entrypoint.sh`](../../backend/entrypoint.sh).
- Creates the admin user from `DJANGO_SUPERUSER_*` env.
- Creates the demo `CodeX` user.
- Updates three sample courses from
  [`sample/`](../../sample/): `Vibe Coding 101`,
  `Meaning of Work in Age of AI`, `Self-identity and Expression in
  Modern Arts`. Each course's notes are recreated each run.
- `resolve_codex_path()` searches a candidate list (now
  `is_file()`-guarded after the AGENTS.md submodule reanchor) to
  find the seed file containing the agent rules; the result
  becomes the body of one of the demo notes.

## Frontend cross-refs

- The "Learner" view in
  [editor](../client/editor_app.md) /
  [planner](../client/planner_app.md) /
  [portal](../client/portal_app.md) is built on
  `/api/v1/courses/`, `/api/v1/courses/<id>/notes/`, and
  `/api/v1/notes/<id>/`.
- Calendar subscribe in
  [planner_app](../client/planner_app.md#calendar-subscription-flow)
  → `/api/v1/calendar-feeds/`.
- Welcome note seeding fires on first sign-in via
  [`creators` app](creators.md) → `seed_inbox_and_welcome_note`.
