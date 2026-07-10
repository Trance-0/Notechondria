"""Baseline MCP server instructions.

Returned in the ``initialize`` result's ``instructions`` field (the
user's per-account ``skill.md`` is appended after this when present),
so any spec-compliant agent host reads a complete operating manual for
the app on connect.

Parity rule: keep this text byte-identical with
``backend/mcp/instructions.py`` (the in-backend server) — same
contract as the tool specs.
"""

BASE_INSTRUCTIONS = """\
Notechondria is a note-taking + study-planning workspace. You are
connected as one user via their personal API key; every tool operates
on that user's data only. Use these tools to do real work for the
user: capture and organize notes, plan tasks and deadlines, and review
activity.

## Data model (what the tools operate on)

- **Note** — the unit of writing. Belongs to one course (category);
  has markdown `content`, structured blocks, attachments, version
  history, a recycle bin, and an `is_public` flag. Notes have both an
  integer `id` (use in tools) and a `uuid` (only for share links —
  `get_note_by_uuid`).
- **Course** — a category/folder for notes (also used as an academic
  course). Every user has a default course; deleting a course moves
  its notes there, it never deletes notes.
- **Planner event** — a task/deadline/study block. Fields:
  `event_date` (ISO date), optional `starts_at`/`ends_at` (full ISO
  8601 datetimes, e.g. `2026-07-12T14:00:00Z` — NOT bare clock
  times), `difficulty_weight` 1-4 (heatmap intensity), optional
  `course_id`, `is_completed`. An event without times renders as a
  noon one-hour window; the server normalizes stored windows the same
  way the app does. Completing an event keeps it visible
  (struck-through) in the app's todo list — complete, don't delete,
  unless the user asks.
- **Note activity session** — a timed work interval on a note
  (`create_note_session` … `end_note_session`), feeding the activity
  views.
- **Calendar feed** — an external iCal source shown in the week
  calendar: `source_kind` `'S'` = subscribed URL (refetched; use the
  calendar's *secret* iCal address — a "public" Google URL that
  returns HTML will not parse), `'I'` = one-shot iCal paste.
- **Heatmap** — contribution-graph data derived from note edits and
  event weights.

## Common workflows

- **Capture a note**: `list_courses` → `create_note` (course_id
  optional; defaults to the default course) → `update_note` to edit.
  Search before creating to avoid duplicates (`search_notes`).
- **Create a task for the user**: `create_event` with `title` +
  `event_date`; add `starts_at`/`ends_at` only for a real timed block.
- **Weekly review**: `get_activity_week` (grid + urgency-sorted
  `deadlines`), `get_heatmap`, `get_recent_activity`.
- **Complete / reschedule a task**: `update_event` with
  `is_completed: true`, or a new `event_date`/`starts_at`.
- **Recover data**: `list_note_versions` + `restore_note_version` for
  edits; `list_deleted_notes` + `restore_deleted_note` for deletions.
  `empty_recycle_bin` is PERMANENT — confirm with the user first.

## Batch work

Each `tools/call` is one request. For bulk jobs (importing a
syllabus of deadlines, creating many notes), prefer the standalone
CLI server (`pip install notechondria-mcp` or `cli/` in the repo):
`notechondria-mcp batch` reads newline-delimited JSON
(`{"tool": ..., "arguments": ...}` per line) from a file or stdin and
executes sequentially, printing one JSON result per line and
continuing past per-item errors. The stdio server also accepts
pipelined JSON-RPC lines. Keep batches idempotent-friendly: list
first, then create only what is missing.
"""
