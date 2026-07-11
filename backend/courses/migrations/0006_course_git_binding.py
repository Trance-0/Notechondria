from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("courses", "0005_coursesubscription_is_private"),
    ]

    operations = [
        migrations.AddField(
            model_name="course",
            name="git_provider",
            field=models.CharField(
                choices=[("github", "GitHub")],
                default="github",
                max_length=16,
            ),
        ),
        migrations.AddField(
            model_name="course",
            name="git_repo",
            field=models.CharField(blank=True, max_length=255, null=True),
        ),
        migrations.AddField(
            model_name="course",
            name="git_branch",
            field=models.CharField(
                blank=True, default="main", max_length=255, null=True
            ),
        ),
        migrations.AddField(
            model_name="course",
            name="git_sync_enabled",
            field=models.BooleanField(default=False),
        ),
        migrations.AddField(
            model_name="course",
            name="git_sync_timeout_minutes",
            field=models.PositiveIntegerField(default=5),
        ),
        migrations.AddField(
            model_name="course",
            name="git_pending_since",
            field=models.DateTimeField(blank=True, null=True),
        ),
        migrations.AddField(
            model_name="course",
            name="git_last_synced_at",
            field=models.DateTimeField(blank=True, null=True),
        ),
        migrations.AddField(
            model_name="course",
            name="git_last_sync_error",
            field=models.CharField(blank=True, max_length=512, null=True),
        ),
    ]
