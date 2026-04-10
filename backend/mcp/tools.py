"""MCP tool implementations for Notechondria.

Each tool is a function with signature ``(user, creator, params) -> dict``.
Tools are auto-registered at import time via ``register_tool()``.
"""

from django.db import transaction
from django.db.models import Q
from django.shortcuts import get_object_or_404
from django.utils import timezone
from django.utils.text import slugify

from notes.models import (
    Course,
    Note,
    NoteIndex,
    NoteAttachment,
    PlannerEvent,
)
from notes.services import (
    build_heatmap_payload,
    snapshot_note_version,
)
from notechondria.utils import generate_unique_id

from .protocol import register_tool

# ===================================================================
# Helpers
# ===================================================================


def _note_payload(note):
    """Compact note dict for tool responses."""
    return {
        "id": note.id,
        "uuid": str(note.uuid),
        "title": note.title,
        "description": note.description or "",
        "is_public": note.is_public,
        "editor_mode": note.editor_mode,
        "note_type": note.note_type,
        "course_id": note.course_id_id,
        "last_edit": note.last_edit.isoformat() if note.last_edit else None,
        "date_created": note.date_created.isoformat() if note.date_created else None,
    }


def _note_detail_payload(note):
    payload = _note_payload(note)
    payload["content"] = note.content or ""
    payload["metadata_json"] = note.metadata_json or ""
    blocks = []
    for handle in NoteIndex.objects.filter(note_id=note).select_related("noteblock_id").order_by("index"):
        b = handle.noteblock_id
        blocks.append({
            "id": b.id,
            "block_type": b.block_type,
            "text": b.text or "",
            "args": b.args or "",
        })
    payload["blocks"] = blocks
    return payload


def _course_payload(course):
    return {
        "id": course.id,
        "title": course.title,
        "slug": course.slug,
        "description": course.description or "",
        "icon": course.icon,
        "is_default": course.is_default,
    }


def _event_payload(event):
    def _iso(val):
        if val is None:
            return None
        return val.isoformat() if hasattr(val, "isoformat") else str(val)

    return {
        "id": event.id,
        "title": event.title,
        "event_date": _iso(event.event_date),
        "starts_at": _iso(event.starts_at),
        "ends_at": _iso(event.ends_at),
        "difficulty_weight": event.difficulty_weight,
        "description": event.description or "",
        "course_id": event.course_id_id if event.course_id_id else None,
        "is_completed": event.is_completed,
    }


def _ensure_own_note(user, creator, note_id):
    note = get_object_or_404(
        Note.objects.select_related("course_id", "creator_id"),
        pk=note_id,
        creator_id=creator,
        deleted_at__isnull=True,
    )
    return note


# ===================================================================
# Profile tools
# ===================================================================


register_tool(
    "get_profile",
    "Get the authenticated user's profile and settings.",
    {"type": "object", "properties": {}, "required": []},
    lambda user, creator, params: {
        "username": user.username,
        "email": user.email,
        "first_name": user.first_name,
        "last_name": user.last_name,
        "motto": creator.motto or "",
        "social_link": creator.social_link or "",
        "editor_mode": creator.editor_mode,
        "theme_preset": creator.theme_preset,
        "theme_mode": creator.theme_mode,
    },
)


def _update_profile(user, creator, params):
    dirty = False
    if "motto" in params:
        creator.motto = params["motto"]
        dirty = True
    if "social_link" in params:
        creator.social_link = params["social_link"]
        dirty = True
    if "editor_mode" in params and params["editor_mode"] in ("G", "B", "P"):
        creator.editor_mode = params["editor_mode"]
        dirty = True
    if dirty:
        creator.save()
    user_dirty = False
    if "first_name" in params:
        user.first_name = params["first_name"]
        user_dirty = True
    if "last_name" in params:
        user.last_name = params["last_name"]
        user_dirty = True
    if user_dirty:
        user.save(update_fields=["first_name", "last_name"])
    return {"updated": True}


