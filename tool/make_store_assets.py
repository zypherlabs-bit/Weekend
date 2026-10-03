"""Generate Google Play store assets from the committed brand sources.

Play requires:
  * App icon          512 x 512, 32-bit PNG
  * Feature graphic   1024 x 500, PNG/JPEG, no transparency

Both are produced from `assets/icons/weekend_logo.svg`, the same artwork the
in-app launcher icon is built from, so the listing cannot drift from the app.

Nothing here invents brand content: no invented statistics, no stock people, no
competitor branding. The feature graphic is the real logo plus the real
tagline on the brand gradient.

Usage:
    python tool/make_store_assets.py
    python tool/make_store_assets.py --out-dir docs/store-assets
"""

from __future__ import annotations

import argparse
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
SVG = ROOT / "assets" / "icons" / "weekend_logo.svg"

# Brand gradient, identical to the <linearGradient id="bgGrad"> in the SVG and
# to the adaptive-icon background in pubspec.yaml (#FF6C5C).
BRAND_A = (255, 75, 114)  # #FF4B72
BRAND_B = (255, 153, 102)  # #FF9966
TAGLINE = "Make Every Weekend Brighter."


def _require_pillow() -> None:
    try:
        import PIL  # noqa: F401
    except ImportError as exc:  # pragma: no cover - environment issue
        raise SystemExit(
            "Pillow is required to render the store assets.\n"
            "Install it with:  python -m pip install Pillow"
        ) from exc


def render_logo_png(size: int):
    """Rasterise the brand SVG to a square RGBA image.

    cairosvg is preferred because it reproduces the gradients and the glow
    filter faithfully. When it is unavailable we fall back to drawing the mark
    directly with Pillow, which keeps the pipeline usable offline.
    """
    try:
        import io

        import cairosvg
        from PIL import Image

        png = cairosvg.svg2png(url=str(SVG), output_width=size, output_height=size)
        return Image.open(io.BytesIO(png)).convert("RGBA")
    except Exception:
        return _draw_mark_fallback(size)


def _draw_mark_fallback(size: int):
    """Draw the Weekend mark with Pillow only (no SVG rasteriser needed).

    Mirrors the geometry of the SVG: a filled gradient circle, a soft inner
    ring, and the four-stroke "W".
    """
    from PIL import Image, ImageDraw

    ss = 4  # supersample, then downscale for clean edges
    s = size * ss
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # Diagonal gradient background circle.
    grad = Image.new("RGB", (s, s))
    gdraw = ImageDraw.Draw(grad)
    for i in range(s):
        t = i / max(s - 1, 1)
        gdraw.line(
            [(i, 0), (i, s)],
            fill=tuple(round(a + (b - a) * t) for a, b in zip(BRAND_A, BRAND_B)),
        )
    mask = Image.new("L", (s, s), 0)
    ImageDraw.Draw(mask).ellipse([0, 0, s - 1, s - 1], fill=255)
    img.paste(grad, (0, 0), mask)

    # Inner ring.
    draw.ellipse(
        [s * 0.055, s * 0.055, s * 0.945, s * 0.945],
        outline=(255, 255, 255, 77),
        width=max(int(s * 0.008), 1),
    )

    # The "W": two outer verticals joined by two peaks, exactly as the SVG
    # draws it - down the left, up to the centre peak, down to the right, and
    # up the right-hand side. Drawn as one polyline so the joins stay round.
    w = max(int(s * 0.047), 2)
    left, right = s * 0.324, s * 0.676
    top, bottom = s * 0.383, s * 0.617
    mid_x = s * 0.5
    cream = (255, 255, 255, 230)

    points = [
        (left, top),
        (left, bottom),
        (mid_x, top),
        (right, bottom),
        (right, top),
    ]
    draw.line(points, fill=cream, width=w, joint="curve")
    r = w // 2
    for px, py in points:
        draw.ellipse([px - r, py - r, px + r, py + r], fill=cream)

    # Connection dots, as in the SVG.
    for cx, cy, rad, col in (
        (0.324, 0.383, 0.016, (255, 75, 114, 255)),
        (0.5, 0.383, 0.02, (255, 153, 102, 255)),
        (0.676, 0.383, 0.016, (255, 75, 114, 255)),
        (0.324, 0.617, 0.012, (255, 153, 102, 153)),
        (0.676, 0.617, 0.012, (255, 153, 102, 153)),
    ):
        rr = s * rad
        draw.ellipse([s * cx - rr, s * cy - rr, s * cx + rr, s * cy + rr], fill=col)

    return img.resize((size, size), Image.LANCZOS)


def make_icon(out_dir: pathlib.Path, size: int = 512) -> pathlib.Path:
    """512x512 Play icon. Play accepts alpha, but a solid mark is safer."""
    from PIL import Image

    mark = render_logo_png(size)
    flat = Image.new("RGB", (size, size), BRAND_A)
    flat.paste(mark, (0, 0), mark)
    path = out_dir / "play-icon-512.png"
    flat.save(path, "PNG", optimize=True)
    return path


def make_feature_graphic(
    out_dir: pathlib.Path, width: int = 1024, height: int = 500
) -> pathlib.Path:
    """1024x500 feature graphic: brand gradient, real logo, real tagline.

    Play requires no transparency here, so the artwork is composited onto the
    gradient rather than saved with an alpha channel.
    """
    from PIL import Image, ImageDraw

    base = Image.new("RGB", (width, height), BRAND_A)
    draw = ImageDraw.Draw(base)
    for y in range(height):
        t = y / max(height - 1, 1)
        draw.line(
            [(0, y), (width, y)],
            fill=tuple(round(a + (b - a) * t) for a, b in zip(BRAND_A, BRAND_B)),
        )

    logo_px = int(height * 0.66)
    mark = render_logo_png(logo_px)
    lx = int(width * 0.055)
    ly = (height - logo_px) // 2
    base.paste(mark, (lx, ly), mark)

    text_x = lx + logo_px + int(width * 0.045)
    draw.text(
        (text_x, height * 0.34),
        "Weekend",
        font=_load_font(int(height * 0.135)),
        fill=(255, 255, 255),
    )
    draw.text(
        (text_x, height * 0.55),
        TAGLINE,
        font=_load_font(int(height * 0.068)),
        fill=(255, 255, 255),
    )

    path = out_dir / "play-feature-graphic-1024x500.png"
    base.save(path, "PNG", optimize=True)
    return path


def _load_font(size: int):
    """Prefer a real UI font so the wordmark does not render as boxes."""
    from PIL import ImageFont

    for name in (
        "segoeuib.ttf",
        "arialbd.ttf",
        "arial.ttf",
        "DejaVuSans-Bold.ttf",
        "DejaVuSans.ttf",
    ):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            continue
    return ImageFont.load_default()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--out-dir",
        default=str(ROOT / "docs" / "store-assets"),
        help="directory to write the PNG assets into",
    )
    args = parser.parse_args()

    _require_pillow()
    out = pathlib.Path(args.out_dir)
    out.mkdir(parents=True, exist_ok=True)

    for path in (make_icon(out), make_feature_graphic(out)):
        print(f"{path}  ({path.stat().st_size / 1024:.1f} KiB)")
    return 0


if __name__ == "__main__":
    sys.exit(main())