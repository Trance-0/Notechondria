import os
import logging
from io import BytesIO

from PIL import Image, ImageDraw

from django.conf import settings
from django.contrib.auth.models import User
from django.core.files.base import ContentFile

from .models import Creator


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


def mirror_remote_avatar(creator: Creator, *, timeout: int = 8) -> bool:
    """Copy the creator's remote (Casdoor) avatar into our own media
    storage (0.1.184).

    Why: Casdoor serves avatar files WITHOUT CORS headers, and Flutter
    web's renderer refuses to draw cross-origin images without CORS — so
    avatars pointing at the IdP never render in the apps. Our R2/CDN
    media serves with proper CORS, so a mirrored copy renders everywhere.

    Idempotent per avatar change: skips when ``avatar_mirrored_from``
    already equals the current ``avatar_url``. Best-effort — any network
    or validation failure returns False and leaves the creator untouched.
    Returns True when a new copy was stored.
    """
    import requests

    url = (creator.avatar_url or "").strip()
    if not url or creator.avatar_mirrored_from == url:
        return False
    try:
        resp = requests.get(url, timeout=timeout)
    except requests.RequestException:
        return False
    if resp.status_code != 200:
        return False
    content_type = (resp.headers.get("content-type") or "").split(";")[0].strip()
    ext = {
        "image/png": "png",
        "image/jpeg": "jpg",
        "image/gif": "gif",
        "image/webp": "webp",
    }.get(content_type)
    if ext is None:
        return False
    data = resp.content
    if not data or len(data) > 8 * 1024 * 1024:
        return False
    creator.image.save(
        f"casdoor_avatar.{ext}", ContentFile(data), save=False,
    )
    creator.avatar_mirrored_from = url
    creator.save(update_fields=["image", "avatar_mirrored_from"])
    return True


def mirrored_avatar_is_fresh(creator: Creator) -> bool:
    """True when `image` holds a mirror of the CURRENT `avatar_url` —
    i.e. the stored copy can be served instead of the CORS-less IdP URL.

    Field-only check (0.1.185): the original version verified the file
    with ``storage.exists()`` — an R2 network HEAD — and this predicate
    runs per author payload, i.e. per note row. A 193-note course paid
    ~200 storage round-trips (~15 s) for one author. ``mirror_remote_avatar``
    only records ``avatar_mirrored_from`` after a successful save, so the
    field comparison alone is trustworthy."""
    return bool(
        creator.avatar_url
        and creator.avatar_mirrored_from == creator.avatar_url
        and creator.image
        and creator.image.name
    )
