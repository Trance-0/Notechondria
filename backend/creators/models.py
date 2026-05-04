"""
Place to set up database

After you modified these files, please remember to make migrations

1. run the following command
python manage.py makemigrations members
python manage.py migrate
python manage.py runserver

2. If you modified the table too much, it is really easy to get errors,
please save the origional database and edit for postgre
"""

import os
from django.conf import settings
from django.db import models
from django.utils.translation import gettext_lazy as _

def user_profile_path(instance, filename):
    """ 
    file will be uploaded to MEDIA_ROOT/user_<id>/<filename>
    https://docs.djangoproject.com/en/dev/ref/models/fields/#django.db.models.FileField.upload_to
    """
    # return "profile_pic/user_{0}/{1}".format(instance.user.id, filename)
    # we save only one latest image.
    _name, extension = os.path.splitext(filename)
    return "user_upload/user_{0}/profile_pic/profile_latest{1}".format(instance.user_id.id, extension)

class Creator(models.Model):
    """for django built-in authentication: https://docs.djangoproject.com/en/4.2/ref/contrib/auth/"""

    # This objects contains the username, password, first_name, last_name, and email of member.
    user_id = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        # when member is delete, user would also be deleted
        on_delete=models.CASCADE,
        null=False,
    )
    image = models.ImageField(upload_to=user_profile_path, blank=True, null=False)
    motto = models.CharField(max_length=100, blank=True, null=True)
    reputation = models.IntegerField(default=0, null=False)
    exp = models.IntegerField(default=0, null=False)
    social_link = models.URLField(max_length=255, blank=True, null=True)
    credit_remains = models.IntegerField(default=0, null=False)
    editor_mode = models.CharField(
        max_length=1,
        choices=(
            ("G", _("GFM")),
            ("B", _("Blocks")),
            ("P", _("Plain Text")),
        ),
        default="P",
        null=False,
    )
    theme_preset = models.CharField(max_length=32, default="teal", null=False)
    theme_mode = models.CharField(
        max_length=1,
        choices=(
            ("S", _("System")),
            ("L", _("Light")),
            ("D", _("Dark")),
        ),
        default="S",
        null=False,
    )
    api_base_url = models.CharField(max_length=255, default="http://localhost:9080/api/v1", null=False)
    api_key_hash = models.CharField(
        max_length=64, blank=True, default="",
        help_text="SHA-256 hex digest of the user's MCP API key.",
    )
    api_key_prefix = models.CharField(
        max_length=8, blank=True, default="",
        help_text="First 8 chars of the plaintext API key (for display).",
    )
    mcp_skill_md = models.TextField(
        blank=True, default="",
        help_text=(
            "User-authored skill.md content served to MCP-connected agents "
            "via the `instructions` field of the MCP `initialize` response. "
            "Holds per-user import / export preferences (where to pull "
            "external notes from, what file format to write back, which "
            "platform to publish to). Plain markdown."
        ),
    )
    casdoor_sub = models.CharField(
        max_length=128, blank=True, default="", db_index=True,
        help_text=(
            "Soft pointer to the Casdoor user record (the `sub` / `id` "
            "claim on the JWT). Populated by `CasdoorJWTAuthentication` "
            "on first sign-in via Casdoor; left empty for accounts that "
            "still use the legacy MultiSessionAuthentication path. "
            "See docs/integrations/casdoor-migration.md."
        ),
    )
    app_settings_json = models.TextField(blank=True, default="")
    app_settings_updated_at = models.DateTimeField(blank=True, null=True)

    # last_login and date_joined automatically created by user_id, for these field, create one time value to timezone.now()
    # The field is only automatically updated when calling Model.save().
    last_login=models.DateTimeField(auto_now=True, null=False)
    # Automatically set the field to now when the object is first created. 
    date_joined=models.DateTimeField(auto_now_add=True, null=False)

    # user status is determined by the group in user attribute

    def __str__(self):
        """for better list display"""
        return f"{self.user_id.get_full_name()}"

class SocialProviderChoices(models.TextChoices):
    GOOGLE = "google", _("Google")
    GITHUB = "github", _("GitHub")


class SocialAccount(models.Model):
    """Links a Django user to an external OAuth provider account."""

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="social_accounts",
    )
    provider = models.CharField(
        max_length=16,
        choices=SocialProviderChoices.choices,
    )
    provider_uid = models.CharField(
        max_length=255,
        help_text="Unique ID from the OAuth provider (e.g. Google sub, GitHub id).",
    )
    email = models.EmailField(blank=True, default="")
    extra_data = models.JSONField(default=dict, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        unique_together = ("provider", "provider_uid")

    def __str__(self):
        return f"{self.provider}:{self.provider_uid} → {self.user.username}"


class GithubIntegration(models.Model):
    """Per-creator GitHub App installation used by the experimental
    user-profile sync feature.

    The goal of the sync is *full server-loss recovery*: a user's
    Creator profile, app settings, MCP skill, courses, notes, custom
    meta, planner events, and any other user-owned text content are
    materialized into a tracked Git repository. Static assets that we
    host (avatars, attachments, cover images) are referenced by URL or
    UUID; their bytes stay on our CDN and are not committed.

    Only the install id, the chosen repo, and last-sync metadata live
    here. The OAuth access token is held by the Django installation
    and not re-encrypted at rest beyond what the DB layer already
    provides; treat this row as a sensitive credential record.
    """

    creator = models.OneToOneField(
        Creator,
        on_delete=models.CASCADE,
        related_name="github_integration",
    )
    installation_id = models.CharField(
        max_length=64,
        help_text="GitHub App installation id returned by the install callback.",
    )
    account_login = models.CharField(
        max_length=80, blank=True, default="",
        help_text="GitHub account login that owns the installation.",
    )
    repo_full_name = models.CharField(
        max_length=160, blank=True, default="",
        help_text="`owner/repo` chosen by the user as the sync target.",
    )
    repo_default_branch = models.CharField(
        max_length=80, blank=True, default="main",
    )
    access_token = models.CharField(
        max_length=512, blank=True, default="",
        help_text=(
            "Latest installation access token (server-side use only; "
            "rotates roughly every hour per GitHub policy). Never "
            "returned by API."
        ),
    )
    access_token_expires_at = models.DateTimeField(blank=True, null=True)
    last_push_at = models.DateTimeField(blank=True, null=True)
    last_push_sha = models.CharField(max_length=64, blank=True, default="")
    last_pull_at = models.DateTimeField(blank=True, null=True)
    last_error = models.TextField(blank=True, default="")
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self) -> str:
        return f"GithubIntegration({self.creator}, {self.repo_full_name or '<no repo>'})"
