"""Build the promotional README assets from the captured app screens.

The captures in `assets/readme/raw/` are genuine renders of the shipped
Flutter screens. This script dresses them in a consistent device frame and
composes the brand banners, so the whole set reads like one product site.

Run from the repository root:

    python tool/readme_capture/build_readme_assets.py

Outputs (all under `assets/readme/`):

    weekend-logo.png         brand mark on transparency
    weekend-hero.png         1280x640 repository banner / social preview
    weekend-app-preview.png  wide gallery of three screens
    weekend-<screen>.png     one device mockup per captured screen
"""

from __future__ import annotations

import glob
import math
import os

from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
RAW = os.path.join(ROOT, "assets", "readme", "raw")
OUT = os.path.join(ROOT, "assets", "readme")
LOGO_SRC = os.path.join(ROOT, "assets", "icons", "weekend_logo.png")

# Brand tokens - lib/theme/app_theme.dart
NIGHT_TOP = (0x16, 0x0F, 0x26)
NIGHT_MID = (0x0B, 0x07, 0x14)
NIGHT_BOTTOM = (0x1B, 0x10, 0x30)
CORAL = (0xFF, 0x4B, 0x72)
CORAL_DEEP = (0xD9, 0x2F, 0x58)
PEACH = (0xFF, 0x99, 0x66)
VIOLET = (0x8B, 0x5C, 0xF6)
VIOLET_DEEP = (0x6D, 0x3F, 0xD1)
ON_SURFACE = (0xF7, 0xF1, 0xFB)
ON_SURFACE_VARIANT = (0xC9, 0xBB, 0xD5)
BEZEL = (0x14, 0x10, 0x1F)
BEZEL_EDGE = (0x3A, 0x2D, 0x48)

FONT_DIRS = [
    os.path.join(os.environ.get("LOCALAPPDATA", ""), "Pub", "Cache"),
    r"C:\src\flutter-3.41.9\bin\cache\artifacts\material_fonts",
]


# ----------------------------------------------------------------- helpers


def font(size: int, bold: bool = False, light: bool = False) -> ImageFont.FreeTypeFont:
    """Load Roboto from the local Flutter SDK."""
    names = ["roboto-regular.ttf"]
    if bold:
        names = ["roboto-bold.ttf", "roboto-black.ttf"]
    elif light:
        names = ["roboto-light.ttf", "roboto-regular.ttf"]
    for directory in FONT_DIRS:
        for name in names:
            path = os.path.join(directory, name)
            if os.path.isfile(path):
                return ImageFont.truetype(path, size)
            path = os.path.join(directory, "material_fonts", name)
            if os.path.isfile(path):
                return ImageFont.truetype(path, size)
    raise FileNotFoundError("Roboto not found; install the Flutter SDK locally")


def vertical_gradient(size, stops) -> Image.Image:
    """Gradient with (position 0..1, colour) stops."""
    width, height = size
    base = Image.new("RGB", (1, height))
    pixels = base.load()
    stops = sorted(stops)
    for y in range(height):
        t = y / max(1, height - 1)
        for i in range(len(stops) - 1):
            p0, c0 = stops[i]
            p1, c1 = stops[i + 1]
            if p0 <= t <= p1:
                span = max(1e-6, p1 - p0)
                local = (t - p0) / span
                pixels[0, y] = tuple(
                    int(round(c0[k] + (c1[k] - c0[k]) * local)) for k in range(3)
                )
                break
        else:
            pixels[0, y] = stops[-1][1]
    return base.resize((width, height), Image.BICUBIC)


def glow(size, center, radius, colour, alpha) -> Image.Image:
    """Soft radial light on a transparent layer."""
    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    steps = 26
    for i in range(steps, 0, -1):
        r = radius * i / steps
        a = int(alpha * (1 - i / steps) ** 2)
        draw.ellipse(
            [center[0] - r, center[1] - r, center[0] + r, center[1] + r],
            fill=colour + (a,),
        )
    return layer.filter(ImageFilter.GaussianBlur(radius * 0.08))


