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
    return client.get("activity/week/", params=params)


# --- planner events ---------------------------------------------------

def _list_events(client: BackendClient, args: dict) -> Any:
    return client.get("planner-events/")


def _create_event(client: BackendClient, args: dict) -> Any:
    body = {"title": args["title"], "event_date": args["event_date"]}
    for key in ("starts_at", "ends_at", "description",
                "difficulty_weight", "course_id"):
        if key in args and args[key] is not None:
            body[key] = args[key]
    return client.post("planner-events/", body)


def _update_event(client: BackendClient, args: dict) -> Any:
    body = {}
    for key in ("title", "event_date", "starts_at", "ends_at",
                "difficulty_weight", "description", "course_id",
                "is_completed"):
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
        "description": "Soft-delete a note (moves it to the recycle bin).",
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
        "description": "Permanently delete every note in the recycle bin.",
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
        "description": "Week-view planner payload (sessions, events, "
                       "deadlines) for the 7-day window from start_date.",
        "inputSchema": _schema({"start_date": _STR}),
        "handler": _get_activity_week,
    },
    # planner events
    {
        "name": "list_events",
        "description": "List planner events (incomplete deadlines).",
        "inputSchema": _schema({}),
        "handler": _list_events,
    },
    {
        "name": "create_event",
        "description": "Create a planner event with a due date (ISO-8601).",
        "inputSchema": _schema({
            "title": _STR, "event_date": _STR, "starts_at": _STR,
            "ends_at": _STR, "description": _STR,
            "difficulty_weight": _INT, "course_id": _INT,
        }, ["title", "event_date"]),
        "handler": _create_event,
    },
    {
        "name": "update_event",
        "description": "Update a planner event's fields.",
        "inputSchema": _schema({
            "event_id": _INT, "title": _STR, "event_date": _STR,
            "starts_at": {"type": ["string", "null"]},
            "ends_at": {"type": ["string", "null"]},
            "difficulty_weight": _INT, "description": _STR,
            "course_id": _INT_NULL, "is_completed": _BOOL,
        }, ["event_id"]),
        "handler": _update_event,
    },
    {
        "name": "delete_event",
        "description": "Delete a planner event.",
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
        "description": "Create a calendar feed. source_kind='I' (paste "
                       "raw_ical) or 'S' (subscribe to source_url).",
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
