"""Generate Google Play store assets from the real brand artwork.

Play requires:
  * App icon          512 x 512, 32-bit PNG
  * Feature graphic   1024 x 500, PNG/JPEG, no transparency

Both are produced from `assets/icons/weekend_logo.png`, which
`tool/prepare_brand_assets.py` derives from the supplied artwork
(`assets/logo/weekend-logo.jpg`). The script does not draw, approximate or
re-invent the mark: it only scales the real pixels and composites them onto the
brand colour.

The feature graphic is the real logo plus the real tagline - no invented
statistics, no stock people, no competitor branding.

Usage:
    python tool/make_store_assets.py
    python tool/make_store_assets.py --out-dir docs/store-assets
"""

from __future__ import annotations

import argparse
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]

# The delivered artwork, matted to alpha at 1024x1024.
LOGO = ROOT / "assets" / "icons" / "weekend_logo.png"
# The untouched supplied file, used only if the derived master is missing.
LOGO_SOURCE = ROOT / "assets" / "logo" / "weekend-logo.jpg"

# The launcher background the adaptive icon uses (`ic_launcher_background`).
BRAND_BACKGROUND = (13, 8, 24)  # #0D0818
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
    """Scale the real brand artwork to a square RGBA image."""
    from PIL import Image

    source = LOGO if LOGO.exists() else LOGO_SOURCE
    if not source.exists():
        raise SystemExit(
            f"Brand artwork missing: looked for {LOGO} and {LOGO_SOURCE}.\n"
            "Run:  python tool/prepare_brand_assets.py"
        )
    with Image.open(source) as raw:
        image = raw.convert("RGBA")
    if image.size != (size, size):
        image = image.resize((size, size), Image.LANCZOS)
    return image


def _flatten(mark, size: int):
    """Composite the mark onto the brand colour (Play icon: no transparency)."""
    from PIL import Image

    flat = Image.new("RGB", (size, size), BRAND_BACKGROUND)
    flat.paste(mark, (0, 0), mark)
    return flat


def make_icon(out_dir: pathlib.Path, size: int = 512) -> pathlib.Path:
    """512x512 Play icon, composited on the launcher background colour."""
    mark = render_logo_png(size)
    flat = _flatten(mark, size)
    path = out_dir / "play-icon-512.png"
    flat.save(path, "PNG", optimize=True)
    return path


def make_feature_graphic(
    out_dir: pathlib.Path, width: int = 1024, height: int = 500
) -> pathlib.Path:
    """1024x500 feature graphic: real logo and tagline on the brand background."""
    from PIL import Image, ImageDraw

    base = Image.new("RGB", (width, height), BRAND_BACKGROUND)
    draw = ImageDraw.Draw(base)

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
