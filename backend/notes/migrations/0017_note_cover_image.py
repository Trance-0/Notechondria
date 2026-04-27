from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("notes", "0016_remove_moved_models_from_notes_state"),
    ]

    operations = [
        migrations.AddField(
            model_name="note",
            name="cover_image",
            field=models.ImageField(
                blank=True,
                help_text=(
                    "Optional user-uploaded cover image. Shown in note "
                    "view but not in the editor; the frontend renders a "
                    "UUID-derived barcode placeholder when this is empty."
                ),
                null=True,
                upload_to="user_upload/note_covers/",
            ),
        ),
    ]
