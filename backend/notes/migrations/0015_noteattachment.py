from django.db import migrations, models
import django.db.models.deletion
import notes.models


class Migration(migrations.Migration):

    dependencies = [
        ("notes", "0014_course_icon"),
    ]

    operations = [
        migrations.CreateModel(
            name="NoteAttachment",
            fields=[
                (
                    "id",
                    models.AutoField(
                        auto_created=True,
                        primary_key=True,
                        serialize=False,
                        verbose_name="ID",
                    ),
                ),
                (
                    "file",
                    models.FileField(upload_to=notes.models.note_attachment_path),
                ),
                ("original_filename", models.CharField(max_length=255)),
                ("file_size", models.PositiveBigIntegerField()),
                (
                    "content_type",
                    models.CharField(blank=True, default="", max_length=128),
                ),
                ("date_created", models.DateTimeField(auto_now_add=True)),
                (
                    "note_id",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name="attachments",
                        to="notes.note",
                    ),
                ),
            ],
            options={
                "ordering": ["-date_created", "-id"],
            },
        ),
    ]
