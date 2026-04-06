from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("creators", "0024_creator_app_settings"),
    ]

    operations = [
        migrations.CreateModel(
            name="InvitationCode",
            fields=[
                (
                    "id",
                    models.BigAutoField(
                        auto_created=True,
                        primary_key=True,
                        serialize=False,
                        verbose_name="ID",
                    ),
                ),
                (
                    "code_hash",
                    models.CharField(
                        help_text="SHA-256 hex digest of the invitation code.",
                        max_length=64,
                        unique=True,
                    ),
                ),
                (
                    "label",
                    models.CharField(
                        blank=True,
                        default="",
                        help_text="Human-readable label (e.g. 'batch-2026-spring').",
                        max_length=255,
                    ),
                ),
                ("max_uses", models.IntegerField(default=1)),
                ("times_used", models.IntegerField(default=0)),
                ("expire_date", models.DateTimeField(blank=True, null=True)),
                ("created_at", models.DateTimeField(auto_now_add=True)),
            ],
        ),
    ]
