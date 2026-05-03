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

import hashlib
import secrets
from datetime import timedelta
import os
from django.conf import settings
from django.db import models
from django.utils.timezone import now
from django.utils.translation import gettext_lazy as _
from django.utils.crypto import get_random_string

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


class VerificationChoices(models.TextChoices):
    """User group choices, may be more efficient if use django internal group"""

    REGISTER = "R", _("Register")
    AUTHENTICATE = "A", _("Authenticate")
    FUNCTION = "F", _("Function")

class VerificationCode(models.Model):
    """Activation / verification code. The ``code`` column stores a SHA-256
    hex digest; the plaintext 6-digit code is only transmitted via email and
    never persisted."""

    code = models.CharField(max_length=255, unique=True, null=True, blank=True)
    # editable datetime field with auto-now
    # https://stackoverflow.com/a/18752680/14110380
    expire_date = models.DateTimeField(default=now, null=False)
    usage = models.CharField(
        null=False,
        max_length=1,
        choices=VerificationChoices.choices,
        default=VerificationChoices.AUTHENTICATE,
    )
    function = models.CharField(max_length=255, default="", null=True)
    max_use = models.IntegerField(default=1, null=False)

    def __str__(self):
        return f'{self.code[:12]}...:{self.function}'

    @staticmethod
    def hash_code(plaintext: str) -> str:
        """Return the SHA-256 hex digest used to store / look up codes."""
        return hashlib.sha256(plaintext.strip().encode()).hexdigest()

    def generate_code(self) -> str:
        """Generate a random 6-digit code, store its hash, and return the
        plaintext so it can be emailed to the user."""
        plaintext = f"{secrets.randbelow(1_000_000):06d}"
        self.code = self.hash_code(plaintext)
        return plaintext

    def save(self, *args, **kwargs):
        if not self.code:
            # Legacy fallback — callers should use generate_code() instead.
            self.code = get_random_string(32)
        super().save(*args, **kwargs)


class InvitationCode(models.Model):
    """Admin-created invitation codes. Only the SHA-256 hash of the code is
    stored; on registration the user's input is hashed and compared.

    Create codes via the Django admin: enter the plaintext once, the model
    hashes it on save.  Distribute the plaintext out-of-band."""

    code_hash = models.CharField(
        max_length=64,
        unique=True,
        help_text="SHA-256 hex digest of the invitation code.",
    )
    label = models.CharField(
        max_length=255,
        blank=True,
        default="",
        help_text="Human-readable label (e.g. 'batch-2026-spring').",
    )
    max_uses = models.IntegerField(default=1)
    times_used = models.IntegerField(default=0)
    expire_date = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return self.label or self.code_hash[:12]

    @staticmethod
    def hash_code(plaintext: str) -> str:
        return hashlib.sha256(plaintext.strip().encode()).hexdigest()

    def is_valid(self) -> bool:
        if self.times_used >= self.max_uses:
            return False
        if self.expire_date and now() > self.expire_date:
            return False
        return True

    def consume(self) -> None:
        self.times_used += 1
        self.save(update_fields=["times_used"])

    def save(self, *args, **kwargs):
        # If someone pastes a plaintext code that isn't already 64 hex chars,
        # hash it automatically so the admin form stays friendly.
        if self.code_hash and len(self.code_hash) != 64:
            self.code_hash = self.hash_code(self.code_hash)
        super().save(*args, **kwargs)


# Inactivity window: if a session hasn't made a request in this long,
# MultiSessionAuthentication will refuse it and the user has to re-login.
SESSION_IDLE_TIMEOUT = timedelta(days=1)
# Absolute window: a session is dead this long after `created_at`
# regardless of activity. Prevents an always-online attacker from
# holding a stolen token forever.
SESSION_ABSOLUTE_TIMEOUT = timedelta(days=3)


