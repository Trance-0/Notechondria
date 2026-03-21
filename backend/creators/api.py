from django.contrib.auth import authenticate
from django.contrib.auth.models import User
from django.utils.timezone import now

from rest_framework import permissions, serializers, status
from rest_framework.authtoken.models import Token
from rest_framework.response import Response
from rest_framework.views import APIView

from .models import VerificationChoices, VerificationCode
from .utils import ensure_creator, issue_registration_code, send_registration_email


def auth_payload(user: User):
    token, _ = Token.objects.get_or_create(user=user)
    creator = ensure_creator(user)
    return {
        "token": token.key,
        "user": {
            "id": user.id,
            "email": user.email,
            "username": user.username,
            "motto": creator.motto or "",
            "social_link": creator.social_link or "",
            "image_url": creator.image.url if creator.image else "",
        },
    }


class RegisterSerializer(serializers.Serializer):
    email = serializers.EmailField()
    password = serializers.CharField(write_only=True, min_length=9)

    def validate_email(self, value):
        existing = User.objects.filter(email__iexact=value).first()
        if existing and existing.is_active:
            raise serializers.ValidationError("A verified account already exists for this email.")
        return value.lower()

    def create(self, validated_data):
        email = validated_data["email"]
        password = validated_data["password"]
        user = User.objects.filter(email__iexact=email).first()
        if user is None:
            user = User.objects.create(
                username=email,
                email=email,
                is_active=False,
            )
        user.username = email
        user.email = email
        user.is_active = False
        user.set_password(password)
        user.save()
        ensure_creator(user)
        verification = issue_registration_code(email)
        delivery = send_registration_email(email, verification.code)
        return {"user": user, "delivery": delivery}


class VerifyEmailSerializer(serializers.Serializer):
    email = serializers.EmailField()
    code = serializers.CharField()

    def validate(self, attrs):
        email = attrs["email"].lower()
        code = attrs["code"]
        verification = VerificationCode.objects.filter(
            code=code,
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
    email = serializers.EmailField()
    password = serializers.CharField(write_only=True)

    def validate(self, attrs):
        email = attrs["email"].lower()
        user = authenticate(username=email, password=attrs["password"])
        if user is None:
            raise serializers.ValidationError("Email/password mismatch.")
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
        return value.lower()


class SettingsSerializer(serializers.Serializer):
    email = serializers.EmailField(read_only=True)
    motto = serializers.CharField(allow_blank=True, required=False, max_length=100)
    social_link = serializers.URLField(allow_blank=True, required=False)
    image_url = serializers.CharField(read_only=True)

    def to_representation(self, instance):
        return {
            "email": instance.user_id.email,
            "motto": instance.motto or "",
            "social_link": instance.social_link or "",
            "image_url": instance.image.url if instance.image else "",
        }

    def update(self, instance, validated_data):
        instance.motto = validated_data.get("motto", instance.motto)
        instance.social_link = validated_data.get("social_link", instance.social_link)
        instance.save()
        return instance


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
        return Response(auth_payload(user))


class ResendVerificationApiView(APIView):
    permission_classes = [permissions.AllowAny]

    def post(self, request):
        serializer = ResendVerificationSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        email = serializer.validated_data["email"]
        verification = issue_registration_code(email)
        delivery = send_registration_email(email, verification.code)
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
        return Response(auth_payload(serializer.validated_data["user"]))


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
        payload = auth_payload(request.user)
        payload["authenticated"] = True
        return Response(payload)


class SettingsApiView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        creator = ensure_creator(request.user)
        return Response(SettingsSerializer(creator).data)

    def patch(self, request):
        creator = ensure_creator(request.user)
        serializer = SettingsSerializer(instance=creator, data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)
        serializer.save()
        return Response(SettingsSerializer(creator).data)
