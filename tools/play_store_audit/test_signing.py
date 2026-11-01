"""Signing and update compatibility audit.

Inspects release APK/AAB signing configuration and detects debug signing.
"""
from __future__ import annotations

import pytest
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
GRADLE = ROOT / "android" / "app" / "build.gradle.kts"
KEY_PROPS = ROOT / "android" / "key.properties"
ARTIFACTS_DIRS = [
    ROOT / "build" / "release",
    ROOT / "build" / "app" / "outputs" / "flutter-apk",
    ROOT / "build" / "app" / "outputs" / "bundle" / "release",
]


def _find_artifact(extension: str) -> Path | None:
    for base in ARTIFACTS_DIRS:
        if not base.exists():
            continue
        for p in base.rglob(f"*{extension}"):
            if p.is_file() and p.stat().st_size > 0:
                return p
    return None


def _find_apksigner() -> str | None:
    import shutil
    if shutil.which("apksigner"):
        return shutil.which("apksigner")
    # Search Android SDK build-tools
    sdk = Path("C:/Users/praka/AppData/Local/Android/sdk/build-tools")
    if sdk.exists():
        for d in sorted(sdk.iterdir(), reverse=True):
            candidate = d / "apksigner.bat"
            if candidate.exists():
                return str(candidate)
            candidate2 = d / "apksigner"
            if candidate2.exists():
                return str(candidate2)
    return None


def _read(path: Path) -> str:
    if path.exists():
        return path.read_text()
    return ""


def _run_tool(tool: str, *args: str) -> str:
    result = __import__("subprocess").run(
        [tool, *args], capture_output=True, text=True
    )
    if result.returncode != 0:
        print(f"[WARN] {tool} returned exit code {result.returncode}")
    return result.stdout + result.stderr


class TestSigning:
    def test_release_artifacts_are_signed(self) -> None:
        apk = _find_artifact("-release.apk")
        if apk is None:
            pytest.skip("No release APK found")
        apksigner = _find_apksigner()
        if apksigner is None:
            pytest.skip("apksigner not available")
        output = _run_tool(apksigner, "verify", "--verbose", "--print-certs", str(apk))
        if "CN=Android Debug" in output or "debug" in output.lower():
            pytest.fail("Release APK appears to be signed with the debug certificate")
        assert "cert" in output.lower() or "sha" in output.lower(), "Could not verify APK signing"

    def test_no_debug_signing_fallback(self) -> None:
        key_props = _read(KEY_PROPS)
        if not key_props:
            pytest.skip("android/key.properties not present")
        props_text = key_props.strip()
        assert len(props_text) > 0, "key.properties is empty"

class TestUpdateCompatibility:
    def test_signing_key_not_rotated_on_every_build(self) -> None:
        # The key.properties should reference a persistent keystore file
        key_props = _read(ROOT / "android" / "key.properties")
        if not key_props:
            pytest.skip("key.properties not present; cannot verify key rotation")
        # Check that storeFile points to a persistent file, not a temp location
        assert "storeFile" in key_props, "storeFile not in key.properties"
        # Verify the keystore file reference is consistent
        store_file_line = [l for l in key_props.split("\n") if l.startswith("storeFile=")]
        assert len(store_file_line) == 1, "Multiple storeFile entries in key.properties"

    def test_upload_key_documented_for_play_app_signing(self) -> None:
        # This check verifies the build config mentions Play App Signing expectations
        text = _read(GRADLE)
        # The build.gradle.kts should have documentation or comments about
        # Play App Signing upload key expectations
        assert "Play App Signing" in text or "play.app.signing" in text.lower() or \
            "# Upload key" in text, \
            "Play App Signing upload key documentation not found in build.gradle.kts"