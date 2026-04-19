from django.db import models
from django.utils import timezone
from django.utils.translation import gettext_lazy as _

from creators.models import Creator
from courses.models import Course


class PlannerEvent(models.Model):
    creator_id = models.ForeignKey(
        Creator,
        related_name="planner_events",
        on_delete=models.CASCADE,
        null=False,
    )
    course_id = models.ForeignKey(
        Course,
        related_name="planner_events",
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
    )
    title = models.CharField(max_length=120, null=False)
    event_date = models.DateField(null=False, default=timezone.localdate)
    starts_at = models.DateTimeField(blank=True, null=True)
    ends_at = models.DateTimeField(blank=True, null=True)
    difficulty_weight = models.PositiveIntegerField(default=1, null=False)
    description = models.CharField(max_length=255, blank=True, null=True)
    is_completed = models.BooleanField(default=False, null=False)
    completed_at = models.DateTimeField(blank=True, null=True)
    date_created = models.DateTimeField(auto_now_add=True, null=False)
    last_edit = models.DateTimeField(auto_now=True, null=False)

    class Meta:
        ordering = ["event_date", "title", "id"]

    def __str__(self) -> str:
        return f"{self.title}@{self.event_date}"


class HeatmapActivityTypeChoices(models.TextChoices):
    CREATED = "C", _("Created")
    EDITED = "E", _("Edited")


class HeatmapActivity(models.Model):
    creator_id = models.ForeignKey(
        Creator,
        related_name="heatmap_activities",
        on_delete=models.CASCADE,
        null=False,
    )
    course_id = models.ForeignKey(
        Course,
        related_name="heatmap_activities",
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
    )
    note_id = models.ForeignKey(
        "notes.Note",
        related_name="heatmap_activities",
        on_delete=models.CASCADE,
        null=False,
    )
    activity_type = models.CharField(
        max_length=1,
        choices=HeatmapActivityTypeChoices.choices,
        default=HeatmapActivityTypeChoices.EDITED,
        null=False,
    )
    activity_date = models.DateField(default=timezone.localdate, null=False)
    word_count = models.PositiveIntegerField(default=0, null=False)
    date_created = models.DateTimeField(auto_now_add=True, null=False)

    class Meta:
        ordering = ["activity_date", "id"]

    def __str__(self) -> str:
        return f"{self.note_id.title}:{self.activity_date}:{self.word_count}"


class CalendarFeed(models.Model):
    creator_id = models.ForeignKey(
        Creator,
        related_name="calendar_feeds",
        on_delete=models.CASCADE,
        null=False,
    )
    course_id = models.ForeignKey(
        Course,
        related_name="calendar_feeds",
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
    )
    title = models.CharField(max_length=120, null=False)
    source_kind = models.CharField(
        max_length=1,
        choices=(
            ("I", _("Imported iCal")),
            ("S", _("Subscribed iCal")),
        ),
        default="I",
        null=False,
    )
    source_url = models.URLField(blank=True, null=True)
    raw_ical = models.TextField(blank=True, default="")
    is_enabled = models.BooleanField(default=True, null=False)
    last_sync = models.DateTimeField(blank=True, null=True)
    date_created = models.DateTimeField(auto_now_add=True, null=False)
    last_edit = models.DateTimeField(auto_now=True, null=False)

    class Meta:
        ordering = ["title", "id"]

    def __str__(self) -> str:
        return self.title
