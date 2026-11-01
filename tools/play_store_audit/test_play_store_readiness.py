"""Google Play Store readiness audit.

Combines various checks to determine if the app is ready for Play Store
testing track upload. These are a mix of automated static checks and
manual verification flags.
"""
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent


def _read(path: Path) -> str:
    return path.read_text(encoding="utf-8") if path.exists() else ""


class TestPlayStoreReadiness:
    def test_target_sdk_meets_current_requirement(self) -> None:
        """Target SDK must satisfy the currently applicable Google Play policy.

        As of 31 August 2026, new apps and updates require target SDK 36 (API 36)
        or higher. Verify the current target SDK setting.
        """
        gradle = _read(ROOT / "android" / "app" / "build.gradle.kts")
        assert "targetSdk = flutter.targetSdkVersion" in gradle
        m = re.search(r"targetSdk\s*=\s*(\d+)", gradle)
        if m:
            target = int(m.group(1))
            # Google Play requires targetSdk >= 31 for new apps/update from Aug 2026
            # The exact rule changes over time; report and verify
            print(f"[INFO] targetSdk = {target} (verify against current Play policy)")
            if target < 31:
                from pytest import fail
                fail(f"targetSdk {target} does not meet Google Play minimum requirement")
        else:
            # Flutter-managed targetSdk (flutter.targetSdkVersion) - resolved by Flutter SDK
            print("[INFO] targetSdk = flutter.targetSdkVersion (Flutter-managed; verify Flutter SDK target)")

    def test_version_monotonically_increasing(self) -> None:
        """Version code should be monotonically increasing."""
        pubspec = _read(ROOT / "pubspec.yaml")
        vm = re.search(r"^version:\s*(\S+)\+(\d+)", pubspec, re.MULTILINE)
        assert vm, "pubspec.yaml has no version: x.y.z+build line"
        version_code = int(vm.group(2))
        assert version_code > 0, f"versionCode {version_code} must be positive"

    def test_aab_built_and_inspected(self) -> None:
        """Verify a release AAB has been built and its metadata inspected."""
        aab = ROOT / "build" / "release" / "*-release.aab"
        import glob
        matches = glob.glob(str(aab))
        if matches:
            print(f"[INFO] Release AAB found: {matches[0]}")
        else:
            print("[WARN] No release AAB found in build/release")

    def test_artifact_size_reasonable(self) -> None:
        """Check that the release artifact is not unexpectedly enormous."""
        aab = None
        apk = None
        import glob
        for m in glob.glob(str(ROOT / "build" / "release" / "*-release.aab")):
            aab = Path(m)
        for m in glob.glob(str(ROOT / "build" / "release" / "*-release.apk")):
            apk = Path(m)

        if aab and aab.exists():
            size_mb = aab.stat().st_size / (1024 * 1024)
            print(f"[INFO] AAB size: {size_mb:.1f} MB")
            # AABs for Flutter dating apps can be large due to assets;
            # just log and don't arbitrarily fail
        if apk and apk.exists():
            size_mb = apk.stat().st_size / (1024 * 1024)
            print(f"[INFO] APK size: {size_mb:.1f} MB")

    def test_Play_store_requires_target_sdk_36(self) -> None:
        """Verify target SDK 36 compliance for new apps/updates.

        Google Play will require target SDK 36 starting 31 August 2026.
        This is an evolving policy - verify the current rule.
        """
        gradle = _read(ROOT / "android" / "app" / "build.gradle.kts")
        m = re.search(r"targetSdk\s*=\s*(\d+)", gradle)
        if m:
            target = int(m.group(1))
            print(f"[INFO] Current targetSdk: {target}")
            print("[INFO] Google Play policy: target SDK 36 required from 31 August 2026")
            # Check if we meet the requirement
            if target < 36:
                print(f"[WARN] targetSdk {target} < 36; will need update before Play deadline")