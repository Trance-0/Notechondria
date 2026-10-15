from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("planner", "0003_normalize_table_names"),
    ]

    operations = [
        migrations.AddField(
            model_name="plannerevent",
            name="recurrence_freq",
            field=models.CharField(
                choices=[
                    ("N", "Does not repeat"),
                    ("W", "Weekly"),
                    ("M", "Monthly"),
                    ("Y", "Yearly"),
                ],
                default="N",
                max_length=1,
            ),
        ),
        migrations.AddField(
            model_name="plannerevent",
            name="recurrence_interval",
            field=models.PositiveIntegerField(default=1),
        ),
        migrations.AddField(
            model_name="plannerevent",
            name="recurrence_end_date",
            field=models.DateField(blank=True, null=True),
        ),
        migrations.AddField(
            model_name="plannerevent",
            name="recurrence_count",
            field=models.PositiveIntegerField(blank=True, null=True),
        ),
    ]