register_tool(
    "update_profile",
    "Update user profile fields (motto, social_link, editor_mode, first_name, last_name).",
    {
        "type": "object",
        "properties": {
            "motto": {"type": "string", "description": "Short bio (max 100 chars)."},
            "social_link": {"type": "string", "description": "URL to social profile."},
            "editor_mode": {"type": "string", "enum": ["G", "B", "P"], "description": "Editor mode: G=GFM, B=Blocks, P=PlainText."},
            "first_name": {"type": "string"},
            "last_name": {"type": "string"},
        },
        "required": [],
    },
    _update_profile,
)


# ===================================================================
# Notes tools
# ===================================================================


def _list_notes(user, creator, params):
    notes = Note.objects.filter(
        creator_id=creator,
        deleted_at__isnull=True,
    ).select_related("course_id").order_by("-last_edit")
    if "course_id" in params and params["course_id"] is not None:
        notes = notes.filter(course_id_id=params["course_id"])
    if params.get("query"):
        q = params["query"].lower()
        notes = [n for n in notes if q in (n.title or "").lower() or q in (n.content or "").lower()]
    else:
        notes = list(notes)
    limit = min(params.get("limit", 50), 100)
    offset = params.get("offset", 0)
    page = notes[offset: offset + limit]
    return {
        "total": len(notes),
        "offset": offset,
        "limit": limit,
        "notes": [_note_payload(n) for n in page],
    }


register_tool(
    "list_notes",
    "List the user's notes. Optionally filter by course_id or search query.",
    {
        "type": "object",
        "properties": {
            "course_id": {"type": "integer", "description": "Filter by course/category ID."},
            "query": {"type": "string", "description": "Search in title and content."},
            "limit": {"type": "integer", "description": "Max results (default 50, max 100)."},
            "offset": {"type": "integer", "description": "Pagination offset."},
        },
        "required": [],
    },
    _list_notes,
)


def _get_note(user, creator, params):
    note = _ensure_own_note(user, creator, params["note_id"])
    return _note_detail_payload(note)


register_tool(
    "get_note",
    "Get full note content and blocks by note ID.",
    {
        "type": "object",
        "properties": {
            "note_id": {"type": "integer", "description": "Note ID."},
        },
        "required": ["note_id"],
    },
    _get_note,
)


def _create_note(user, creator, params):
    course = None
    if params.get("course_id"):
        course = get_object_or_404(Course, pk=params["course_id"])
    note = Note.objects.create(
        creator_id=creator,
        course_id=course,
        sharing_id=generate_unique_id(Note, "sharing_id"),
        title=params.get("title", "Untitled"),
        description=params.get("description", ""),
        content=params.get("content", ""),
        is_public=params.get("is_public", False),
        editor_mode=params.get("editor_mode", creator.editor_mode),
    )
    return _note_detail_payload(note)


register_tool(
    "create_note",
    "Create a new note. Returns the created note with its ID.",
    {
        "type": "object",
        "properties": {
            "title": {"type": "string", "description": "Note title (max 100 chars)."},
            "content": {"type": "string", "description": "Markdown content."},
            "description": {"type": "string"},
            "course_id": {"type": "integer", "description": "Category ID to file under."},
            "is_public": {"type": "boolean", "description": "Make note publicly visible."},
            "editor_mode": {"type": "string", "enum": ["G", "B", "P"]},
        },
        "required": ["title"],
    },
    _create_note,
)


def _update_note(user, creator, params):
    note = _ensure_own_note(user, creator, params["note_id"])
    if "title" in params:
        note.title = params["title"]
    if "content" in params:
        note.content = params["content"]
    if "description" in params:
        note.description = params["description"]
    if "is_public" in params:
        note.is_public = params["is_public"]
    if "course_id" in params:
        if params["course_id"] is None:
            note.course_id = None
        else:
            note.course_id = get_object_or_404(Course, pk=params["course_id"])
    note.last_edit = timezone.now()
    note.save()
    return _note_detail_payload(note)


