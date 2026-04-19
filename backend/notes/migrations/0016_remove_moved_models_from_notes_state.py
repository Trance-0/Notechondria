"""State-only: delete Course, CourseMedia, CourseSubscription,
CourseOperationLog, PlannerEvent, HeatmapActivity, CalendarFeed from
the notes app migration state. Paired with courses.0001_initial /
planner.0001_initial which already claim these models under their
new apps. The database tables are not touched here — they are
renamed afterwards by courses.0002_rename_tables /
planner.0002_rename_tables.

Note.course_id's FK target is re-pointed from `notes.course` to
`courses.course` in state only (the DB column is unchanged since
both models share the same underlying table during the transition).
"""

import django.db.models.deletion
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("notes", "0015_noteattachment"),
        ("courses", "0001_initial"),
        ("planner", "0001_initial"),
    ]

    operations = [
        migrations.SeparateDatabaseAndState(
            state_operations=[
                migrations.AlterField(
                    model_name="note",
                    name="course_id",
                    field=models.ForeignKey(
                        blank=True,
                        null=True,
                        on_delete=django.db.models.deletion.SET_NULL,
                        related_name="notes",
                        to="courses.course",
                    ),
                ),
                migrations.DeleteModel(name="HeatmapActivity"),
                migrations.DeleteModel(name="PlannerEvent"),
                migrations.DeleteModel(name="CalendarFeed"),
                migrations.RemoveConstraint(
                    model_name="coursesubscription",
                    name="unique_course_subscription_per_creator",
                ),
                migrations.DeleteModel(name="CourseSubscription"),
                migrations.DeleteModel(name="CourseOperationLog"),
                migrations.DeleteModel(name="CourseMedia"),
                migrations.RemoveConstraint(
                    model_name="course",
                    name="unique_course_client_id_per_creator",
                ),
                migrations.DeleteModel(name="Course"),
            ],
            database_operations=[],
        ),
    ]
