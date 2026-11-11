"""Generate synthetic avatar fixtures for the README screenshot harness.

The Weekend promotional imagery must never contain a real person's
photograph.  These fixtures are abstract brand-coloured avatars (gradient +
monogram) so the captured screens show realistic image loading without
publishing anyone's likeness.

Every fixture carries the initials of the synthetic person it stands in for,
so the captured screens stay internally consistent.

Run:  python tool/readme_capture/make_fixtures.py
"""

from __future__ import annotations

import glob
import math
import os

from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "fixtures")

# Brand ramp taken from lib/theme/app_theme.dart
PALETTE = [
    ((0xFF, 0x4B, 0x72), (0xFF, 0x99, 0x66)),   # coral -> peach
    ((0x8B, 0x5C, 0xF6), (0xFF, 0x4B, 0x72)),   # violet -> coral
    ((0x6D, 0x3F, 0xD1), (0xFF, 0xB3, 0x8A)),   # deep violet -> light peach
    ((0xD9, 0x2F, 0x58), (0x6D, 0x3F, 0xD1)),   # deep coral -> deep violet
    ((0xE0, 0x38, 0x5D), (0xFF, 0xB3, 0x8A)),   # dark coral -> light peach
    ((0x8B, 0x5C, 0xF6), (0x6D, 0x3F, 0xD1)),   # violet -> deep violet
    ((0xC8, 0x3A, 0x66), (0x8B, 0x5C, 0xF6)),   # coral -> violet
]

# key, initials - the synthetic people used by fixtures.dart.
# Only the people that appear in a captured screen are generated: Sam Chen and
# Nina Prado on the Discover deck, Diego Ramos in the match list, and Alex
# Rivera as the signed-in demo user.
PEOPLE = [
    ("sc", "SC"),  # Sam Chen - Discover deck, Explore list, match row
    ("np", "NP"),  # Nina Prado - Discover deck, Explore list, match row
    ("dr", "DR"),  # Diego Ramos - Discover deck, Explore list, match row
    ("ar", "AR"),  # Alex Rivera - the signed-in demo user
]

# Which fixture each capture needs.
CARD_PEOPLE = ["sc", "np", "dr"]
SQUARE_PEOPLE = ["sc", "np", "dr", "ar"]


def _lerp(a: int, b: int, t: float) -> int:
    return int(round(a + (b - a) * t))


def _mix(c1, c2, t):
    return tuple(_lerp(c1[i], c2[i], t) for i in range(3))


def _gradient(size, c1, c2, angle_deg):
    """Smooth diagonal two-stop gradient."""
    w, h = size
    base = Image.new("RGB", (w, h), c1)
    top = Image.new("RGB", (w, h), c2)
    mask = Image.new("L", (w, h), 0)
    px = mask.load()
    rad = math.radians(angle_deg)
    dx, dy = math.cos(rad), math.sin(rad)
    span = abs(dx) * w + abs(dy) * h
    ox = 0 if dx >= 0 else w
    oy = 0 if dy >= 0 else h
    for y in range(h):
        for x in range(w):
            t = ((x - ox) * dx + (y - oy) * dy) / span
            px[x, y] = int(max(0.0, min(1.0, t)) * 255)
    return Image.composite(top, base, mask)


def _soft_blob(img, cx, cy, r, colour, alpha=90):
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=colour + (alpha,))
    layer = layer.filter(ImageFilter.GaussianBlur(r * 0.45))
    return Image.alpha_composite(img, layer)


def _font(size):
    try:
        from PIL import ImageFont

        return ImageFont.truetype("arialbd.ttf", int(size))
    except Exception:  # pragma: no cover - font fallback
        return ImageFont.load_default()


def make_avatar(index: int, initials: str, width: int, height: int) -> Image.Image:
    c1, c2 = PALETTE[index % len(PALETTE)]
    img = _gradient((width, height), c1, c2, 30 + (index * 37) % 120).convert("RGBA")

    # Soft light blooms for depth.
    img = _soft_blob(img, width * 0.22, height * 0.20, width * 0.45, (255, 255, 255), 46)
    img = _soft_blob(img, width * 0.85, height * 0.82, width * 0.50, (0, 0, 0), 52)

    # Thin arc for a crafted, editorial feel.
    arc = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    ad = ImageDraw.Draw(arc)
    inset = int(width * 0.16)
    ad.arc(
        [inset, int(height * 0.30), width - inset, int(height * 1.15)],
        start=200,
        end=340,
        fill=(255, 255, 255, 70),
        width=max(3, width // 90),
    )
    img = Image.alpha_composite(img, arc)

    # Monogram.
    glyph = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glyph)
    font = _font(width * 0.26)
    bbox = gd.textbbox((0, 0), initials, font=font)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    gd.text(
        ((width - tw) / 2 - bbox[0], (height - th) / 2 - bbox[1]),
        initials,
        font=font,
        fill=(255, 255, 255, 236),
    )
    img = Image.alpha_composite(img, glyph)
    return img.convert("RGB")


def main() -> None:
    os.makedirs(OUT, exist_ok=True)
    for stale in glob.glob(os.path.join(OUT, "*.png")):
        os.remove(stale)

    made = []
    for i, (key, initials) in enumerate(PEOPLE):
        if key in CARD_PEOPLE:
            card = make_avatar(i, initials, 900, 1200)
            card_path = os.path.join(OUT, f"card_{key}.png")
            card.save(card_path, "PNG", optimize=True)
            made.append(card_path)

        if key in SQUARE_PEOPLE:
            square = make_avatar(i + 3, initials, 600, 600)
            square_path = os.path.join(OUT, f"avatar_{key}.png")
            square.save(square_path, "PNG", optimize=True)
            made.append(square_path)

    for p in made:
        print(f"{os.path.basename(p):>18}  {os.path.getsize(p) / 1024:7.1f} KB")


if __name__ == "__main__":
    main()
