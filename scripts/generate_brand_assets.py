"""Generate the public-facing brand assets that ship in `/media/`:
``logo.png``, ``favicon.png``, and ``default_avatar.png``.

Brand color is the same teal the existing Flutter favicons use
(``rgb(15, 118, 110)`` / ``#0F766E``); the brand mark is the
curly-brace-asterisk-curly-brace pattern from
``frontend/portal_app/web/icons/Icon-512.png``. This script reuses the
existing icon as the source-of-truth for the mark so the wordmark
matches the favicon byte-for-byte.

Run from repo root:

    python scripts/generate_brand_assets.py

Outputs:

* ``media/logo.png`` — wordmark "{ * } Notechondria", brand mark on
  the left + bold sans-serif on the right.
* ``media/favicon.png`` — copy of the existing
  ``frontend/portal_app/web/favicon.png`` so backend templates and
  shareable links can point at a stable URL.
* ``media/default_avatar.png`` — solid teal circle with a white
  asterisk (the central glyph of the brand mark), 512x512. Used as
  the fallback when a user has not uploaded an avatar.
"""

from __future__ import annotations

import shutil
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

REPO_ROOT = Path(__file__).resolve().parent.parent
MEDIA = REPO_ROOT / "media"
SOURCE_FAVICON = REPO_ROOT / "frontend" / "portal_app" / "web" / "favicon.png"
SOURCE_ICON_512 = REPO_ROOT / "frontend" / "portal_app" / "web" / "icons" / "Icon-512.png"

BRAND_TEAL = (15, 118, 110, 255)
BRAND_TEAL_HEX = "#0F766E"


def _font(size: int) -> ImageFont.FreeTypeFont:
    """Pick the heaviest reasonable sans-serif on the host. We try a
    short list rather than ship a font binary into the repo — the
    caller runs this on the build machine, which always has *some*
    bold sans-serif available."""
    candidates = [
        r"C:\Windows\Fonts\segoeuib.ttf",
        r"C:\Windows\Fonts\arialbd.ttf",
        r"C:\Windows\Fonts\calibrib.ttf",
        # Linux / macOS fallbacks for CI / dev containers.
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
        "/System/Library/Fonts/Helvetica.ttc",
    ]
    for path in candidates:
        try:
            return ImageFont.truetype(path, size)
        except OSError:
            continue
    return ImageFont.load_default()


def make_favicon():
    """Copy the existing favicon into /media so backend templates and
    shareable links can resolve a stable path. The existing favicon is
    the canonical brand mark — re-deriving it loses fidelity."""
    target = MEDIA / "favicon.png"
    shutil.copyfile(SOURCE_FAVICON, target)
    print(f"wrote {target.relative_to(REPO_ROOT)} ({target.stat().st_size} bytes, copied from frontend favicon)")


def make_logo():
    """Wordmark = brand mark + "Notechondria" in bold sans-serif.

    The mark on the left is the existing 512x512 icon downscaled to
    the wordmark's cap-height. The text on the right is rendered with
    the brand teal so the whole wordmark sits as one coherent unit
    against any background.
    """
    mark_src = Image.open(SOURCE_ICON_512).convert("RGBA")

    # Wordmark canvas height drives the mark height. 256 px of cap
    # height feels right for retina-friendly hero placements.
    canvas_h = 256
    mark_size = canvas_h  # full-height brand mark

    # Resize the mark with high-quality resampling.
    mark = mark_src.resize((mark_size, mark_size), Image.LANCZOS)

    # Pick a font size that gives a visually balanced wordmark.
    # Roughly 60% of canvas height tends to look right for a single
    # word with descender ("d", "p", "y").
    font = _font(int(canvas_h * 0.65))

    # Measure the text bounding box at the chosen font.
    text = "Notechondria"
    tmp_img = Image.new("RGBA", (1, 1))
    tmp_draw = ImageDraw.Draw(tmp_img)
    text_left, text_top, text_right, text_bottom = tmp_draw.textbbox(
        (0, 0), text, font=font
    )
    text_w = text_right - text_left
    text_h = text_bottom - text_top

    # Layout: mark | gap | text
    gap = canvas_h // 8
    canvas_w = mark_size + gap + text_w + canvas_h // 16  # trailing pad
    canvas = Image.new("RGBA", (canvas_w, canvas_h), (0, 0, 0, 0))

    # Paste the mark flush-left, vertically centered.
    canvas.alpha_composite(mark, (0, 0))

    # Draw the text, vertically centered on the mark's optical center.
    # PIL's textbbox returns coordinates relative to the text origin,
    # so we offset by -text_top to get the visible glyphs aligned.
    draw = ImageDraw.Draw(canvas)
    text_x = mark_size + gap
    text_y = (canvas_h - text_h) // 2 - text_top
    draw.text((text_x, text_y), text, font=font, fill=BRAND_TEAL)

    target = MEDIA / "logo.png"
    canvas.save(target, "PNG", optimize=True)
    print(
        f"wrote {target.relative_to(REPO_ROOT)} "
        f"({canvas_w}x{canvas_h}, {target.stat().st_size} bytes)"
    )


def make_default_avatar():
    """Solid teal circle + white asterisk glyph in the middle.

    The asterisk echoes the brand mark's central glyph without
    duplicating the curly braces, so a user grid of default avatars
    doesn't end up looking like rows of identical favicons.
    """
    size = 512
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(canvas)
    draw.ellipse((0, 0, size, size), fill=BRAND_TEAL)

    # Render a six-pointed asterisk as a bold "*" character. Using a
    # font glyph rather than vector strokes keeps the render
    # consistent with the favicon's central glyph.
    font = _font(int(size * 0.7))
    glyph = "*"
    text_left, text_top, text_right, text_bottom = draw.textbbox(
        (0, 0), glyph, font=font
    )
    glyph_w = text_right - text_left
    glyph_h = text_bottom - text_top
    # Center the glyph optically — text origin is the baseline, so we
    # offset by -text_top to align the visible top.
    x = (size - glyph_w) // 2 - text_left
    y = (size - glyph_h) // 2 - text_top
    draw.text((x, y), glyph, font=font, fill=(255, 255, 255, 255))

    target = MEDIA / "default_avatar.png"
    canvas.save(target, "PNG", optimize=True)
    print(
        f"wrote {target.relative_to(REPO_ROOT)} "
        f"({size}x{size}, {target.stat().st_size} bytes)"
    )


def main():
    if not MEDIA.exists():
        raise SystemExit(
            "Cannot generate brand assets: "
            "Scripts.GenerateBrandAssets/main — "
            f"target directory {MEDIA} does not exist. Create it first."
        )
    if not SOURCE_FAVICON.exists():
        raise SystemExit(
            "Cannot generate brand assets: "
            "Scripts.GenerateBrandAssets/main — "
            f"source favicon {SOURCE_FAVICON} not found."
        )
    make_favicon()
    make_logo()
    make_default_avatar()
    print(f"done. brand color = {BRAND_TEAL_HEX}")


if __name__ == "__main__":
    main()
