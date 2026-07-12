"""Agent-facing tool definitions for the standalone MCP server.

Each tool maps an MCP ``tools/call`` to one or more ``/api/v1`` requests
via :class:`BackendClient`. Tool names + input schemas mirror the
in-backend ``backend/mcp/tools.py`` so an agent sees the same surface on
either server.

PARITY RULE: when you add or change a tool here, make the matching
change in ``backend/mcp/tools.py`` (and vice versa). As of 0.1.146 this
file is at full parity — all 41 backend tools are implemented over REST.
"""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Any, Callable, Dict, List

from .client import BackendClient

# A tool: name -> {description, inputSchema, handler}. The handler takes
# (client, arguments) and returns a JSON-serializable result.
Handler = Callable[[BackendClient, dict], Any]

_STR = {"type": "string"}
_INT = {"type": "integer"}
_BOOL = {"type": "boolean"}
_INT_NULL = {"type": ["integer", "null"]}


def _schema(properties: dict, required: List[str] | None = None) -> dict:
    return {
        "type": "object",
        "properties": properties,
        "required": required or [],
    }


def _body(args: dict, keys) -> dict:
    """Pick the given keys from ``args`` when present (non-None) into a
    request body. ``None`` is kept for keys that are explicitly nullable
    server-side (callers pass those via ``keys`` tuples that allow it)."""
    out: Dict[str, Any] = {}
    for key in keys:
        if key in args:
            out[key] = args[key]
    return out


# --- profile ----------------------------------------------------------

def _get_profile(client: BackendClient, args: dict) -> Any:
    data = client.get("settings/")
    if isinstance(data, dict):
        # Trim to the agent-relevant fields; never leak api_key material.
        return {
            k: data.get(k)
            for k in (
                "username", "email", "display_name", "motto",
                "editor_mode", "theme_preset", "theme_mode",
                "mcp_skill_md",
            )
        }
    return data


def _update_profile(client: BackendClient, args: dict) -> Any:
    return client.patch("settings/", _body(
        args, ("motto", "social_link", "editor_mode",
               "first_name", "last_name")))


# --- notes ------------------------------------------------------------

def _list_notes(client: BackendClient, args: dict) -> Any:
    params: Dict[str, Any] = {
        "limit": args.get("limit", 20),
        "offset": args.get("offset", 0),
    }
    if args.get("course_id") is not None:
        params["course_id"] = args["course_id"]
    if args.get("q"):
        params["q"] = args["q"]
    return client.get("notes/", params=params)


def _get_note(client: BackendClient, args: dict) -> Any:
    return client.get(f"notes/{int(args['note_id'])}/")


def _get_note_by_uuid(client: BackendClient, args: dict) -> Any:
    return client.get(f"notes/uuid/{args['uuid']}/")


def _search_notes(client: BackendClient, args: dict) -> Any:
    params: Dict[str, Any] = {"q": args["query"], "scope": args.get("scope", "personal")}
    return client.get("notes/", params=params)


def _create_note(client: BackendClient, args: dict) -> Any:
    body = {"title": args.get("title", "Untitled")}
    for key in ("content", "course_id", "is_public", "editor_mode",
                "description"):
        if key in args and args[key] is not None:
            body[key] = args[key]
    return client.post("notes/", body)


def _update_note(client: BackendClient, args: dict) -> Any:
    body = {}
    for key in ("title", "content", "description", "is_public",
                "course_id", "editor_mode"):
        if key in args and args[key] is not None:
            body[key] = args[key]
    return client.patch(f"notes/{int(args['note_id'])}/", body)


def _delete_note(client: BackendClient, args: dict) -> Any:
    client.delete(f"notes/{int(args['note_id'])}/")
    return {"deleted": True, "note_id": int(args["note_id"])}


# --- note versions ----------------------------------------------------

def _list_note_versions(client: BackendClient, args: dict) -> Any:
    return client.get(f"notes/{int(args['note_id'])}/history/")