def atmosphere(size, *, coral_at=None, violet_at=None) -> Image.Image:
    """The app's night backdrop: gradient plus two soft colour glows."""
    canvas = vertical_gradient(
        size, [(0.0, NIGHT_TOP), (0.55, NIGHT_MID), (1.0, NIGHT_BOTTOM)]
    ).convert("RGBA")
    width, height = size
    if coral_at is None:
        coral_at = (width * 0.12, height * 0.92)
    if violet_at is None:
        violet_at = (width * 0.88, height * 0.06)
    canvas = Image.alpha_composite(
        canvas,
        glow(size, violet_at, max(width, height) * 0.42, VIOLET, 92),
    )
    canvas = Image.alpha_composite(
        canvas,
        glow(size, coral_at, max(width, height) * 0.38, CORAL, 74),
    )
    return canvas


def rounded_mask(size, radius) -> Image.Image:
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, size[0] - 1, size[1] - 1], radius, fill=255)
    return mask


def drop_shadow(canvas: Image.Image, shape: Image.Image, offset, blur, opacity) -> None:
    """Paint a blurred silhouette of `shape` behind it on `canvas`."""
    alpha = shape.split()[3] if shape.mode == "RGBA" else shape.convert("L")
    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    silhouette = Image.new("RGBA", shape.size, (0, 0, 0, 0))
    silhouette.putalpha(alpha.point(lambda v: int(v * opacity)))
    shadow.paste(silhouette, offset, silhouette)
    shadow = shadow.filter(ImageFilter.GaussianBlur(blur))
    canvas.alpha_composite(shadow)


