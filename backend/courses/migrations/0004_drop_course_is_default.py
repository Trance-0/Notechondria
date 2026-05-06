"""Drop ``Course.is_default``.

Pre-0.1.120, Inbox was a magic ``Course`` row carrying ``is_default=True``
plus the literal title "Inbox". 0.1.120 collapses Inbox into the natural
"category not selected" state — a Note with ``course_id IS NULL`` (already
supported by ``Note.course_id``'s ``null=True, on_delete=SET_NULL``) — and
moves the user-facing display label onto ``Creator.uncategorized_folder_name``.
With Inbox gone, no caller still needs ``is_default``: rename/delete guards
were keyed on the literal "inbox" title (also dropped this release), and
queryset filtering for "where do orphan notes live" is now answered by
``Note.course_id__isnull=True`` rather than a join into Course.

Drop is non-destructive — only the column is removed; existing Course rows
keep all other fields, including any title that happened to equal "Inbox"
(those become normal user-managed categories with no special status).
"""

from django.db import migrations


class Migration(migrations.Migration):

    dependencies = [
        ("courses", "0003_normalize_table_names"),
    ]

    operations = [
        migrations.RemoveField(
            model_name="course",
            name="is_default",
        ),
    ]
