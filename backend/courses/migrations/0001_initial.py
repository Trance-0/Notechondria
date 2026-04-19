"""State-only move of Course, CourseMedia, CourseSubscription,
CourseOperationLog from the notes app into the courses app.

This migration tells Django's migration state that these models now
live under `courses.*`, but it does NOT touch the database — the
tables physically remain `notes_course*` until the companion
0002_rename_tables migration runs. Splitting the move in two steps
keeps the state/schema transitions ordered cleanly across apps.
"""

import courses.models
import django.db.models.deletion
import django.utils.timezone
from django.db import migrations, models
from django.db.models import Q


class Migration(migrations.Migration):

    initial = True

    dependencies = [
        ("creators", "0021_remove_creator_user_group"),
        ("notes", "0015_noteattachment"),
    ]

    operations = [
        migrations.SeparateDatabaseAndState(
            state_operations=[
                migrations.CreateModel(
                    name="Course",
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
                            "client_course_id",
                            models.CharField(blank=True, max_length=64, null=True),
                        ),
                        ("slug", models.SlugField(max_length=120, unique=True)),
                        ("title", models.CharField(max_length=120)),
                        ("description", models.TextField(blank=True, null=True)),
                        (
                            "cover_image",
                            models.ImageField(
                                blank=True,
                                null=True,
                                upload_to=courses.models.course_cover_path,
                            ),
                        ),
                        (
                            "icon",
                            models.IntegerField(
                                blank=True,
                                help_text="Material Icons codePoint",
                                null=True,
                            ),
                        ),
                        ("is_default", models.BooleanField(default=False)),
                        ("sort_order", models.IntegerField(default=0)),
                        ("date_created", models.DateTimeField(auto_now_add=True)),
                        ("last_edit", models.DateTimeField(auto_now=True)),
                        (
                            "creator_id",
                            models.ForeignKey(
                                blank=True,
                                null=True,
                                on_delete=django.db.models.deletion.SET_NULL,
                                to="creators.creator",
                            ),
                        ),
                    ],
                    options={
                        "ordering": ["sort_order", "title"],
                        "db_table": "notes_course",
                    },
                ),
                migrations.AddConstraint(
                    model_name="course",
                    constraint=models.UniqueConstraint(
                        condition=Q(client_course_id__isnull=False),
                        fields=("creator_id", "client_course_id"),
                        name="unique_course_client_id_per_creator",
                    ),
                ),
                migrations.CreateModel(
                    name="CourseMedia",
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
                            "description",
                            models.CharField(blank=True, max_length=255, null=True),
                        ),
                        (
                            "image",
                            models.ImageField(
                                blank=True,
                                null=True,
                                upload_to=courses.models.course_media_path,
                            ),
                        ),
                        (
                            "source",
                            models.CharField(blank=True, max_length=255, null=True),
                        ),
                        ("date_created", models.DateTimeField(auto_now_add=True)),
                        (
                            "course_id",
                            models.ForeignKey(
                                on_delete=django.db.models.deletion.CASCADE,
                                related_name="media_items",
                                to="courses.course",
                            ),
                        ),
                    ],
                    options={
                        "ordering": ["date_created", "id"],
                        "db_table": "notes_coursemedia",
                    },
                ),
                migrations.CreateModel(
                    name="CourseSubscription",
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
                        ("is_active", models.BooleanField(default=True)),
                        (
                            "subscribed_at",
                            models.DateTimeField(default=django.utils.timezone.now),
                        ),
                        ("last_opened_at", models.DateTimeField(blank=True, null=True)),
                        ("date_created", models.DateTimeField(auto_now_add=True)),
                        ("last_edit", models.DateTimeField(auto_now=True)),
                        (
                            "course_id",
                            models.ForeignKey(
                                on_delete=django.db.models.deletion.CASCADE,
                                related_name="subscriptions",
                                to="courses.course",
                            ),
                        ),
                        (
                            "creator_id",
                            models.ForeignKey(
                                on_delete=django.db.models.deletion.CASCADE,
                                related_name="course_subscriptions",
                                to="creators.creator",
                            ),
                        ),
                    ],
                    options={
                        "ordering": ["-last_opened_at", "-subscribed_at", "-id"],
                        "db_table": "notes_coursesubscription",
                    },
                ),
                migrations.AddConstraint(
                    model_name="coursesubscription",
                    constraint=models.UniqueConstraint(
                        fields=("creator_id", "course_id"),
                        name="unique_course_subscription_per_creator",
                    ),
                ),
                migrations.CreateModel(
                    name="CourseOperationLog",
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
                            "operation_type",
                            models.CharField(
                                choices=[
                                    ("subscribe", "Subscribe"),
                                    ("unsubscribe", "Unsubscribe"),
                                    ("open", "Open"),
                                ],
                                max_length=16,
                            ),
                        ),
                        ("metadata_json", models.TextField(blank=True, default="")),
                        (
                            "occurred_at",
                            models.DateTimeField(default=django.utils.timezone.now),
                        ),
                        ("date_created", models.DateTimeField(auto_now_add=True)),
                        (
                            "course_id",
                            models.ForeignKey(
                                on_delete=django.db.models.deletion.CASCADE,
                                related_name="operation_logs",
                                to="courses.course",
                            ),
                        ),
                        (
                            "creator_id",
                            models.ForeignKey(
                                on_delete=django.db.models.deletion.CASCADE,
                                related_name="course_operation_logs",
                                to="creators.creator",
                            ),
                        ),
                    ],
                    options={
                        "ordering": ["-occurred_at", "-id"],
                        "db_table": "notes_courseoperationlog",
                    },
                ),
            ],
            database_operations=[],
        ),
    ]
