import hashlib
import json
from django.conf import settings
from django.contrib.auth import authenticate
from django.contrib.auth.models import User
from django.utils import timezone
from django.utils.timezone import now
from urllib.parse import urlparse

from rest_framework import permissions, serializers, status
from rest_framework.authtoken.models import Token
from rest_framework.parsers import FormParser, JSONParser, MultiPartParser
from rest_framework.response import Response
from rest_framework.views import APIView

import logging
import requests as http_requests

from .models import (
    InvitationCode,
    Session,
    SESSION_ABSOLUTE_TIMEOUT,
    SESSION_IDLE_TIMEOUT,
    VerificationChoices,
    VerificationCode,
)
from .utils import (
    _send_code_email,
    ensure_creator,
    ensure_creator_avatar,
    issue_password_reset_code,
    issue_registration_code,
    send_password_reset_email,
    send_registration_email,
)


def absolute_media_url(request, raw_url: str) -> str:
    if not raw_url:
        return ""
    if raw_url.startswith("http://") or raw_url.startswith("https://"):
        return raw_url
    if request is None:
        return raw_url
    host = (
        request.META.get("HTTP_X_FORWARDED_HOST")
        or request.META.get("HTTP_HOST")
        or request.get_host()
    )
    scheme = request.META.get("HTTP_X_FORWARDED_PROTO") or request.scheme
    normalized = raw_url if raw_url.startswith("/") else f"/{raw_url}"
    if host:
        return f"{scheme}://{host}{normalized}"
    return request.build_absolute_uri(normalized)


def creator_app_settings_payload(creator):
    payload = {
        "theme_preset": creator.theme_preset,
        "theme_mode": creator.theme_mode,
        "api_base_url": creator.api_base_url,
    }
    if creator.app_settings_json:
        try:
            decoded = json.loads(creator.app_settings_json)
        except json.JSONDecodeError:
            decoded = {}
        if isinstance(decoded, dict):
            payload.update(decoded)
    return payload


def auth_payload(user: User, request=None):
    """Mint a fresh session for *user* and return the response body the
    frontend expects after a successful login / register / OAuth call.

    ``token`` is the new ``Session.key`` — same wire shape
    (``Authorization: Token <hex>``) as the old DRF-authtoken flow, but
    backed by ``creators.Session`` so the user can be signed in on
    multiple devices simultaneously. The response also includes:

    - ``session.id`` — so the frontend can highlight the current row
      in the Active Sessions list.
    - ``session.device_label`` — derived from User-Agent at create-time.
    - ``multi_device`` — ``true`` when the user already had another
      active (non-revoked, non-expired) session at the time this one
      was minted. The frontend uses this to show a "you've signed in
      on another device" warning.
    - ``other_sessions_count`` — count of other active sessions.
    """
    # Use the request User-Agent + X-Forwarded-For to seed the session
    # metadata. Everything here is best-effort — missing headers just
    # collapse to empty strings / "Unknown device".
    user_agent = ""
    ip_hash = ""
    if request is not None:
        user_agent = request.META.get("HTTP_USER_AGENT", "") or ""
        raw_ip = request.META.get("HTTP_X_FORWARDED_FOR", "") or request.META.get("REMOTE_ADDR", "") or ""
        # Take only the first hop of X-Forwarded-For (the original client).
        raw_ip = raw_ip.split(",")[0].strip()
        if raw_ip:
            ip_hash = hashlib.sha256(raw_ip.encode()).hexdigest()
    session = Session.create_for_user(
        user,
        user_agent=user_agent,
        ip_hash=ip_hash,
    )
    now_ts = timezone.now()
    other_active = Session.objects.filter(
        user=user,
        revoked_at__isnull=True,
        last_seen_at__gt=now_ts - SESSION_IDLE_TIMEOUT,
        created_at__gt=now_ts - SESSION_ABSOLUTE_TIMEOUT,
    ).exclude(pk=session.pk).count()
    creator = ensure_creator_avatar(ensure_creator(user))
    return {
        "token": session.key,
        "session": {
            "id": session.id,
            "device_label": session.device_label,
            "created_at": session.created_at.isoformat(),
            "last_seen_at": session.last_seen_at.isoformat(),
        },
        "multi_device": other_active > 0,
        "other_sessions_count": other_active,
        "user": {
            "id": user.id,
            "email": user.email,
            "username": user.username,
            "first_name": user.first_name,
            "last_name": user.last_name,
            "display_name": f"{user.first_name} {user.last_name}".strip() or user.username,
            "is_staff": user.is_staff,
            "is_superuser": user.is_superuser,
            "motto": creator.motto or "",
            "social_link": creator.social_link or "",
            "image_url": absolute_media_url(request, creator.image.url if creator.image else ""),
            "editor_mode": creator.editor_mode,
            "theme_preset": creator.theme_preset,
            "theme_mode": creator.theme_mode,
            "api_base_url": creator.api_base_url,
            "app_settings": creator_app_settings_payload(creator),
            "app_settings_updated_at": creator.app_settings_updated_at.isoformat()
            if creator.app_settings_updated_at
            else None,
        },
    }


