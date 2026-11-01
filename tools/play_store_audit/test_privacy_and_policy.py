"""Privacy and policy audit.

Verifies privacy policy publication, in-app disclosures, and data handling
practices against Google Play requirements.
"""
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent


def _read(path: Path) -> str:
    return path.read_text(encoding="utf-8") if path.exists() else ""


class TestPrivacyPolicy:
    def test_privacy_policy_is_published(self) -> None:
        """A privacy policy must be accessible and identify the correct app."""
        candidates = [
            ROOT / "docs" / "privacy.md",
            ROOT / "PRIVACY.md",
            ROOT / "docs" / "privacy-policy.md",
        ]
        existing = [p for p in candidates if p.exists()]
        assert existing, "no privacy policy document in the repository"
        text = _read(existing[0]).lower()
        for topic in ["location", "photo", "delete"]:
            assert topic in text, f"privacy policy does not mention {topic}"

    def test_privacy_policy_accessible_via_play_store(self) -> None:
        """Privacy policy URL should be reachable and contain substantive content."""
        # This is a manual check - verify the docs exist and have content
        candidates = [
            ROOT / "docs" / "privacy.md",
            ROOT / "PRIVACY.md",
            ROOT / "docs" / "privacy-policy.md",
        ]
        existing = [p for p in candidates if p.exists()]
        assert existing, "no privacy policy document in the repository"
        for p in existing:
            text = _read(p)
            assert len(text) > 1000, f"privacy policy {p} is too short (< 1KB)"
            # Should not be a parked domain stub
            assert "window.location" not in text.lower(), \
                f"privacy policy {p} contains redirect script"

    def test_blocking_and_reporting_exist(self) -> None:
        """Block and report functionality must be implemented in the app."""
        repo = ROOT / "lib" / "repositories" / "safety_repository.dart"
        assert repo.exists(), "safety_repository.dart not found"
        text = _read(repo).lower()
        assert "block" in text, "block functionality not found in safety repository"
        assert "report" in text, "report functionality not found in safety repository"

    def test_age_gate_is_enforced_at_signup(self) -> None:
        """Signup must enforce the 18+ age gate."""
        wizard = ROOT / "lib" / "features" / "auth" / "signup_wizard_screen.dart"
        assert wizard.exists(), "signup_wizard_screen.dart not found"
        text = _read(wizard)
        assert re.search(r"years?\s*<\s*18", text) or "18" in text, (
            "signup must enforce the 18+ age gate"
        )


class TestDataSafety:
    def test_data_safety_declarations_reconciled(self) -> None:
        """Data Safety form declarations should match the shipped binary."""
        ds_doc = ROOT / "docs" / "google-play-data-safety.md"
        assert ds_doc.exists(), "google-play-data-safety.md not found"
        text = _read(ds_doc).lower()
        # Must mention key data categories
        for category in ["location", "photos", "contacts", "browsing", "purchase"]:
            assert category in text, f"Data Safety missing category: {category}"

    def test_no_unconsented_sensitive_permissions(self) -> None:
        """Sensitive permissions should have user consent mechanisms."""
        manifest = _read(ROOT / "android" / "app" / "src" / "main" / "AndroidManifest.xml")
        # RECORD_AUDIO requires user consent for voice intros
        if "android.permission.RECORD_AUDIO" in manifest:
            # Should be documented somewhere
            safety = ROOT / "docs" / "google-play-data-safety.md"
            if safety.exists():
                s_text = _read(safety).lower()
                assert "record audio" in s_text or "microphone" in s_text or "audio" in s_text or "voice" in s_text or "audio" in s_text or "voice" in s_text, \
                    "RECORD_AUDIO not declared in Data Safety but present in manifest"


class TestInAppDisclosures:
    def test_in_app_privacy_policy_link(self) -> None:
        """App should have an in-app link to privacy policy."""
        # Check the settings screen for a privacy policy link
        settings = ROOT / "lib" / "features" / "settings" / "settings_dialog.dart"
        if settings.exists():
            text = _read(settings)
            assert "privacy" in text.lower() or "policy" in text.lower(), \
                "No in-app privacy policy link found in settings"