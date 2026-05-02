from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("notes", "0017_note_cover_image"),
    ]

    operations = [
        migrations.AddField(
            model_name="note",
            name="custom_meta",
            field=models.TextField(
                blank=True,
                default="",
                help_text=(
                    "User-defined metadata variables surfaced as expandable "
                    "list in the note metadata UI and round-tripped to YAML "
                    "frontmatter on export. Stored as a JSON object string "
                    "(`{key: value}`). Distinct from `metadata_json`, which "
                    "is reserved for system-managed keys (sync state, "
                    "attachment manifest, etc)."
                ),
            ),
        ),
    ]