class RegisterSerializer(serializers.Serializer):
    username = serializers.RegexField(
        r'^[a-zA-Z0-9_-]+$',
        min_length=3,
        max_length=150,
        help_text="Alphanumeric, hyphens, and underscores only.",
    )
    email = serializers.EmailField()
    password = serializers.CharField(write_only=True, min_length=8)
    invitation_code = serializers.CharField(write_only=True, required=False, allow_blank=True)

    def validate_username(self, value):
        if User.objects.filter(username__iexact=value).exists():
            raise serializers.ValidationError(
                "Registration rejected: "
                "Backend.Creators.Auth/register.validate_username \u2014 "
                "this username is already taken."
            )
        return value

    def validate_email(self, value):
        existing = User.objects.filter(email__iexact=value).first()
        if existing and existing.is_active:
            raise serializers.ValidationError(
                "Registration rejected: "
                "Backend.Creators.Auth/register.validate_email \u2014 "
                "a verified account already exists for this email."
            )
        return value.lower()

    def validate_password(self, value):
        has_upper = any(c.isupper() for c in value)
        has_lower = any(c.islower() for c in value)
        has_digit_or_special = any(not c.isalpha() for c in value)
        if not (has_upper and has_lower and has_digit_or_special):
            raise serializers.ValidationError(
                "Registration rejected: "
                "Backend.Creators.Auth/register.validate_password \u2014 "
                "password must contain at least one uppercase letter, "
                "one lowercase letter, and one digit or special character."
            )
        return value

    def validate_invitation_code(self, value):
        if not value:
            return value
        code_hash = InvitationCode.hash_code(value)
        invite = InvitationCode.objects.filter(code_hash=code_hash).first()
        if invite is None or not invite.is_valid():
            raise serializers.ValidationError(
                "Registration rejected: "
                "Backend.Creators.Auth/register.validate_invitation_code \u2014 "
                "invitation code is invalid or expired."
            )
        return value

    def validate(self, attrs):
        # Invitation code is required when any InvitationCode records exist
        # in the database (i.e. admin has set up the invitation system).
        if InvitationCode.objects.exists():
            code = attrs.get("invitation_code", "").strip()
            if not code:
                raise serializers.ValidationError(
                    {"invitation_code": (
                        "Registration rejected: "
                        "Backend.Creators.Auth/register.validate \u2014 "
                        "an invitation code is required because this instance "
                        "has at least one active invitation gate."
                    )}
                )
        return attrs

    def create(self, validated_data):
        username = validated_data["username"]
        email = validated_data["email"]
        password = validated_data["password"]
        invitation_raw = validated_data.get("invitation_code", "").strip()

        # Consume invitation code if provided.
        if invitation_raw:
            code_hash = InvitationCode.hash_code(invitation_raw)
            invite = InvitationCode.objects.filter(code_hash=code_hash).first()
            if invite:
                invite.consume()

        user = User.objects.filter(email__iexact=email).first()
        if user is None:
            user = User.objects.create(
                username=username,
                email=email,
                is_active=False,
            )
        else:
            user.username = username
        user.email = email
        user.is_active = False
        user.set_password(password)
        user.save()
        ensure_creator(user)
        _, plaintext = issue_registration_code(email)
        delivery = send_registration_email(email, plaintext)
        return {"user": user, "delivery": delivery}


class VerifyEmailSerializer(serializers.Serializer):
    email = serializers.EmailField()
    code = serializers.CharField()

    def validate(self, attrs):
        email = attrs["email"].lower()
        code_hash = VerificationCode.hash_code(attrs["code"])
        verification = VerificationCode.objects.filter(
            code=code_hash,
            function=email,
            usage=VerificationChoices.REGISTER,
            max_use__gt=0,
            expire_date__gt=now(),
        ).first()
        if verification is None:
            raise serializers.ValidationError(
                "Email verification failed: "
                "Backend.Creators.Auth/verify \u2014 "
                "verification code is invalid, expired, or already consumed."
            )
        user = User.objects.filter(email__iexact=email).first()
        if user is None:
            raise serializers.ValidationError(
                "Email verification failed: "
                "Backend.Creators.Auth/verify \u2014 "
                "no pending account found for this email."
            )
        attrs["user"] = user
        attrs["verification"] = verification
        return attrs


class LoginSerializer(serializers.Serializer):
    identifier = serializers.CharField(required=False)
    email = serializers.CharField(required=False)
    password = serializers.CharField(write_only=True)

    def validate(self, attrs):
        identifier = (attrs.get("identifier") or attrs.get("email") or "").strip()
        if not identifier:
            raise serializers.ValidationError(
                "Sign-in rejected: "
                "Backend.Creators.Auth/login \u2014 "
                "either email or username is required in the login payload."
            )
        matched_user = User.objects.filter(email__iexact=identifier).first()
        if matched_user is None:
            matched_user = User.objects.filter(username__iexact=identifier).first()
        username = matched_user.username if matched_user else identifier
        user = authenticate(username=username, password=attrs["password"])
        if user is None:
            raise serializers.ValidationError(
                "Sign-in rejected: "
                "Backend.Creators.Auth/login \u2014 "
                "email/username and password do not match any active account."
            )
        if not user.is_active:
            raise serializers.ValidationError(
                "Sign-in rejected: "
                "Backend.Creators.Auth/login \u2014 "
                "email verification is still pending for this account."
            )
        attrs["user"] = user
        return attrs


class ResendVerificationSerializer(serializers.Serializer):
    email = serializers.EmailField()

    def validate_email(self, value):
        user = User.objects.filter(email__iexact=value).first()
        if user is None:
            raise serializers.ValidationError(
                "Verification code not resent: "
                "Backend.Creators.Auth/resend_verification \u2014 "
                "no account found for this email."
            )
        if user.is_active:
            raise serializers.ValidationError(
                "Verification code not resent: "
                "Backend.Creators.Auth/resend_verification \u2014 "
                "this account is already verified."
            )
        # 60-second cooldown: reject if a valid code was issued less than
        # 60 seconds ago to prevent spamming the email endpoint.
        from datetime import timedelta
        recent = VerificationCode.objects.filter(
            function=value.lower(),
            usage=VerificationChoices.REGISTER,
            max_use__gt=0,
            expire_date__gt=now() - timedelta(seconds=60),
        ).order_by("-expire_date").first()
        if recent:
            ttl_hours = getattr(settings, "EMAIL_VERIFICATION_TTL_HOURS", 24)
            created_approx = recent.expire_date - timedelta(hours=ttl_hours)
            if (now() - created_approx).total_seconds() < 60:
                raise serializers.ValidationError(
                    "Verification code not resent: "
                    "Backend.Creators.Auth/resend_verification \u2014 "
                    "cooldown is active; wait 60 seconds before requesting "
                    "a new code."
                )
        return value.lower()


