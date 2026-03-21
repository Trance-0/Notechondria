import os
from datetime import timedelta
from io import BytesIO

from PIL import Image

from django.conf import settings
from django.contrib.auth.models import User
from django.core.files.base import ContentFile
from django.core.mail import send_mail
from django.template.loader import render_to_string
from django.utils.timezone import now

from .models import Creator, VerificationChoices, VerificationCode


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


def send_registration_email(email: str, code: str) -> None:
    subject = "Verify your Notechondria account"
    body = render_to_string(
        "emails/verify_email.txt",
        {
            "email": email,
            "code": code,
            "ttl_hours": settings.EMAIL_VERIFICATION_TTL_HOURS,
            "frontend_verify_url": settings.FRONTEND_VERIFY_URL,
        },
    )
    send_mail(
        subject=subject,
        message=body,
        from_email=settings.DEFAULT_FROM_EMAIL,
        recipient_list=[email],
        fail_silently=False,
    )
