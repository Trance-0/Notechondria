import json
from django.conf import settings
from django.contrib.auth import authenticate
from django.contrib.auth.models import User
from django.utils.timezone import now
from urllib.parse import urlparse

from rest_framework import permissions, serializers, status
from rest_framework.authtoken.models import Token
from rest_framework.parsers import FormParser, JSONParser, MultiPartParser
from rest_framework.response import Response
from rest_framework.views import APIView

import logging
import requests as http_requests

from .models import InvitationCode, SocialAccount, VerificationChoices, VerificationCode
from .utils import (
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
    token, _ = Token.objects.get_or_create(user=user)
    creator = ensure_creator_avatar(ensure_creator(user))
    return {
        "token": token.key,
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
            raise serializers.ValidationError("This username is already taken.")
        return value

    def validate_email(self, value):
        existing = User.objects.filter(email__iexact=value).first()
        if existing and existing.is_active:
            raise serializers.ValidationError("A verified account already exists for this email.")
        return value.lower()

    def validate_password(self, value):
        has_upper = any(c.isupper() for c in value)
        has_lower = any(c.islower() for c in value)
        has_digit_or_special = any(not c.isalpha() for c in value)
        if not (has_upper and has_lower and has_digit_or_special):
            raise serializers.ValidationError(
                "Password must contain at least one uppercase letter, "
                "one lowercase letter, and one digit or special character."
            )
        return value

    def validate_invitation_code(self, value):
        if not value:
            return value
        code_hash = InvitationCode.hash_code(value)
        invite = InvitationCode.objects.filter(code_hash=code_hash).first()
        if invite is None or not invite.is_valid():
            raise serializers.ValidationError("Invalid or expired invitation code.")
        return value

    def validate(self, attrs):
        # Invitation code is required when any InvitationCode records exist
        # in the database (i.e. admin has set up the invitation system).
        if InvitationCode.objects.exists():
            code = attrs.get("invitation_code", "").strip()
            if not code:
                raise serializers.ValidationError(
                    {"invitation_code": "An invitation code is required to register."}
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
            raise serializers.ValidationError("Invalid or expired verification code.")
        user = User.objects.filter(email__iexact=email).first()
        if user is None:
            raise serializers.ValidationError("No pending account found for this email.")
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
            raise serializers.ValidationError("Email or username is required.")
        matched_user = User.objects.filter(email__iexact=identifier).first()
        if matched_user is None:
            matched_user = User.objects.filter(username__iexact=identifier).first()
        username = matched_user.username if matched_user else identifier
        user = authenticate(username=username, password=attrs["password"])
        if user is None:
            raise serializers.ValidationError("Email/username/password mismatch.")
        if not user.is_active:
            raise serializers.ValidationError("Email verification is still pending.")
        attrs["user"] = user
        return attrs


class ResendVerificationSerializer(serializers.Serializer):
    email = serializers.EmailField()

    def validate_email(self, value):
        user = User.objects.filter(email__iexact=value).first()
        if user is None:
            raise serializers.ValidationError("No account found for this email.")
        if user.is_active:
            raise serializers.ValidationError("This account is already verified.")
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
                    "Please wait 60 seconds before requesting a new code."
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
            "api_base_url": instance.api_base_url,
            "app_settings": creator_app_settings_payload(instance),
            "app_settings_updated_at": instance.app_settings_updated_at.isoformat()
            if instance.app_settings_updated_at
            else None,
        }

    def validate_username(self, value):
        user = self.instance.user_id if self.instance is not None else None
        existing = User.objects.filter(username__iexact=value).exclude(pk=user.pk if user else None).first()
        if existing is not None:
            raise serializers.ValidationError("This username is already in use.")
        return value

    def validate_email(self, value):
        user = self.instance.user_id if self.instance is not None else None
        if user is not None and user.email.lower() == value.lower():
            return user.email
        existing = User.objects.filter(email__iexact=value).exclude(pk=user.pk if user else None).first()
        if existing is not None:
            raise serializers.ValidationError("This email is already in use.")
        return value.lower()

    def validate_api_base_url(self, value):
        normalized = value.strip()
        parsed = urlparse(normalized)
        if parsed.scheme not in {"http", "https"} or not parsed.netloc:
            raise serializers.ValidationError(
                "Use a full http:// or https:// API base URL."
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
            raise serializers.ValidationError("No account found for this email.")
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
            raise serializers.ValidationError("Invalid or expired reset code.")
        user = User.objects.filter(email__iexact=email).first()
        if user is None:
            raise serializers.ValidationError("No account found for this email.")
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


class ChangePasswordSerializer(serializers.Serializer):
    current_password = serializers.CharField(write_only=True)
    new_password = serializers.CharField(write_only=True, min_length=8)

    def validate_new_password(self, value):
        has_upper = any(c.isupper() for c in value)
        has_lower = any(c.islower() for c in value)
        has_other = any(not c.isalpha() for c in value)
        if not (has_upper and has_lower and has_other):
            raise serializers.ValidationError(
                "Password needs uppercase, lowercase, and a digit or special character."
            )
        return value


class ChangePasswordApiView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request):
        serializer = ChangePasswordSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        user = request.user
        if not user.check_password(serializer.validated_data["current_password"]):
            return Response(
                {"detail": "Current password is incorrect."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        user.set_password(serializer.validated_data["new_password"])
        user.save(update_fields=["password"])
        # Rotate auth token so old sessions are invalidated.
        Token.objects.filter(user=user).delete()
        token, _ = Token.objects.get_or_create(user=user)
        return Response({"message": "Password changed.", "token": token.key})


class ChangeEmailRequestSerializer(serializers.Serializer):
    new_email = serializers.EmailField()

    def validate_new_email(self, value):
        normalised = value.lower()
        if User.objects.filter(email__iexact=normalised).exists():
            raise serializers.ValidationError("This email is already in use.")
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
            raise serializers.ValidationError("Invalid or expired verification code.")
        if User.objects.filter(email__iexact=email).exists():
            raise serializers.ValidationError("This email is already in use.")
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
        Token.objects.filter(user=request.user).delete()
        return Response(status=status.HTTP_204_NO_CONTENT)


class SessionApiView(APIView):
    permission_classes = [permissions.AllowAny]

    def get(self, request):
        if not request.user or not request.user.is_authenticated:
            return Response({"authenticated": False})
        payload = auth_payload(request.user, request=request)
        payload["authenticated"] = True
        return Response(payload)


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


# ---------------------------------------------------------------------------
# OAuth helpers
# ---------------------------------------------------------------------------

logger = logging.getLogger("django")


def _validate_invitation_if_required(invitation_code: str):
    """Validate and consume an invitation code when the invitation system is
    active. Raises ``serializers.ValidationError`` on failure."""
    if not InvitationCode.objects.exists():
        return
    code = invitation_code.strip()
    if not code:
        raise serializers.ValidationError(
            {"invitation_code": "An invitation code is required to register."}
        )
    code_hash = InvitationCode.hash_code(code)
    invite = InvitationCode.objects.filter(code_hash=code_hash).first()
    if invite is None or not invite.is_valid():
        raise serializers.ValidationError(
            {"invitation_code": "Invalid or expired invitation code."}
        )
    invite.consume()


def _get_or_create_oauth_user(provider: str, provider_uid: str, email: str,
                              username: str, display_name: str,
                              extra_data: dict, invitation_code: str = "",
                              intent: str = "register", request=None):
    """Find an existing user linked to this social account, or create a new
    one.  Returns the ``auth_payload`` dict ready for the frontend.

    *intent* controls what happens when no existing user is found:
    - ``"register"`` (default): create a new account (validates invitation code).
    - ``"login"``: reject with 404 so the frontend can prompt registration.
    """

    # 1. Check for existing social link.
    social = SocialAccount.objects.filter(
        provider=provider, provider_uid=str(provider_uid)
    ).select_related("user").first()

    if social is not None:
        user = social.user
        if not user.is_active:
            user.is_active = True
            user.save(update_fields=["is_active"])
        social.extra_data = extra_data
        social.save(update_fields=["extra_data"])
        ensure_creator(user)
        return auth_payload(user, request=request)

    # 2. Check if a user with this email already exists — link the account.
    user = User.objects.filter(email__iexact=email).first() if email else None
    if user is not None:
        SocialAccount.objects.create(
            user=user,
            provider=provider,
            provider_uid=str(provider_uid),
            email=email,
            extra_data=extra_data,
        )
        if not user.is_active:
            user.is_active = True
            user.save(update_fields=["is_active"])
        ensure_creator(user)
        return auth_payload(user, request=request)

    # 3. No existing user found.
    if intent == "login":
        return None  # Caller returns 404 to prompt registration.

    # intent == "register": create a new account.
    _validate_invitation_if_required(invitation_code)

    # Deduplicate username.
    base_username = username or email.split("@")[0] if email else f"{provider}_user"
    candidate = base_username[:150]
    suffix = 0
    while User.objects.filter(username__iexact=candidate).exists():
        suffix += 1
        candidate = f"{base_username[:145]}_{suffix}"

    user = User.objects.create(
        username=candidate,
        email=email or "",
        first_name=(display_name or "").split()[0][:30] if display_name else "",
        last_name=" ".join((display_name or "").split()[1:])[:150] if display_name else "",
        is_active=True,
    )
    user.set_unusable_password()
    user.save()
    SocialAccount.objects.create(
        user=user,
        provider=provider,
        provider_uid=str(provider_uid),
        email=email,
        extra_data=extra_data,
    )
    ensure_creator(user)
    return auth_payload(user, request=request)


# ---------------------------------------------------------------------------
# Google OAuth
# ---------------------------------------------------------------------------

class OAuthConfigApiView(APIView):
    """Return public OAuth client IDs and redirect URIs for the frontend."""
    permission_classes = [permissions.AllowAny]

    def get(self, request):
        return Response({
            "google": {
                "client_id": settings.GOOGLE_OAUTH_CLIENT_ID,
                "redirect_uri": settings.GOOGLE_AUTHORIZED_REDIRECT_URI,
            },
            "github": {
                "client_id": settings.GITHUB_APP_CLIENT_ID,
                "redirect_uri": settings.GITHUB_AUTHORIZED_REDIRECT_URI,
            },
        })


class GoogleOAuthSerializer(serializers.Serializer):
    code = serializers.CharField(
        required=False, allow_blank=True,
        help_text="Authorization code from Google redirect.",
    )
    id_token = serializers.CharField(
        required=False, allow_blank=True,
        help_text="ID token from Google Sign-In (client-side flow).",
    )
    redirect_uri = serializers.CharField(
        required=False, allow_blank=True, default="",
        help_text="Redirect URI used in the authorization request (must match).",
    )
    invitation_code = serializers.CharField(
        required=False, allow_blank=True, default="",
    )
    intent = serializers.ChoiceField(
        choices=["login", "register"], default="register", required=False,
        help_text="'login' rejects unregistered users; 'register' creates them.",
    )

    def validate(self, attrs):
        code = (attrs.get("code") or "").strip()
        id_token = (attrs.get("id_token") or "").strip()
        if not code and not id_token:
            raise serializers.ValidationError(
                "Either 'code' (authorization code) or 'id_token' is required."
            )
        return attrs


class GoogleOAuthApiView(APIView):
    """Exchange a Google authorization code or ID token for an app auth token.

    POST /api/v1/auth/google/
    Body: { "code": "...", "invitation_code": "..." }
       or { "id_token": "...", "invitation_code": "..." }
    """
    permission_classes = [permissions.AllowAny]

    def post(self, request):
        serializer = GoogleOAuthSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data

        code = (data.get("code") or "").strip()
        raw_id_token = (data.get("id_token") or "").strip()
        redirect_uri = (data.get("redirect_uri") or "").strip() or settings.GOOGLE_AUTHORIZED_REDIRECT_URI
        invitation_code = data.get("invitation_code", "")
        intent = data.get("intent", "register")

        if code:
            # Exchange authorization code for tokens.
            token_resp = http_requests.post(
                "https://oauth2.googleapis.com/token",
                data={
                    "code": code,
                    "client_id": settings.GOOGLE_OAUTH_CLIENT_ID,
                    "client_secret": settings.GOOGLE_OAUTH_CLIENT_SECRET,
                    "redirect_uri": redirect_uri,
                    "grant_type": "authorization_code",
                },
                timeout=15,
            )
            if token_resp.status_code != 200:
                logger.warning("Google token exchange failed: %s", token_resp.text)
                error_detail = "Failed to exchange Google authorization code."
                try:
                    err = token_resp.json()
                    error_detail = err.get("error_description", err.get("error", error_detail))
                except Exception:
                    pass
                return Response(
                    {"detail": error_detail},
                    status=status.HTTP_400_BAD_REQUEST,
                )
            raw_id_token = token_resp.json().get("id_token", "")

        if not raw_id_token:
            return Response(
                {"detail": "No ID token received from Google."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        # Verify the ID token via Google's tokeninfo endpoint.
        verify_resp = http_requests.get(
            "https://oauth2.googleapis.com/tokeninfo",
            params={"id_token": raw_id_token},
            timeout=10,
        )
        if verify_resp.status_code != 200:
            return Response(
                {"detail": "Google ID token verification failed."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        info = verify_resp.json()
        aud = info.get("aud", "")
        if aud != settings.GOOGLE_OAUTH_CLIENT_ID:
            return Response(
                {"detail": "ID token audience mismatch."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        google_uid = info.get("sub", "")
        email = info.get("email", "")
        name = info.get("name", "")
        username = email.split("@")[0] if email else f"google_{google_uid}"

        payload = _get_or_create_oauth_user(
            provider="google",
            provider_uid=google_uid,
            email=email,
            username=username,
            display_name=name,
            extra_data={"picture": info.get("picture", ""), "locale": info.get("locale", "")},
            invitation_code=invitation_code,
            intent=intent,
            request=request,
        )
        if payload is None:
            return Response(
                {"detail": "No account found for this Google identity. Please register first.",
                 "code": "not_registered"},
                status=status.HTTP_404_NOT_FOUND,
            )
        return Response(payload)


# ---------------------------------------------------------------------------
# GitHub OAuth
# ---------------------------------------------------------------------------

class GitHubOAuthSerializer(serializers.Serializer):
    code = serializers.CharField(
        help_text="Authorization code from GitHub redirect.",
    )
    redirect_uri = serializers.CharField(
        required=False, allow_blank=True, default="",
        help_text="Redirect URI used in the authorization request.",
    )
    invitation_code = serializers.CharField(
        required=False, allow_blank=True, default="",
    )
    intent = serializers.ChoiceField(
        choices=["login", "register"], default="register", required=False,
        help_text="'login' rejects unregistered users; 'register' creates them.",
    )


class GitHubOAuthApiView(APIView):
    """Exchange a GitHub authorization code for an app auth token.

    POST /api/v1/auth/github/
    Body: { "code": "...", "invitation_code": "..." }
    """
    permission_classes = [permissions.AllowAny]

    def post(self, request):
        serializer = GitHubOAuthSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data

        code = data["code"]
        redirect_uri = (data.get("redirect_uri") or "").strip() or settings.GITHUB_AUTHORIZED_REDIRECT_URI
        invitation_code = data.get("invitation_code", "")
        intent = data.get("intent", "register")

        # Exchange code for access token.
        token_payload = {
            "client_id": settings.GITHUB_APP_CLIENT_ID,
            "client_secret": settings.GITHUB_APP_CLIENT_SECRET,
            "code": code,
        }
        if redirect_uri:
            token_payload["redirect_uri"] = redirect_uri
        token_resp = http_requests.post(
            "https://github.com/login/oauth/access_token",
            json=token_payload,
            headers={"Accept": "application/json"},
            timeout=15,
        )
        if token_resp.status_code != 200:
            logger.warning("GitHub token exchange failed: %s", token_resp.text)
            error_detail = "Failed to exchange GitHub authorization code."
            try:
                err = token_resp.json()
                error_detail = err.get("error_description", err.get("error", error_detail))
            except Exception:
                pass
            return Response(
                {"detail": error_detail},
                status=status.HTTP_400_BAD_REQUEST,
            )
        token_data = token_resp.json()
        access_token = token_data.get("access_token", "")
        if not access_token:
            error_desc = token_data.get("error_description", token_data.get("error", "unknown"))
            return Response(
                {"detail": f"GitHub OAuth error: {error_desc}"},
                status=status.HTTP_400_BAD_REQUEST,
            )

        # Fetch user profile.
        user_resp = http_requests.get(
            "https://api.github.com/user",
            headers={
                "Authorization": f"Bearer {access_token}",
                "Accept": "application/vnd.github+json",
            },
            timeout=10,
        )
        if user_resp.status_code != 200:
            return Response(
                {"detail": "Failed to fetch GitHub user profile."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        gh_user = user_resp.json()

        # Fetch primary email if not public.
        email = gh_user.get("email") or ""
        if not email:
            emails_resp = http_requests.get(
                "https://api.github.com/user/emails",
                headers={
                    "Authorization": f"Bearer {access_token}",
                    "Accept": "application/vnd.github+json",
                },
                timeout=10,
            )
            if emails_resp.status_code == 200:
                for em in emails_resp.json():
                    if em.get("primary") and em.get("verified"):
                        email = em["email"]
                        break

        github_uid = str(gh_user.get("id", ""))
        username = gh_user.get("login", "") or f"github_{github_uid}"
        display_name = gh_user.get("name", "") or username

        payload = _get_or_create_oauth_user(
            provider="github",
            provider_uid=github_uid,
            email=email,
            username=username,
            display_name=display_name,
            extra_data={
                "login": gh_user.get("login", ""),
                "avatar_url": gh_user.get("avatar_url", ""),
                "html_url": gh_user.get("html_url", ""),
            },
            invitation_code=invitation_code,
            intent=intent,
            request=request,
        )
        if payload is None:
            return Response(
                {"detail": "No account found for this GitHub identity. Please register first.",
                 "code": "not_registered"},
                status=status.HTTP_404_NOT_FOUND,
            )
        return Response(payload)


# ---------------------------------------------------------------------------
# Social Account Binding (for authenticated users)
# ---------------------------------------------------------------------------

class SocialAccountListApiView(APIView):
    """List connected social accounts for the authenticated user."""
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        accounts = SocialAccount.objects.filter(user=request.user).values(
            "id", "provider", "provider_uid", "email", "created_at",
        )
        return Response(list(accounts))


class SocialAccountUnlinkApiView(APIView):
    """Unlink a social account from the authenticated user."""
    permission_classes = [permissions.IsAuthenticated]

    def delete(self, request, provider):
        deleted, _ = SocialAccount.objects.filter(
            user=request.user, provider=provider,
        ).delete()
        if not deleted:
            return Response(
                {"detail": f"No {provider} account linked."},
                status=status.HTTP_404_NOT_FOUND,
            )
        return Response(status=status.HTTP_204_NO_CONTENT)


class _BindOAuthMixin:
    """Shared logic for authenticated social-account binding views."""

    def _bind_social_account(self, user, provider, provider_uid, email, extra_data):
        """Create or update a SocialAccount link for *user*."""
        logger.info(
            "Bind %s: user=%s uid=%s email=%s",
            provider, user.username, provider_uid, email,
        )
        social, created = SocialAccount.objects.update_or_create(
            user=user,
            provider=provider,
            defaults={
                "provider_uid": str(provider_uid),
                "email": email,
                "extra_data": extra_data,
            },
        )
        # If this provider_uid was previously linked to a different user, reject.
        conflict = SocialAccount.objects.filter(
            provider=provider, provider_uid=str(provider_uid),
        ).exclude(user=user).first()
        if conflict is not None:
            logger.warning(
                "Bind %s conflict: uid=%s already linked to user_id=%s",
                provider, provider_uid, conflict.user_id,
            )
            return Response(
                {"detail": "This account is already linked to another user."},
                status=status.HTTP_409_CONFLICT,
            )
        logger.info("Bind %s %s: social_id=%s", provider, "created" if created else "updated", social.id)
        return Response({
            "id": social.id,
            "provider": social.provider,
            "provider_uid": social.provider_uid,
            "email": social.email,
        }, status=status.HTTP_200_OK if not created else status.HTTP_201_CREATED)


class BindGoogleApiView(_BindOAuthMixin, APIView):
    """Link a Google account to the authenticated user.

    POST /api/v1/auth/bind/google/
    Body: { "code": "..." } or { "id_token": "..." }
    """
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request):
        logger.info("BindGoogle: user=%s payload_keys=%s", request.user.username, list(request.data.keys()))
        serializer = GoogleOAuthSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data

        code = (data.get("code") or "").strip()
        raw_id_token = (data.get("id_token") or "").strip()
        redirect_uri = (data.get("redirect_uri") or "").strip() or settings.GOOGLE_AUTHORIZED_REDIRECT_URI
        logger.info("BindGoogle: redirect_uri=%s has_code=%s has_id_token=%s", redirect_uri, bool(code), bool(raw_id_token))

        if code:
            token_resp = http_requests.post(
                "https://oauth2.googleapis.com/token",
                data={
                    "code": code,
                    "client_id": settings.GOOGLE_OAUTH_CLIENT_ID,
                    "client_secret": settings.GOOGLE_OAUTH_CLIENT_SECRET,
                    "redirect_uri": redirect_uri,
                    "grant_type": "authorization_code",
                },
                timeout=15,
            )
            if token_resp.status_code != 200:
                logger.warning("BindGoogle token exchange failed (%s): %s", token_resp.status_code, token_resp.text)
                error_detail = "Failed to exchange Google authorization code."
                try:
                    err = token_resp.json()
                    error_detail = err.get("error_description", err.get("error", error_detail))
                except Exception:
                    pass
                return Response(
                    {"detail": error_detail},
                    status=status.HTTP_400_BAD_REQUEST,
                )
            raw_id_token = token_resp.json().get("id_token", "")
            logger.info("BindGoogle: token exchange OK, got id_token=%s", bool(raw_id_token))

        if not raw_id_token:
            logger.warning("BindGoogle: no id_token after exchange")
            return Response(
                {"detail": "No ID token received from Google."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        verify_resp = http_requests.get(
            "https://oauth2.googleapis.com/tokeninfo",
            params={"id_token": raw_id_token},
            timeout=10,
        )
        if verify_resp.status_code != 200:
            logger.warning("BindGoogle: tokeninfo verify failed (%s): %s", verify_resp.status_code, verify_resp.text)
            return Response(
                {"detail": "Google ID token verification failed."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        info = verify_resp.json()
        if info.get("aud", "") != settings.GOOGLE_OAUTH_CLIENT_ID:
            logger.warning("BindGoogle: audience mismatch got=%s expected=%s", info.get("aud"), settings.GOOGLE_OAUTH_CLIENT_ID)
            return Response(
                {"detail": "ID token audience mismatch."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        logger.info("BindGoogle: verified sub=%s email=%s", info.get("sub"), info.get("email"))
        return self._bind_social_account(
            user=request.user,
            provider="google",
            provider_uid=info.get("sub", ""),
            email=info.get("email", ""),
            extra_data={"picture": info.get("picture", ""), "locale": info.get("locale", "")},
        )


class BindGithubApiView(_BindOAuthMixin, APIView):
    """Link a GitHub account to the authenticated user.

    POST /api/v1/auth/bind/github/
    Body: { "code": "..." }
    """
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request):
        logger.info("BindGitHub: user=%s payload_keys=%s", request.user.username, list(request.data.keys()))
        serializer = GitHubOAuthSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data

        code = data["code"]
        redirect_uri = (data.get("redirect_uri") or "").strip() or settings.GITHUB_AUTHORIZED_REDIRECT_URI
        logger.info("BindGitHub: redirect_uri=%s", redirect_uri)

        token_payload = {
            "client_id": settings.GITHUB_APP_CLIENT_ID,
            "client_secret": settings.GITHUB_APP_CLIENT_SECRET,
            "code": code,
        }
        if redirect_uri:
            token_payload["redirect_uri"] = redirect_uri
        token_resp = http_requests.post(
            "https://github.com/login/oauth/access_token",
            json=token_payload,
            headers={"Accept": "application/json"},
            timeout=15,
        )
        if token_resp.status_code != 200:
            logger.warning("BindGitHub token exchange failed (%s): %s", token_resp.status_code, token_resp.text)
            error_detail = "Failed to exchange GitHub authorization code."
            try:
                err = token_resp.json()
                error_detail = err.get("error_description", err.get("error", error_detail))
            except Exception:
                pass
            return Response(
                {"detail": error_detail},
                status=status.HTTP_400_BAD_REQUEST,
            )
        token_data = token_resp.json()
        access_token = token_data.get("access_token", "")
        if not access_token:
            error_desc = token_data.get("error_description", token_data.get("error", "unknown"))
            logger.warning("BindGitHub: no access_token, error=%s", error_desc)
            return Response(
                {"detail": f"GitHub OAuth error: {error_desc}"},
                status=status.HTTP_400_BAD_REQUEST,
            )
        logger.info("BindGitHub: token exchange OK")

        user_resp = http_requests.get(
            "https://api.github.com/user",
            headers={
                "Authorization": f"Bearer {access_token}",
                "Accept": "application/vnd.github+json",
            },
            timeout=10,
        )
        if user_resp.status_code != 200:
            logger.warning("BindGitHub: user profile fetch failed (%s): %s", user_resp.status_code, user_resp.text)
            return Response(
                {"detail": "Failed to fetch GitHub user profile."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        gh_user = user_resp.json()
        logger.info("BindGitHub: fetched user login=%s id=%s", gh_user.get("login"), gh_user.get("id"))

        email = gh_user.get("email") or ""
        if not email:
            emails_resp = http_requests.get(
                "https://api.github.com/user/emails",
                headers={
                    "Authorization": f"Bearer {access_token}",
                    "Accept": "application/vnd.github+json",
                },
                timeout=10,
            )
            if emails_resp.status_code == 200:
                for em in emails_resp.json():
                    if em.get("primary") and em.get("verified"):
                        email = em["email"]
                        break
            logger.info("BindGitHub: resolved email=%s", email)

        return self._bind_social_account(
            user=request.user,
            provider="github",
            provider_uid=str(gh_user.get("id", "")),
            email=email,
            extra_data={
                "login": gh_user.get("login", ""),
                "avatar_url": gh_user.get("avatar_url", ""),
                "html_url": gh_user.get("html_url", ""),
            },
        )