class SettingsSerializer(serializers.Serializer):
    username = serializers.CharField(required=False, max_length=150)
    first_name = serializers.CharField(required=False, allow_blank=True, max_length=150)
    last_name = serializers.CharField(required=False, allow_blank=True, max_length=150)
    email = serializers.EmailField(required=False)
    motto = serializers.CharField(allow_blank=True, required=False, max_length=100)
    social_link = serializers.URLField(allow_blank=True, required=False)
    image_url = serializers.CharField(read_only=True)
    avatar = serializers.ImageField(write_only=True, required=False)
    theme_preset = serializers.CharField(required=False, allow_blank=False, max_length=32)
    theme_mode = serializers.ChoiceField(
        choices=[
            ("S", "system"),
            ("L", "light"),
            ("D", "dark"),
        ],
        required=False,
    )
    api_base_url = serializers.CharField(required=False, allow_blank=False, max_length=255)
    mcp_skill_md = serializers.CharField(required=False, allow_blank=True)
    app_settings = serializers.JSONField(required=False)
    app_settings_updated_at = serializers.DateTimeField(required=False, allow_null=True)
    editor_mode = serializers.ChoiceField(
        choices=[
            ("G", "gfm"),
            ("B", "blocks"),
            ("P", "plain_text"),
        ],
        required=False,
    )

    def to_representation(self, instance):
        request = self.context.get("request") if self.context else None
        return {
            "username": instance.user_id.username,
            "first_name": instance.user_id.first_name,
            "last_name": instance.user_id.last_name,
            "email": instance.user_id.email,
            "is_staff": instance.user_id.is_staff,
            "is_superuser": instance.user_id.is_superuser,
            "motto": instance.motto or "",
            "social_link": instance.social_link or "",
            "image_url": absolute_media_url(request, instance.image.url if instance.image else ""),
            "editor_mode": instance.editor_mode,
            "theme_preset": instance.theme_preset,
            "theme_mode": instance.theme_mode,
            "api_key_prefix": instance.api_key_prefix or "",
            "api_base_url": instance.api_base_url,
            "mcp_skill_md": instance.mcp_skill_md or "",
            "casdoor_linked": bool(instance.casdoor_sub),
            "app_settings": creator_app_settings_payload(instance),
            "app_settings_updated_at": instance.app_settings_updated_at.isoformat()
            if instance.app_settings_updated_at
            else None,
        }

    def validate_username(self, value):
        user = self.instance.user_id if self.instance is not None else None
        existing = User.objects.filter(username__iexact=value).exclude(pk=user.pk if user else None).first()
        if existing is not None:
            raise serializers.ValidationError(
                "Settings not saved: "
                "Backend.Creators.Settings/update.validate_username \u2014 "
                "this username is already in use by another account."
            )
        return value

    def validate_email(self, value):
        user = self.instance.user_id if self.instance is not None else None
        if user is not None and user.email.lower() == value.lower():
            return user.email
        existing = User.objects.filter(email__iexact=value).exclude(pk=user.pk if user else None).first()
        if existing is not None:
            raise serializers.ValidationError(
                "Settings not saved: "
                "Backend.Creators.Settings/update.validate_email \u2014 "
                "this email is already in use by another account."
            )
        return value.lower()

    def validate_api_base_url(self, value):
        normalized = value.strip()
        parsed = urlparse(normalized)
        if parsed.scheme not in {"http", "https"} or not parsed.netloc:
            raise serializers.ValidationError(
                "Settings not saved: "
                "Backend.Creators.Settings/update.validate_api_base_url \u2014 "
                "value must be a full http:// or https:// URL with a host."
            )
        return normalized

    def update(self, instance, validated_data):
        user = instance.user_id
        user_dirty = False
        if "username" in validated_data:
            user.username = validated_data["username"]
            user_dirty = True
        if "email" in validated_data:
            user.email = validated_data["email"]
            user_dirty = True
        if "first_name" in validated_data:
            user.first_name = validated_data["first_name"]
            user_dirty = True
        if "last_name" in validated_data:
            user.last_name = validated_data["last_name"]
            user_dirty = True
        if user_dirty:
            user.save(update_fields=["username", "email", "first_name", "last_name"])
        instance.motto = validated_data.get("motto", instance.motto)
        instance.social_link = validated_data.get("social_link", instance.social_link)
        instance.editor_mode = validated_data.get("editor_mode", instance.editor_mode)
        if "mcp_skill_md" in validated_data:
            instance.mcp_skill_md = validated_data["mcp_skill_md"]
        if "avatar" in validated_data:
            instance.image = validated_data["avatar"]
        app_settings = creator_app_settings_payload(instance)
        if "app_settings" in validated_data and isinstance(validated_data["app_settings"], dict):
            app_settings.update(validated_data["app_settings"])
        if "theme_preset" in validated_data:
            app_settings["theme_preset"] = validated_data["theme_preset"]
        if "theme_mode" in validated_data:
            app_settings["theme_mode"] = validated_data["theme_mode"]
        if "api_base_url" in validated_data:
            app_settings["api_base_url"] = validated_data["api_base_url"]
        instance.theme_preset = app_settings.get("theme_preset", instance.theme_preset)
        instance.theme_mode = app_settings.get("theme_mode", instance.theme_mode)
        instance.api_base_url = app_settings.get("api_base_url", instance.api_base_url)
        if (
            "app_settings" in validated_data
            or "theme_preset" in validated_data
            or "theme_mode" in validated_data
            or "api_base_url" in validated_data
        ):
            instance.app_settings_json = json.dumps(app_settings, sort_keys=True)
            instance.app_settings_updated_at = validated_data.get("app_settings_updated_at") or now()
        instance.save()
        return instance


class PasswordResetRequestSerializer(serializers.Serializer):
    email = serializers.EmailField()

    def validate_email(self, value):
        user = User.objects.filter(email__iexact=value).first()
        if user is None:
            raise serializers.ValidationError(
                "Password reset email not sent: "
                "Backend.Creators.Auth/password.reset.request \u2014 "
                "no account found for this email."
            )
        return value.lower()


class PasswordResetConfirmSerializer(serializers.Serializer):
    email = serializers.EmailField()
    code = serializers.CharField()
    password = serializers.CharField(write_only=True, min_length=8)

    def validate(self, attrs):
        email = attrs["email"].lower()
        code_hash = VerificationCode.hash_code(attrs["code"])
        verification = VerificationCode.objects.filter(
            code=code_hash,
            function=f"password_reset:{email}",
            usage=VerificationChoices.FUNCTION,
            max_use__gt=0,
            expire_date__gt=now(),
        ).first()
        if verification is None:
            raise serializers.ValidationError(
                "Password not updated: "
                "Backend.Creators.Auth/password.reset.confirm \u2014 "
                "reset code is invalid, expired, or already consumed."
            )
        user = User.objects.filter(email__iexact=email).first()
        if user is None:
            raise serializers.ValidationError(
                "Password not updated: "
                "Backend.Creators.Auth/password.reset.confirm \u2014 "
                "no account found for this email."
            )
        attrs["user"] = user
        attrs["verification"] = verification
        return attrs


class RegisterApiView(APIView):
    permission_classes = [permissions.AllowAny]

    def post(self, request):
        serializer = RegisterSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        result = serializer.save()
        user = result["user"]
        delivery = result["delivery"]
        return Response(
            {
                "message": delivery["message"],
                "delivery_fallback": delivery["fallback"],
                "email": user.email,
            },
            status=status.HTTP_201_CREATED,
        )


class ValidateInvitationApiView(APIView):
    """Check whether an invitation code is required and, if provided, valid.

    Returns ``{"required": bool, "valid": bool}``.  The code is **not**
    consumed — consumption happens during registration or OAuth sign-up.
    """
    permission_classes = [permissions.AllowAny]

    def post(self, request):
        required = InvitationCode.objects.exists()
        code = (request.data.get("invitation_code") or "").strip()
        if not required:
            return Response({"required": False, "valid": True})
        if not code:
            return Response({"required": True, "valid": False})
        code_hash = InvitationCode.hash_code(code)
        invite = InvitationCode.objects.filter(code_hash=code_hash).first()
        valid = invite is not None and invite.is_valid()
        return Response({"required": True, "valid": valid})


