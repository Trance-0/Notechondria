"""Agent-facing tool definitions for the standalone MCP server.

Each tool maps an MCP ``tools/call`` to one or more ``/api/v1`` requests
via :class:`BackendClient`. Tool names + input schemas mirror the
in-backend ``backend/mcp/tools.py`` so an agent sees the same surface on
either server.

PARITY RULE: when you add or change a tool here, make the matching
change in ``backend/mcp/tools.py`` (and vice versa). This starter set is
a representative subset; port the rest as Phase 3 of the migration
(`docs/integrations/mcp-cli-migration.md`).
"""

from __future__ import annotations

from typing import Any, Callable, Dict, List

from .client import BackendClient

# A tool: name -> {description, inputSchema, handler}. The handler takes
# (client, arguments) and returns a JSON-serializable result.
Handler = Callable[[BackendClient, dict], Any]

_STR = {"type": "string"}
_INT = {"type": "integer"}
_BOOL = {"type": "boolean"}


def _schema(properties: dict, required: List[str] | None = None) -> dict:
    return {
        "type": "object",
        "properties": properties,
        "required": required or [],
    }


# --- handlers ---------------------------------------------------------

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


def _list_events(client: BackendClient, args: dict) -> Any:
    return client.get("planner-events/")


def _create_event(client: BackendClient, args: dict) -> Any:
    body = {"title": args["title"], "event_date": args["event_date"]}
    for key in ("description", "difficulty_weight", "course_id"):
        if key in args and args[key] is not None:
            body[key] = args[key]
    return client.post("planner-events/", body)


# --- registry ---------------------------------------------------------

TOOLS: List[dict] = [
    {
        "name": "get_profile",
        "description": "Get the signed-in user's profile and MCP skill.md.",
        "inputSchema": _schema({}),
        "handler": _get_profile,
    },
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
        "name": "create_note",
        "description": "Create a note. Title required; content/course "
                       "optional.",
        "inputSchema": _schema({
            "title": _STR, "content": _STR, "course_id": _INT,
            "is_public": _BOOL, "editor_mode": _STR,
        }, ["title"]),
        "handler": _create_note,
    },
    {
        "name": "update_note",
        "description": "Update a note's fields.",
        "inputSchema": _schema({
            "note_id": _INT, "title": _STR, "content": _STR,
            "description": _STR, "is_public": _BOOL, "course_id": _INT,
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
        "name": "list_events",
        "description": "List planner events (deadlines).",
        "inputSchema": _schema({}),
        "handler": _list_events,
    },
    {
        "name": "create_event",
        "description": "Create a planner event with a due date (ISO-8601).",
        "inputSchema": _schema({
            "title": _STR, "event_date": _STR, "description": _STR,
            "difficulty_weight": _INT, "course_id": _INT,
        }, ["title", "event_date"]),
        "handler": _create_event,
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
