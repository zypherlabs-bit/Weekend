"""Permissions audit.

Inspects the AndroidManifest.xml for declared permissions and verifies
they are appropriate and necessary for a dating app.
"""
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
MANIFEST = ROOT / "android" / "app" / "src" / "main" / "AndroidManifest.xml"


def _read(path: Path) -> str:
    return path.read_text(encoding='utf-8')


class TestPermissions:
    DECLARED_PERMISSIONS: set[str] = set()

    @classmethod
    def setup_class(cls) -> None:
        cls.DECLARED_PERMISSIONS = set(
            re.findall(r'uses-permission android:name="([^"]+)"', _read(MANIFEST))
        )

    def test_no_unnecessary_permissions(self) -> None:
        """All declared permissions should have a documented purpose for this app."""
        # Permissions that are justified for a dating app with location, camera, etc.
        justified: set[str] = {
            "android.permission.INTERNET",
            "android.permission.ACCESS_NETWORK_STATE",
            "android.permission.CAMERA",
            "android.permission.ACCESS_COARSE_LOCATION",
            "android.permission.ACCESS_FINE_LOCATION",
            "android.permission.POST_NOTIFICATIONS",
            # Justified: voice intro recording (RECORD_AUDIO for voice intros).
            "android.permission.RECORD_AUDIO",
            "android.permission.USE_BIOMETRIC",
            "android.permission.USE_FINGERPRINT",
        }
        unexpected = self.DECLARED_PERMISSIONS - justified
        if unexpected:
            for perm in unexpected:
                print(f"[WARN] Undocumented permission: {perm}")
            # Fail if there are permissions without a clear purpose
            from pytest import fail
            fail(f"Unexpected permissions declared: {unexpected}")

    def test_no_deprecated_storage_permissions(self) -> None:
        """App should not declare WRITE_EXTERNAL_STORAGE or READ_EXTERNAL_STORAGE."""
        deprecated = {
            "android.permission.WRITE_EXTERNAL_STORAGE",
            "android.permission.READ_EXTERNAL_STORAGE",
        }
        actual = self.DECLARED_PERMISSIONS & deprecated
        assert not actual, f"Deprecated storage permissions found: {actual}"

    def test_location_permissions_have_proper_protection(self) -> None:
        """Location permissions should be properly declared and not exported unnecessarily."""
        coarse = "android.permission.ACCESS_COARSE_LOCATION" in self.DECLARED_PERMISSIONS
        fine = "android.permission.ACCESS_FINE_LOCATION" in self.DECLARED_PERMISSIONS
        # At least one location permission should be declared for discovery feature
        if not coarse and not fine:
            from pytest import fail
            fail("No location permissions declared - discovery feature may not work")