class VerifyEmailApiView(APIView):
    permission_classes = [permissions.AllowAny]

    def post(self, request):
        serializer = VerifyEmailSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        user = serializer.validated_data["user"]
        verification = serializer.validated_data["verification"]
        user.is_active = True
        user.save(update_fields=["is_active"])
        verification.max_use = 0
        verification.save(update_fields=["max_use"])
        # First successful verification — make sure the new account lands on a
        # non-empty workspace. The helper is idempotent, so re-verifying an
        # existing account never duplicates the welcome note.
        from notes.services import seed_inbox_and_welcome_note
        seed_inbox_and_welcome_note(ensure_creator(user))
        return Response(auth_payload(user, request=request))


class ResendVerificationApiView(APIView):
    permission_classes = [permissions.AllowAny]

    def post(self, request):
        serializer = ResendVerificationSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        email = serializer.validated_data["email"]
        _, plaintext = issue_registration_code(email)
        delivery = send_registration_email(email, plaintext)
        return Response(
            {
                "message": delivery["message"],
                "delivery_fallback": delivery["fallback"],
            }
        )


class LoginApiView(APIView):
    permission_classes = [permissions.AllowAny]

    def post(self, request):
        serializer = LoginSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        return Response(auth_payload(serializer.validated_data["user"], request=request))


class PasswordResetRequestApiView(APIView):
    permission_classes = [permissions.AllowAny]

    def post(self, request):
        serializer = PasswordResetRequestSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        email = serializer.validated_data["email"]
        _, plaintext = issue_password_reset_code(email)
        delivery = send_password_reset_email(email, plaintext)
        return Response(
            {
                "message": delivery["message"],
                "delivery_fallback": delivery["fallback"],
                "email": email,
            }
        )


class PasswordResetConfirmApiView(APIView):
    permission_classes = [permissions.AllowAny]

    def post(self, request):
        serializer = PasswordResetConfirmSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        user = serializer.validated_data["user"]
        verification = serializer.validated_data["verification"]
        user.set_password(serializer.validated_data["password"])
        user.save(update_fields=["password"])
        verification.max_use = 0
        verification.save(update_fields=["max_use"])
        return Response({"message": "Password updated. You can now log in."})


