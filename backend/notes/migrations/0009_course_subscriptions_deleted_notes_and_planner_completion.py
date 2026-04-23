import django.db.models.deletion
from django.db import migrations, models
from django.db.models import Q
from django.utils import timezone


class Migration(migrations.Migration):

    dependencies = [
        ("creators", "0024_creator_app_settings"),
        ("notes", "0008_note_visibility_planner_windows_and_sessions"),
    ]

    operations = [
        migrations.AddField(
            model_name="note",
            name="client_draft_id",
            field=models.CharField(blank=True, max_length=64, null=True),
        ),
        migrations.AddField(
            model_name="note",
            name="deleted_at",
            field=models.DateTimeField(blank=True, null=True),
        ),
        migrations.AddField(
            model_name="plannerevent",
            name="completed_at",
            field=models.DateTimeField(blank=True, null=True),
        ),
        migrations.AddField(
            model_name="plannerevent",
            name="is_completed",
            field=models.BooleanField(default=False),
        ),
        migrations.CreateModel(
            name="CourseSubscription",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                ("is_active", models.BooleanField(default=True)),
                ("subscribed_at", models.DateTimeField(default=timezone.now)),
                ("last_opened_at", models.DateTimeField(blank=True, null=True)),
                ("date_created", models.DateTimeField(auto_now_add=True)),
                ("last_edit", models.DateTimeField(auto_now=True)),
                (
                    "course_id",
                    models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name="subscriptions", to="notes.course"),
                ),
                (
                    "creator_id",
                    models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name="course_subscriptions", to="creators.creator"),
                ),
            ],
            options={
                "ordering": ["-last_opened_at", "-subscribed_at", "-id"],
            },
        ),
        migrations.CreateModel(
            name="CourseOperationLog",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
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
                ("occurred_at", models.DateTimeField(default=timezone.now)),
                ("date_created", models.DateTimeField(auto_now_add=True)),
                (
                    "course_id",
                    models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name="operation_logs", to="notes.course"),
                ),
                (
                    "creator_id",
                    models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name="course_operation_logs", to="creators.creator"),
                ),
            ],
            options={
                "ordering": ["-occurred_at", "-id"],
            },
        ),
        migrations.AddConstraint(
            model_name="coursesubscription",
            constraint=models.UniqueConstraint(fields=("creator_id", "course_id"), name="unique_course_subscription_per_creator"),
        ),
        migrations.AddConstraint(
            model_name="note",
            constraint=models.UniqueConstraint(
                condition=Q(client_draft_id__isnull=False),
                fields=("creator_id", "client_draft_id"),
                name="unique_note_client_draft_per_creator",
            ),
        ),
    ]