register_tool(
    "update_note",
    "Update an existing note's title, content, description, visibility, or category.",
    {
        "type": "object",
        "properties": {
            "note_id": {"type": "integer"},
            "title": {"type": "string"},
            "content": {"type": "string", "description": "Full markdown content (replaces existing)."},
            "description": {"type": "string"},
            "is_public": {"type": "boolean"},
            "course_id": {"type": ["integer", "null"], "description": "Category ID or null to unfile."},
        },
        "required": ["note_id"],
    },
    _update_note,
)


def _delete_note(user, creator, params):
    from notes.models import RecycleBinEntry
    note = _ensure_own_note(user, creator, params["note_id"])
    note.deleted_at = timezone.now()
    note.save(update_fields=["deleted_at"])
    RecycleBinEntry.objects.get_or_create(note_id=note, defaults={"deleted_at": note.deleted_at, "creator_id": creator})
    return {"deleted": True, "note_id": note.id}


register_tool(
    "delete_note",
    "Soft-delete a note (moves to recycle bin).",
    {
        "type": "object",
        "properties": {
            "note_id": {"type": "integer"},
        },
        "required": ["note_id"],
    },
    _delete_note,
)


def _search_notes(user, creator, params):
    query = params.get("query", "").strip()
    if not query:
        return {"error": "query is required"}
    scope = params.get("scope", "personal")
    notes = Note.objects.filter(deleted_at__isnull=True).select_related("course_id", "creator_id__user_id")
    if scope == "all":
        notes = notes.filter(Q(creator_id=creator) | Q(is_public=True))
    else:
        notes = notes.filter(creator_id=creator)
    q = query.lower()
    results = []
    for note in notes:
        title_match = q in (note.title or "").lower()
        content_match = q in (note.content or "").lower()
        if title_match or content_match:
            results.append(_note_payload(note))
        if len(results) >= 50:
            break
    return {"query": query, "count": len(results), "notes": results}


register_tool(
    "search_notes",
    "Search notes by keyword in title and content.",
    {
        "type": "object",
        "properties": {
            "query": {"type": "string", "description": "Search keyword."},
            "scope": {"type": "string", "enum": ["personal", "all"], "description": "personal = own notes only; all = include public notes."},
        },
        "required": ["query"],
    },
    _search_notes,
)


# ===================================================================
# Course tools
# ===================================================================


def _list_courses(user, creator, params):
    courses = Course.objects.select_related("creator_id__user_id").all()
    return {"courses": [_course_payload(c) for c in courses]}


register_tool(
    "list_courses",
    "List all available courses/categories.",
    {"type": "object", "properties": {}, "required": []},
    _list_courses,
)


def _get_course(user, creator, params):
    course = get_object_or_404(Course, pk=params["course_id"])
    payload = _course_payload(course)
    notes = Note.objects.filter(
        course_id=course, deleted_at__isnull=True,
    ).select_related("creator_id__user_id").order_by("-last_edit")[:20]
    payload["notes"] = [_note_payload(n) for n in notes]
    return payload


register_tool(
    "get_course",
    "Get course details and its recent notes.",
    {
        "type": "object",
        "properties": {
            "course_id": {"type": "integer"},
        },
        "required": ["course_id"],
    },
    _get_course,
)


def _create_course(user, creator, params):
    title = params.get("title", "").strip()
    if not title:
        raise ValueError("title is required")
    # Generate unique slug.
    base_slug = slugify(title) or "course"
    slug = base_slug
    counter = 1
    while Course.objects.filter(slug=slug).exists():
        slug = f"{base_slug}-{counter}"
        counter += 1
    course = Course.objects.create(
        creator_id=creator,
        slug=slug,
        title=title,
        description=params.get("description", ""),
        icon=params.get("icon"),
        is_default=False,
    )
    return _course_payload(course)


