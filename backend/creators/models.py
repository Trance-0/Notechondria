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
