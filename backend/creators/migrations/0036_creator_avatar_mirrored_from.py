from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("creators", "0035_creator_last_seen_versions"),
    ]

    operations = [
        migrations.AddField(
            model_name="creator",
            name="avatar_mirrored_from",
            field=models.URLField(blank=True, default="", max_length=512),
        ),
    ]