class Session(models.Model):
    """A per-device authenticated session. Multiple rows per user means
    a user can be signed in on several devices at once and manage them
    from the Settings surface (like Telegram's "Active sessions" list).

    `key` is the opaque bearer token; the frontend sends it back via
    ``Authorization: Token <key>``. The key is 40 hex chars so the
    header shape stays identical to what the old DRF-authtoken-based
    flow used — no frontend change needed.

    Two timeouts:
      * SESSION_IDLE_TIMEOUT (1d): evicts the session if `last_seen_at`
        drifts more than 1 day behind `now()`. Rolls forward on every
        authenticated request.
      * SESSION_ABSOLUTE_TIMEOUT (3d): evicts regardless of activity,
        counted from `created_at`. Forces a fresh auth ~every 3 days.

    Expired sessions are rejected with the same "Invalid token"
    error DRF's TokenAuthentication raised, so the frontend's
    existing stale-token handling (boot-time probe → clearSession)
    continues to work unchanged.
    """

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="sessions",
    )
    key = models.CharField(
        max_length=40,
        unique=True,
        db_index=True,
        help_text="Opaque bearer token (40 hex chars). Transmitted over "
                  "the wire as ``Authorization: Token <key>``.",
    )
    device_label = models.CharField(
        max_length=120,
        blank=True,
        default="",
        help_text="Human-friendly device name for the sessions list. "
                  "Derived from the User-Agent at create-time if the "
                  "client doesn't supply one.",
    )
    user_agent = models.CharField(
        max_length=512,
        blank=True,
        default="",
        help_text="Raw User-Agent header at create-time.",
    )
    ip_hash = models.CharField(
        max_length=64,
        blank=True,
        default="",
        help_text="SHA-256 of the creating IP. Stored hashed so we can "
                  "tell 'new IP since last login' without holding the "
                  "raw address.",
    )
    created_at = models.DateTimeField(auto_now_add=True)
    last_seen_at = models.DateTimeField(default=now)
    revoked_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ("-last_seen_at",)

    def __str__(self):
        return f"Session({self.user_id}, {self.key[:8]}…, {self.device_label or '?'})"

    @classmethod
    def generate_key(cls) -> str:
        """Generate a new 40-hex-char session key."""
        return secrets.token_hex(20)

    @classmethod
    def create_for_user(cls, user, *, user_agent: str = "",
                        device_label: str = "", ip_hash: str = "") -> "Session":
        """Create and persist a brand-new Session for `user`."""
        session = cls.objects.create(
            user=user,
            key=cls.generate_key(),
            user_agent=user_agent[:512],
            device_label=(device_label or cls._label_from_user_agent(user_agent))[:120],
            ip_hash=ip_hash,
        )
        return session

    @staticmethod
    def _label_from_user_agent(user_agent: str) -> str:
        """Crude User-Agent → device label extraction. Good enough for
        the sessions list; the user can rename later via PATCH."""
        ua = (user_agent or "").lower()
        if not ua:
            return "Unknown device"
        if "iphone" in ua:
            return "iPhone"
        if "ipad" in ua:
            return "iPad"
        if "android" in ua:
            return "Android device"
        if "macintosh" in ua or "mac os x" in ua:
            return "Mac"
        if "windows" in ua:
            return "Windows PC"
        if "linux" in ua:
            return "Linux"
        return "Web browser"

    def is_active(self, *, at=None) -> bool:
        """True iff this session is non-revoked and not past either
        timeout at the given reference time (defaults to now())."""
        t = at or now()
        if self.revoked_at is not None:
            return False
        if (t - self.last_seen_at) > SESSION_IDLE_TIMEOUT:
            return False
        if (t - self.created_at) > SESSION_ABSOLUTE_TIMEOUT:
            return False
        return True

    def touch(self) -> None:
        """Update `last_seen_at` to now. Called by
        MultiSessionAuthentication on every valid authenticated
        request so the idle-timeout rolls forward."""
        self.last_seen_at = now()
        self.save(update_fields=["last_seen_at"])

    def revoke(self) -> None:
        """Mark the session revoked. Future auth attempts using this
        key will be rejected."""
        if self.revoked_at is None:
            self.revoked_at = now()
            self.save(update_fields=["revoked_at"])


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
