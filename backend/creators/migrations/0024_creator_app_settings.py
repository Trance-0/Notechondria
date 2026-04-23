from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("creators", "0023_creator_theme_and_api_base"),
    ]

    operations = [
        migrations.AddField(
            model_name="creator",
            name="app_settings_json",
            field=models.TextField(blank=True, default=""),
        ),
        migrations.AddField(
            model_name="creator",
            name="app_settings_updated_at",
            field=models.DateTimeField(blank=True, null=True),
        ),
    ]
