from django.conf import settings
from django.db import migrations, models
from django.utils.timezone import now


class Migration(migrations.Migration):

    dependencies = [
        ("creators", "0027_creator_api_key"),
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]

    operations = [
        migrations.CreateModel(
            name="Session",
            fields=[
                ("id", models.AutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                ("key", models.CharField(
                    db_index=True,
                    help_text=(
                        "Opaque bearer token (40 hex chars). Transmitted over "
                        "the wire as ``Authorization: Token <key>``."
                    ),
                    max_length=40,
                    unique=True,
                )),
                ("device_label", models.CharField(
                    blank=True,
                    default="",
                    help_text=(
                        "Human-friendly device name for the sessions list. "
                        "Derived from the User-Agent at create-time if the "
                        "client doesn't supply one."
                    ),
                    max_length=120,
                )),
                ("user_agent", models.CharField(
                    blank=True,
                    default="",
                    help_text="Raw User-Agent header at create-time.",
                    max_length=512,
                )),
                ("ip_hash", models.CharField(
                    blank=True,
                    default="",
                    help_text=(
                        "SHA-256 of the creating IP. Stored hashed so we can "
                        "tell 'new IP since last login' without holding the "
                        "raw address."
                    ),
                    max_length=64,
                )),
                ("created_at", models.DateTimeField(auto_now_add=True)),
                ("last_seen_at", models.DateTimeField(default=now)),
                ("revoked_at", models.DateTimeField(blank=True, null=True)),
                ("user", models.ForeignKey(
                    on_delete=models.deletion.CASCADE,
                    related_name="sessions",
                    to=settings.AUTH_USER_MODEL,
                )),
            ],
            options={
                "ordering": ("-last_seen_at",),
            },
        ),
    ]
