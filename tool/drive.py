"""Small adb driver used to exercise the app on a device/emulator.

Provides `tap`, `text`, `screenshot` and `dump` so UI walks are written once
instead of being retyped in PowerShell (where quoting is error-prone).
"""
from __future__ import annotations

import os
import re
import subprocess
import sys
import time

ADB = os.path.join(
    os.environ.get("LOCALAPPDATA", ""), "Android", "Sdk", "platform-tools", "adb.exe"
)
SHOT_DIR = os.environ.get("WK_SHOT_DIR", os.environ.get("TEMP", "."))


def adb(*args: str, timeout: int = 120) -> str:
    r = subprocess.run([ADB, *args], capture_output=True, timeout=timeout)
    return r.stdout.decode("utf-8", "replace")


def tap(x: int, y: int, wait: float = 1.5) -> None:
    adb("shell", "input", "tap", str(x), str(y))
    time.sleep(wait)


def text(value: str, wait: float = 1.2) -> None:
    # adb input text has no quoting; spaces must be percent-encoded.
    safe = value.replace(" ", "%s").replace("'", "").replace('"', "")
    adb("shell", "input", "text", safe)
    time.sleep(wait)


def key(code: str, wait: float = 1.0) -> None:
    adb("shell", "input", "keyevent", code)
    time.sleep(wait)


def screenshot(name: str) -> str:
    """Capture the screen and downscale it so it can be viewed inline."""
    remote = f"/sdcard/{name}.png"
    local = os.path.join(SHOT_DIR, f"{name}.png")
    adb("shell", "screencap", "-p", remote)
    adb("pull", remote, local)
    out = local
    try:
        from PIL import Image

        im = Image.open(local)
        im.thumbnail((760, 1700))
        out = os.path.join(SHOT_DIR, f"{name}_s.jpg")
        im.convert("RGB").save(out, "JPEG", quality=72)
    except Exception as exc:  # PIL is optional; keep the raw capture either way
        print(f"(no downscale: {exc})")
    print(f"screenshot: {out}")
    return out


def dump_text() -> list[str]:
    adb("shell", "uiautomator", "dump", "/sdcard/ui.xml")
    xml = adb("shell", "cat", "/sdcard/ui.xml")
    seen: list[str] = []
    for m in re.findall(r'text="([^"]*)"', xml):
        m = m.strip()
        if m and m not in seen:
            seen.append(m)
    return seen


def main() -> int:
    cmd = sys.argv[1] if len(sys.argv) > 1 else "dump"
    if cmd == "tap":
        tap(int(sys.argv[2]), int(sys.argv[3]))
    elif cmd == "text":
        text(sys.argv[2])
    elif cmd == "key":
        key(sys.argv[2])
    elif cmd == "shot":
        screenshot(sys.argv[2])
    elif cmd == "dump":
        for s in dump_text():
            print("  -", s)
    elif cmd == "launch":
        adb("shell", "am", "start", "-n", "com.weekend.app/.MainActivity")
        time.sleep(float(sys.argv[2]) if len(sys.argv) > 2 else 8)
    else:
        print(__doc__)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
