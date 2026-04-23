from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("creators", "0022_creator_editor_mode"),
    ]

    operations = [
        migrations.AddField(
            model_name="creator",
            name="api_base_url",
            field=models.CharField(default="http://localhost:9080/api/v1", max_length=255),
        ),
        migrations.AddField(
            model_name="creator",
            name="theme_mode",
            field=models.CharField(
                choices=[("S", "System"), ("L", "Light"), ("D", "Dark")],
                default="S",
                max_length=1,
            ),
        ),
        migrations.AddField(
            model_name="creator",
            name="theme_preset",
            field=models.CharField(default="teal", max_length=32),
        ),
    ]
