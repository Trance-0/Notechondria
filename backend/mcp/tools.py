"""MCP tool implementations for Notechondria.

Each tool is a function with signature ``(user, creator, params) -> dict``.
Tools are auto-registered at import time via ``register_tool()``.
"""

from django.db import transaction
from django.db.models import Q
from django.shortcuts import get_object_or_404
from django.utils import timezone
from django.utils.text import slugify

from courses.models import (
    Course,
    CourseOperationTypeChoices,
    CourseSubscription,
)
from notes.models import (
    Note,
    NoteActivitySession,
    NoteIndex,
    NoteAttachment,
    NoteVersion,
    RecycleBinEntry,
)
from planner.models import CalendarFeed, PlannerEvent
from notes.services import (
    build_heatmap_payload,
    calendar_week_payload,
    normalize_calendar_url,
    note_session_payload,
    restore_note_version,
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
    "Soft-delete a note (moves to the recycle bin; recoverable via "
    "restore_deleted_note until the bin is emptied).",
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
    # 0.1.120: notes whose category is deleted fall to ``course_id IS
    # NULL`` automatically because ``Note.course_id`` is
    # ``on_delete=SET_NULL``. The SPA's synthetic uncategorized bucket
    # picks them up — no manual reassignment to a "default" course.
    course.delete()
    return {"deleted": True}


register_tool(
    "delete_course",
    "Delete a course/category. Notes inside are moved to the user's "
    "uncategorized bucket (course_id=NULL) automatically.",
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
    "List the user's planner events (tasks/deadlines/blocks) ordered by "
    "event_date. Only incomplete (open) events by default. List before "
    "creating in bulk so you do not duplicate existing tasks.",
    {
        "type": "object",
        "properties": {
            "include_completed": {"type": "boolean", "description": "Also include completed events. Default false."},
            "limit": {"type": "integer", "description": "Max results (default 50, max 200)."},
        },
        "required": [],
    },
    _list_events,
)


def _create_event(user, creator, params):
    from notes.api import normalize_planner_event_window

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
    # Same stored-window contract as the REST create (a bare-date event
    # gets a noon one-hour window; event_date snaps to starts_at's day).
    event.refresh_from_db()
    normalize_planner_event_window(event)
    return _event_payload(event)


register_tool(
    "create_event",
    "Create a planner event (a task, deadline, or study block). For a "
    "plain task/deadline pass only `title` + `event_date`; the server "
    "assigns a default noon one-hour window so it renders on the "
    "calendar grid. Pass `starts_at`/`ends_at` only for a real timed "
    "block. New events are incomplete; they appear in the app's todo "
    "list ordered by urgency and on the week calendar.",
    {
        "type": "object",
        "properties": {
            "title": {"type": "string", "description": "Short task/event title (max 120 chars)."},
            "event_date": {"type": "string", "description": "Due/occurrence date, ISO date (YYYY-MM-DD)."},
            "starts_at": {"type": "string", "description": "Full ISO 8601 datetime (e.g. 2026-07-12T14:00:00Z), NOT a bare clock time. Optional; omit for an all-day task."},
            "ends_at": {"type": "string", "description": "Full ISO 8601 datetime. Optional; defaults to starts_at + 1 hour, and is forced after starts_at."},
            "difficulty_weight": {"type": "integer", "description": "Effort weight 1 (light) to 4 (heavy); feeds the activity heatmap. Default 1."},
            "description": {"type": "string", "description": "Optional detail shown in the event dialog (max 255 chars)."},
            "course_id": {"type": "integer", "description": "Optional owning course id (see list_courses)."},
        },
        "required": ["title", "event_date"],
    },
    _create_event,
)


def _update_event(user, creator, params):
    from notes.api import normalize_planner_event_window

    event = get_object_or_404(PlannerEvent, pk=params["event_id"], creator_id=creator)
    for field in ("title", "event_date", "starts_at", "ends_at", "difficulty_weight", "description", "is_completed"):
        if field in params:
            setattr(event, field, params[field])
    if "course_id" in params:
        event.course_id_id = params["course_id"]
    if params.get("is_completed") and not event.completed_at:
        event.completed_at = timezone.now()
    if params.get("is_completed") is False:
        event.completed_at = None
    event.save()
    # Same stored-window contract as the REST PATCH.
    event.refresh_from_db()
    normalize_planner_event_window(event)
    return _event_payload(event)


register_tool(
    "update_event",
    "Update a planner event. To complete a task set `is_completed: "
    "true` (completed tasks stay visible, struck through — prefer this "
    "over delete_event); `is_completed: false` reopens it. To "
    "reschedule a timed event set `starts_at` (and `ends_at`) — the "
    "stored time window wins over `event_date`, which is snapped to "
    "starts_at's day.",
    {
        "type": "object",
        "properties": {
            "event_id": {"type": "integer", "description": "Event id from list_events / get_activity_week."},
            "title": {"type": "string"},
            "event_date": {"type": "string", "description": "ISO date (YYYY-MM-DD). Snapped to starts_at's day after save — set starts_at to actually move a timed event."},
            "starts_at": {"type": ["string", "null"], "description": "Full ISO 8601 datetime (e.g. 2026-07-12T14:00:00Z)."},
            "ends_at": {"type": ["string", "null"], "description": "Full ISO 8601 datetime; forced after starts_at."},
            "difficulty_weight": {"type": "integer", "description": "Effort weight 1-4."},
            "description": {"type": "string"},
            "course_id": {"type": ["integer", "null"], "description": "Owning course id, or null to detach."},
            "is_completed": {"type": "boolean", "description": "true completes (stamps completed_at), false reopens (clears it)."},
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


def _delete_attachment(user, creator, params):
    note = _ensure_own_note(user, creator, params["note_id"])
    attachment = get_object_or_404(
        NoteAttachment, pk=params["attachment_id"], note_id=note
    )
    attachment.file.delete(save=False)
    attachment.delete()
    return {"deleted": True, "attachment_id": params["attachment_id"]}


register_tool(
    "delete_attachment",
    "Delete an attachment from a note.",
    {
        "type": "object",
        "properties": {
            "note_id": {"type": "integer"},
            "attachment_id": {"type": "integer"},
        },
        "required": ["note_id", "attachment_id"],
    },
    _delete_attachment,
)


# ===================================================================
# Recycle bin tools
# ===================================================================


def _list_deleted_notes(user, creator, params):
    entries = (
        RecycleBinEntry.objects.filter(
            creator_id=creator,
            note_id__deleted_at__isnull=False,
        )
        .select_related("note_id__course_id")
    )
    return {
        "deleted_notes": [
            {
                "id": entry.note_id.id,
                "title": entry.note_id.title,
                "description": entry.note_id.description or "",
                "course_id": entry.note_id.course_id_id,
                "deleted_at": entry.deleted_at.isoformat(),
            }
            for entry in entries
        ]
    }


register_tool(
    "list_deleted_notes",
    "List notes currently in the recycle bin.",
    {"type": "object", "properties": {}, "required": []},
    _list_deleted_notes,
)


def _restore_deleted_note(user, creator, params):
    note = get_object_or_404(
        Note,
        pk=params["note_id"],
        creator_id=creator,
        deleted_at__isnull=False,
    )
    note.deleted_at = None
    note.save(update_fields=["deleted_at", "last_edit"])
    RecycleBinEntry.objects.filter(creator_id=creator, note_id=note).delete()
    return _note_detail_payload(note)


register_tool(
    "restore_deleted_note",
    "Restore a note from the recycle bin.",
    {
        "type": "object",
        "properties": {
            "note_id": {"type": "integer"},
        },
        "required": ["note_id"],
    },
    _restore_deleted_note,
)


def _empty_recycle_bin(user, creator, params):
    entries = RecycleBinEntry.objects.filter(
        creator_id=creator,
        note_id__deleted_at__isnull=False,
    )
    note_ids = list(entries.values_list("note_id_id", flat=True))
    count = len(note_ids)
    entries.delete()
    Note.objects.filter(id__in=note_ids).delete()
    return {"deleted_count": count}


register_tool(
    "empty_recycle_bin",
    "PERMANENTLY delete every note in the recycle bin. Irreversible — "
    "only call when the user explicitly confirms emptying the bin.",
    {"type": "object", "properties": {}, "required": []},
    _empty_recycle_bin,
)


# ===================================================================
# Note UUID lookup + version restore
# ===================================================================


def _get_note_by_uuid(user, creator, params):
    note = get_object_or_404(
        Note.objects.select_related("course_id", "creator_id"),
        uuid=params["uuid"],
        deleted_at__isnull=True,
    )
    # Match REST `NoteByUuidApiView`: owner gets full detail; non-owner
    # only when the note is explicitly flagged ``is_public=True``.
    is_owner = note.creator_id_id == creator.id
    if not is_owner:
        if not note.is_public:
            raise PermissionError(
                "Note is not public and is owned by another creator."
            )
    return _note_detail_payload(note)


register_tool(
    "get_note_by_uuid",
    "Fetch a note by its UUID. Used for deep-link / share-link resolution. "
    "Returns full detail for the owner; for other users only when the "
    "note is flagged ``is_public=True``.",
    {
        "type": "object",
        "properties": {
            "uuid": {"type": "string", "description": "Note UUID."},
        },
        "required": ["uuid"],
    },
    _get_note_by_uuid,
)


def _restore_note_version(user, creator, params):
    note = _ensure_own_note(user, creator, params["note_id"])
    version = get_object_or_404(
        NoteVersion, pk=params["version_id"], note_id=note
    )
    snapshot_note_version(note, reason="before_restore_mcp")
    restore_note_version(note, version)
    note.refresh_from_db()
    return _note_detail_payload(note)


register_tool(
    "restore_note_version",
    "Restore a note to a previous version. Automatically snapshots the "
    "current state first (reason=before_restore_mcp) so the restore is "
    "itself undoable.",
    {
        "type": "object",
        "properties": {
            "note_id": {"type": "integer"},
            "version_id": {"type": "integer"},
        },
        "required": ["note_id", "version_id"],
    },
    _restore_note_version,
)


# ===================================================================
# Course subscription tools
# ===================================================================


def _append_course_operation(creator, course, operation_type):
    """Mirrors `notes.api.append_course_operation` without pulling the
    whole module graph; keeps the MCP layer decoupled."""
    from courses.models import CourseOperationLog

    CourseOperationLog.objects.create(
        creator_id=creator,
        course_id=course,
        operation_type=operation_type,
    )


def _subscribe_course(user, creator, params):
    course = get_object_or_404(Course, pk=params["course_id"])
    subscription, created = CourseSubscription.objects.get_or_create(
        creator_id=creator,
        course_id=course,
        defaults={"is_active": True, "subscribed_at": timezone.now()},
    )
    if not created:
        subscription.is_active = True
        subscription.subscribed_at = timezone.now()
        subscription.save(
            update_fields=["is_active", "subscribed_at", "last_edit"]
        )
    _append_course_operation(creator, course, CourseOperationTypeChoices.SUBSCRIBE)
    return _course_payload(course)


register_tool(
    "subscribe_course",
    "Subscribe the authenticated user to a course so it appears in their sidebar.",
    {
        "type": "object",
        "properties": {
            "course_id": {"type": "integer"},
        },
        "required": ["course_id"],
    },
    _subscribe_course,
)


def _unsubscribe_course(user, creator, params):
    course = get_object_or_404(Course, pk=params["course_id"])
    subscription = get_object_or_404(
        CourseSubscription,
        creator_id=creator,
        course_id=course,
        is_active=True,
    )
    subscription.is_active = False
    subscription.save(update_fields=["is_active", "last_edit"])
    _append_course_operation(
        creator, course, CourseOperationTypeChoices.UNSUBSCRIBE
    )
    return {"unsubscribed": True, "course_id": course.id}


register_tool(
    "unsubscribe_course",
    "Remove an active course subscription for the authenticated user.",
    {
        "type": "object",
        "properties": {
            "course_id": {"type": "integer"},
        },
        "required": ["course_id"],
    },
    _unsubscribe_course,
)


def _reorder_courses(user, creator, params):
    ids = params.get("course_ids")
    if not isinstance(ids, list):
        raise ValueError("`course_ids` must be a list of integers.")
    owned = {
        c.id: c
        for c in Course.objects.filter(creator_id=creator)
    }
    new_order = []
    seen = set()
    for raw in ids:
        try:
            cid = int(raw)
        except (TypeError, ValueError):
            continue
        if cid in owned and cid not in seen:
            new_order.append(cid)
            seen.add(cid)
    with transaction.atomic():
        for index, cid in enumerate(new_order, start=1):
            course = owned[cid]
            course.sort_order = index
            course.save(update_fields=["sort_order", "last_edit"])
    return {"reordered": new_order}


register_tool(
    "reorder_courses",
    "Rewrite the sidebar sort order for the authenticated user's "
    "courses. The synthetic uncategorized bucket is rendered "
    "client-side and does not appear in this list.",
    {
        "type": "object",
        "properties": {
            "course_ids": {
                "type": "array",
                "items": {"type": "integer"},
                "description": "Ordered list of course ids; any id not "
                "owned by the user is silently skipped.",
            },
        },
        "required": ["course_ids"],
    },
    _reorder_courses,
)


def _list_course_notes(user, creator, params):
    course = get_object_or_404(Course, pk=params["course_id"])
    notes_qs = (
        course.notes.filter(deleted_at__isnull=True)
        .select_related("course_id", "creator_id__user_id")
        .order_by("-last_edit")
    )
    is_owner = course.creator_id_id == creator.id
    if not is_owner:
        notes_qs = notes_qs.filter(is_public=True)
    return {
        "course_id": course.id,
        "notes": [_note_payload(n) for n in notes_qs[:200]],
    }


register_tool(
    "list_course_notes",
    "List notes that live inside a course. For the owner, returns every "
    "non-deleted note; for other users, only notes flagged "
    "``is_public=True``.",
    {
        "type": "object",
        "properties": {
            "course_id": {"type": "integer"},
        },
        "required": ["course_id"],
    },
    _list_course_notes,
)


# ===================================================================
# Planner event delete (paired with create/update already present)
# ===================================================================


def _delete_event(user, creator, params):
    event = get_object_or_404(
        PlannerEvent, pk=params["event_id"], creator_id=creator
    )
    event.delete()
    return {"deleted": True, "event_id": params["event_id"]}


register_tool(
    "delete_event",
    "Permanently delete a planner event (no recycle bin). To finish a "
    "task keep it and set update_event `is_completed: true` instead; "
    "delete only when the user asks to remove it outright.",
    {
        "type": "object",
        "properties": {
            "event_id": {"type": "integer"},
        },
        "required": ["event_id"],
    },
    _delete_event,
)


# ===================================================================
# Activity tools (recent-notes list + weekly planner window)
# ===================================================================


def _get_activity(user, creator, params):
    limit = min(int(params.get("limit", 10)), 50)
    notes = (
        Note.objects.filter(
            creator_id=creator,
            deleted_at__isnull=True,
        )
        .select_related("course_id")
        .order_by("-last_edit")[:limit]
    )
    return {"notes": [_note_payload(n) for n in notes]}


register_tool(
    "get_activity",
    "List the authenticated user's most recently edited notes.",
    {
        "type": "object",
        "properties": {
            "limit": {
                "type": "integer",
                "minimum": 1,
                "maximum": 50,
                "description": "Max notes to return (default 10, cap 50).",
            },
        },
        "required": [],
    },
    _get_activity,
)


def _get_activity_week(user, creator, params):
    start_date = params.get("start_date")
    parsed_start = timezone.localdate()
    if start_date:
        from datetime import datetime as _dt

        try:
            parsed_start = _dt.fromisoformat(start_date).date()
        except ValueError:
            parsed_start = timezone.localdate()
    day_count = params.get("days", 7)
    return calendar_week_payload(
        creator, start_date=parsed_start, day_count=day_count
    )


register_tool(
    "get_activity_week",
    "The user's calendar window: per-day `events` (planner events with "
    "kind 'plan', calendar-feed entries with kind 'feed', work sessions) "
    "plus a `deadlines` list of open tasks sorted by urgency_score "
    "(completed ones inside the window stay, at the bottom). This is "
    "the tool for 'what is on my plate' questions and for a weekly "
    "review. Same payload the app's Activity screen renders.",
    {
        "type": "object",
        "properties": {
            "start_date": {
                "type": "string",
                "description": "Window start, ISO date (YYYY-MM-DD). Defaults to today.",
            },
            "days": {
                "type": "integer",
                "enum": [3, 7, 30],
                "description": "Window length in days (the app's 3-day / week / month ranges). Default 7; other values fall back to 7.",
            },
        },
        "required": [],
    },
    _get_activity_week,
)


# ===================================================================
# Note session tools (start/end work-session on a note)
# ===================================================================


def _list_note_sessions(user, creator, params):
    qs = NoteActivitySession.objects.filter(creator_id=creator)
    if params.get("note_id"):
        qs = qs.filter(note_id_id=params["note_id"])
    qs = qs.order_by("-started_at", "-id")[: min(int(params.get("limit", 50)), 200)]
    return {"sessions": [note_session_payload(s) for s in qs]}


register_tool(
    "list_note_sessions",
    "List the user's note activity sessions, optionally filtered by note.",
    {
        "type": "object",
        "properties": {
            "note_id": {"type": "integer"},
            "limit": {"type": "integer", "minimum": 1, "maximum": 200},
        },
        "required": [],
    },
    _list_note_sessions,
)


def _create_note_session(user, creator, params):
    note = _ensure_own_note(user, creator, params["note_id"])
    session = NoteActivitySession.objects.create(
        creator_id=creator,
        note_id=note,
        title=params.get("title") or note.title,
        summary=(params.get("summary") or (note.description or ""))[:255],
        started_at=timezone.now(),
    )
    return note_session_payload(session)


register_tool(
    "create_note_session",
    "Start a new note activity session. `started_at` is always set to "
    "the current server time.",
    {
        "type": "object",
        "properties": {
            "note_id": {"type": "integer"},
            "title": {"type": "string"},
            "summary": {"type": "string"},
        },
        "required": ["note_id"],
    },
    _create_note_session,
)


def _end_note_session(user, creator, params):
    session = get_object_or_404(
        NoteActivitySession,
        pk=params["session_id"],
        creator_id=creator,
    )
    if "title" in params:
        session.title = params["title"]
    if "summary" in params:
        session.summary = params["summary"][:255]
    session.ended_at = timezone.now()
    session.save()
    return note_session_payload(session)


register_tool(
    "end_note_session",
    "Mark a note activity session finished by setting `ended_at` to now.",
    {
        "type": "object",
        "properties": {
            "session_id": {"type": "integer"},
            "title": {"type": "string"},
            "summary": {"type": "string"},
        },
        "required": ["session_id"],
    },
    _end_note_session,
)


# ===================================================================
# Calendar feed tools (iCal imports + subscribed Google Calendar URLs)
# ===================================================================


def _calendar_feed_payload(feed):
    return {
        "id": feed.id,
        "title": feed.title,
        "source_kind": feed.source_kind,
        "source_url": feed.source_url or "",
        "is_enabled": feed.is_enabled,
        "course_id": feed.course_id_id,
        "last_sync": feed.last_sync.isoformat() if feed.last_sync else None,
    }


def _list_calendar_feeds(user, creator, params):
    feeds = CalendarFeed.objects.filter(creator_id=creator).order_by("title", "id")
    return {"feeds": [_calendar_feed_payload(f) for f in feeds]}


register_tool(
    "list_calendar_feeds",
    "List the authenticated user's calendar feeds (imported iCal + "
    "subscribed URLs).",
    {"type": "object", "properties": {}, "required": []},
    _list_calendar_feeds,
)


def _create_calendar_feed(user, creator, params):
    course = None
    if params.get("course_id") is not None:
        course = get_object_or_404(Course, pk=params["course_id"])
    source_url = params.get("source_url") or ""
    if source_url:
        source_url = normalize_calendar_url(source_url)
    feed = CalendarFeed.objects.create(
        creator_id=creator,
        course_id=course,
        title=params["title"],
        source_kind=params.get("source_kind", "I"),
        source_url=source_url,
        raw_ical=params.get("raw_ical") or "",
        is_enabled=bool(params.get("is_enabled", True)),
    )
    return _calendar_feed_payload(feed)


register_tool(
    "create_calendar_feed",
    "Create a calendar feed shown in the week calendar. `source_kind`="
    "'I' for a one-shot iCal paste (supply `raw_ical`); 'S' for a "
    "subscribed URL that is refetched (supply `source_url` — use the "
    "calendar's secret/private iCal address; a 'public' Google Calendar "
    "page URL returns HTML and will not parse).",
    {
        "type": "object",
        "properties": {
            "title": {"type": "string"},
            "source_kind": {"type": "string", "enum": ["I", "S"]},
            "source_url": {"type": "string"},
            "raw_ical": {"type": "string"},
            "is_enabled": {"type": "boolean"},
            "course_id": {"type": ["integer", "null"]},
        },
        "required": ["title"],
    },
    _create_calendar_feed,
)


def _update_calendar_feed(user, creator, params):
    feed = get_object_or_404(CalendarFeed, pk=params["feed_id"], creator_id=creator)
    for field in ("title", "source_kind", "raw_ical", "is_enabled"):
        if field in params:
            setattr(feed, field, params[field])
    if "source_url" in params:
        feed.source_url = (
            normalize_calendar_url(params["source_url"])
            if params["source_url"]
            else ""
        )
    if "course_id" in params:
        feed.course_id = (
            get_object_or_404(Course, pk=params["course_id"])
            if params["course_id"] is not None
            else None
        )
    feed.save()
    return _calendar_feed_payload(feed)


register_tool(
    "update_calendar_feed",
    "Update a calendar feed's fields.",
    {
        "type": "object",
        "properties": {
            "feed_id": {"type": "integer"},
            "title": {"type": "string"},
            "source_kind": {"type": "string", "enum": ["I", "S"]},
            "source_url": {"type": "string"},
            "raw_ical": {"type": "string"},
            "is_enabled": {"type": "boolean"},
            "course_id": {"type": ["integer", "null"]},
        },
        "required": ["feed_id"],
    },
    _update_calendar_feed,
)


def _delete_calendar_feed(user, creator, params):
    feed = get_object_or_404(CalendarFeed, pk=params["feed_id"], creator_id=creator)
    feed.delete()
    return {"deleted": True, "feed_id": params["feed_id"]}


register_tool(
    "delete_calendar_feed",
    "Delete a calendar feed.",
    {
        "type": "object",
        "properties": {
            "feed_id": {"type": "integer"},
        },
        "required": ["feed_id"],
    },
    _delete_calendar_feed,
)
