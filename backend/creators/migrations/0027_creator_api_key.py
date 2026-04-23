from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("creators", "0026_socialaccount"),
    ]

    operations = [
        migrations.AddField(
            model_name="creator",
            name="api_key_hash",
            field=models.CharField(
                blank=True,
                default="",
                help_text="SHA-256 hex digest of the user's MCP API key.",
                max_length=64,
            ),
        ),
        migrations.AddField(
            model_name="creator",
            name="api_key_prefix",
            field=models.CharField(
                blank=True,
                default="",
                help_text="First 8 chars of the plaintext API key (for display).",
                max_length=8,
            ),
        ),
    ]
