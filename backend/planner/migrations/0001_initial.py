"""State-only move of PlannerEvent, HeatmapActivity, CalendarFeed
from the notes app into the planner app. Paired with
0002_rename_tables which renames the physical tables from
`notes_*` to `planner_*`.
"""

import django.db.models.deletion
import django.utils.timezone
from django.db import migrations, models


class Migration(migrations.Migration):

    initial = True

    dependencies = [
        ("creators", "0021_remove_creator_user_group"),
        ("courses", "0001_initial"),
        ("notes", "0015_noteattachment"),
    ]

    operations = [
        migrations.SeparateDatabaseAndState(
            state_operations=[
                migrations.CreateModel(
                    name="PlannerEvent",
                    fields=[
                        (
                            "id",
                            models.BigAutoField(
                                auto_created=True,
                                primary_key=True,
                                serialize=False,
                                verbose_name="ID",
                            ),
                        ),
                        ("title", models.CharField(max_length=120)),
                        (
                            "event_date",
                            models.DateField(default=django.utils.timezone.localdate),
                        ),
                        ("starts_at", models.DateTimeField(blank=True, null=True)),
                        ("ends_at", models.DateTimeField(blank=True, null=True)),
                        ("difficulty_weight", models.PositiveIntegerField(default=1)),
                        (
                            "description",
                            models.CharField(blank=True, max_length=255, null=True),
                        ),
                        ("is_completed", models.BooleanField(default=False)),
                        ("completed_at", models.DateTimeField(blank=True, null=True)),
                        ("date_created", models.DateTimeField(auto_now_add=True)),
                        ("last_edit", models.DateTimeField(auto_now=True)),
                        (
                            "course_id",
                            models.ForeignKey(
                                blank=True,
                                null=True,
                                on_delete=django.db.models.deletion.SET_NULL,
                                related_name="planner_events",
                                to="courses.course",
                            ),
                        ),
                        (
                            "creator_id",
                            models.ForeignKey(
                                on_delete=django.db.models.deletion.CASCADE,
                                related_name="planner_events",
                                to="creators.creator",
                            ),
                        ),
                    ],
                    options={
                        "ordering": ["event_date", "title", "id"],
                        "db_table": "notes_plannerevent",
                    },
                ),
                migrations.CreateModel(
                    name="HeatmapActivity",
                    fields=[
                        (
                            "id",
                            models.BigAutoField(
                                auto_created=True,
                                primary_key=True,
                                serialize=False,
                                verbose_name="ID",
                            ),
                        ),
                        (
                            "activity_type",
                            models.CharField(
                                choices=[("C", "Created"), ("E", "Edited")],
                                default="E",
                                max_length=1,
                            ),
                        ),
                        (
                            "activity_date",
                            models.DateField(default=django.utils.timezone.localdate),
                        ),
                        ("word_count", models.PositiveIntegerField(default=0)),
                        ("date_created", models.DateTimeField(auto_now_add=True)),
                        (
                            "course_id",
                            models.ForeignKey(
                                blank=True,
                                null=True,
                                on_delete=django.db.models.deletion.SET_NULL,
                                related_name="heatmap_activities",
                                to="courses.course",
                            ),
                        ),
                        (
                            "creator_id",
                            models.ForeignKey(
                                on_delete=django.db.models.deletion.CASCADE,
                                related_name="heatmap_activities",
                                to="creators.creator",
                            ),
                        ),
                        (
                            "note_id",
                            models.ForeignKey(
                                on_delete=django.db.models.deletion.CASCADE,
                                related_name="heatmap_activities",
                                to="notes.note",
                            ),
                        ),
                    ],
                    options={
                        "ordering": ["activity_date", "id"],
                        "db_table": "notes_heatmapactivity",
                    },
                ),
                migrations.CreateModel(
                    name="CalendarFeed",
                    fields=[
                        (
                            "id",
                            models.BigAutoField(
                                auto_created=True,
                                primary_key=True,
                                serialize=False,
                                verbose_name="ID",
                            ),
                        ),
                        ("title", models.CharField(max_length=120)),
                        (
                            "source_kind",
                            models.CharField(
                                choices=[
                                    ("I", "Imported iCal"),
                                    ("S", "Subscribed iCal"),
                                ],
                                default="I",
                                max_length=1,
                            ),
                        ),
                        ("source_url", models.URLField(blank=True, null=True)),
                        ("raw_ical", models.TextField(blank=True, default="")),
                        ("is_enabled", models.BooleanField(default=True)),
                        ("last_sync", models.DateTimeField(blank=True, null=True)),
                        ("date_created", models.DateTimeField(auto_now_add=True)),
                        ("last_edit", models.DateTimeField(auto_now=True)),
                        (
                            "course_id",
                            models.ForeignKey(
                                blank=True,
                                null=True,
                                on_delete=django.db.models.deletion.SET_NULL,
                                related_name="calendar_feeds",
                                to="courses.course",
                            ),
                        ),
                        (
                            "creator_id",
                            models.ForeignKey(
                                on_delete=django.db.models.deletion.CASCADE,
                                related_name="calendar_feeds",
                                to="creators.creator",
                            ),
                        ),
                    ],
                    options={
                        "ordering": ["title", "id"],
                        "db_table": "notes_calendarfeed",
                    },
                ),
            ],
            database_operations=[],
        ),
    ]
