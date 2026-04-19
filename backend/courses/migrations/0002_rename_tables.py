"""Rename the physical DB tables for the Course-family models from
`notes_course*` to `courses_course*`. State is unchanged — only the
database-side table names move. Depends on 0001_initial, which
already handed ownership of the tables to the `courses` app.
"""

from django.db import migrations


class Migration(migrations.Migration):

    dependencies = [
        ("courses", "0001_initial"),
        ("notes", "0016_remove_moved_models_from_notes_state"),
    ]

    operations = [
        migrations.AlterModelTable(
            name="course",
            table="courses_course",
        ),
        migrations.AlterModelTable(
            name="coursemedia",
            table="courses_coursemedia",
        ),
        migrations.AlterModelTable(
            name="coursesubscription",
            table="courses_coursesubscription",
        ),
        migrations.AlterModelTable(
            name="courseoperationlog",
            table="courses_courseoperationlog",
        ),
    ]
