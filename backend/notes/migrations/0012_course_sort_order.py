from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("notes", "0011_course_client_course_id"),
    ]

    operations = [
        migrations.AddField(
            model_name="course",
            name="sort_order",
            field=models.IntegerField(default=0),
        ),
        migrations.AlterModelOptions(
            name="course",
            options={"ordering": ["sort_order", "title"]},
        ),
    ]
