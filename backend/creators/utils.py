import os
import logging
from datetime import timedelta
from io import BytesIO

from PIL import Image

from django.conf import settings
from django.contrib.auth.models import User
from django.core.files.base import ContentFile
from django.core.mail import send_mail
from django.utils.timezone import now

from .models import Creator, VerificationChoices, VerificationCode


logger = logging.getLogger("django")


def get_default_profile_image_path() -> str:
    candidates = [
        os.path.join(settings.STATIC_ROOT, "images", "person-circle.png") if settings.STATIC_ROOT else None,
        os.path.join(settings.BASE_DIR, "static", "images", "person-circle.png"),
    ]

    for candidate in candidates:
        if candidate and os.path.exists(candidate):
            return candidate

    raise FileNotFoundError("Default profile image not found in static assets.")


def attach_default_profile_image(creator: Creator) -> None:
    default_image_file = Image.open(get_default_profile_image_path())
    buffer = BytesIO()
    default_image_file.save(fp=buffer, format="PNG")
    default_image = ContentFile(buffer.getvalue())
    image_name = "profile_latest.png"
    creator.image.save(image_name, default_image, save=False)


def ensure_creator(user: User) -> Creator:
    creator, created = Creator.objects.get_or_create(user_id=user)
    if created or not creator.image:
        attach_default_profile_image(creator)
        creator.save()
    return creator


def issue_registration_code(email: str) -> VerificationCode:
    VerificationCode.objects.filter(
        usage=VerificationChoices.REGISTER,
        function=email,
    ).update(max_use=0)
    return VerificationCode.objects.create(
        expire_date=now() + timedelta(hours=settings.EMAIL_VERIFICATION_TTL_HOURS),
        usage=VerificationChoices.REGISTER,
        function=email,
    )


def issue_password_reset_code(email: str) -> VerificationCode:
    VerificationCode.objects.filter(
        usage=VerificationChoices.FUNCTION,
        function=f"password_reset:{email}",
    ).update(max_use=0)
    return VerificationCode.objects.create(
        expire_date=now() + timedelta(hours=settings.EMAIL_VERIFICATION_TTL_HOURS),
        usage=VerificationChoices.FUNCTION,
        function=f"password_reset:{email}",
    )


def smtp_is_configured() -> bool:
    return bool(
        settings.EMAIL_HOST
        and settings.EMAIL_PORT
        and settings.DEFAULT_FROM_EMAIL
    )


def log_manual_verification_code(email: str, code: str, reason: str) -> None:
    logger.warning(
        "SMTP verification fallback for %s. reason=%s verification_code=%s. Ask the user to contact an admin for the code.",
        email,
        reason,
        code,
    )


def _send_code_email(email: str, code: str, *, subject: str, intro: str, action_label: str) -> dict:
    action_url = settings.FRONTEND_VERIFY_URL or "Open the app settings page to continue."
    body = (
        f"{intro}\n\n"
        f"Email: {email}\n"
        f"Code: {code}\n"
        f"Code expires in: {settings.EMAIL_VERIFICATION_TTL_HOURS} hours\n"
        f"{action_label}: {action_url}\n"
    )
    if not smtp_is_configured():
        log_manual_verification_code(email, code, "smtp_not_configured")
        return {
            "delivered": False,
            "fallback": True,
            "message": "SMTP is not configured. Contact an admin for the verification code.",
        }
    try:
        send_mail(
            subject=subject,
            message=body,
            from_email=settings.DEFAULT_FROM_EMAIL,
            recipient_list=[email],
            fail_silently=False,
        )
        return {
            "delivered": True,
            "fallback": False,
            "message": "Email sent.",
        }
    except Exception as exc:
        log_manual_verification_code(email, code, f"smtp_send_failed:{exc.__class__.__name__}")
        return {
            "delivered": False,
            "fallback": True,
            "message": "Email delivery failed. Contact an admin for the verification code.",
        }


def send_registration_email(email: str, code: str) -> dict:
    result = _send_code_email(
        email,
        code,
        subject="Verify your Notechondria account",
        intro="Use this code to verify your Notechondria account.",
        action_label="Verify here",
    )
    if result["delivered"]:
        result["message"] = "Verification email sent."
    return result


def send_password_reset_email(email: str, code: str) -> dict:
    result = _send_code_email(
        email,
        code,
        subject="Reset your Notechondria password",
        intro="Use this code to reset your Notechondria password.",
        action_label="Open settings",
    )
    if result["delivered"]:
        result["message"] = "Password reset email sent."
    return result
