"""Drive Weekend from launch to the passkey button and tap it.

Kept as a script (not inline adb calls) so the whole walk is reproducible and
the resulting logcat slice can be captured the same way every time.
"""
from __future__ import annotations

import subprocess
import sys
import time

sys.path.insert(0, __file__.rsplit("\\", 1)[0])
from drive import ADB, adb, screenshot, tap  # noqa: E402


def main() -> int:
    adb("shell", "am", "force-stop", "com.weekend.app")
    adb("logcat", "-c")
    adb("shell", "am", "start", "-n", "com.weekend.app/.MainActivity")
    time.sleep(12)

    # Onboarding carousel -> "Already have an account? Sign in"
    tap(540, 2181, wait=4)
    screenshot("walk_signin")

    # "Sign in with Passkey" sits below the email/password fields.
    tap(540, 1368, wait=8)
    screenshot("walk_passkey")

    out = subprocess.run(
        [ADB, "logcat", "-d", "-v", "brief"],
        capture_output=True,
        timeout=120,
    ).stdout.decode("utf-8", "replace")
    keys = (
        "CredentialManager",
        "Passkey",
        "passkey",
        "Assertion",
        "assetlink",
        "AssetLink",
        "credential",
    )
    hits = [ln for ln in out.splitlines() if any(k in ln for k in keys)]
    print("=== relevant logcat ===")
    for ln in hits[-25:]:
        print(" ", ln[:200])
    if not hits:
        print("  (no credential/passkey lines at all)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
