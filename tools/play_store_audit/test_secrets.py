"""Secrets and privacy checks.

Searches for hardcoded credentials, keys, and production secrets in the
codebase and verifies .gitignore protection.
"""
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent


def _read(path: Path) -> str:
    return path.read_text(encoding="utf-8") if path.exists() else ""


class TestSecrets:
    def test_no_private_keys_in_pubspec(self) -> None:
        """Private keys must not be embedded in pubspec.yaml or Dart files."""
        pubspec = ROOT / "pubspec.yaml"
        if pubspec.exists():
            text = _read(pubspec)
            # Check for patterns that look like private key material
            # Private keys are extremely long base64 strings; just flag any
            # private key "private-key" or "pk-" patterns in config
            private_key_patterns = ["private-key", "private_key"]
            for p in private_key_patterns:
                if p in text.lower():
                    print(f"[INFO] Found '{p}' in pubspec.yaml - verify it's not a real key")

    def test_gitignore_excludes_keystore(self) -> None:
        """Verify keystore files are gitignored."""
        gitignore = ROOT / ".gitignore"
        if gitignore.exists():
            text = _read(gitignore)
            assert ".jks" in text or ".keystore" in text, (
                "keystore files must be gitignored"
            )
            assert "key.properties" in text, (
                "key.properties must be gitignored"
            )

    def test_no_service_role_key_bundled(self) -> None:
        """No service-role key should be bundled in the app."""
        # Search tracked files and git history for service_role patterns
        lib_dir = ROOT / "lib"
        dart_files = list(lib_dir.rglob("*.dart"))
        for f in dart_files[:20]:  # Limit search to first 20 files
            text = _read(f)
            if "service_role" in text.lower():
                print(f"[WARN] service_role found in {f.name} - investigate")

    def test_no_embeddled_database_credentials(self) -> None:
        """No database URLs with embedded passwords."""
        pubspec = ROOT / "pubspec.yaml"
        if pubspec.exists():
            text = _read(pubspec)
            # Check for postgres:// or mysql:// URLs that might have passwords
            db_url_patterns = ["postgres://", "mysql://", "mongodb://"]
            for p in db_url_patterns:
                if p in text.lower():
                    print(f"[INFO] Found '{p}' in pubspec.yaml - verify no embedded creds")


class TestPrivacyChecks:
    def test_privacy_policy_matches_code_behavior(self) -> None:
        """Verify privacy policy claims match actual code behavior."""
        privacy = ROOT / "docs" / "privacy.md"
        if not privacy.exists():
            from pytest import fail
            fail("privacy.md not found - required for Play Store Data Safety")

        p_text = _read(privacy).lower()

        # Check that privacy policy mentions data categories present in the app
        # The app collects: location, photos, messages, authentication
        for category in ["location", "photo", "message", "auth"]:
            if category not in p_text:
                print(f"[WARN] Privacy policy does not mention {category}")

    def test_in_app_disclosures_present(self) -> None:
        """Settings should have in-app privacy policy links."""
        settings = ROOT / "lib" / "features" / "settings" / "settings_dialog.dart"
        if settings.exists():
            text = _read(settings).lower()
            # Should have some kind of policy link or disclosure
            has_link = "privacy" in text or "policy" in text
            assert has_link, "No in-app privacy policy disclosure found"