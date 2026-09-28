"""QR code verification.

The QR must resolve to the official Weekend repository and nothing else. Two
independent sources are checked so a change in one place cannot silently
break the other:

* the Dart constant that is actually rendered, and
* the QR image, if a raster asset was generated, decoded back to text.
"""

from __future__ import annotations

import re
from pathlib import Path

import pytest

from conftest import PROJECT_ROOT, lib_files, read

EXPECTED_URL = "https://github.com/zypherlabs-bit/Weekend"

DART_SCREEN = PROJECT_ROOT / "lib" / "features" / "qr" / "about_open_source_screen.dart"


@pytest.fixture(scope="module")
def screen_source() -> str:
    assert DART_SCREEN.exists(), f"missing {DART_SCREEN}"
    return read(DART_SCREEN)


class TestQrDestination:
    def test_constant_matches_the_official_repository(self, screen_source: str) -> None:
        m = re.search(
            r"kWeekendRepositoryUrl\s*=\s*\n?\s*'([^']+)'", screen_source
        )
        assert m, "kWeekendRepositoryUrl not found in the Dart source"
        assert m.group(1) == EXPECTED_URL, (
            f"QR destination is {m.group(1)!r}, expected {EXPECTED_URL!r}"
        )

    def test_constant_is_https_github_with_no_query_or_fragment(
        self, screen_source: str
    ) -> None:
        url = re.search(
            r"kWeekendRepositoryUrl\s*=\s*\n?\s*'([^']+)'", screen_source
        ).group(1)
        assert url.startswith("https://")
        assert "?" not in url
        assert "#" not in url
        assert "@" not in url, "credentials must never appear in a URL"

    def test_qr_renders_that_constant(self, screen_source: str) -> None:
        # The widget must pass the constant itself, not a literal that could
        # drift away from it.
        assert "data: kWeekendRepositoryUrl" in screen_source
        assert "QrImageView(" in screen_source

    def test_no_other_qr_payload_is_mislabelled_as_the_repository(self) -> None:
        # The referral invite QR is a separate, signed payload and must not be
        # presented as the open-source link.
        invite = PROJECT_ROOT / "lib" / "features" / "qr" / "qr_invite_screen.dart"
        if invite.exists():
            text = read(invite)
            assert "kWeekendRepositoryUrl" not in text, (
                "the referral invite screen must not encode the repository URL"
            )


class TestQrContainsNoSecrets:
    def test_payload_has_no_credential_material(self, screen_source: str) -> None:
        m = re.search(
            r"kWeekendRepositoryUrl\s*=\s*\n?\s*'([^']+)'", screen_source
        )
        url = m.group(1).lower()
        for forbidden in [
            "service_role",
            "eyj",  # base64 JWT prefix
            "supabase",
            "token",
            "password",
            "secret",
            "apikey",
            "api_key",
        ]:
            assert forbidden not in url, f"QR payload leaks {forbidden!r}"

    def test_no_authorization_header_in_the_qr_feature(self) -> None:
        for path in (PROJECT_ROOT / "lib" / "features" / "qr").glob("*.dart"):
            text = read(path).lower()
            assert "service_role" not in text


class TestQrAsset:
    """If a QR image was generated as an asset, decode it back to text."""

    def test_generated_qr_asset_decodes_to_the_repository(self) -> None:
        candidates = sorted(
            [
                p
                for p in (PROJECT_ROOT / "assets").rglob("*")
                if p.suffix.lower() in {".png", ".jpg", ".jpeg", ".webp"}
                and "qr" in p.stem.lower()
            ]
        )
        if not candidates:
            pytest.skip(
                "no rasterised QR asset: the code is rendered at runtime by "
                "qr_flutter, so the Dart constant is the authoritative payload"
            )

        try:
            from PIL import Image  # type: ignore
        except ImportError:
            pytest.skip("Pillow is not installed; cannot decode a QR asset")

        try:
            from pyzbar import pyzbar  # type: ignore
        except ImportError:
            pytest.skip("pyzbar is not installed; cannot decode a QR asset")

        for path in candidates:
            with Image.open(path) as img:
                decoded = pyzbar.decode(img)
            assert decoded, f"{path.name} contains no decodable QR code"
            payloads = {d.data.decode("utf-8") for d in decoded}
            assert payloads == {EXPECTED_URL}, (
                f"{path.name} encodes {payloads}, expected {{{EXPECTED_URL}}}"
            )


class TestRepositoryUrlConsistency:
    def test_readme_links_to_the_same_repository(self) -> None:
        readme = PROJECT_ROOT / "README.md"
        if not readme.exists():
            pytest.skip("README.md not present")
        text = read(readme)
        # At least one canonical form must appear, and no competing fork URL.
        assert "github.com/zypherlabs-bit/Weekend" in text
        others = set(
            re.findall(r"github\.com/([\w.-]+)/([\w.-]+?)(?=[)\s\"'<]|$)", text)
        )
        for owner, repo in others:
            if owner == "zypherlabs-bit" and repo.lower() == "weekend":
                continue
            # Links to other projects (Flutter, Supabase...) are fine; a
            # competing Weekend fork is not.
            assert repo.lower() != "weekend", (
                f"README points at a different Weekend repo: {owner}/{repo}"
            )

    def test_remote_origin_matches(self) -> None:
        import subprocess

        proc = subprocess.run(
            ["git", "remote", "get-url", "origin"],
            cwd=str(PROJECT_ROOT),
            capture_output=True,
            text=True,
        )
        if proc.returncode != 0:
            pytest.skip("no git remote configured")
        url = proc.stdout.strip()
        assert "github.com/zypherlabs-bit/Weekend" in url