def phone(screen_path: str, screen_width: int = 620) -> Image.Image:
    """Wrap a captured screen in a realistic device frame."""
    screen = Image.open(screen_path).convert("RGB")
    ratio = screen.height / screen.width
    screen = screen.resize((screen_width, int(screen_width * ratio)), Image.LANCZOS)

    bezel = max(10, int(screen_width * 0.026))
    radius_out = int(screen_width * 0.095)
    radius_in = max(8, radius_out - bezel)

    device_w = screen.width + bezel * 2
    device_h = screen.height + bezel * 2

    device = Image.new("RGBA", (device_w, device_h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(device)
    draw.rounded_rectangle(
        [0, 0, device_w - 1, device_h - 1], radius_out, fill=BEZEL + (255,)
    )
    # A thin lit edge along the top of the frame.
    draw.rounded_rectangle(
        [0, 0, device_w - 1, device_h - 1], radius_out, outline=BEZEL_EDGE + (190,), width=2
    )

    screen_mask = rounded_mask(screen.size, radius_in)
    device.paste(screen, (bezel, bezel), screen_mask)

    # Punch-hole camera.
    hole_r = max(5, int(screen_width * 0.017))
    cx = device_w // 2
    cy = bezel // 2 + 1
    draw.ellipse(
        [cx - hole_r, cy - hole_r, cx + hole_r, cy + hole_r],
        fill=(0x08, 0x05, 0x10, 255),
    )
    draw.ellipse(
        [cx - hole_r, cy - hole_r, cx + hole_r, cy + hole_r],
        outline=(0x3A, 0x2D, 0x48, 220),
        width=1,
    )
    return device


def place(canvas, device, center, *, rotate=0.0, shadow=True):
    """Paste a device into the canvas with a soft shadow."""
    if rotate:
        device = device.rotate(rotate, resample=Image.BICUBIC, expand=True)
    x = int(center[0] - device.width / 2)
    y = int(center[1] - device.height / 2)
    if shadow:
        drop_shadow(canvas, device, (x, y + int(device.height * 0.035)), 34, 0.55)
    canvas.alpha_composite(device, (x, y))
    return canvas


def raw(name: str) -> str:
    path = os.path.join(RAW, f"{name}.png")
    if not os.path.isfile(path):
        raise FileNotFoundError(path)
    return path


def save(image: Image.Image, name: str) -> None:
    path = os.path.join(OUT, name)
    image.convert("RGB").save(path, "PNG", optimize=True)
    print(f"{name:<28} {image.width}x{image.height}  {os.path.getsize(path) / 1024:7.1f} KB")


# ------------------------------------------------------------------ assets


def build_logo() -> None:
    """Brand mark on transparency, cropped tight and softly lit."""
    logo = Image.open(LOGO_SRC).convert("RGBA")
    bbox = logo.split()[3].getbbox()
    if bbox:
        logo = logo.crop(bbox)
    logo = logo.resize((420, 420), Image.LANCZOS)

    canvas = Image.new("RGBA", (512, 512), (0, 0, 0, 0))
    halo = Image.new("RGBA", (512, 512), (0, 0, 0, 0))
    ImageDraw.Draw(halo).ellipse([96, 96, 416, 416], fill=CORAL + (70,))
    halo = halo.filter(ImageFilter.GaussianBlur(46))
    canvas = Image.alpha_composite(canvas, halo)
    canvas.alpha_composite(logo, (46, 46))

    path = os.path.join(OUT, "weekend-logo.png")
    canvas.save(path, "PNG", optimize=True)
    print(f"{'weekend-logo.png':<28} 512x512  {os.path.getsize(path) / 1024:7.1f} KB")


def build_hero() -> None:
    """The repository banner and GitHub social preview."""
    size = (1280, 640)
    canvas = atmosphere(size, coral_at=(240, 620), violet_at=(1080, 40))

    logo = Image.open(LOGO_SRC).convert("RGBA")
    bbox = logo.split()[3].getbbox()
    if bbox:
        logo = logo.crop(bbox)
    logo = logo.resize((128, 128), Image.LANCZOS)
    canvas.alpha_composite(logo, (96, 104))

    draw = ImageDraw.Draw(canvas)
    draw.text((96, 252), "Weekend", font=font(82, bold=True), fill=ON_SURFACE + (255,))
    draw.text(
        (98, 352),
        "Make Every Weekend Brighter.",
        font=font(31),
        fill=ON_SURFACE_VARIANT + (255,),
    )

    # Coral accent rule under the wordmark.
    accent = Image.new("RGBA", size, (0, 0, 0, 0))
    ImageDraw.Draw(accent).rounded_rectangle(
        [98, 412, 98 + 132, 412 + 7], 4, fill=CORAL + (255,)
    )
    canvas = Image.alpha_composite(canvas, accent)

    draw = ImageDraw.Draw(canvas)
    draw.text(
        (98, 452),
        "Open-source dating & social discovery for Android",
        font=font(21),
        fill=(0x9B, 0x8D, 0xA8, 255),
    )

    # Three screens fanned on the right, centre one in front.
    specs = [
        ("discover", -6.0, 792, 322),
        ("plans", 6.0, 1092, 322),
        ("chat", 0.0, 942, 318),
    ]
    for name, angle, cx, cy in specs:
        device = phone(raw(name), screen_width=236)
        place(canvas, device, (cx, cy), rotate=angle)

    save(canvas, "weekend-hero.png")


def build_app_preview() -> None:
    """A wide gallery of three screens."""
    size = (1600, 940)
    canvas = atmosphere(size, coral_at=(300, 920), violet_at=(1340, 40))

    specs = [("explore", 1116, 470, 4.0), ("discover", 800, 452, 0.0), ("chat", 484, 470, -4.0)]
    for name, cx, cy, angle in specs:
        device = phone(raw(name), screen_width=300)
        place(canvas, device, (cx, cy), rotate=angle)

    save(canvas, "weekend-app-preview.png")


def build_screen_mockups() -> None:
    """One consistent device mockup per captured screen."""
    screens = [
        ("discover", "weekend-discover.png"),
        ("explore", "weekend-explore.png"),
        ("matches", "weekend-matches.png"),
        ("chat", "weekend-chat.png"),
        ("profile", "weekend-profile.png"),
        ("plans", "weekend-plans.png"),
        ("safety", "weekend-privacy.png"),
    ]
    for source, target in screens:
        size = (760, 1520)
        canvas = atmosphere(size, coral_at=(120, 1480), violet_at=(640, 60))
        device = phone(raw(source), screen_width=600)
        place(canvas, device, (size[0] // 2, size[1] // 2 - 10))
        save(canvas, target)


def main() -> None:
    os.makedirs(OUT, exist_ok=True)
    build_logo()
    build_hero()
    build_app_preview()
    build_screen_mockups()
    print()
    print("Raw captures used:")
    for path in sorted(glob.glob(os.path.join(RAW, "*.png"))):
        print(f"  {os.path.basename(path):<16} {os.path.getsize(path) / 1024:7.1f} KB")


if __name__ == "__main__":
    main()
