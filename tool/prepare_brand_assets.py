#!/usr/bin/env python3
"""Prepare Weekend launcher / splash / in-app brand assets.

Source of truth
---------------
`assets/logo/weekend-logo.jpg` is the supplied 1254x1254 brand artwork (the
3-D ribbon "W" on a black field).  It is a JPEG, so it has no alpha channel.
The script derives a transparent master by treating the black field as a
matte and un-premultiplying the artwork, then emits:

  assets/icons/weekend_logo.png            transparent in-app / splash master
  assets/icons/weekend_logo_fg.png         transparent adaptive-icon foreground
  assets/icons/weekend_logo_legacy.png     opaque square launcher master
  assets/icons/weekend_logo_monochrome.png white Android 13 themed-icon mask
  android/.../drawable-nodpi/weekend_splash_logo.png
  android/.../drawable-*/weekend_notification_icon.png

Run from the repository root:

  python tool/prepare_brand_assets.py
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets" / "logo" / "weekend-logo.jpg"
ICONS = ROOT / "assets" / "icons"
ANDROID_RES = ROOT / "android" / "app" / "src" / "main" / "res"

# The artwork's own background is near-black; a few JPEG units of noise must
# not become a translucent grey haze around the mark.
BLACK_FLOOR = 6
ALPHA_GAIN = 255 / (255 - BLACK_FLOOR)

# Launcher / splash geometry.  Android adaptive icons crop aggressively, so
# the foreground mark is deliberately smaller than the legacy square mark.
ADAPTIVE_MARK_FRACTION = 0.62
LEGACY_MARK_FRACTION = 0.80
SPLASH_MARK_FRACTION = 0.86

ICON_BACKGROUND = (13, 8, 24, 255)  # #0D0818 - matches the Night palette.


def remove_black_matte(source: Image.Image) -> Image.Image:
    """Return an RGBA image with the black studio background removed."""

    rgb = source.convert("RGB")
    out = Image.new("RGBA", rgb.size)
    src = rgb.load()
    dst = out.load()
    width, height = rgb.size

    for y in range(height):
        for x in range(width):
            r, g, b = src[x, y]
            peak = max(r, g, b)
            if peak <= BLACK_FLOOR:
                dst[x, y] = (0, 0, 0, 0)
                continue

            # The source is a photograph of a logo on black: observed colour is
            # foreground * alpha. Recover both, so the mark keeps its colour
            # when composited over light glass instead of carrying a black halo.
            alpha = min(255, round((peak - BLACK_FLOOR) * ALPHA_GAIN))
            scale = 255 / alpha
            dst[x, y] = (
                min(255, round(r * scale)),
                min(255, round(g * scale)),
                min(255, round(b * scale)),
                alpha,
            )
    return out


def content_bbox(image: Image.Image, threshold: int = 12) -> tuple[int, int, int, int]:
    """Bounding box of pixels with meaningful alpha."""

    alpha = image.getchannel("A")
    mask = alpha.point(lambda v: 255 if v > threshold else 0)
    bbox = mask.getbbox()
    if bbox is None:
        raise SystemExit("Brand artwork appears to be empty")
    return bbox


def square_with_padding(
    image: Image.Image, mark_fraction: float, canvas_size: int
) -> Image.Image:
    """Crop the mark, then centre it on a square canvas at a known size."""

    mark = image.crop(content_bbox(image))
    target = max(1, round(canvas_size * mark_fraction))
    if mark.width >= mark.height:
        width = target
        height = max(1, round(mark.height * target / mark.width))
    else:
        height = target
        width = max(1, round(mark.width * target / mark.height))
    mark = mark.resize((width, height), Image.Resampling.LANCZOS)

    canvas = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    canvas.alpha_composite(
        mark,
        ((canvas_size - width) // 2, (canvas_size - height) // 2),
    )
    return canvas


def save(image: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, optimize=True)
    print(f"wrote {path.relative_to(ROOT)}  ({path.stat().st_size:,} bytes)")


def main() -> None:
    if not SOURCE.exists():
        raise SystemExit(
            f"Missing brand source {SOURCE}. Copy the supplied logo to "
            "assets/logo/weekend-logo.jpg first."
        )

    with Image.open(SOURCE) as opened:
        master = remove_black_matte(opened)

    master.save(ICONS / "weekend_logo_source.png", optimize=True)
    print(f"wrote {(ICONS / 'weekend_logo_source.png').relative_to(ROOT)}")

    # In-app master: transparent, with a comfortable margin so it can be used
    # at any size without clipping the glow.
    in_app = square_with_padding(master, 0.88, 1024)
    save(in_app, ICONS / "weekend_logo.png")

    # Adaptive foreground: Android masks the outer ~18% of an adaptive icon,
    # so the mark is kept inside the 66% safe zone.
    save(square_with_padding(master, ADAPTIVE_MARK_FRACTION, 1024),
         ICONS / "weekend_logo_fg.png")

    # Legacy opaque square icon.  A full-bleed plate matches what users see in
    # launchers that do not support adaptive icons; no rounded corners are
    # drawn because the launcher applies its own mask.
    legacy = Image.new("RGBA", (1024, 1024), ICON_BACKGROUND)
    legacy.alpha_composite(square_with_padding(master, LEGACY_MARK_FRACTION, 1024))
    save(legacy, ICONS / "weekend_logo_legacy.png")

    # Android 13 monochrome themed icon: silhouette only.  Paste solid white
    # through the alpha mask rather than compositing, which would retain the
    # source colours.
    mono = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
    silhouette = square_with_padding(master, ADAPTIVE_MARK_FRACTION, 1024)
    mono.paste((255, 255, 255, 255), (0, 0), silhouette.getchannel("A"))
    save(mono, ICONS / "weekend_logo_monochrome.png")

    # Android splash artwork (transparent; the launch theme supplies #130E20).
    save(square_with_padding(master, SPLASH_MARK_FRACTION, 512),
         ANDROID_RES / "drawable-nodpi" / "weekend_splash_logo.png")

    # Notification small icons must be a white silhouette on transparent, not
    # the full-colour launcher icon.
    notification = square_with_padding(master, 0.88, 96)
    white_icon = Image.new("RGBA", notification.size, (0, 0, 0, 0))
    white_icon.paste((255, 255, 255, 255), (0, 0), notification.getchannel("A"))
    notification = white_icon
    for folder, size in {
        "drawable-mdpi": 24,
        "drawable-hdpi": 36,
        "drawable-xhdpi": 48,
        "drawable-xxhdpi": 72,
        "drawable-xxxhdpi": 96,
    }.items():
        save(
            notification.resize((size, size), Image.Resampling.LANCZOS),
            ANDROID_RES / folder / "weekend_notification_icon.png",
        )


if __name__ == "__main__":
    main()
