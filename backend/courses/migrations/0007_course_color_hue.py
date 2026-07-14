from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("courses", "0006_course_git_binding"),
    ]

    operations = [
        migrations.AddField(
            model_name="course",
            name="color_hue",
            field=models.PositiveSmallIntegerField(blank=True, null=True),
        ),
    ]