def _snapshot_note(client: BackendClient, args: dict) -> Any:
    body = {}
    if args.get("reason"):
        body["reason"] = args["reason"]
    return client.post(f"notes/{int(args['note_id'])}/snapshot/", body)


def _restore_note_version(client: BackendClient, args: dict) -> Any:
    return client.post(
        f"notes/{int(args['note_id'])}/restore/{int(args['version_id'])}/")


# --- attachments ------------------------------------------------------

def _list_attachments(client: BackendClient, args: dict) -> Any:
    return client.get(f"notes/{int(args['note_id'])}/attachments/")


def _delete_attachment(client: BackendClient, args: dict) -> Any:
    client.delete(
        f"notes/{int(args['note_id'])}/attachments/"
        f"{int(args['attachment_id'])}/")
    return {"deleted": True, "attachment_id": int(args["attachment_id"])}


# --- recycle bin ------------------------------------------------------

def _list_deleted_notes(client: BackendClient, args: dict) -> Any:
    return client.get("notes/deleted/")


def _restore_deleted_note(client: BackendClient, args: dict) -> Any:
    return client.post(f"notes/{int(args['note_id'])}/restore/")


def _empty_recycle_bin(client: BackendClient, args: dict) -> Any:
    return client.delete("notes/deleted/empty/") or {"emptied": True}


# --- courses ----------------------------------------------------------

def _list_courses(client: BackendClient, args: dict) -> Any:
    return client.get("courses/")


def _get_course(client: BackendClient, args: dict) -> Any:
    return client.get(f"courses/{int(args['course_id'])}/")


def _create_course(client: BackendClient, args: dict) -> Any:
    body = {"title": args["title"]}
    for key in ("description", "icon"):
        if key in args and args[key] is not None:
            body[key] = args[key]
    return client.post("courses/", body)


def _update_course(client: BackendClient, args: dict) -> Any:
    body = {}
    for key in ("title", "description", "icon"):
        if key in args:
            body[key] = args[key]
    return client.patch(f"courses/{int(args['course_id'])}/", body)


def _delete_course(client: BackendClient, args: dict) -> Any:
    client.delete(f"courses/{int(args['course_id'])}/")
    return {"deleted": True, "course_id": int(args["course_id"])}


def _get_course_git(client: BackendClient, args: dict) -> Any:
    return client.get(f"courses/{int(args['course_id'])}/git/")


def _import_course_git(client: BackendClient, args: dict) -> Any:
    return client.post(f"courses/{int(args['course_id'])}/git/import/", {})


def _sync_course_git(client: BackendClient, args: dict) -> Any:
    return client.post(f"courses/{int(args['course_id'])}/git/sync/", {})


def _set_course_git(client: BackendClient, args: dict) -> Any:
    course_id = int(args["course_id"])
    if args.get("unlink"):
        return client.delete(f"courses/{course_id}/git/")
    body = {}
    for key in ("repo", "branch", "sync_enabled", "sync_timeout_minutes"):
        if key in args and args[key] is not None:
            body[key] = args[key]
    return client.put(f"courses/{course_id}/git/", body)


def _github_app_status(client: BackendClient, args: dict) -> Any:
    return client.get("integrations/github/status/")


def _connect_github_app(client: BackendClient, args: dict) -> Any:
    body = {"installation_id": args["installation_id"]}
    for key in ("account_login", "repo_full_name", "repo_default_branch"):
        if key in args and args[key] is not None:
            body[key] = args[key]
    return client.post("integrations/github/callback/", body)


def _list_github_repos(client: BackendClient, args: dict) -> Any:
    return client.get("integrations/github/repos/")


def _list_course_notes(client: BackendClient, args: dict) -> Any:
    return client.get(f"courses/{int(args['course_id'])}/notes/")


def _reorder_courses(client: BackendClient, args: dict) -> Any:
    return client.post("courses/reorder/", {"course_ids": args["course_ids"]})


def _subscribe_course(client: BackendClient, args: dict) -> Any:
    return client.post(f"courses/{int(args['course_id'])}/subscribe/")


