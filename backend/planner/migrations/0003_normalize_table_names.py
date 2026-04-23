"""Drop the explicit `db_table` entry from each Planner model's
Meta so Django's autodetector stops reporting drift. Physical
tables are already `planner_<model>`, matching Django's default
naming.
"""

from django.db import migrations


class Migration(migrations.Migration):

    dependencies = [
        ("planner", "0002_rename_tables"),
    ]

    operations = [
        migrations.AlterModelTable(name="plannerevent", table=None),
        migrations.AlterModelTable(name="heatmapactivity", table=None),
        migrations.AlterModelTable(name="calendarfeed", table=None),
    ]
