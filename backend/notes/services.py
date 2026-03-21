from datetime import datetime, timedelta, timezone as dt_timezone
import urllib.request

from django.db.models import Sum
from django.utils import timezone

from .models import (
    CalendarFeed,
    HeatmapActivity,
    HeatmapActivityTypeChoices,
    Note,
    NoteBlock,
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
        )
        .values("activity_date")
        .annotate(total_words=Sum("word_count"))
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

    past_map = {row["activity_date"]: int(row["total_words"] or 0) for row in past_rows}
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
                "intensity": past_value if current <= today else future_value,
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
    return {
        "id": event.id,
        "title": event.title,
        "event_date": event.event_date.isoformat(),
        "difficulty_weight": event.difficulty_weight,
        "description": event.description or "",
        "course_id": event.course_id_id,
    }


def note_preview_lines(note: Note, limit: int = 3):
    lines = [line.strip() for line in (note.content or "").splitlines() if line.strip()]
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


def parse_ical_datetime(raw_value: str):
    value = raw_value.strip()
    if not value:
        return None
    if "T" not in value:
        return datetime.strptime(value, "%Y%m%d").replace(tzinfo=dt_timezone.utc)
    value = value.rstrip("Z")
    dt = datetime.strptime(value, "%Y%m%dT%H%M%S")
    return dt.replace(tzinfo=dt_timezone.utc)


def read_calendar_feed(feed: CalendarFeed) -> str:
    if feed.raw_ical:
        return feed.raw_ical
    if feed.source_url:
        with urllib.request.urlopen(feed.source_url, timeout=10) as response:
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
    )
    for event in planner_rows:
        payload[event.event_date.isoformat()].append(
            {
                "title": event.title,
                "kind": "plan",
                "course_id": event.course_id_id,
                "source_id": event.id,
            }
        )

    for feed in CalendarFeed.objects.filter(creator_id=creator, is_enabled=True):
        try:
            raw_ical = read_calendar_feed(feed)
        except Exception:
            continue
        for event in parse_ical_events(raw_ical):
            dt_value = parse_ical_datetime(event.get("DTSTART", ""))
            if dt_value is None:
                continue
            event_date = timezone.localtime(dt_value).date()
            if event_date < days[0] or event_date > days[-1]:
                continue
            payload[event_date.isoformat()].append(
                {
                    "title": event.get("SUMMARY", feed.title),
                    "kind": "calendar",
                    "course_id": feed.course_id_id,
                    "source_id": feed.id,
                    "calendar_title": feed.title,
                }
            )

    return {
        "start_date": days[0].isoformat(),
        "days": [
            {
                "date": day.isoformat(),
                "events": payload[day.isoformat()],
            }
            for day in days
        ],
    }
