"""Sign in to Weekend as the probe account, starting from onboarding.

walk_signin.py assumes the app opens directly on the sign-in screen and reads
credentials from %TEMP%\\wknd_b_*.txt; neither holds on this machine. This walk
reads PROBE_EMAIL / PROBE_PASSWORD from the repo's .env, taps "Sign in" on the
onboarding carousel, then fills the form.

Coordinates are for the 1080x2400 emulator this repo targets. Each step
screenshots so the next run can be re-aimed without guessing.

Usage: python tool/sign_in_probe.py
"""
from __future__ import annotations

import os
import pathlib
import sys
import time

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from drive import adb, key, screenshot, tap, text  # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parents[1]


def env() -> dict:
    out = {}
    for line in (ROOT / ".env").read_text(encoding="utf-8-sig").splitlines():
        s = line.strip()
        if s and not s.startswith("#") and "=" in s:
            k, v = s.split("=", 1)
            out[k.strip()] = v.strip()
    return out


# Onboarding page 1/3: the sign-in link sits under the Next button.
LINK_SIGN_IN = (540, 2237)

# Measured from the sign-in screen at 1080x2400 (no inline error banner).
FIELD_EMAIL = (540, 594)
FIELD_PASSWORD = (540, 774)
BUTTON_SIGN_IN = (540, 993)


def main() -> int:
    e = env()
    email, password = e["PROBE_EMAIL"], e["PROBE_PASSWORD"]

    adb("shell", "am", "force-stop", "com.zypherlabs.weekend")
    adb("logcat", "-c")
    adb("shell", "am", "start", "-n", "com.zypherlabs.weekend/.MainActivity")
    time.sleep(10)
    screenshot("si_0_launch")

    # Onboarding -> sign-in.
    tap(*LINK_SIGN_IN, wait=3)
    screenshot("si_1_form")

    tap(*FIELD_EMAIL, wait=1)
    text(email)
    key("111", wait=1)  # ESC closes the keyboard

    tap(*FIELD_PASSWORD, wait=1)
    text(password)
    key("111", wait=1)
    screenshot("si_2_filled")

    tap(*BUTTON_SIGN_IN, wait=12)
    screenshot("si_3_after")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
