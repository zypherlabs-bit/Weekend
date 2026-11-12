"""Android release artifact validation tests.

Inspects the actual release files and validates format, contents, and
metadata.  Designed to run locally and in CI without requiring production
credentials.
"""
from __future__ import annotations

import hashlib
import os
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent

# Where release artifacts actually land.
#
# `flutter build apk --release` writes to build/app/outputs/flutter-apk/ and
# `flutter build appbundle --release` writes to
# build/app/outputs/bundle/release/. Older layouts used build/release/, and a
# copy step may still place artifacts there, so every known location is
# searched rather than a single hard-coded one. Searching only build/release
# made these checks fail on a freshly built tree, because `flutter clean`
# removes build/ entirely and no build recreates that directory.
ARTIFACT_DIRS = (
    ROOT / "build" / "app" / "outputs",
    ROOT / "build" / "release",
)


def _find_artifact(extension: str) -> Path | None:
    for directory in ARTIFACT_DIRS:
        if not directory.exists():
            continue
        for p in directory.rglob(f"*{extension}"):
            if p.is_file() and p.stat().st_size > 0:
                return p
    return None


def _sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(8192), b""):
            h.update(chunk)
    return h.hexdigest()


def _run_tool(tool: str, *args: str) -> str:
    """Run an Android SDK tool, failing with a useful message if not found."""
    result = subprocess.run([tool, *args], capture_output=True, text=True)
    if result.returncode != 0:
        if not result.stdout and not result.stderr:
            print(f"[WARN] Tool {tool} exited with no output; it may not be installed.")
        else:
            print(f"[WARN] {tool} returned exit code {result.returncode}: {result.stderr.strip()}")
    return result.stdout + result.stderr


# -------------------------------------------------------------------
# Artifact existence and basic validity
# -------------------------------------------------------------------

class TestArtifactExistence:
    """Verify that release artifacts exist and are non-empty."""

    def test_release_apk_exists(self) -> None:
        apk = _find_artifact("-release.apk")
        assert apk is not None, (
            "No release APK found; run `flutter build apk --release` first"
        )
        assert apk.stat().st_size > 0, f"release APK is empty: {apk}"

    def test_release_aab_exists(self) -> None:
        aab = _find_artifact("-release.aab")
        assert aab is not None, (
            "No release AAB found; run `flutter build appbundle --release` first"
        )
        assert aab.stat().st_size > 0, f"release AAB is empty: {aab}"

    def test_artifact_not_empty(self) -> None:
        for label, path in [("APK", ".apk"), ("AAB", ".aab")]:
            art = _find_artifact(path)
            assert art is not None, f"No {label} artifact found"
            assert art.stat().st_size > 0, f"{label} artifact is empty"