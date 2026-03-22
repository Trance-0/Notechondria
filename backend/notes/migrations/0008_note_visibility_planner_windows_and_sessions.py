from django.db import migrations, models
import django.db.models.deletion
import django.utils.timezone


class Migration(migrations.Migration):

    dependencies = [
        ("creators", "0023_creator_theme_and_api_base"),
        ("notes", "0007_note_calendarfeed_noteversion_and_more"),
    ]

    operations = [
        migrations.AddField(
            model_name="note",
            name="is_public",
            field=models.BooleanField(default=False),
        ),
        migrations.AddField(
            model_name="plannerevent",
            name="ends_at",
            field=models.DateTimeField(blank=True, null=True),
        ),
        migrations.AddField(
            model_name="plannerevent",
            name="starts_at",
            field=models.DateTimeField(blank=True, null=True),
        ),
        migrations.CreateModel(
            name="NoteActivitySession",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                ("title", models.CharField(max_length=120)),
                ("summary", models.CharField(blank=True, default="", max_length=255)),
                ("started_at", models.DateTimeField(default=django.utils.timezone.now)),
                ("ended_at", models.DateTimeField(blank=True, null=True)),
                ("date_created", models.DateTimeField(auto_now_add=True)),
                ("last_edit", models.DateTimeField(auto_now=True)),
                (
                    "creator_id",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name="note_activity_sessions",
                        to="creators.creator",
                    ),
                ),
                (
                    "note_id",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name="activity_sessions",
                        to="notes.note",
                    ),
                ),
            ],
            options={"ordering": ["-started_at", "-id"]},
        ),
    ]
