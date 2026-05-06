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
    # 0.1.119: profile attributes refreshed from the Casdoor JWT on
    # every authenticated request. `display_name` is the user-facing
    # label preferred over `User.username` on public surfaces (note
    # author bylines, comment headers, etc.) when set; the username
    # is left untouched on every refresh because changing it would
    # break PK references and external links to /api/v1/creators/<id>.
    display_name = models.CharField(
        max_length=255, blank=True, default="",
        help_text=(
            "User-facing display name. Refreshed from the Casdoor "
            "`displayName` claim on every authenticated request. "
            "Empty = fall back to `User.first_name + last_name` and "
            "ultimately to `User.username`. Editable from settings; "
            "the next Casdoor sign-in re-overwrites local edits "
            "with whatever the IdP currently has."
        ),
    )
    avatar_url = models.URLField(
        max_length=512, blank=True, default="",
        help_text=(
            "Remote avatar URL refreshed from the Casdoor `avatar` "
            "claim. When set, the SPA prefers this over the locally-"
            "uploaded `image` so a single Casdoor profile change "
            "propagates to every Notechondria surface on next login. "
            "Empty = use the local `image`."
        ),
    )
    casdoor_profile_synced_at = models.DateTimeField(
        blank=True, null=True,
        help_text=(
            "UTC timestamp of the most recent Casdoor profile refresh "
            "(`display_name`, `avatar_url`, `User.first_name` / "
            "`last_name` / `email`). Used by the in-process throttle "
            "in `_sync_creator_from_claims` so a busy SPA doesn't "
            "stamp the row on every JWT-authenticated request."
        ),
    )
    uncategorized_folder_name = models.CharField(
        max_length=120, blank=False, default="Inbox",
        help_text=(
            "User-chosen display label for the synthetic 'no category' "
            "bucket the SPA renders at the top of the categories list. "
            "It groups every Note whose `course_id IS NULL` (the "
            "natural state for a freshly-created note and for notes "
            "left behind when their category is deleted via "
            "`SET_NULL`). Defaults to 'Inbox' for continuity with the "
            "pre-0.1.120 hard-coded Inbox category, but the field is "
            "freely editable from settings — there is no special "
            "Course row backing this bucket on the server side."
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

class LinkChallenge(models.Model):
    """Pending Casdoor identity awaiting an account-link decision.

    Created by ``CasdoorExchangeApiView`` when a verified Casdoor
    JWT arrives carrying a `sub` not yet linked to any
    ``Creator.casdoor_sub``. The SPA shows the user a choice
    dialog (gitea-style account linking): bind the Casdoor
    identity to an existing legacy account (proves ownership via
    legacy username + password) or create a brand-new
    Notechondria account (user picks a fresh password). The row is
    a one-time-use ticket — it's deleted on either path's success
    and skipped (treated as expired) past `expires_at`.

    The ``access_token`` is the Casdoor JWT we already verified,
    stashed here so the link-completion endpoints can return it
    in the standard ``auth_payload`` shape without re-exchanging
    the auth code (Casdoor codes are one-time use). Storing a
    short-lived bearer in the DB is acceptable because (a) the
    row is deleted within a few minutes either way, (b) this
    backend already trusts the same JWT in the headers of every
    authenticated request, and (c) the row is owner-keyed by the
    nonce which only the SPA that initiated the exchange knows.
    """

    nonce = models.CharField(
        max_length=64,
        unique=True,
        db_index=True,
        help_text="Cryptographically random URL-safe token returned to the "
                  "SPA in the exchange response; must be supplied verbatim "
                  "to the bind/create completion endpoints.",
    )
    sub = models.CharField(
        max_length=255,
        db_index=True,
        help_text="Casdoor user sub claim from the verified JWT — what we "
                  "stamp onto Creator.casdoor_sub once the link completes.",
    )
    casdoor_username = models.CharField(max_length=150, blank=True, default="")
    casdoor_email = models.EmailField(blank=True, default="")
    casdoor_display_name = models.CharField(max_length=255, blank=True, default="")
    casdoor_groups = models.JSONField(default=list, blank=True)
    access_token = models.TextField(
        help_text="Verified Casdoor JWT replayed back to the SPA in "
                  "auth_payload after the link completes.",
    )
    created_at = models.DateTimeField(auto_now_add=True)
    expires_at = models.DateTimeField(
        help_text="UTC; the bind/create endpoints reject the row past this.",
    )

    class Meta:
        # Indexed by nonce + (sub, expires_at) for the two hot lookups:
        # the completion endpoints fetch by nonce, and the cleanup job
        # may sweep expired rows by (sub, expires_at).
        indexes = [
            models.Index(fields=["sub", "expires_at"]),
        ]

    def __str__(self):
        return f"LinkChallenge sub={self.sub[:12]}… expires_at={self.expires_at}"

    def is_expired(self):
        from django.utils import timezone
        return timezone.now() >= self.expires_at


# 0.1.119: SocialAccount + SocialProviderChoices removed. The pre-
# Casdoor era Google / GitHub OAuth flows used these to link a
# Django user to a provider sub; post-cutover everything goes
# through Casdoor's own provider proxy and the link is held by
# `Creator.casdoor_sub`. The `creators_socialaccount` table is
# dropped by migration 0033_drop_socialaccount.

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
