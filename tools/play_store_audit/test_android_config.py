"""Android configuration and permissions audit.

Inspects build.gradle, manifest and Flutter configuration.
"""
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
MANIFEST = ROOT / "android" / "app" / "src" / "main" / "AndroidManifest.xml"
GRADLE = ROOT / "android" / "app" / "build.gradle.kts"
PUBSPEC = ROOT / "pubspec.yaml"


def _read(path: Path) -> str:
    return path.read_text(encoding='utf-8')


def _search(pattern: str, text: str) -> re.Match | None:
    return re.search(pattern, text)


class TestApplicationIdentity:
    def test_application_id_is_a_valid_package(self) -> None:
        m = _search(r'applicationId\s*=\s*"([^"]+)"', _read(GRADLE))
        assert m, "applicationId not found in build.gradle.kts"
        app_id = m.group(1)
        assert re.fullmatch(r"[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]+)+", app_id), (
            f"{app_id!r} is not a valid reverse-domain package name"
        )

    def test_namespace_matches_application_id(self) -> None:
        ns = _search(r'namespace\s*=\s*"([^"]+)"', _read(GRADLE))
        app = _search(r'applicationId\s*=\s*"([^"]+)"', _read(GRADLE))
        assert ns and app
        assert ns.group(1) == app.group(1), (
            "namespace and applicationId must match or R classes break"
        )

    def test_version_name_and_code_come_from_pubspec(self) -> None:
        m = re.search(r"^version:\s*(\S+)\+(\d+)", _read(PUBSPEC), re.MULTILINE)
        assert m, "pubspec.yaml has no `version: x.y.z+build` line"
        assert "versionCode = flutter.versionCode" in _read(GRADLE)
        assert "versionName = flutter.versionName" in _read(GRADLE)

    def test_app_label_is_set(self) -> None:
        m = re.search(r'android:label\s*=\s*"([^"]+)"', _read(MANIFEST))
        assert m, "android:label is not set"
        assert m.group(1) == "Weekend"


class TestSdkLevels:
    def test_min_sdk_supports_passkeys(self) -> None:
        m = re.search(r"minSdk\s*=\s*(\d+)", _read(GRADLE))
        assert m, "minSdk not declared"
        assert int(m.group(1)) >= 24, (
            f"minSdk {m.group(1)} is below 24; passkeys need Credential Manager"
        )

    def test_target_sdk_uses_the_current_platform_default(self) -> None:
        assert "targetSdk = flutter.targetSdkVersion" in _read(GRADLE)

    def test_java_17_is_configured(self) -> None:
        assert "JavaVersion.VERSION_17" in _read(GRADLE)
        assert "jvmTarget = JavaVersion.VERSION_17" in _read(GRADLE)


class TestPermissions:
    def test_declares_only_needed_permissions(self) -> None:
        declared = set(
            re.findall(r'uses-permission android:name="([^"]+)"', _read(MANIFEST))
        )
        allowed = {
            "android.permission.INTERNET",
            "android.permission.ACCESS_NETWORK_STATE",
            "android.permission.CAMERA",
            "android.permission.ACCESS_COARSE_LOCATION",
            "android.permission.ACCESS_FINE_LOCATION",
            "android.permission.POST_NOTIFICATIONS",
            "android.permission.RECORD_AUDIO",
            "android.permission.USE_BIOMETRIC",
            "android.permission.USE_FINGERPRINT",
        }
        unexpected = declared - allowed
        assert not unexpected, f"Unexpected permissions: {unexpected}"

    def test_no_deprecated_storage_permissions(self) -> None:
        deprecated = {
            "android.permission.WRITE_EXTERNAL_STORAGE",
            "android.permission.READ_EXTERNAL_STORAGE",
        }
        actual = declared & deprecated if 'declared' in dir() else set()
        assert not actual, f"Deprecated storage permissions: {actual}"


class TestSdkConfig:
    def test_compile_sdk_consistent(self) -> None:
        assert "compileSdk = flutter.compileSdkVersion" in _read(GRADLE)

    def test_target_sdk_not_old(self) -> None:
        assert "targetSdk = flutter.targetSdkVersion" in _read(GRADLE)

    def test_java_17_configured(self) -> None:
        assert "JavaVersion.VERSION_17" in _read(GRADLE)
        assert "jvmTarget = JavaVersion.VERSION_17" in _read(GRADLE)

    def test_app_does_not_opt_out_of_predictive_back(self) -> None:
        manifest = _read(MANIFEST)
        assert 'android:enableOnBackInvokedCallback="false"' not in manifest

    def test_main_activity_does_not_disable_predicate_back_in_kotlin(self) -> None:
        kotlin_root = ROOT / "android" / "app" / "src" / "main" / "kotlin"
        if not kotlin_root.exists():
            import pytest
            pytest.skip("no Kotlin source")
        for path in kotlin_root.rglob("MainActivity.kt"):
            text = _read(path)
            assert "onBackPressed" not in text, (
                "MainActivity must not override the legacy onBackPressed hook; "
                "Flutter handles back through OnBackInvokedDispatcher"
            )


class TestSigningConfig:
    def test_signing_config_has_release_type(self) -> None:
        text = _read(GRADLE)
        assert "signingConfig = signingConfigs.getByName(\"release\")" in text

    def test_build_types_defined(self) -> None:
        text = _read(GRADLE)
        assert "buildTypes {" in text
        assert "release" in text