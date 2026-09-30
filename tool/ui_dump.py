"""Dump the visible text of the foreground activity (debugging aid)."""
import os
import re
import subprocess
import sys

ADB = os.path.join(
    os.environ.get("LOCALAPPDATA", ""), "Android", "Sdk", "platform-tools", "adb.exe"
)


def main() -> int:
    subprocess.run([ADB, "shell", "uiautomator", "dump", "/sdcard/ui.xml"],
                   capture_output=True, timeout=90)
    out = subprocess.run([ADB, "shell", "cat", "/sdcard/ui.xml"],
                         capture_output=True, timeout=90)
    xml = out.stdout.decode("utf-8", "replace")
    seen: list[str] = []
    for m in re.findall(r'text="([^"]*)"', xml):
        m = m.strip()
        if m and m not in seen:
            seen.append(m)
    if not seen:
        print("(no visible text - the activity may be blank or still loading)")
    for s in seen:
        print("  -", s)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