class SendIdentityCodeApiView(APIView):
    """Send a 6-digit verification code to the authenticated user's current
    email.  Used as a pre-step before sensitive account changes (email /
    password)."""
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request):
        email = request.user.email
        if not email:
            return Response(
                {"detail": "No email address on file for this account."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        # Invalidate any outstanding identity codes for this user.
        VerificationCode.objects.filter(
            usage=VerificationChoices.FUNCTION,
            function=f"verify_identity:{request.user.id}",
        ).update(max_use=0)
        from datetime import timedelta
        vc = VerificationCode(
            expire_date=now() + timedelta(hours=settings.EMAIL_VERIFICATION_TTL_HOURS),
            usage=VerificationChoices.FUNCTION,
            function=f"verify_identity:{request.user.id}",
        )
        plaintext = vc.generate_code()
        vc.save()
        delivery = _send_code_email(
            email,
            plaintext,
            subject="Verify your identity \u2013 Notechondria",
            intro="Use this code to verify your identity before making account changes.",
            action_label="Open settings",
        )
        # Mask email for the frontend display.
        at = email.find("@")
        masked = email[0] + "***" + email[at:] if at > 0 else "***"
        return Response({
            "message": delivery["message"],
            "delivery_fallback": delivery.get("fallback", False),
            "masked_email": masked,
        })


def _consume_identity_code(user, code_value):
    """Validate and consume an identity-verification code.
    Returns the ``VerificationCode`` on success, or ``None`` if invalid."""
    if not code_value:
        return None
    code_hash = VerificationCode.hash_code(code_value)
    vc = VerificationCode.objects.filter(
        code=code_hash,
        function=f"verify_identity:{user.id}",
        usage=VerificationChoices.FUNCTION,
        max_use__gt=0,
        expire_date__gt=now(),
    ).first()
    if vc is not None:
        vc.max_use = 0
        vc.save(update_fields=["max_use"])
    return vc


class ChangePasswordSerializer(serializers.Serializer):
    current_password = serializers.CharField(write_only=True)
    new_password = serializers.CharField(write_only=True, min_length=8)
    identity_code = serializers.CharField(write_only=True)

    def validate_new_password(self, value):
        has_upper = any(c.isupper() for c in value)
        has_lower = any(c.islower() for c in value)
        has_other = any(not c.isalpha() for c in value)
        if not (has_upper and has_lower and has_other):
            raise serializers.ValidationError(
                "Password not updated: "
                "Backend.Creators.Auth/password.change.validate \u2014 "
                "password must contain at least one uppercase letter, one "
                "lowercase letter, and one digit or special character."
            )
        return value


class ChangePasswordApiView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request):
        serializer = ChangePasswordSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        user = request.user
        # Verify identity code (sent to current email).
        vc = _consume_identity_code(user, serializer.validated_data["identity_code"])
        if vc is None:
            return Response(
                {"detail": (
                    "Password not updated: "
                    "Backend.Creators.Auth/password.change \u2014 "
                    "identity verification code is invalid, expired, or "
                    "already consumed."
                )},
                status=status.HTTP_400_BAD_REQUEST,
            )
        if not user.check_password(serializer.validated_data["current_password"]):
            return Response(
                {"detail": (
                    "Password not updated: "
                    "Backend.Creators.Auth/password.change \u2014 "
                    "current password does not match."
                )},
                status=status.HTTP_400_BAD_REQUEST,
            )
        user.set_password(serializer.validated_data["new_password"])
        user.save(update_fields=["password"])
        # Revoke every existing session so the old password can't hold
        # any device online. Then mint a brand-new session for THIS
        # request and return its key so the caller doesn't get logged
        # out of the device they're changing the password on.
        Session.objects.filter(user=user, revoked_at__isnull=True).update(
            revoked_at=timezone.now(),
        )
        # Legacy DRF Token cleanup; harmless no-op once the table is empty.
        Token.objects.filter(user=user).delete()
        user_agent = request.META.get("HTTP_USER_AGENT", "") or ""
        ip_raw = (
            request.META.get("HTTP_X_FORWARDED_FOR", "")
            or request.META.get("REMOTE_ADDR", "")
            or ""
        ).split(",")[0].strip()
        ip_hash = hashlib.sha256(ip_raw.encode()).hexdigest() if ip_raw else ""
        fresh = Session.create_for_user(
            user, user_agent=user_agent, ip_hash=ip_hash,
        )
        return Response({
            "message": (
                "Password changed: "
                "Backend.Creators.Auth/password.change \u2014 "
                "session token rotated; previous sessions invalidated."
            ),
            "token": fresh.key,
            "session": {
                "id": fresh.id,
                "device_label": fresh.device_label,
                "created_at": fresh.created_at.isoformat(),
                "last_seen_at": fresh.last_seen_at.isoformat(),
            },
        })


class ChangeEmailRequestSerializer(serializers.Serializer):
    new_email = serializers.EmailField()
    identity_code = serializers.CharField()

    def validate_new_email(self, value):
        normalised = value.lower()
        if User.objects.filter(email__iexact=normalised).exists():
            raise serializers.ValidationError(
                "Email change aborted: "
                "Backend.Creators.Auth/email.change.request \u2014 "
                "this email is already in use by another account."
            )
        return normalised


class ChangeEmailConfirmSerializer(serializers.Serializer):
    new_email = serializers.EmailField()
    code = serializers.CharField()

    def validate(self, attrs):
        email = attrs["new_email"].lower()
        code_hash = VerificationCode.hash_code(attrs["code"])
        verification = VerificationCode.objects.filter(
            code=code_hash,
            function=f"change_email:{email}",
            usage=VerificationChoices.FUNCTION,
            max_use__gt=0,
            expire_date__gt=now(),
        ).first()
        if verification is None:
            raise serializers.ValidationError(
                "Email change aborted: "
                "Backend.Creators.Auth/email.change.confirm \u2014 "
                "verification code is invalid, expired, or already consumed."
            )
        if User.objects.filter(email__iexact=email).exists():
            raise serializers.ValidationError(
                "Email change aborted: "
                "Backend.Creators.Auth/email.change.confirm \u2014 "
                "this email is already in use by another account."
            )
        attrs["verification"] = verification
        return attrs


class ChangeEmailApiView(APIView):
    """Two-step email change: POST without `code` sends a verification code to
    the new email.  POST with `code` confirms and updates the email."""
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request):
        if "code" in request.data and request.data["code"]:
            return self._confirm(request)
        return self._request(request)

    def _request(self, request):
        serializer = ChangeEmailRequestSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        # Verify identity code (sent to current email).
        vc = _consume_identity_code(request.user, serializer.validated_data["identity_code"])
        if vc is None:
            return Response(
                {"detail": "Invalid or expired identity verification code."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        new_email = serializer.validated_data["new_email"]
        # Invalidate old change-email codes for this address.
        VerificationCode.objects.filter(
            usage=VerificationChoices.FUNCTION,
            function=f"change_email:{new_email}",
        ).update(max_use=0)
        from datetime import timedelta
        vc = VerificationCode(
            expire_date=now() + timedelta(hours=settings.EMAIL_VERIFICATION_TTL_HOURS),
            usage=VerificationChoices.FUNCTION,
            function=f"change_email:{new_email}",
        )
        plaintext = vc.generate_code()
        vc.save()
        from .utils import _send_code_email
        delivery = _send_code_email(
            new_email,
            plaintext,
            subject="Confirm your new Notechondria email",
            intro="Use this code to confirm your new email address.",
            action_label="Open settings",
        )
        return Response({
            "message": delivery["message"],
            "delivery_fallback": delivery.get("fallback", False),
            "email": new_email,
        })

    def _confirm(self, request):
        serializer = ChangeEmailConfirmSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        new_email = serializer.validated_data["new_email"]
        verification = serializer.validated_data["verification"]
        user = request.user
        user.email = new_email
        user.save(update_fields=["email"])
        verification.max_use = 0
        verification.save(update_fields=["max_use"])
        return Response({"message": "Email updated.", "email": new_email})


class LogoutApiView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request):
        # Revoke ONLY the session behind the current request, not
        # every session the user owns. `MultiSessionAuthentication`
        # attaches `request.auth_session` on successful auth.
        # Sign-out on device A should not sign out device B — that's
        # what SessionRevokeApiView is for.
        current = getattr(request, "auth_session", None)
        if current is not None:
            current.revoke()
        # Fallback for legacy DRF-Token callers: clean those up too.
        # Harmless when the table is empty (post-0.1.65 flow).
        Token.objects.filter(user=request.user).delete()
        return Response(status=status.HTTP_204_NO_CONTENT)


def _serialize_session(session, *, current_id=None):
    """Wire-format for Active Sessions list. Never includes the raw
    `key` — that's the bearer token. The client only needs the id to
    revoke, and metadata to display."""
    return {
        "id": session.id,
        "device_label": session.device_label,
        "user_agent": session.user_agent,
        "ip_hash_prefix": session.ip_hash[:8] if session.ip_hash else "",
        "created_at": session.created_at.isoformat(),
        "last_seen_at": session.last_seen_at.isoformat(),
        "is_current": current_id is not None and session.id == current_id,
    }


class SessionListApiView(APIView):
    """GET /api/v1/auth/sessions/ — list the caller's active sessions.

    Returns every non-revoked, non-expired row belonging to the
    authenticated user, ordered by most-recently-active first. The
    entry whose id matches the caller's own session is flagged
    ``is_current: true`` so the UI can label it "This device" and
    hide / style the revoke button appropriately.
    """
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        now_ts = timezone.now()
        qs = Session.objects.filter(
            user=request.user,
            revoked_at__isnull=True,
            last_seen_at__gt=now_ts - SESSION_IDLE_TIMEOUT,
            created_at__gt=now_ts - SESSION_ABSOLUTE_TIMEOUT,
        ).order_by("-last_seen_at")
        current = getattr(request, "auth_session", None)
        current_id = current.id if current is not None else None
        return Response({
            "sessions": [_serialize_session(s, current_id=current_id) for s in qs],
            "current_session_id": current_id,
        })


class SessionRevokeApiView(APIView):
    """DELETE /api/v1/auth/sessions/<int:session_id>/ — revoke a
    specific session.

    Only the OWNER can revoke; trying to revoke someone else's session
    returns 404 (not 403 — we don't leak whether the id exists).
    Revoking your CURRENT session is permitted: the caller is
    effectively signing themselves out from this device, same as
    /auth/logout/.
    """
    permission_classes = [permissions.IsAuthenticated]

    def delete(self, request, session_id: int):
        try:
            session = Session.objects.get(pk=session_id, user=request.user)
        except Session.DoesNotExist:
            return Response(
                {"detail": "Session not found."},
                status=status.HTTP_404_NOT_FOUND,
            )
        session.revoke()
        return Response(status=status.HTTP_204_NO_CONTENT)


class SessionApiView(APIView):
    # Same rationale as the 0.1.64 fix: empty authentication_classes so
    # DRF's default chain doesn't 401 this endpoint on a stale token
    # before the view can answer. The view inspects the Authorization
    # header itself and returns 200 with ``{"authenticated": false}``
    # for any missing / malformed / unrecognised / expired / revoked
    # token. As of 0.1.65 the lookup is against ``creators.Session``
    # (multi-device) instead of ``rest_framework.authtoken.Token``.
    #
    # Important: this probe does NOT mint a new session and does NOT
    # roll the idle window forward — we only return the token the
    # frontend gave us if it's still valid, so the caller knows
    # whether their saved credential is still good.
    authentication_classes = []
    permission_classes = [permissions.AllowAny]

    def get(self, request):
        header = request.META.get("HTTP_AUTHORIZATION", "") or ""
        parts = header.split(None, 1)
        if len(parts) != 2 or parts[0].lower() != "token" or not parts[1].strip():
            return Response({"authenticated": False})
        key = parts[1].strip()
        try:
            session = Session.objects.select_related("user").get(key=key)
        except Session.DoesNotExist:
            return Response({"authenticated": False})
        if not session.is_active():
            return Response({"authenticated": False})
        user = session.user
        if not user.is_active:
            return Response({"authenticated": False})
        # Echo back the user payload plus the existing session key, so
        # the frontend's `_restoreSession` can reuse it without a fresh
        # mint. We piggy-back on auth_payload's user-side shape but
        # override token/session fields with the ALREADY-active row.
        creator = ensure_creator_avatar(ensure_creator(user))
        now_ts = timezone.now()
        other_active = Session.objects.filter(
            user=user,
            revoked_at__isnull=True,
            last_seen_at__gt=now_ts - SESSION_IDLE_TIMEOUT,
            created_at__gt=now_ts - SESSION_ABSOLUTE_TIMEOUT,
        ).exclude(pk=session.pk).count()
        return Response({
            "authenticated": True,
            "token": session.key,
            "session": {
                "id": session.id,
                "device_label": session.device_label,
                "created_at": session.created_at.isoformat(),
                "last_seen_at": session.last_seen_at.isoformat(),
            },
            "multi_device": other_active > 0,
            "other_sessions_count": other_active,
            "user": {
                "id": user.id,
                "email": user.email,
                "username": user.username,
                "first_name": user.first_name,
                "last_name": user.last_name,
                "display_name": f"{user.first_name} {user.last_name}".strip() or user.username,
                "is_staff": user.is_staff,
                "is_superuser": user.is_superuser,
                "motto": creator.motto or "",
                "social_link": creator.social_link or "",
                "image_url": absolute_media_url(request, creator.image.url if creator.image else ""),
                "editor_mode": creator.editor_mode,
                "theme_preset": creator.theme_preset,
                "theme_mode": creator.theme_mode,
                "api_base_url": creator.api_base_url,
                "app_settings": creator_app_settings_payload(creator),
                "app_settings_updated_at": creator.app_settings_updated_at.isoformat()
                if creator.app_settings_updated_at
                else None,
            },
        })


class SettingsApiView(APIView):
    permission_classes = [permissions.IsAuthenticated]
    parser_classes = [MultiPartParser, FormParser, JSONParser]

    def get(self, request):
        creator = ensure_creator_avatar(ensure_creator(request.user))
        return Response(SettingsSerializer(creator, context={"request": request}).data)

    def patch(self, request):
        creator = ensure_creator_avatar(ensure_creator(request.user))
        serializer = SettingsSerializer(
            instance=creator,
            data=request.data,
            partial=True,
            context={"request": request},
        )
        serializer.is_valid(raise_exception=True)
        serializer.save()
        return Response(SettingsSerializer(creator, context={"request": request}).data)


class RotateApiKeyApiView(APIView):
    """Generate a new MCP API key for the authenticated user.

    POST /api/v1/auth/rotate-api-key/
    Returns the plaintext key ONCE.  Only the SHA-256 hash is stored.
    """
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request):
        import hashlib
        import secrets
        creator = ensure_creator(request.user)
        plaintext = f"ntc_{secrets.token_hex(16)}"  # 32 hex chars after prefix
        creator.api_key_hash = hashlib.sha256(plaintext.encode()).hexdigest()
        creator.api_key_prefix = plaintext[:8]
        creator.save(update_fields=["api_key_hash", "api_key_prefix"])
        return Response({
            "api_key": plaintext,
            "api_key_prefix": creator.api_key_prefix,
        })


