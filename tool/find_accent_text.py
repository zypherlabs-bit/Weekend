"""Weekend - locate tappable text in a device screenshot.

Flutter renders to a canvas, so ``uiautomator dump`` exposes no widget nodes.
This reads a pulled screenshot and reports the bounding box of coral-coloured
(accent) text, so UI automation can tap exact pixel coordinates.

Usage:  python tool/find_accent_text.py <screenshot.png>
"""
from __future__ import annotations

import sys

from PIL import Image

# The brand accent used for the primary button and the "Sign in" link.
ACCENT = (242, 108, 92)
TOLERANCE = 60


def main() -> int:
    path = sys.argv[1]
    img = Image.open(path).convert("RGB")
    w, h = img.size
    px = img.load()

    # Count accent-ish pixels per row, ignoring the big filled CTA button
    # (which spans a very wide run) so text links stand out.
    rows: dict[int, int] = {}
    for y in range(h):
        count = 0
        for x in range(0, w, 3):
            r, g, b = px[x, y]
            if (abs(r - ACCENT[0]) < TOLERANCE and abs(g - ACCENT[1]) < TOLERANCE
                    and abs(b - ACCENT[2]) < TOLERANCE):
                count += 1
        if count:
            rows[y] = count

    if not rows:
        print("no accent pixels found")
        return 1

    # Group contiguous rows into bands.
    bands: list[list[int]] = []
    for y in sorted(rows):
        if bands and y - bands[-1][-1] <= 3:
            bands[-1].append(y)
        else:
            bands.append([y])

    print(f"image {w}x{h}")
    for band in bands:
        y0, y1 = band[0], band[-1]
        width = max(rows[y] for y in band) * 3
        print(f"  band y={y0}..{y1} (height={y1 - y0 + 1}, max_run~{width}px)"
              f"  -> tap centre (540, {(y0 + y1) // 2})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
