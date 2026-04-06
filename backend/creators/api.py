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

from .models import InvitationCode, VerificationChoices, VerificationCode
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
            "display_name": user.username,
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
        if "username" in validated_data:
            user.username = validated_data["username"]
        if "email" in validated_data:
            user.email = validated_data["email"]
        if "username" in validated_data or "email" in validated_data:
            user.save(update_fields=["username", "email"])
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
