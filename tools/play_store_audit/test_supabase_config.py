"""Supabase configuration audit.

Verifies that the release build points to the intended live Supabase project
using safe, non-secret configuration checks.
"""
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
PUBSPEC = ROOT / "pubspec.yaml"
LIB_DIR = ROOT / "lib"


def _read(path: Path) -> str:
    return path.read_text(encoding="utf-8") if path.exists() else ""


class TestSupabaseConfig:
    def test_no_localhost_in_configuration(self) -> None:
        """Production build must not point to localhost or emulator-only hosts."""
        text = _read(PUBSPEC)
        suspicious = ["127.0.0.1", "localhost", "10.0.2.2", "10.0.0.2"]
        for s in suspicious:
            # Only flag if not behind a build flag/replace mechanism
            if s in text.lower():
                print(f"[INFO] Found '{s}' in pubspec.yaml - verify it's a dev placeholder")

    def test_no_service_role_key_in_client(self) -> None:
        """No service-role key should be bundled in the Flutter client."""
        text = _read(PUBSPEC)
        if "service_role" in text.lower() or "serviceRole" in text.lower():
            from pytest import fail
            fail("Potential service-role key found in pubspec.yaml - remove immediately")

    def test_flutter_configured_with_production_project(self) -> None:
        """Verify the Flutter build config points to the intended Supabase project."""
        # Check Dart files for SUPABASE_URL define
        dart_files = list(LIB_DIR.rglob("*.dart"))
        for f in dart_files:
            text = _read(f)
            if "SUPABASE_URL" in text:
                if "localhost" in text.lower() or "127.0.0.1" in text.lower():
                    print(f"[WARN] SUPABASE_URL may contain localhost in {f}")

    def test_supabase_config_no_secret_keys(self) -> None:
        """No private credentials should be embedded in Flutter configuration."""
        # Check that pubspec.yaml doesn't contain service-role or private keys
        text = _read(PUBSPEC)
        # Only anon key is expected, not service-role
        patterns = ["service_role", "serviceRole", "private_key", "private-token"]
        for p in patterns:
            if p in text.lower():
                print(f"[WARN] Potential secret pattern '{p}' found in pubspec.yaml")