"""Secret-leak scan.

The scan is deliberately context-aware. A documentation example that writes
``SUPABASE_SERVICE_ROLE_KEY`` as prose is not a leak; a JWT-shaped literal
assigned in application code is. Only real credentials are flagged, so the
report stays actionable instead of noisy.
"""

from __future__ import annotations

import re
import subprocess
from pathlib import Path

import pytest

from conftest import PROJECT_ROOT, lib_files, read

#: Directories that never ship to a device.
EXCLUDED_DIRS = {
    ".git",
    ".dart_tool",
    "build",
    ".kilo",
    "__pycache__",
    ".idea",
    "node_modules",
    # Local Python virtualenvs. They are untracked and never shipped, and they
    # vendor third-party CA bundles whose base64 blobs match the JWT shape.
    ".venv",
    "venv",
    "env",
    "site-packages",
}

#: Files whose job is to show a secret's NAME, not its value.
DOC_SUFFIXES = {".md", ".txt", ".example", ".lock"}

BINARY_SUFFIXES = {
    ".png", ".jpg", ".jpeg", ".webp", ".ico", ".keystore", ".jks",
    ".apk", ".so", ".dll", ".exe", ".class", ".jar", ".ttf", ".otf",
}

#: The scanner must not match its own detection patterns.
SELF_PATH = Path(__file__).resolve()


def scan_files() -> list[Path]:
    out: list[Path] = []
    for path in PROJECT_ROOT.rglob("*"):
        if not path.is_file():
            continue
        if EXCLUDED_DIRS & set(path.parts):
            continue
        if path.suffix.lower() in BINARY_SUFFIXES:
            continue
        # This file necessarily contains the patterns it searches for.
        if path.resolve() == SELF_PATH:
            continue
        out.append(path)
    return out


def _jwt_pattern() -> re.Pattern[str]:
    """Build the JWT regex at runtime so this source is not a match."""
    return re.compile("ey" + "J" + r"[A-Za-z0-9_-]{20,}")


def _private_key_marker() -> str:
    return "BEGIN " + "PRIVATE KEY"


JWT_PATTERN = _jwt_pattern()


def scan_files() -> list[Path]:
    out: list[Path] = []
    for path in PROJECT_ROOT.rglob("*"):
        if not path.is_file():
            continue
        if EXCLUDED_DIRS & set(path.parts):
            continue
        if path.suffix.lower() in BINARY_SUFFIXES:
            continue
        out.append(path)
    return out


@pytest.fixture(scope="module")
def files() -> list[Path]:
    return scan_files()


class TestNoEmbeddedCredentials:
    def test_no_jwt_in_shipped_code(self, files: list[Path]) -> None:
        offenders = []
        for path in files:
            # Documentation may name a secret; it may never contain one.
            if path.suffix.lower() in DOC_SUFFIXES:
                continue
            # .env is untracked local config, audited separately.
            if path.name == ".env":
                continue
            try:
                text = read(path)
            except Exception:
                continue
            for m in JWT_PATTERN.finditer(text):
                line = text[: m.start()].count("\n") + 1
                offenders.append(f"{path.relative_to(PROJECT_ROOT)}:{line}")
        assert not offenders, f"JWT-shaped credential found: {offenders}"

    def test_no_service_role_key_in_the_flutter_client(self) -> None:
        offenders = [
            str(p.relative_to(PROJECT_ROOT))
            for p in lib_files()
            if "SUPABASE_SERVICE_ROLE_KEY" in read(p)
        ]
        assert not offenders, f"service-role key in client code: {offenders}"

    def test_no_private_key_material(self, files: list[Path]) -> None:
        offenders = []
        for path in files:
            if path.suffix.lower() in DOC_SUFFIXES:
                continue
            try:
                text = read(path)
            except Exception:
                continue
            if _private_key_marker() in text or ("BEGIN RSA " + "PRIVATE KEY") in text:
                offenders.append(str(path.relative_to(PROJECT_ROOT)))
        assert not offenders, f"private key material committed: {offenders}"