logger = logging.getLogger("django")


# ---------------------------------------------------------------------------
# Experimental: GitHub data-sync integration
# ---------------------------------------------------------------------------


class GithubSyncStatusApiView(APIView):
    """GET the current install/status for the authenticated user."""

    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        from .models import GithubIntegration

        creator = ensure_creator(request.user)
        integration = GithubIntegration.objects.filter(creator=creator).first()
        install_url = settings.GITHUB_DATA_SYNC_APP_INSTALL_URL or ""
        if not integration:
            return Response({
                "connected": False,
                "install_url": install_url,
                "app_name": settings.GITHUB_DATA_SYNC_APP_NAME or "",
            })
        return Response({
            "connected": True,
            "install_url": install_url,
            "app_name": settings.GITHUB_DATA_SYNC_APP_NAME or "",
            "account_login": integration.account_login,
            "repo_full_name": integration.repo_full_name,
            "repo_default_branch": integration.repo_default_branch,
            "last_push_at": integration.last_push_at.isoformat()
            if integration.last_push_at
            else None,
            "last_push_sha": integration.last_push_sha,
            "last_error": integration.last_error or "",
        })

    def delete(self, request):
        """Disconnect the App installation. Does NOT uninstall the App
        on GitHub's side — the user must do that from their GitHub
        settings; we just drop our record so the local UI shows
        disconnected."""
        from .models import GithubIntegration

        creator = ensure_creator(request.user)
        GithubIntegration.objects.filter(creator=creator).delete()
        return Response({"connected": False})


class GithubSyncCallbackSerializer(serializers.Serializer):
    installation_id = serializers.CharField(max_length=64)
    account_login = serializers.CharField(
        max_length=80, required=False, allow_blank=True, default=""
    )
    repo_full_name = serializers.CharField(
        max_length=160, required=False, allow_blank=True, default=""
    )
    repo_default_branch = serializers.CharField(
        max_length=80, required=False, allow_blank=True, default="main"
    )


