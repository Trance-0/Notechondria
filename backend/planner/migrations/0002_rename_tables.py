"""Rename the physical DB tables for PlannerEvent, HeatmapActivity,
CalendarFeed from `notes_*` to `planner_*`. Depends on the notes
state-removal migration so the old state is gone before the rename.
"""

from django.db import migrations


class Migration(migrations.Migration):

    dependencies = [
        ("planner", "0001_initial"),
        ("notes", "0016_remove_moved_models_from_notes_state"),
    ]

    operations = [
        migrations.AlterModelTable(
            name="plannerevent",
            table="planner_plannerevent",
        ),
        migrations.AlterModelTable(
            name="heatmapactivity",
            table="planner_heatmapactivity",
        ),
        migrations.AlterModelTable(
            name="calendarfeed",
            table="planner_calendarfeed",
        ),
    ]
