"""Sign in to Weekend on a connected device with the stored test account.

Reaches the app so the photo picker/upload path can be exercised for real
rather than only through an API probe. Coordinates are for the 1080x2400
emulator this repo is developed against; each step screenshots so the next
run can be re-aimed without guessing.
"""
from __future__ import annotations

import pathlib
import sys
import tempfile
import time

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from drive import adb, screenshot, tap, text  # noqa: E402

EMAIL = (pathlib.Path(tempfile.gettempdir()) / "wknd_b_email.txt").read_text(
    encoding="utf-8"
).strip()
PASSWORD = (pathlib.Path(tempfile.gettempdir()) / "wknd_b_pw.txt").read_text(
    encoding="utf-8"
).strip()

# Measured from the sign-in screen at 1080x2400 (no inline error banner shown).
FIELD_EMAIL = (540, 594)
FIELD_PASSWORD = (540, 774)
BUTTON_SIGN_IN = (540, 993)


def main() -> int:
    adb("shell", "am", "force-stop", "com.weekend.app")
    adb("logcat", "-c")
    adb("shell", "am", "start", "-n", "com.weekend.app/.MainActivity")
    time.sleep(12)
    screenshot("si_0_launch")

    tap(*FIELD_EMAIL, wait=1)
    text(EMAIL)
    adb("shell", "input", "keyevent", "111")  # ESC closes the keyboard
    time.sleep(1)

    tap(*FIELD_PASSWORD, wait=1)
    text(PASSWORD)
    adb("shell", "input", "keyevent", "111")
    time.sleep(1)
    screenshot("si_1_filled")

    tap(*BUTTON_SIGN_IN, wait=10)
    screenshot("si_2_after")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
