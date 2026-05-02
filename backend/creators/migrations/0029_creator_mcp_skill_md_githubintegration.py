from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("creators", "0028_session"),
    ]

    operations = [
        migrations.AddField(
            model_name="creator",
            name="mcp_skill_md",
            field=models.TextField(
                blank=True,
                default="",
                help_text=(
                    "User-authored skill.md content served to MCP-connected "
                    "agents via the `instructions` field of the MCP "
                    "`initialize` response. Holds per-user import / export "
                    "preferences (where to pull external notes from, what "
                    "file format to write back, which platform to publish "
                    "to). Plain markdown."
                ),
            ),
        ),
        migrations.CreateModel(
            name="GithubIntegration",
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
                    "installation_id",
                    models.CharField(
                        help_text=(
                            "GitHub App installation id returned by the install "
                            "callback."
                        ),
                        max_length=64,
                    ),
                ),
                (
                    "account_login",
                    models.CharField(
                        blank=True,
                        default="",
                        help_text=(
                            "GitHub account login that owns the installation."
                        ),
                        max_length=80,
                    ),
                ),
                (
                    "repo_full_name",
                    models.CharField(
                        blank=True,
                        default="",
                        help_text=(
                            "`owner/repo` chosen by the user as the sync target."
                        ),
                        max_length=160,
                    ),
                ),
                (
                    "repo_default_branch",
                    models.CharField(blank=True, default="main", max_length=80),
                ),
                (
                    "access_token",
                    models.CharField(
                        blank=True,
                        default="",
                        help_text=(
                            "Latest installation access token (server-side "
                            "use only; rotates roughly every hour per GitHub "
                            "policy). Never returned by API."
                        ),
                        max_length=512,
                    ),
                ),
                ("access_token_expires_at", models.DateTimeField(blank=True, null=True)),
                ("last_push_at", models.DateTimeField(blank=True, null=True)),
                ("last_push_sha", models.CharField(blank=True, default="", max_length=64)),
                ("last_pull_at", models.DateTimeField(blank=True, null=True)),
                ("last_error", models.TextField(blank=True, default="")),
                ("created_at", models.DateTimeField(auto_now_add=True)),
                ("updated_at", models.DateTimeField(auto_now=True)),
                (
                    "creator",
                    models.OneToOneField(
                        on_delete=models.deletion.CASCADE,
                        related_name="github_integration",
                        to="creators.creator",
                    ),
                ),
            ],
        ),
    ]