class GithubSyncCallbackApiView(APIView):
    """Persist (or update) the install id after the user completes the
    GitHub App install flow.

    The frontend sends the install id from the GitHub redirect query
    string (`?installation_id=...`) along with the user's chosen repo.
    """

    permission_classes = [permissions.IsAuthenticated]

    def post(self, request):
        from .models import GithubIntegration

        serializer = GithubSyncCallbackSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        creator = ensure_creator(request.user)
        integration, _created = GithubIntegration.objects.update_or_create(
            creator=creator,
            defaults={
                "installation_id": serializer.validated_data["installation_id"],
                "account_login": serializer.validated_data.get(
                    "account_login", ""
                ),
                "repo_full_name": serializer.validated_data.get(
                    "repo_full_name", ""
                ),
                "repo_default_branch": serializer.validated_data.get(
                    "repo_default_branch", "main"
                ) or "main",
                "last_error": "",
            },
        )
        return Response({
            "connected": True,
            "installation_id": integration.installation_id,
            "repo_full_name": integration.repo_full_name,
        })


class GithubSyncPushApiView(APIView):
    """Push the authenticated user's full server-side data to their
    linked GitHub repo. Returns the resulting commit SHA.

    Accepts an optional ``include_assets`` query string flag (or JSON
    body field) — when truthy, avatar / cover / attachment bytes are
    inlined under ``assets/`` in the export so the resulting clone is
    self-contained. Subject to the per-file and per-push size caps in
    `creators.services.github_sync`.
    """

    permission_classes = [permissions.IsAuthenticated]

    def post(self, request):
        from .services.github_sync import GithubSyncError, push_user_data

        creator = ensure_creator(request.user)
        # Accept the flag from either the query string (for the
        # frontend's GET-style toggle) or the JSON body (for scripted
        # callers that prefer to keep everything in one payload).
        raw = (
            request.query_params.get("include_assets")
            or request.data.get("include_assets")
            if hasattr(request, "data") else None
        )
        include_assets = str(raw).lower() in ("1", "true", "yes", "on")
        try:
            sha = push_user_data(creator, include_assets=include_assets)
        except GithubSyncError as exc:
            return Response(
                {"detail": str(exc)},
                status=status.HTTP_400_BAD_REQUEST,
            )
        return Response({"commit_sha": sha, "include_assets": include_assets})


class GithubSyncReposApiView(APIView):
    """List the repositories accessible to the user's GitHub App
    installation. Used by the frontend repo-picker dropdown.

    Returns ``{"repositories": [{"full_name", "default_branch",
    "private"}]}`` paginated through ``per_page=100`` until GitHub
    runs out of results. Errors map to a 400 with the structured
    `GithubSyncError` message so the UI can surface a useful hint.
    """

    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        import requests as http_requests

        from .models import GithubIntegration
        from .services.github_sync import (
            GithubSyncError,
            _ensure_token,
            _github_headers,
        )

        creator = ensure_creator(request.user)
        integration = GithubIntegration.objects.filter(creator=creator).first()
        if integration is None:
            return Response(
                {"detail": (
                    "Cannot list repositories: "
                    "Backend.Creators.GithubSync/list_repos — "
                    "no GitHub App installation linked to this account. "
                    "Click “Install Notechondria GitHub App” first."
                )},
                status=status.HTTP_400_BAD_REQUEST,
            )
        try:
            token = _ensure_token(integration)
        except GithubSyncError as exc:
            return Response({"detail": str(exc)}, status=status.HTTP_400_BAD_REQUEST)
        headers = _github_headers(token)
        repos = []
        page = 1
        while True:
            try:
                resp = http_requests.get(
                    "https://api.github.com/installation/repositories",
                    headers=headers,
                    params={"per_page": 100, "page": page},
                    timeout=15,
                )
            except http_requests.RequestException as exc:
                return Response(
                    {"detail": (
                        "Cannot list repositories: "
                        "Backend.Creators.GithubSync/list_repos — "
                        f"network error contacting GitHub: {exc}."
                    )},
                    status=status.HTTP_400_BAD_REQUEST,
                )
            if resp.status_code >= 400:
                return Response(
                    {"detail": (
                        "Cannot list repositories: "
                        "Backend.Creators.GithubSync/list_repos — "
                        f"GitHub returned {resp.status_code}."
                    )},
                    status=status.HTTP_400_BAD_REQUEST,
                )
            payload = resp.json() or {}
            chunk = payload.get("repositories") or []
            for repo in chunk:
                repos.append({
                    "full_name": repo.get("full_name", ""),
                    "default_branch": repo.get("default_branch", "main"),
                    "private": bool(repo.get("private", False)),
                })
            # GitHub paginates via Link header; falling out when a page
            # returns fewer than per_page entries is the simpler invariant
            # and matches the contract of /installation/repositories.
            if len(chunk) < 100:
                break
            page += 1
            if page > 50:
                # Defensive cap: 5,000 repos. Anything past that is a
                # mis-installed App, not a real personal account.
                break
        return Response({"repositories": repos})


# ---------------------------------------------------------------------------
# Casdoor: phase 2 of the auth migration plan
# (docs/integrations/casdoor-migration.md)
# ---------------------------------------------------------------------------


class CasdoorConfigApiView(APIView):
    """Public OIDC endpoints + client id for the frontend Casdoor
    SDK. Returns ``configured: false`` plus an empty payload when the
    backend doesn't have ``CASDOOR_*`` env vars set, so the SPA can
    keep showing the legacy auth surface in shadow mode."""

    permission_classes = [permissions.AllowAny]

    def get(self, request):
        endpoint = (settings.CASDOOR_ENDPOINT or "").rstrip("/")
        configured = bool(
            endpoint
            and settings.CASDOOR_CLIENT_ID
            and settings.CASDOOR_ORG_NAME
            and settings.CASDOOR_APP_NAME
        )
        if not configured:
            return Response({"configured": False})
        return Response({
            "configured": True,
            "endpoint": endpoint,
            "client_id": settings.CASDOOR_CLIENT_ID,
            "organization": settings.CASDOOR_ORG_NAME,
            "application": settings.CASDOOR_APP_NAME,
            "signin_url": f"{endpoint}/login/oauth/authorize",
        })


class CasdoorExchangeSerializer(serializers.Serializer):
    code = serializers.CharField(required=True, allow_blank=False)
    state = serializers.CharField(required=False, allow_blank=True, default="")


class CasdoorUnlinkApiView(APIView):
    """Drop the Casdoor link on the current user's Creator. Idempotent
    — returns success even if the link wasn't set. Does NOT log the
    user out: the legacy Token session continues to work, and
    `_resolve_user` in casdoor_auth will simply auto-link again on
    next Casdoor sign-in via the email-iexact path (or refuse to
    auto-provision if the email differs)."""

    permission_classes = [permissions.IsAuthenticated]

    def delete(self, request):
        creator = ensure_creator(request.user)
        had_link = bool(creator.casdoor_sub)
        if had_link:
            creator.casdoor_sub = ""
            creator.save(update_fields=["casdoor_sub"])
            logger.info(
                "Unlinked Casdoor account: "
                "Backend.Creators.CasdoorAuth/unlink — user=%s.",
                request.user.username,
            )
        return Response({"casdoor_linked": False, "was_linked": had_link})


