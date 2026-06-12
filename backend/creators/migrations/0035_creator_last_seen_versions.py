from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("creators", "0034_creator_uncategorized_folder_name"),
    ]

    operations = [
        migrations.AddField(
            model_name="creator",
            name="last_seen_versions",
            field=models.JSONField(
                blank=True,
                default=dict,
                help_text=(
                    "Per-app map of the newest app version whose What's-New "
                    "overlay this user has seen or skipped, e.g. "
                    '{"editor": "0.1.127", "planner": "0.1.126"}. The SPA '
                    "diffs this against its built APP_VERSION on boot to "
                    "decide which feature-update cards the user missed; "
                    "skipping the overlay also stamps the current version. "
                    "Signed-out users keep the same map in local storage only."
                ),
            ),
        ),
    ]
