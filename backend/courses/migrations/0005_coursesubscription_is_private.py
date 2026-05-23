from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("courses", "0004_drop_course_is_default"),
    ]

    operations = [
        migrations.AddField(
            model_name="coursesubscription",
            name="is_private",
            field=models.BooleanField(default=False),
        ),
    ]