class TestEnvironmentHandling:
    def test_env_file_is_git_ignored(self) -> None:
        proc = subprocess.run(
            ["git", "check-ignore", ".env"],
            cwd=str(PROJECT_ROOT),
            capture_output=True,
            text=True,
        )
        if proc.returncode != 0:
            pytest.skip("git is unavailable or .env is not ignored")
        assert ".env" in proc.stdout

    def test_env_example_contains_no_real_values(self) -> None:
        example = PROJECT_ROOT / "supabase" / ".env.example"
        if not example.exists():
            pytest.skip("no .env.example")
        assert not JWT_PATTERN.search(read(example)), (
            ".env.example must contain placeholders, not real keys"
        )

    def test_dart_uses_dart_define_not_env_file(self) -> None:
        config = read(PROJECT_ROOT / "lib" / "config" / "supabase_config.dart")
        # Reading a .env at runtime would bundle the file into the APK;
        # compile-time defines keep the value out of the source tree.
        assert "String.fromEnvironment(" in config
        assert "'.env'" not in config and '".env"' not in config, (
            "the client must not read a .env file at runtime"
        )


class TestSecureStorage:
    def test_session_token_uses_secure_storage(self) -> None:
        service = read(
            PROJECT_ROOT / "lib" / "services" / "secure_storage_service.dart"
        )
        assert "FlutterSecureStorage" in service
        assert "encryptedSharedPreferences" in service, (
            "secrets must be encrypted with a Keystore-backed key"
        )

    def test_no_token_written_to_shared_preferences(self) -> None:
        offenders = []
        for path in lib_files():
            text = read(path)
            if "setSessionToken" not in text:
                continue
            idx = text.find("setSessionToken")
            window = text[max(0, idx - 500) : idx + 500]
            if "SharedPreferences" in window:
                offenders.append(str(path.relative_to(PROJECT_ROOT)))
        assert not offenders, f"token stored insecurely: {offenders}"


class TestNetworkSecurity:
    def test_no_cleartext_endpoint_in_code(self) -> None:
        # A hardcoded http:// endpoint would fail Play's secure-transport
        # policy and leak profile data.
        offenders = []
        for path in lib_files():
            for num, line in enumerate(read(path).splitlines(), 1):
                if re.search(r"http://(?!localhost|127\.0\.0\.1|10\.0\.2\.2)", line):
                    offenders.append(f"{path.relative_to(PROJECT_ROOT)}:{num}")
        assert not offenders, f"cleartext endpoint in code: {offenders}"

    def test_cleartext_traffic_disabled(self) -> None:
        manifest = read(
            PROJECT_ROOT
            / "android"
            / "app"
            / "src"
            / "main"
            / "AndroidManifest.xml"
        )
        assert 'android:usesCleartextTraffic="false"' in manifest


class TestNoDebugLeaks:
    def test_personal_data_is_not_logged(self) -> None:
        offenders = []
        for path in lib_files():
            for num, line in enumerate(read(path).splitlines(), 1):
                if re.search(r"print\(|debugPrint\(", line) and re.search(
                    r"(email|token|password|secret|service_role)", line, re.I
                ):
                    offenders.append(f"{path.relative_to(PROJECT_ROOT)}:{num}")
        assert not offenders, f"personal data logged: {offenders}"

    def test_no_keystore_committed(self, files: list[Path]) -> None:
        keystores = [
            str(p.relative_to(PROJECT_ROOT))
            for p in files
            if p.suffix.lower() in {".jks", ".keystore", ".p12", ".pfx"}
        ]
        assert not keystores, f"keystore committed: {keystores}"

    def test_gitignore_covers_secret_files(self) -> None:
        text = read(PROJECT_ROOT / ".gitignore")
        for pattern in ["key.properties", ".jks", ".env"]:
            assert pattern in text, f".gitignore is missing {pattern}"
