from datetime import timedelta

from django.db.models import Sum
from django.utils import timezone

from .models import (
    HeatmapActivity,
    HeatmapActivityTypeChoices,
    Note,
    NoteBlock,
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
