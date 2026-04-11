import base64
from datetime import datetime, timedelta, timezone as dt_timezone
import urllib.parse
import urllib.request

from django.db.models import Count, Max, Sum
from django.utils import timezone

from .models import (
    CalendarFeed,
    Course,
    HeatmapActivity,
    HeatmapActivityTypeChoices,
    Note,
    NoteActivitySession,
    NoteBlock,
    NoteBlockTypeChoices,
    NoteVersion,
    NoteIndex,
    PlannerEvent,
)


def count_words(text: str) -> int:
    if not text:
        return 0
    return len([token for token in text.split() if token.strip()])


def note_word_count(note: Note) -> int:
    blocks = [
        handle.noteblock_id
        for handle in NoteIndex.objects.filter(note_id=note).select_related("noteblock_id").order_by("index")
    ]
    return sum(count_words(block.get_md_str() or "") for block in blocks)


def block_word_count(block: NoteBlock) -> int:
    return count_words(block.get_md_str() or "")


def record_note_activity(note: Note, word_count: int, activity_type: str) -> None:
    if word_count <= 0:
        return
    HeatmapActivity.objects.create(
        creator_id=note.creator_id,
        course_id=note.course_id,
        note_id=note,
        activity_type=activity_type,
        activity_date=timezone.localdate(),
        word_count=word_count,
    )


