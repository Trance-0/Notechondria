"""Drop the explicit `db_table` entry from each Course model's Meta
so Django's autodetector stops reporting drift. The physical table
name is already `courses_<model>`, which matches Django's default
naming convention, so no SQL runs — this migration only rewrites
the in-memory state metadata.
"""

from django.db import migrations


class Migration(migrations.Migration):

    dependencies = [
        ("courses", "0002_rename_tables"),
    ]

    operations = [
        migrations.AlterModelTable(name="course", table=None),
        migrations.AlterModelTable(name="coursemedia", table=None),
        migrations.AlterModelTable(name="coursesubscription", table=None),
        migrations.AlterModelTable(name="courseoperationlog", table=None),
    ]