register_tool(
    "create_course",
    "Create a new course/category.",
    {
        "type": "object",
        "properties": {
            "title": {"type": "string", "description": "Course title (max 120 chars)."},
            "description": {"type": "string"},
            "icon": {"type": ["integer", "null"], "description": "Material icon codepoint."},
        },
        "required": ["title"],
    },
    _create_course,
)


def _update_course(user, creator, params):
    course = get_object_or_404(Course, pk=params["course_id"])
    if course.creator_id_id != creator.id:
        raise PermissionError("You can only edit your own courses.")
    if course.is_default:
        raise ValueError("The default category cannot be edited.")
    if "title" in params:
        course.title = params["title"]
    if "description" in params:
        course.description = params["description"]
    if "icon" in params:
        course.icon = params["icon"]
    course.save()
    return _course_payload(course)


register_tool(
    "update_course",
    "Update a course/category's title, description, or icon.",
    {
        "type": "object",
        "properties": {
            "course_id": {"type": "integer"},
            "title": {"type": "string"},
            "description": {"type": "string"},
            "icon": {"type": ["integer", "null"]},
        },
        "required": ["course_id"],
    },
    _update_course,
)


def _delete_course(user, creator, params):
    course = get_object_or_404(Course, pk=params["course_id"])
    if course.creator_id_id != creator.id:
        raise PermissionError("You can only delete your own courses.")
    if course.is_default:
        raise ValueError("The default category cannot be deleted.")
    default = Course.objects.filter(creator_id=creator, is_default=True).first()
    if default is None:
        raise ValueError("No default category found to move notes into.")
    with transaction.atomic():
        Note.objects.filter(course_id=course).update(course_id=default)
        course.delete()
    return {"deleted": True, "notes_moved_to": default.id}


register_tool(
    "delete_course",
    "Delete a course/category. Notes are moved to the default Inbox.",
    {
        "type": "object",
        "properties": {
            "course_id": {"type": "integer"},
        },
        "required": ["course_id"],
    },
    _delete_course,
)


# ===================================================================
# Activity / Heatmap tools
# ===================================================================


def _get_heatmap(user, creator, params):
    return build_heatmap_payload(creator)


register_tool(
    "get_heatmap",
    "Get the user's activity heatmap (contribution graph data).",
    {"type": "object", "properties": {}, "required": []},
    _get_heatmap,
)


def _get_recent_activity(user, creator, params):
    notes = Note.objects.filter(
        creator_id=creator,
        deleted_at__isnull=True,
    ).order_by("-last_edit")[:10]
    return {"recent_notes": [_note_payload(n) for n in notes]}


register_tool(
    "get_recent_activity",
    "Get the 10 most recently edited notes.",
    {"type": "object", "properties": {}, "required": []},
    _get_recent_activity,
)


# ===================================================================
# Planner event tools
# ===================================================================


def _list_events(user, creator, params):
    events = PlannerEvent.objects.filter(
        creator_id=creator,
    ).order_by("event_date", "title")
    if not params.get("include_completed", False):
        events = events.filter(is_completed=False)
    limit = min(params.get("limit", 50), 200)
    events = list(events[:limit])
    return {"events": [_event_payload(e) for e in events]}


register_tool(
    "list_events",
    "List planner events. By default only incomplete events.",
    {
        "type": "object",
        "properties": {
            "include_completed": {"type": "boolean", "description": "Include completed events."},
            "limit": {"type": "integer", "description": "Max results (default 50, max 200)."},
        },
        "required": [],
    },
    _list_events,
)


def _create_event(user, creator, params):
    event = PlannerEvent.objects.create(
        creator_id=creator,
        title=params.get("title", ""),
        event_date=params.get("event_date"),
        starts_at=params.get("starts_at"),
        ends_at=params.get("ends_at"),
        difficulty_weight=params.get("difficulty_weight", 1),
        description=params.get("description", ""),
        course_id_id=params.get("course_id"),
    )
    return _event_payload(event)


