from django.db import migrations, models
import django.db.models.deletion
import django.utils.timezone


class Migration(migrations.Migration):

    dependencies = [
        ("creators", "0024_creator_app_settings"),
        ("notes", "0009_course_subscriptions_deleted_notes_and_planner_completion"),
    ]

    operations = [
        migrations.CreateModel(
            name="RecycleBinEntry",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                ("item_type", models.CharField(choices=[("note", "Note")], default="note", max_length=16)),
                ("deleted_at", models.DateTimeField(default=django.utils.timezone.now)),
                ("metadata_json", models.TextField(blank=True, default="")),
                ("date_created", models.DateTimeField(auto_now_add=True)),
                ("last_edit", models.DateTimeField(auto_now=True)),
                ("creator_id", models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name="recycle_bin_entries", to="creators.creator")),
                ("note_id", models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name="recycle_bin_entries", to="notes.note")),
            ],
            options={
                "ordering": ["-deleted_at", "-id"],
            },
        ),
        migrations.AddConstraint(
            model_name="recyclebinentry",
            constraint=models.UniqueConstraint(fields=("creator_id", "note_id"), name="unique_recycle_bin_note_per_creator"),
        ),
    ]