def _unsubscribe_course(client: BackendClient, args: dict) -> Any:
    client.delete(f"courses/{int(args['course_id'])}/subscribe/")
    return {"unsubscribed": True, "course_id": int(args["course_id"])}


# --- activity / heatmap ----------------------------------------------

def _get_heatmap(client: BackendClient, args: dict) -> Any:
    return client.get("heatmap/")


def _get_recent_activity(client: BackendClient, args: dict) -> Any:
    return client.get("activity/")


def _get_activity(client: BackendClient, args: dict) -> Any:
    data = client.get("activity/")
    limit = args.get("limit")
    if isinstance(data, list) and isinstance(limit, int) and limit > 0:
        return data[:limit]
    return data


def _get_activity_week(client: BackendClient, args: dict) -> Any:
    params = {}
    if args.get("start_date"):
        params["start_date"] = args["start_date"]
    if args.get("days"):
        params["days"] = args["days"]
    return client.get("activity/week/", params=params)


# --- planner events ---------------------------------------------------

def _list_events(client: BackendClient, args: dict) -> Any:
    params: Dict[str, Any] = {}
    if args.get("include_completed"):
        params["include_completed"] = "1"
    if args.get("limit") is not None:
        params["limit"] = args["limit"]
    return client.get("planner-events/", params=params)


def _create_event(client: BackendClient, args: dict) -> Any:
    body = {"title": args["title"], "event_date": args["event_date"]}
    for key in ("starts_at", "ends_at", "description",
                "difficulty_weight", "course_id", "recurrence_freq",
                "recurrence_interval", "recurrence_end_date", "recurrence_count"):
        if key in args and args[key] is not None:
            body[key] = args[key]
    return client.post("planner-events/", body)


def _update_event(client: BackendClient, args: dict) -> Any:
    body = {}
    for key in ("title", "event_date", "starts_at", "ends_at",
                "difficulty_weight", "description", "course_id",
                "is_completed", "recurrence_freq", "recurrence_interval",
                "recurrence_end_date", "recurrence_count"):
        if key in args:
            body[key] = args[key]
    return client.patch(f"planner-events/{int(args['event_id'])}/", body)


def _delete_event(client: BackendClient, args: dict) -> Any:
    client.delete(f"planner-events/{int(args['event_id'])}/")
    return {"deleted": True, "event_id": int(args["event_id"])}


# --- note sessions ----------------------------------------------------

def _list_note_sessions(client: BackendClient, args: dict) -> Any:
    params: Dict[str, Any] = {}
    if args.get("note_id") is not None:
        params["note_id"] = args["note_id"]
    if args.get("limit") is not None:
        params["limit"] = args["limit"]
    return client.get("note-sessions/", params=params)


def _create_note_session(client: BackendClient, args: dict) -> Any:
    body = {"note_id": int(args["note_id"])}
    for key in ("title", "summary"):
        if key in args and args[key] is not None:
            body[key] = args[key]
    return client.post("note-sessions/", body)


def _end_note_session(client: BackendClient, args: dict) -> Any:
    # The REST PATCH only sets ``ended_at`` if supplied (unlike the
    # in-backend tool, which stamps "now" server-side), so default it to
    # the current UTC time when the caller doesn't pass one.
    body: Dict[str, Any] = {
        "ended_at": args.get("ended_at")
        or datetime.now(timezone.utc).isoformat()
    }
    for key in ("title", "summary"):
        if key in args and args[key] is not None:
            body[key] = args[key]
    return client.patch(f"note-sessions/{int(args['session_id'])}/", body)


# --- calendar feeds ---------------------------------------------------

def _list_calendar_feeds(client: BackendClient, args: dict) -> Any:
    return client.get("calendar-feeds/")


def _create_calendar_feed(client: BackendClient, args: dict) -> Any:
    body = {"title": args["title"]}
    for key in ("source_kind", "source_url", "raw_ical",
                "is_enabled", "course_id"):
        if key in args and args[key] is not None:
            body[key] = args[key]
    return client.post("calendar-feeds/", body)