register_tool(
    "create_event",
    "Create a planner event.",
    {
        "type": "object",
        "properties": {
            "title": {"type": "string"},
            "event_date": {"type": "string", "description": "ISO date (YYYY-MM-DD)."},
            "starts_at": {"type": "string", "description": "ISO time (HH:MM:SS), optional."},
            "ends_at": {"type": "string", "description": "ISO time (HH:MM:SS), optional."},
            "difficulty_weight": {"type": "integer", "description": "1-4 weight for heatmap."},
            "description": {"type": "string"},
            "course_id": {"type": "integer", "description": "Associated course."},
        },
        "required": ["title", "event_date"],
    },
    _create_event,
)


def _update_event(user, creator, params):
    event = get_object_or_404(PlannerEvent, pk=params["event_id"], creator_id=creator)
    for field in ("title", "event_date", "starts_at", "ends_at", "difficulty_weight", "description", "is_completed"):
        if field in params:
            setattr(event, field, params[field])
    if "course_id" in params:
        event.course_id_id = params["course_id"]
    if params.get("is_completed") and not event.completed_at:
        event.completed_at = timezone.now()
    event.save()
    return _event_payload(event)


register_tool(
    "update_event",
    "Update a planner event's fields.",
    {
        "type": "object",
        "properties": {
            "event_id": {"type": "integer"},
            "title": {"type": "string"},
            "event_date": {"type": "string"},
            "starts_at": {"type": ["string", "null"]},
            "ends_at": {"type": ["string", "null"]},
            "difficulty_weight": {"type": "integer"},
            "description": {"type": "string"},
            "course_id": {"type": ["integer", "null"]},
            "is_completed": {"type": "boolean"},
        },
        "required": ["event_id"],
    },
    _update_event,
)


# ===================================================================
# Note version tools
# ===================================================================


def _list_note_versions(user, creator, params):
    note = _ensure_own_note(user, creator, params["note_id"])
    versions = note.versions.order_by("-date_created")[:12]
    return {
        "note_id": note.id,
        "versions": [
            {
                "id": v.id,
                "title": v.title,
                "reason": v.reason,
                "date_created": v.date_created.isoformat(),
            }
            for v in versions
        ],
    }


register_tool(
    "list_note_versions",
    "List version history of a note (up to 12 most recent).",
    {
        "type": "object",
        "properties": {
            "note_id": {"type": "integer"},
        },
        "required": ["note_id"],
    },
    _list_note_versions,
)


def _snapshot_note(user, creator, params):
    note = _ensure_own_note(user, creator, params["note_id"])
    version = snapshot_note_version(note, reason=params.get("reason", "mcp"))
    return {"version_id": version.id, "date_created": version.date_created.isoformat()}


register_tool(
    "snapshot_note",
    "Create a manual version snapshot of a note.",
    {
        "type": "object",
        "properties": {
            "note_id": {"type": "integer"},
            "reason": {"type": "string", "description": "Reason label for the snapshot."},
        },
        "required": ["note_id"],
    },
    _snapshot_note,
)


# ===================================================================
# Attachment tools
# ===================================================================


def _list_attachments(user, creator, params):
    note = _ensure_own_note(user, creator, params["note_id"])
    attachments = NoteAttachment.objects.filter(note_id=note).order_by("-date_created")
    return {
        "note_id": note.id,
        "attachments": [
            {
                "id": a.id,
                "original_filename": a.original_filename,
                "file_size": a.file_size,
                "content_type": a.content_type,
                "date_created": a.date_created.isoformat(),
            }
            for a in attachments
        ],
    }


register_tool(
    "list_attachments",
    "List file attachments on a note.",
    {
        "type": "object",
        "properties": {
            "note_id": {"type": "integer"},
        },
        "required": ["note_id"],
    },
    _list_attachments,
)