def build_heatmap_payload(creator, center_date=None, days_before=182, days_after=182):
    today = center_date or timezone.localdate()
    start_date = today - timedelta(days=days_before)
    end_date = today + timedelta(days=days_after)

    past_rows = (
        HeatmapActivity.objects.filter(
            creator_id=creator,
            activity_date__gte=start_date,
            activity_date__lte=today,
            activity_type=HeatmapActivityTypeChoices.CREATED,
        )
        .values("activity_date")
        .annotate(created_notes=Count("id"), peak_words=Max("word_count"))
    )
    future_rows = (
        PlannerEvent.objects.filter(
            creator_id=creator,
            event_date__gte=today,
            event_date__lte=end_date,
        )
        .values("event_date")
        .annotate(total_weight=Sum("difficulty_weight"))
    )

    past_map = {}
    for row in past_rows:
        created_notes = int(row["created_notes"] or 0)
        peak_words = int(row["peak_words"] or 0)
        word_grade = min(4, max(0, peak_words // 100))
        if peak_words > 0 and word_grade == 0:
            word_grade = 1
        past_map[row["activity_date"]] = min(4, max(created_notes, word_grade))
    future_map = {row["event_date"]: int(row["total_weight"] or 0) for row in future_rows}

    cells = []
    current = start_date
    while current <= end_date:
        past_value = past_map.get(current, 0)
        future_value = future_map.get(current, 0)
        if current < today:
            cell_kind = "past"
        elif current > today:
            cell_kind = "future"
        else:
            cell_kind = "today"
        cells.append(
            {
                "date": current.isoformat(),
                "kind": cell_kind,
                "past_value": past_value,
                "future_value": future_value,
                "intensity": past_value if current <= today else min(4, future_value),
                "is_today": current == today,
            }
        )
        current += timedelta(days=1)

    return {
        "today": today.isoformat(),
        "start_date": start_date.isoformat(),
        "end_date": end_date.isoformat(),
        "days_before": days_before,
        "days_after": days_after,
        "cells": cells,
        "max_past_value": max(past_map.values(), default=0),
        "max_future_value": max(future_map.values(), default=0),
    }


def planner_event_payload(event: PlannerEvent):
    starts_at = event.starts_at or timezone.make_aware(datetime.combine(event.event_date, datetime.min.time().replace(hour=12)))
    ends_at = event.ends_at or (starts_at + timedelta(hours=1))
    return {
        "id": event.id,
        "title": event.title,
        "event_date": event.event_date.isoformat(),
        "starts_at": starts_at.isoformat(),
        "ends_at": ends_at.isoformat(),
        "difficulty_weight": event.difficulty_weight,
        "description": event.description or "",
        "course_id": event.course_id_id,
        "is_completed": event.is_completed,
        "completed_at": event.completed_at.isoformat() if event.completed_at else None,
    }


def planner_deadline_payload(event: PlannerEvent, now=None):
    reference = now or timezone.now()
    starts_at = event.starts_at or timezone.make_aware(datetime.combine(event.event_date, datetime.min.time().replace(hour=12)))
    hours_remaining = max((starts_at - reference).total_seconds() / 3600.0, 1 / 60.0)
    urgency = round(float(event.difficulty_weight) / hours_remaining, 4)
    payload = planner_event_payload(event)
    payload["urgency_score"] = urgency
    return payload


def note_preview_lines(note: Note, limit: int = 3):
    lines = [line.strip() for line in (note.content or "").splitlines() if line.strip()]
    if lines and lines[0].startswith("# "):
        lines = lines[1:]
    return lines[:limit]


def note_markdown(note: Note) -> str:
    title = note.title or "Untitled"
    body = note.content or ""
    if body.startswith("# "):
        return body
    return f"# {title}\n\n{body}".strip()


def snapshot_note_version(note: Note, reason: str = "manual") -> NoteVersion:
    version = NoteVersion.objects.create(
        note_id=note,
        creator_id=note.creator_id,
        title=note.title,
        description=note.description or "",
        content=note.content or "",
        metadata_json=note.metadata_json or "",
        editor_mode=note.editor_mode,
        reason=reason,
    )
    prune_recent_versions(note)
    return version


def prune_recent_versions(note: Note) -> None:
    versions = list(note.versions.order_by("-date_created"))
    if len(versions) <= 12:
        return
    for version in versions[12:]:
        version.delete()


def restore_note_version(note: Note, version: NoteVersion) -> None:
    note.title = version.title
    note.description = version.description
    note.content = version.content
    note.metadata_json = version.metadata_json
    note.editor_mode = version.editor_mode
    note.save()


def version_label(version: NoteVersion) -> str:
    reason = (version.reason or "").lower()
    if reason == "autosave_1m":
        return "AutoSave-1m"
    if reason == "autosave_10m":
        return "AutoSave-10m"
    if reason == "autosave_1h":
        return "AutoSave-1h"
    return timezone.localtime(version.date_created).strftime("%Y-%m-%d %H:%M")


def note_session_payload(session: NoteActivitySession):
    ends_at = session.ended_at or (session.started_at + timedelta(minutes=15))
    return {
        "id": session.id,
        "title": session.title,
        "kind": "note_session",
        "note_id": session.note_id_id,
        "course_id": session.note_id.course_id_id,
        "summary": session.summary,
        "starts_at": session.started_at.isoformat(),
        "ends_at": ends_at.isoformat(),
    }


def parse_ical_datetime(raw_value: str):
    value = raw_value.strip()
    if not value:
        return None
    if "T" not in value:
        return datetime.strptime(value, "%Y%m%d").replace(tzinfo=dt_timezone.utc)
    is_utc = value.endswith("Z")
    normalized = value.rstrip("Z")
    for fmt in ("%Y%m%dT%H%M%S", "%Y%m%dT%H%M"):
        try:
            dt = datetime.strptime(normalized, fmt)
            tzinfo = dt_timezone.utc if is_utc else timezone.get_current_timezone()
            return dt.replace(tzinfo=tzinfo)
        except ValueError:
            continue
    raise ValueError(f"Unsupported iCal datetime format: {raw_value}")


def normalize_calendar_url(url: str) -> str:
    """Convert common Google Calendar share URLs into their ``.ics`` form.

    Users frequently paste the HTML share link from Google Calendar (the one
    behind the "public URL" or "share" button) instead of the
    ``Secret address in iCal format``. The HTML URLs can't be parsed as iCal,
    so we rewrite them to the canonical
    ``https://calendar.google.com/calendar/ical/<id>/public/basic.ics`` form
    when we can confidently recover the calendar id.

    Supported input shapes:

    - ``https://calendar.google.com/calendar/ical/.../basic.ics`` (returned as-is)
    - ``https://calendar.google.com/calendar/embed?src=<id>&...``
    - ``https://calendar.google.com/calendar/u/0/r?cid=<base64>``
    - ``https://calendar.google.com/calendar?cid=<base64>``

    For any other URL (iCloud, Outlook, raw ``.ics`` files), the original URL
    is returned unchanged so existing subscriptions keep working.
    """

    if not url:
        return url
    try:
        parsed = urllib.parse.urlsplit(url)
    except ValueError:
        return url
    host = (parsed.netloc or "").lower()
    if "calendar.google.com" not in host:
        return url
    # Already an iCal endpoint — no rewrite needed.
    if "/calendar/ical/" in parsed.path:
        return url
    query = urllib.parse.parse_qs(parsed.query)
    cal_id = None
    src_values = query.get("src") or []
    if src_values:
        cal_id = src_values[0]
    if cal_id is None:
        cid_values = query.get("cid") or []
        if cid_values:
            raw_cid = cid_values[0]
            # Google's cid= parameter is base64-url encoded, occasionally
            # without padding. Re-pad before decoding.
            padding = "=" * (-len(raw_cid) % 4)
            try:
                decoded = base64.urlsafe_b64decode(raw_cid + padding)
                cal_id = decoded.decode("utf-8", errors="ignore").strip()
            except Exception:
                cal_id = None
    if not cal_id:
        return url
    quoted = urllib.parse.quote(cal_id, safe="")
    return f"https://calendar.google.com/calendar/ical/{quoted}/public/basic.ics"


WELCOME_NOTE_TITLE = "Welcome to Notechondria"

WELCOME_NOTE_BODY = (
    "Notechondria is an integrated workspace for taking notes, planning study "
    "sessions, and sharing public courses. Here are a few things to try first:\n\n"
    "- **Editor** — create a new note from the `+` button. Notes live inside "
    "categories (this one is your Inbox); drag categories in the sidebar to "
    "reorder them.\n"
    "- **Planner** — the Course view shows subscribed courses and their "
    "modules, and the Activity view lets you import an `.ics` file or "
    "subscribe to a Google Calendar share link.\n"
    "- **Portal** — the front page highlights recent public courses and an "
    "activity heatmap for the whole platform.\n\n"
    "### Keyboard shortcuts\n\n"
    "- `Ctrl/Cmd + S` — save the current note\n"
    "- Long-press the floating add button in Activity to import calendar "
    "files or subscribe to a calendar feed\n\n"
    "Feel free to delete this welcome note once you're done exploring. Your "
    "Inbox category itself is pinned and cannot be removed — it's where any "
    "orphaned notes are moved when you delete a category."
)


def seed_inbox_and_welcome_note(creator) -> Note | None:
    """Ensure *creator* has a default Inbox category with a welcome note.

    Idempotent — if the Inbox already exists with at least one note, this is
    a no-op. Used by the email-verify and OAuth-register flows so new users
    land on a non-empty workspace the first time they sign in.

    Returns the welcome ``Note`` if one was created, or ``None`` if nothing
    had to be done.
    """

    # Late imports avoid a circular dependency with ``notes.api`` (which in
    # turn imports from ``services``).
    from django.utils.text import slugify
    from notechondria.utils import generate_unique_id

    inbox = (
        Course.objects.filter(creator_id=creator, is_default=True)
        .order_by("id")
        .first()
    )
    if inbox is None:
        base = slugify("inbox") or "inbox"
        slug_candidate = f"{base}-{creator.id}"
        counter = 2
        while Course.objects.filter(slug=slug_candidate).exists():
            slug_candidate = f"{base}-{creator.id}-{counter}"
            counter += 1
        inbox = Course.objects.create(
            creator_id=creator,
            slug=slug_candidate,
            title="Inbox",
            description="Default category",
            is_default=True,
        )

    # If the Inbox already contains any non-deleted notes, do not insert a
    # second welcome copy — the user has already been through onboarding.
    if Note.objects.filter(course_id=inbox, deleted_at__isnull=True).exists():
        return None

    note = Note.objects.create(
        creator_id=creator,
        course_id=inbox,
        sharing_id=generate_unique_id(Note, "sharing_id"),
        title=WELCOME_NOTE_TITLE,
        description="A quick tour of Notechondria's editor, planner and portal.",
        editor_mode="G",
        content=WELCOME_NOTE_BODY,
    )
    # Persist the welcome markdown as block content so the editor renders the
    # same text regardless of which editor mode the user opens it with.
    title_block = NoteBlock.objects.create(
        creator_id=creator,
        note_id=note,
        block_type=NoteBlockTypeChoices.TITLE,
        text=WELCOME_NOTE_TITLE,
        is_AI_generated=False,
    )
    NoteIndex.objects.create(note_id=note, index=0, noteblock_id=title_block)
    body_block = NoteBlock.objects.create(
        creator_id=creator,
        note_id=note,
        block_type=NoteBlockTypeChoices.TEXT,
        text=WELCOME_NOTE_BODY,
        is_AI_generated=False,
    )
    NoteIndex.objects.create(note_id=note, index=1, noteblock_id=body_block)
    return note


def read_calendar_feed(feed: CalendarFeed) -> str:
    if feed.raw_ical:
        return feed.raw_ical
    if feed.source_url:
        target = normalize_calendar_url(feed.source_url)
        request = urllib.request.Request(
            target,
            headers={
                # Some providers (notably Google Calendar) reject requests
                # without a real User-Agent header.
                "User-Agent": "Notechondria/0.1 (+calendar-feed)",
                "Accept": "text/calendar, */*;q=0.1",
            },
        )
        with urllib.request.urlopen(request, timeout=10) as response:
            return response.read().decode("utf-8")
    return ""


def parse_ical_events(raw_ical: str):
    events = []
    current = None
    for raw_line in raw_ical.splitlines():
        line = raw_line.strip()
        if line == "BEGIN:VEVENT":
            current = {}
        elif line == "END:VEVENT":
            if current:
                events.append(current)
            current = None
        elif current is not None and ":" in line:
            key, value = line.split(":", 1)
            current[key.split(";")[0]] = value
    return events


def calendar_week_payload(creator, start_date=None):
    start = start_date or timezone.localdate()
    days = [start + timedelta(days=index) for index in range(7)]
    payload = {day.isoformat(): [] for day in days}

    planner_rows = PlannerEvent.objects.filter(
        creator_id=creator,
        event_date__gte=days[0],
        event_date__lte=days[-1],
        is_completed=False,
    )
    for event in planner_rows:
        payload[event.event_date.isoformat()].append(planner_event_payload(event) | {"kind": "plan", "source_id": event.id})

    session_rows = NoteActivitySession.objects.filter(
        creator_id=creator,
        started_at__date__gte=days[0],
        started_at__date__lte=days[-1],
    ).select_related("note_id")
    for session in session_rows:
        payload[timezone.localtime(session.started_at).date().isoformat()].append(note_session_payload(session))

    for feed in CalendarFeed.objects.filter(creator_id=creator, is_enabled=True):
        try:
            raw_ical = read_calendar_feed(feed)
        except Exception:
            continue
        for event in parse_ical_events(raw_ical):
            starts_at = parse_ical_datetime(event.get("DTSTART", ""))
            if starts_at is None:
                continue
            ends_at = parse_ical_datetime(event.get("DTEND", "")) or (starts_at + timedelta(hours=1))
            event_date = timezone.localtime(starts_at).date()
            if event_date < days[0] or event_date > days[-1]:
                continue
            payload[event_date.isoformat()].append(
                {
                    "title": event.get("SUMMARY", feed.title),
                    "kind": "calendar",
                    "course_id": feed.course_id_id,
                    "source_id": feed.id,
                    "calendar_title": feed.title,
                    "starts_at": starts_at.isoformat(),
                    "ends_at": ends_at.isoformat(),
                }
            )

    active_deadlines = [
        planner_deadline_payload(event)
        for event in PlannerEvent.objects.filter(
            creator_id=creator,
            event_date__gte=timezone.localdate(),
            is_completed=False,
        ).order_by("starts_at", "event_date", "title")[:40]
    ]
    active_deadlines.sort(
        key=lambda item: (
            -float(item.get("urgency_score", 0)),
            item.get("starts_at") or "",
            item.get("title") or "",
        )
    )

    return {
        "start_date": days[0].isoformat(),
        "previous_week_start": (days[0] - timedelta(days=7)).isoformat(),
        "next_week_start": (days[0] + timedelta(days=7)).isoformat(),
        "days": [
            {
                "date": day.isoformat(),
                "events": sorted(
                    payload[day.isoformat()],
                    key=lambda item: item.get("starts_at", f"{day.isoformat()}T23:59:00"),
                ),
            }
            for day in days
        ],
        "deadlines": active_deadlines,
    }
