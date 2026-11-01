"""Reliable emulator screenshot + tap helpers.

Works around two Windows issues seen this session:
  1. /sdcard FUSE mount goes dead -> use `exec-out` to stream bytes over adb
     instead of writing to shared storage.
  2. PowerShell's `>` re-encodes binary to UTF-16, corrupting PNGs -> Python
     writes the raw bytes itself.

Usage: python tool/shot.py <name>
       Prints the local path of the downscaled JPEG for inline review.
"""
from __future__ import annotations

import os
import pathlib
import subprocess
import sys

ADB = os.path.join(
    os.environ.get("LOCALAPPDATA", ""), "Android", "Sdk", "platform-tools", "adb.exe"
)
SERIAL = "emulator-5554"
OUT_DIR = pathlib.Path(os.environ.get("TEMP", "."))


def screencap(name: str = "shot") -> pathlib.Path:
    r = subprocess.run(
        [ADB, "-s", SERIAL, "exec-out", "screencap", "-p"],
        capture_output=True,
        timeout=60,
    )
    png = OUT_DIR / f"{name}.png"
    png.write_bytes(r.stdout)

    out = OUT_DIR / f"{name}_s.jpg"
    try:
        from PIL import Image

        im = Image.open(png)
        im.thumbnail((740, 1650))
        im.convert("RGB").save(out, "JPEG", quality=72)
        print(str(out))
    except Exception as exc:
        print(f"PNG saved but no thumbnail: {exc}", file=sys.stderr)
        print(str(png))
    return png


def tap(x: int, y: int, wait: float = 2.0) -> None:
    subprocess.run(
        [ADB, "-s", SERIAL, "shell", "input", "tap", str(x), str(y)],
        capture_output=True,
        timeout=60,
    )
    import time

    time.sleep(wait)


def main() -> int:
    cmd = sys.argv[1] if len(sys.argv) > 1 else "shot"
    if cmd == "tap":
        tap(int(sys.argv[2]), int(sys.argv[3]),
            float(sys.argv[4]) if len(sys.argv) > 4 else 2.0)
        return 0
    screencap(sys.argv[2] if len(sys.argv) > 2 else "shot")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