class CasdoorBindApiView(APIView):
    """Link a Casdoor identity to the *currently* signed-in user.

    The exchange flow on `/auth/casdoor/exchange/` resolves identity
    via `Creator.casdoor_sub` → email-iexact → auto-provision; this
    endpoint is the manual override for users who want to link a
    Casdoor account *to their existing legacy account* without
    going through the email match (e.g. when the Casdoor email
    differs from the Notechondria email).

    Wire shape:

    - Auth: standard ``Authorization: Token <session-key>``.
    - Body: ``{"code": "<casdoor-authz-code>"}``.
    - Returns the standard ``auth_payload`` shape on success.
    - 409 when the Casdoor `sub` is already linked to a different
      Creator. The user must unlink that side first.
    """

    permission_classes = [permissions.IsAuthenticated]

    def post(self, request):
        from .casdoor_auth import _build_sdk, verify_token

        sdk = _build_sdk()
        if sdk is None:
            return Response(
                {"detail": (
                    "Casdoor account linking unavailable: "
                    "Backend.Creators.CasdoorAuth/bind — "
                    "backend is in shadow mode (CASDOOR_* env vars "
                    "not configured)."
                )},
                status=status.HTTP_503_SERVICE_UNAVAILABLE,
            )
        code = (request.data.get("code") or "").strip()
        if not code:
            return Response(
                {"detail": (
                    "Casdoor account linking aborted: "
                    "Backend.Creators.CasdoorAuth/bind — "
                    "request body is missing required field `code`."
                )},
                status=status.HTTP_400_BAD_REQUEST,
            )
        try:
            tokens = sdk.get_oauth_token(code=code)
        except Exception as exc:  # noqa: BLE001
            return Response(
                {"detail": (
                    "Casdoor account linking aborted: "
                    "Backend.Creators.CasdoorAuth/bind — "
                    f"Casdoor rejected the authorization code: {exc}."
                )},
                status=status.HTTP_400_BAD_REQUEST,
            )
        access_token = (
            tokens.get("access_token") if isinstance(tokens, dict) else None
        )
        claims = verify_token(access_token) if access_token else None
        if claims is None:
            return Response(
                {"detail": (
                    "Casdoor account linking aborted: "
                    "Backend.Creators.CasdoorAuth/bind — "
                    "Casdoor returned a token whose JWT signature "
                    "could not be verified."
                )},
                status=status.HTTP_400_BAD_REQUEST,
            )
        sub = (claims.get("id") or claims.get("sub") or "").strip()
        if not sub:
            return Response(
                {"detail": (
                    "Casdoor account linking aborted: "
                    "Backend.Creators.CasdoorAuth/bind — "
                    "JWT does not carry an `id` / `sub` claim."
                )},
                status=status.HTTP_400_BAD_REQUEST,
            )
        creator = ensure_creator(request.user)
        # Conflict: the Casdoor sub is already on a different
        # Creator. We refuse to silently transfer the link.
        from .models import Creator
        existing = (
            Creator.objects.filter(casdoor_sub=sub)
            .exclude(user_id=request.user)
            .first()
        )
        if existing is not None:
            return Response(
                {"detail": (
                    "Casdoor account linking aborted: "
                    "Backend.Creators.CasdoorAuth/bind — "
                    "this Casdoor identity is already linked to "
                    "another Notechondria account. Unlink that side "
                    "first or sign in with it directly."
                )},
                status=status.HTTP_409_CONFLICT,
            )
        creator.casdoor_sub = sub
        creator.save(update_fields=["casdoor_sub"])
        logger.info(
            "Linked Casdoor account: "
            "Backend.Creators.CasdoorAuth/bind — "
            "user=%s sub=%s.",
            request.user.username, sub[:12],
        )
        return Response(auth_payload(request.user, request=request))


class CasdoorExchangeApiView(APIView):
    """Exchange a Casdoor authorization code for the standard
    Notechondria ``auth_payload``. This is the bridge that lets the
    Flutter apps adopt Casdoor without rewriting their auth state
    machinery: same response shape (``token``, ``session``,
    ``user``), but the underlying identity now comes from Casdoor.

    Returns 503 when the SDK isn't configured; the frontend should
    fall through to the legacy ``LoginApiView`` until the operator
    flips the flag.
    """

    permission_classes = [permissions.AllowAny]

    def post(self, request):
        from .casdoor_auth import _build_sdk, _resolve_user, verify_token

        sdk = _build_sdk()
        if sdk is None:
            return Response(
                {"detail": (
                    "Casdoor sign-in unavailable: "
                    "Backend.Creators.CasdoorAuth/exchange — "
                    "backend is in shadow mode (CASDOOR_* env vars "
                    "not configured). Use the legacy login flow."
                )},
                status=status.HTTP_503_SERVICE_UNAVAILABLE,
            )
        serializer = CasdoorExchangeSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        code = serializer.validated_data["code"]
        try:
            tokens = sdk.get_oauth_token(code=code)
        except Exception as exc:  # noqa: BLE001
            return Response(
                {"detail": (
                    "Cannot sign in: "
                    "Backend.Creators.CasdoorAuth/exchange — "
                    f"Casdoor rejected the authorization code: {exc}."
                )},
                status=status.HTTP_400_BAD_REQUEST,
            )
        access_token = (
            tokens.get("access_token") if isinstance(tokens, dict) else None
        )
        if not access_token:
            return Response(
                {"detail": (
                    "Cannot sign in: "
                    "Backend.Creators.CasdoorAuth/exchange — "
                    "Casdoor token response did not include an "
                    "`access_token` field."
                )},
                status=status.HTTP_400_BAD_REQUEST,
            )
        claims = verify_token(access_token)
        if claims is None:
            return Response(
                {"detail": (
                    "Cannot sign in: "
                    "Backend.Creators.CasdoorAuth/exchange — "
                    "Casdoor returned a token whose JWT signature "
                    "could not be verified against the configured "
                    "certificate."
                )},
                status=status.HTTP_400_BAD_REQUEST,
            )
        user = _resolve_user(claims)
        if user is None:
            return Response(
                {"detail": (
                    "Cannot sign in: "
                    "Backend.Creators.CasdoorAuth/exchange — "
                    "JWT is valid but does not carry an `id` / "
                    "`sub` claim, so no Notechondria account can be "
                    "located or auto-provisioned."
                )},
                status=status.HTTP_400_BAD_REQUEST,
            )
        # Mint a session row so the frontend's existing
        # MultiSessionAuthentication path can continue to work
        # alongside Casdoor JWTs. The session token is opaque to
        # Casdoor and lives only on Notechondria.
        return Response(auth_payload(user, request=request))