def _update_calendar_feed(client: BackendClient, args: dict) -> Any:
    body = {}
    for key in ("title", "source_kind", "source_url", "raw_ical",
                "is_enabled", "course_id"):
        if key in args:
            body[key] = args[key]
    return client.patch(f"calendar-feeds/{int(args['feed_id'])}/", body)


def _delete_calendar_feed(client: BackendClient, args: dict) -> Any:
    client.delete(f"calendar-feeds/{int(args['feed_id'])}/")
    return {"deleted": True, "feed_id": int(args["feed_id"])}


# --- registry ---------------------------------------------------------

TOOLS: List[dict] = [
    # profile
    {
        "name": "get_profile",
        "description": "Get the signed-in user's profile and MCP skill.md.",
        "inputSchema": _schema({}),
        "handler": _get_profile,
    },
    {
        "name": "update_profile",
        "description": "Update profile fields (motto, social_link, "
                       "editor_mode, first_name, last_name).",
        "inputSchema": _schema({
            "motto": _STR, "social_link": _STR,
            "editor_mode": {"type": "string", "enum": ["G", "B", "P"]},
            "first_name": _STR, "last_name": _STR,
        }),
        "handler": _update_profile,
    },
    # notes
    {
        "name": "list_notes",
        "description": "List notes (paginated); optional course filter + "
                       "full-text query.",
        "inputSchema": _schema({
            "course_id": _INT, "q": _STR, "limit": _INT, "offset": _INT,
        }),
        "handler": _list_notes,
    },
    {
        "name": "get_note",
        "description": "Get a single note with full content.",
        "inputSchema": _schema({"note_id": _INT}, ["note_id"]),
        "handler": _get_note,
    },
    {
        "name": "get_note_by_uuid",
        "description": "Fetch a note by its UUID (deep-link / share-link "
                       "resolution). Non-owners only see public notes.",
        "inputSchema": _schema({"uuid": _STR}, ["uuid"]),
        "handler": _get_note_by_uuid,
    },
    {
        "name": "create_note",
        "description": "Create a note. Title required; content/course "
                       "optional.",
        "inputSchema": _schema({
            "title": _STR, "content": _STR, "description": _STR,
            "course_id": _INT, "is_public": _BOOL, "editor_mode": _STR,
        }, ["title"]),
        "handler": _create_note,
    },
    {
        "name": "update_note",
        "description": "Update a note's fields.",
        "inputSchema": _schema({
            "note_id": _INT, "title": _STR, "content": _STR,
            "description": _STR, "is_public": _BOOL, "course_id": _INT_NULL,
        }, ["note_id"]),
        "handler": _update_note,
    },
    {
        "name": "delete_note",
        "description": "Soft-delete a note (moves to the recycle bin; "
                       "recoverable via restore_deleted_note until the "
                       "bin is emptied).",
        "inputSchema": _schema({"note_id": _INT}, ["note_id"]),
        "handler": _delete_note,
    },
    {
        "name": "search_notes",
        "description": "Search notes by keyword. scope='personal' (own) "
                       "or 'all' (own + public).",
        "inputSchema": _schema({
            "query": _STR, "scope": {"type": "string",
                                     "enum": ["personal", "all"]},
        }, ["query"]),
        "handler": _search_notes,
    },
    # note versions
    {
        "name": "list_note_versions",
        "description": "List a note's version history (most recent first).",
        "inputSchema": _schema({"note_id": _INT}, ["note_id"]),
        "handler": _list_note_versions,
    },
    {
        "name": "snapshot_note",
        "description": "Create a manual version snapshot of a note.",
        "inputSchema": _schema({"note_id": _INT, "reason": _STR},
                               ["note_id"]),
        "handler": _snapshot_note,
    },
    {
        "name": "restore_note_version",
        "description": "Restore a note to a previous version (snapshots "
                       "current state first).",
        "inputSchema": _schema({"note_id": _INT, "version_id": _INT},
                               ["note_id", "version_id"]),
        "handler": _restore_note_version,
    },
    # attachments
    {
        "name": "list_attachments",
        "description": "List file attachments on a note.",
        "inputSchema": _schema({"note_id": _INT}, ["note_id"]),
        "handler": _list_attachments,
    },
    {
        "name": "delete_attachment",
        "description": "Delete an attachment from a note.",
        "inputSchema": _schema({"note_id": _INT, "attachment_id": _INT},
                               ["note_id", "attachment_id"]),
        "handler": _delete_attachment,
    },
    # recycle bin
    {
        "name": "list_deleted_notes",
        "description": "List notes currently in the recycle bin.",
        "inputSchema": _schema({}),
        "handler": _list_deleted_notes,
    },
    {
        "name": "restore_deleted_note",
        "description": "Restore a note from the recycle bin.",
        "inputSchema": _schema({"note_id": _INT}, ["note_id"]),
        "handler": _restore_deleted_note,
    },
    {
        "name": "empty_recycle_bin",
        "description": "PERMANENTLY delete every note in the recycle "
                       "bin. Irreversible — only call when the user "
                       "explicitly confirms emptying the bin.",
        "inputSchema": _schema({}),
        "handler": _empty_recycle_bin,
    },
    # courses
    {
        "name": "list_courses",
        "description": "List the user's courses / categories.",
        "inputSchema": _schema({}),
        "handler": _list_courses,
    },
    {
        "name": "get_course",
        "description": "Get a course with its recent notes.",
        "inputSchema": _schema({"course_id": _INT}, ["course_id"]),
        "handler": _get_course,
    },
    {
        "name": "create_course",
        "description": "Create a course / category.",
        "inputSchema": _schema({
            "title": _STR, "description": _STR, "icon": _INT,
        }, ["title"]),
        "handler": _create_course,
    },
    {
        "name": "update_course",
        "description": "Update a course's title, description, or icon.",
        "inputSchema": _schema({
            "course_id": _INT, "title": _STR, "description": _STR,
            "icon": _INT_NULL,
        }, ["course_id"]),
        "handler": _update_course,
    },
    {
        "name": "delete_course",
        "description": "Delete a course. Its notes fall to the "
                       "uncategorized bucket (course_id=NULL).",
        "inputSchema": _schema({"course_id": _INT}, ["course_id"]),
        "handler": _delete_course,
    },
    {
        "name": "get_course_git",
        "description": "Get a course's GitHub binding (repo owner/name, "
                       "branch, lazy-sync toggle + timeout, last-sync "
                       "state). Owner-only.",
        "inputSchema": _schema({"course_id": _INT}, ["course_id"]),
        "handler": _get_course_git,
    },
    {
        "name": "set_course_git",
        "description": "Bind (or re-point / tune) a course's GitHub repo, "
                       "or unlink it. The backend stays the source of "
                       "truth; a bound course lazily commits/pushes after "
                       "sync_timeout_minutes of no edits. Pass unlink=true "
                       "to clear the binding. Owner-only.",
        "inputSchema": _schema({
            "course_id": _INT,
            "repo": {"type": "string", "description": "GitHub full name 'owner/name'. Empty string clears the repo."},
            "branch": {"type": "string", "description": "Target branch (default 'main')."},
            "sync_enabled": _BOOL,
            "sync_timeout_minutes": {"type": "integer", "description": "Idle minutes before an auto-sync fires (1-1440, default 5)."},
            "unlink": {"type": "boolean", "description": "If true, unlink the repo and disable sync."},
        }, ["course_id"]),
        "handler": _set_course_git,
    },
    {
        "name": "import_course_git",
        "description": "Pull the bound GitHub repo's markdown into this "
                       "course's notes via the course-repo adapter "
                       "(idempotent; notes matched by repo path). Course "
                       "must be bound and the owner must have the GitHub "
                       "App installed. Owner-only.",
        "inputSchema": _schema({"course_id": _INT}, ["course_id"]),
        "handler": _import_course_git,
    },
    {
        "name": "sync_course_git",
        "description": "Push this course's notes to its bound GitHub repo "
                       "now (markdown only; note frontmatter preserved). "
                       "Backend is the source of truth. Owner-only.",
        "inputSchema": _schema({"course_id": _INT}, ["course_id"]),
        "handler": _sync_course_git,
    },
    {
        "name": "github_app_status",
        "description": "Show whether this account has the Notechondria "
                       "GitHub App installed (the App token backs course "
                       "import/sync). Returns connected, the install_url, "
                       "and the linked installation id / account.",
        "inputSchema": _schema({}),
        "handler": _github_app_status,
    },
    {
        "name": "connect_github_app",
        "description": "Link a GitHub App installation to this account by "
                       "its installation id (from the GitHub redirect after "
                       "installing the App on a repo/org). Idempotent. This "
                       "is how you 'bind the app to a repo' before "
                       "import/sync.",
        "inputSchema": _schema({
            "installation_id": {"type": "string", "description": "Installation id from the GitHub App install redirect."},
            "account_login": {"type": "string", "description": "Owner login the App was installed on (optional)."},
            "repo_full_name": {"type": "string", "description": "Default profile-sync repo 'owner/name' (optional)."},
            "repo_default_branch": {"type": "string", "description": "Default branch (default 'main')."},
        }, ["installation_id"]),
        "handler": _connect_github_app,
    },
    {
        "name": "list_github_repos",
        "description": "List the repositories the linked GitHub App "
                       "installation can access (full_name, default_branch, "
                       "private). Use to confirm a repo is reachable before "
                       "set_course_git. Requires connect_github_app first.",
        "inputSchema": _schema({}),
        "handler": _list_github_repos,
    },
    {
        "name": "list_course_notes",
        "description": "List notes inside a course (public-only for "
                       "non-owners).",
        "inputSchema": _schema({"course_id": _INT}, ["course_id"]),
        "handler": _list_course_notes,
    },
    {
        "name": "reorder_courses",
        "description": "Rewrite the sidebar sort order for the user's "
                       "courses.",
        "inputSchema": _schema({
            "course_ids": {"type": "array", "items": _INT},
        }, ["course_ids"]),
        "handler": _reorder_courses,
    },
    {
        "name": "subscribe_course",
        "description": "Subscribe the user to a course (adds it to their "
                       "sidebar).",
        "inputSchema": _schema({"course_id": _INT}, ["course_id"]),
        "handler": _subscribe_course,
    },
    {
        "name": "unsubscribe_course",
        "description": "Remove an active course subscription.",
        "inputSchema": _schema({"course_id": _INT}, ["course_id"]),
        "handler": _unsubscribe_course,
    },
    # activity / heatmap
    {
        "name": "get_heatmap",
        "description": "Get the user's activity heatmap (contribution "
                       "graph data).",
        "inputSchema": _schema({}),
        "handler": _get_heatmap,
    },
    {
        "name": "get_recent_activity",
        "description": "Get the most recently edited notes (up to 10).",
        "inputSchema": _schema({}),
        "handler": _get_recent_activity,
    },
    {
        "name": "get_activity",
        "description": "List recently edited notes; optional client-side "
                       "limit.",
        "inputSchema": _schema({
            "limit": {"type": "integer", "minimum": 1, "maximum": 50},
        }),
        "handler": _get_activity,
    },
    {
        "name": "get_activity_week",
        "description": "The user's calendar window: per-day `events` "
                       "(planner events with kind 'plan', calendar-feed "
                       "entries with kind 'feed', work sessions) plus a "
                       "`deadlines` list of open tasks sorted by "
                       "urgency_score (completed ones inside the window "
                       "stay, at the bottom). This is the tool for 'what "
                       "is on my plate' questions and for a weekly "
                       "review. Same payload the app's Activity screen "
                       "renders.",
        "inputSchema": _schema({
            "start_date": {"type": "string", "description": "Window start, ISO date (YYYY-MM-DD). Defaults to today."},
            "days": {"type": "integer", "enum": [3, 7, 30], "description": "Window length in days (the app's 3-day / week / month ranges). Default 7; other values fall back to 7."},
        }),
        "handler": _get_activity_week,
    },
    # planner events
    {
        "name": "list_events",
        "description": "List the user's planner events (tasks/deadlines/"
                       "blocks) ordered by event_date. Only incomplete "
                       "(open) events by default. List before creating "
                       "in bulk so you do not duplicate existing tasks.",
        "inputSchema": _schema({
            "include_completed": {"type": "boolean", "description": "Also include completed events. Default false."},
            "limit": {"type": "integer", "description": "Max results (default 50, max 200)."},
        }),
        "handler": _list_events,
    },
    {
        "name": "create_event",
        "description": "Create a planner event (a task, deadline, or "
                       "study block). For a plain task/deadline pass only "
                       "`title` + `event_date`; the server assigns a "
                       "default noon one-hour window so it renders on the "
                       "calendar grid. Pass `starts_at`/`ends_at` only "
                       "for a real timed block. New events are "
                       "incomplete; they appear in the app's todo list "
                       "ordered by urgency and on the week calendar.",
        "inputSchema": _schema({
            "title": {"type": "string", "description": "Short task/event title (max 120 chars)."},
            "event_date": {"type": "string", "description": "Due/occurrence date, ISO date (YYYY-MM-DD)."},
            "starts_at": {"type": "string", "description": "Full ISO 8601 datetime (e.g. 2026-07-12T14:00:00Z), NOT a bare clock time. Optional; omit for an all-day task."},
            "ends_at": {"type": "string", "description": "Full ISO 8601 datetime. Optional; defaults to starts_at + 1 hour, and is forced after starts_at."},
            "difficulty_weight": {"type": "integer", "description": "Effort weight 1 (light) to 4 (heavy); feeds the activity heatmap. Default 1."},
            "description": {"type": "string", "description": "Optional detail shown in the event dialog (max 255 chars)."},
            "course_id": {"type": "integer", "description": "Optional owning course id (see list_courses)."},
            "recurrence_freq": {"type": "string", "enum": ["N", "W", "M", "Y"], "description": "Repeat rule: N=one-time (default), W=weekly, M=monthly, Y=yearly. event_date is the first occurrence."},
            "recurrence_interval": {"type": "integer", "description": "Repeat every N periods (default 1). Ignored when recurrence_freq=N."},
            "recurrence_end_date": {"type": ["string", "null"], "description": "ISO date the series stops on (inclusive). Optional."},
            "recurrence_count": {"type": ["integer", "null"], "description": "Total number of occurrences including the first. Optional; use this OR recurrence_end_date."},
        }, ["title", "event_date"]),
        "handler": _create_event,
    },
    {
        "name": "update_event",
        "description": "Update a planner event. To complete a task set "
                       "`is_completed: true` (completed tasks stay "
                       "visible, struck through — prefer this over "
                       "delete_event); `is_completed: false` reopens it. "
                       "To reschedule a timed event set `starts_at` (and "
                       "`ends_at`) — the stored time window wins over "
                       "`event_date`, which is snapped to starts_at's "
                       "day.",
        "inputSchema": _schema({
            "event_id": {"type": "integer", "description": "Event id from list_events / get_activity_week."},
            "title": _STR,
            "event_date": {"type": "string", "description": "ISO date (YYYY-MM-DD). Snapped to starts_at's day after save — set starts_at to actually move a timed event."},
            "starts_at": {"type": ["string", "null"], "description": "Full ISO 8601 datetime (e.g. 2026-07-12T14:00:00Z)."},
            "ends_at": {"type": ["string", "null"], "description": "Full ISO 8601 datetime; forced after starts_at."},
            "difficulty_weight": {"type": "integer", "description": "Effort weight 1-4."},
            "description": _STR,
            "course_id": {"type": ["integer", "null"], "description": "Owning course id, or null to detach."},
            "is_completed": {"type": "boolean", "description": "true completes (stamps completed_at), false reopens (clears it)."},
            "recurrence_freq": {"type": "string", "enum": ["N", "W", "M", "Y"], "description": "Repeat rule: N=one-time, W=weekly, M=monthly, Y=yearly."},
            "recurrence_interval": {"type": "integer", "description": "Repeat every N periods."},
            "recurrence_end_date": {"type": ["string", "null"], "description": "ISO date the series stops on (inclusive), or null to clear."},
            "recurrence_count": {"type": ["integer", "null"], "description": "Total occurrences including the first, or null to clear."},
        }, ["event_id"]),
        "handler": _update_event,
    },
    {
        "name": "delete_event",
        "description": "Permanently delete a planner event (no recycle "
                       "bin). To finish a task keep it and set "
                       "update_event `is_completed: true` instead; delete "
                       "only when the user asks to remove it outright.",
        "inputSchema": _schema({"event_id": _INT}, ["event_id"]),
        "handler": _delete_event,
    },
    # note sessions
    {
        "name": "list_note_sessions",
        "description": "List note activity sessions, optionally filtered "
                       "by note.",
        "inputSchema": _schema({
            "note_id": _INT,
            "limit": {"type": "integer", "minimum": 1, "maximum": 200},
        }),
        "handler": _list_note_sessions,
    },
    {
        "name": "create_note_session",
        "description": "Start a note activity session (started_at = now).",
        "inputSchema": _schema({
            "note_id": _INT, "title": _STR, "summary": _STR,
        }, ["note_id"]),
        "handler": _create_note_session,
    },
    {
        "name": "end_note_session",
        "description": "Finish a note activity session (sets ended_at).",
        "inputSchema": _schema({
            "session_id": _INT, "title": _STR, "summary": _STR,
            "ended_at": _STR,
        }, ["session_id"]),
        "handler": _end_note_session,
    },
    # calendar feeds
    {
        "name": "list_calendar_feeds",
        "description": "List the user's calendar feeds (iCal imports + "
                       "subscribed URLs).",
        "inputSchema": _schema({}),
        "handler": _list_calendar_feeds,
    },
    {
        "name": "create_calendar_feed",
        "description": "Create a calendar feed shown in the week "
                       "calendar. source_kind='I' for a one-shot iCal "
                       "paste (supply raw_ical); 'S' for a subscribed "
                       "URL that is refetched (supply source_url — use "
                       "the calendar's secret/private iCal address; a "
                       "'public' Google Calendar page URL returns HTML "
                       "and will not parse).",
        "inputSchema": _schema({
            "title": _STR,
            "source_kind": {"type": "string", "enum": ["I", "S"]},
            "source_url": _STR, "raw_ical": _STR, "is_enabled": _BOOL,
            "course_id": _INT_NULL,
        }, ["title"]),
        "handler": _create_calendar_feed,
    },
    {
        "name": "update_calendar_feed",
        "description": "Update a calendar feed's fields.",
        "inputSchema": _schema({
            "feed_id": _INT, "title": _STR,
            "source_kind": {"type": "string", "enum": ["I", "S"]},
            "source_url": _STR, "raw_ical": _STR, "is_enabled": _BOOL,
            "course_id": _INT_NULL,
        }, ["feed_id"]),
        "handler": _update_calendar_feed,
    },
    {
        "name": "delete_calendar_feed",
        "description": "Delete a calendar feed.",
        "inputSchema": _schema({"feed_id": _INT}, ["feed_id"]),
        "handler": _delete_calendar_feed,
    },
]

_BY_NAME: Dict[str, dict] = {tool["name"]: tool for tool in TOOLS}


def tool_specs() -> List[dict]:
    """The ``tools/list`` payload: name + description + inputSchema."""
    return [
        {
            "name": t["name"],
            "description": t["description"],
            "inputSchema": t["inputSchema"],
        }
        for t in TOOLS
    ]


def call_tool(client: BackendClient, name: str, arguments: dict) -> Any:
    """Dispatch a ``tools/call`` to its handler. Raises KeyError for an
    unknown tool name (the caller maps it to a JSON-RPC error)."""
    tool = _BY_NAME[name]
    return tool["handler"](client, arguments or {})
