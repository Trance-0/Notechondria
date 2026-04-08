import os
import logging
from datetime import timedelta
from io import BytesIO

from PIL import Image, ImageDraw

from django.conf import settings
from django.contrib.auth.models import User
from django.core.files.base import ContentFile
from django.core.mail import send_mail
from django.utils.timezone import now

from .models import Creator, VerificationChoices, VerificationCode


logger = logging.getLogger("django")


def get_default_profile_image_path() -> str:
    candidates = [
        os.path.join(settings.STATIC_ROOT, "images", "mitochondria-avatar.png") if settings.STATIC_ROOT else None,
        os.path.join(settings.STATIC_ROOT, "images", "person-circle.png") if settings.STATIC_ROOT else None,
        os.path.join(settings.BASE_DIR, "static", "images", "mitochondria-avatar.png"),
        os.path.join(settings.BASE_DIR, "static", "images", "person-circle.png"),
    ]

    for candidate in candidates:
        if candidate and os.path.exists(candidate):
            return candidate

    return ""


def _generated_default_profile_image() -> Image.Image:
    image = Image.new("RGBA", (256, 256), (245, 247, 250, 255))
    draw = ImageDraw.Draw(image)
    draw.ellipse((18, 18, 238, 238), fill=(28, 39, 54, 255))
    draw.ellipse((34, 34, 222, 222), fill=(247, 250, 252, 255))
    draw.ellipse((76, 88, 180, 168), fill=(196, 222, 255, 255))
    draw.ellipse((104, 106, 152, 150), fill=(36, 88, 170, 255))

    mitochondria = [
        ((72, 58, 144, 104), (220, 96, 74, 255)),
        ((126, 68, 198, 118), (239, 124, 62, 255)),
        ((64, 150, 138, 196), (244, 157, 79, 255)),
        ((142, 146, 210, 194), (227, 108, 68, 255)),
    ]
    for bounds, fill in mitochondria:
        draw.rounded_rectangle(bounds, radius=28, fill=fill)
        x0, y0, x1, y1 = bounds
        draw.arc((x0 + 8, y0 + 10, x1 - 8, y1 - 10), start=30, end=150, fill=(120, 34, 25, 255), width=4)
        draw.arc((x0 + 10, y0 + 14, x1 - 10, y1 - 14), start=190, end=320, fill=(120, 34, 25, 255), width=4)
    return image


def build_default_profile_image_bytes() -> bytes:
    path = get_default_profile_image_path()
    if path:
        with Image.open(path) as default_image_file:
            buffer = BytesIO()
            default_image_file.convert("RGBA").save(fp=buffer, format="PNG")
            return buffer.getvalue()

    generated = _generated_default_profile_image()
    buffer = BytesIO()
    generated.save(fp=buffer, format="PNG")
    return buffer.getvalue()


def attach_default_profile_image(creator: Creator) -> None:
    default_image = ContentFile(build_default_profile_image_bytes())
    image_name = "profile_latest.png"
    creator.image.save(image_name, default_image, save=False)


def creator_has_image_file(creator: Creator) -> bool:
    try:
        return bool(
            creator.image
            and creator.image.name
            and creator.image.storage.exists(creator.image.name)
        )
    except Exception:
        return False


def ensure_creator_avatar(creator: Creator) -> Creator:
    if creator_has_image_file(creator):
        return creator
    attach_default_profile_image(creator)
    creator.save(update_fields=["image"])
    return creator


def ensure_creator(user: User) -> Creator:
    creator, created = Creator.objects.get_or_create(user_id=user)
    if created or not creator.image:
        attach_default_profile_image(creator)
        creator.save()
    return creator


def issue_registration_code(email: str) -> tuple[VerificationCode, str]:
    """Invalidate old registration codes for *email*, create a new 6-digit
    hashed code, and return ``(model_instance, plaintext_code)``."""
    VerificationCode.objects.filter(
        usage=VerificationChoices.REGISTER,
        function=email,
    ).update(max_use=0)
    vc = VerificationCode(
        expire_date=now() + timedelta(hours=settings.EMAIL_VERIFICATION_TTL_HOURS),
        usage=VerificationChoices.REGISTER,
        function=email,
    )
    plaintext = vc.generate_code()
    vc.save()
    return vc, plaintext


def issue_password_reset_code(email: str) -> tuple[VerificationCode, str]:
    """Invalidate old password-reset codes for *email*, create a new 6-digit
    hashed code, and return ``(model_instance, plaintext_code)``."""
    VerificationCode.objects.filter(
        usage=VerificationChoices.FUNCTION,
        function=f"password_reset:{email}",
    ).update(max_use=0)
    vc = VerificationCode(
        expire_date=now() + timedelta(hours=settings.EMAIL_VERIFICATION_TTL_HOURS),
        usage=VerificationChoices.FUNCTION,
        function=f"password_reset:{email}",
    )
    plaintext = vc.generate_code()
    vc.save()
    return vc, plaintext


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
