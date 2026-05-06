"""Add ``Creator.uncategorized_folder_name``.

Backs the SPA's synthetic "no category" bucket that replaces the pre-0.1.120
Inbox course. The bucket itself is purely a frontend rendering of every
Note where ``course_id IS NULL``; this field stores the user-chosen display
label for that bucket so renaming it is per-user, not global.

Default ``"Inbox"`` preserves the pre-refactor wording for existing users
without a server-side data migration: every Creator silently picks up the
old label on first read after migrate runs.
"""

from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("creators", "0033_profile_refresh_drop_social"),
    ]

    operations = [
        migrations.AddField(
            model_name="creator",
            name="uncategorized_folder_name",
            field=models.CharField(
                max_length=120,
                default="Inbox",
                help_text=(
                    "User-chosen display label for the synthetic 'no "
                    "category' bucket the SPA renders at the top of "
                    "the categories list. It groups every Note whose "
                    "`course_id IS NULL` (the natural state for a "
                    "freshly-created note and for notes left behind "
                    "when their category is deleted via `SET_NULL`). "
                    "Defaults to 'Inbox' for continuity with the "
                    "pre-0.1.120 hard-coded Inbox category, but the "
                    "field is freely editable from settings — there "
                    "is no special Course row backing this bucket on "
                    "the server side."
                ),
            ),
        ),
    ]
