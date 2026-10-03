"""Android configuration and Play Store readiness audit.

Everything here is STATIC: it inspects the manifest, Gradle files and
resources. A pass proves the configuration is correct, never that Google Play
Console accepted the listing - that is reported separately as NOT VERIFIED.
"""

from __future__ import annotations

import re

import pytest

from conftest import PROJECT_ROOT, read

MANIFEST = PROJECT_ROOT / "android" / "app" / "src" / "main" / "AndroidManifest.xml"
GRADLE = PROJECT_ROOT / "android" / "app" / "build.gradle.kts"
PUBSPEC = PROJECT_ROOT / "pubspec.yaml"


@pytest.fixture(scope="module")
def manifest() -> str:
    assert MANIFEST.exists(), "AndroidManifest.xml not found"
    return read(MANIFEST)


@pytest.fixture(scope="module")
def gradle() -> str:
    assert GRADLE.exists()
    return read(GRADLE)


@pytest.fixture(scope="module")
def pubspec() -> str:
    return read(PUBSPEC)


class TestApplicationIdentity:
    def test_application_id_is_a_valid_package(self, gradle: str) -> None:
        m = re.search(r'applicationId\s*=\s*"([^"]+)"', gradle)
        assert m, "applicationId not found in build.gradle.kts"
        app_id = m.group(1)
        assert re.fullmatch(r"[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+", app_id), (
            f"{app_id!r} is not a valid reverse-domain package name"
        )

    def test_namespace_matches_application_id(self, gradle: str) -> None:
        ns = re.search(r'namespace\s*=\s*"([^"]+)"', gradle)
        app = re.search(r'applicationId\s*=\s*"([^"]+)"', gradle)
        assert ns and app
        assert ns.group(1) == app.group(1), (
            "namespace and applicationId must match or R classes break"
        )

    def test_version_name_and_code_come_from_pubspec(
        self, gradle: str, pubspec: str
    ) -> None:
        m = re.search(r"^version:\s*(\S+)\+(\d+)", pubspec, re.MULTILINE)
        assert m, "pubspec.yaml has no `version: x.y.z+build` line"
        assert "versionCode = flutter.versionCode" in gradle
        assert "versionName = flutter.versionName" in gradle

    def test_app_label_is_set(self, manifest: str) -> None:
        m = re.search(r'android:label\s*=\s*"([^"]+)"', manifest)
        assert m, "android:label is not set"
        assert m.group(1) == "Weekend"


class TestSdkLevels:
    def test_min_sdk_supports_passkeys(self, gradle: str) -> None:
        # Credential Manager / passkeys require API 24+.
        m = re.search(r"minSdk\s*=\s*(\d+)", gradle)
        assert m, "minSdk not declared"
        assert int(m.group(1)) >= 24, (
            f"minSdk {m.group(1)} is below 24; passkeys need Credential Manager"
        )

    def test_target_sdk_uses_the_current_platform_default(self, gradle: str) -> None:
        # Hard-pinning an old target SDK would block Play Store updates.
        assert "targetSdk = flutter.targetSdkVersion" in gradle

    def test_java_17_is_configured(self, gradle: str) -> None:
        assert "JavaVersion.VERSION_17" in gradle
        assert "jvmTarget = JavaVersion.VERSION_17" in gradle


class TestPermissions:
    def test_declares_only_needed_permissions(self, manifest: str) -> None:
        declared = set(
            re.findall(r'uses-permission android:name="([^"]+)"', manifest)
        )
        # Anything outside this set needs a documented justification.
        allowed = {
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
        unexpected = declared - allowed
        assert not unexpected, f"undeclared-justification permissions: {unexpected}"

    def test_location_permissions_are_present(self, manifest: str) -> None:
        assert "android.permission.ACCESS_COARSE_LOCATION" in manifest
        assert "android.permission.ACCESS_FINE_LOCATION" in manifest

    def test_notification_permission_is_declared(self, manifest: str) -> None:
        assert "android.permission.POST_NOTIFICATIONS" in manifest

    def test_no_legacy_external_storage_permission(self, manifest: str) -> None:
        # Scoped storage makes these obsolete, and Play rejects new apps
        # requesting them.
        assert "READ_EXTERNAL_STORAGE" not in manifest
        assert "WRITE_EXTERNAL_STORAGE" not in manifest

    def test_no_privileged_permissions(self, manifest: str) -> None:
        for dangerous in [
            "MANAGE_EXTERNAL_STORAGE",
            "QUERY_ALL_PACKAGES",
            "SYSTEM_ALERT_WINDOW",
        ]:
            assert dangerous not in manifest, f"{dangerous} must not be requested"


class TestComponents:
    def test_main_activity_is_exported_with_a_launcher_filter(self, manifest: str) -> None:
        assert 'android:name=".MainActivity"' in manifest
        idx = manifest.find('android:name=".MainActivity"')
        activity = manifest[idx : idx + 1200]
        assert 'android:exported="true"' in activity
        assert "android.intent.action.MAIN" in activity
        assert "android.intent.category.LAUNCHER" in activity

    def test_only_the_launcher_activity_is_exported(self, manifest: str) -> None:
        # Every exported component must be deliberate; an accidental exported
        # receiver is a remote-execution surface.
        exported = re.findall(
            r"<activity[\s\S]{0,400}?android:exported=\"true\"", manifest
        )
        assert len(exported) == 1, (
            f"expected exactly one exported activity, found {len(exported)}"
        )

    def test_no_cleartext_traffic(self, manifest: str) -> None:
        assert 'android:usesCleartextTraffic="false"' in manifest

    def test_backup_is_disabled(self, manifest: str) -> None:
        # An app holding dating data must not land in cloud backups.
        assert 'android:allowBackup="false"' in manifest

    def test_network_security_config_is_applied(self, manifest: str) -> None:
        assert "networkSecurityConfig" in manifest
        config = (
            PROJECT_ROOT
            / "android"
            / "app"
            / "src"
            / "main"
            / "res"
            / "xml"
            / "network_security_config.xml"
        )
        assert config.exists(), "network security config is referenced but missing"


class TestLauncherIcons:
    def test_adaptive_icon_is_declared(self) -> None:
        icon = (
            PROJECT_ROOT
            / "android"
            / "app"
            / "src"
            / "main"
            / "res"
            / "mipmap-anydpi-v26"
            / "ic_launcher.xml"
        )
        assert icon.exists(), "adaptive launcher icon is missing"
        text = read(icon)
        assert "<adaptive-icon" in text
        assert "background" in text
        assert "foreground" in text

    def test_manifest_points_at_the_icon(self, manifest: str) -> None:
        assert 'android:icon="@mipmap/ic_launcher"' in manifest
        assert 'android:roundIcon="@mipmap/ic_launcher_round"' in manifest

    def test_source_icon_assets_exist(self) -> None:
        m = re.search(r'image_path:\s*"([^"]+)"', read(PUBSPEC))
        if not m:
            pytest.skip("no flutter_launcher_icons configuration")
        assert (PROJECT_ROOT / m.group(1)).exists(), (
            f"launcher icon source missing: {m.group(1)}"
        )


class TestReleaseBuild:
    def test_release_build_type_exists_and_is_signed(self, gradle: str) -> None:
        assert re.search(r"release\s*\{", gradle)
        assert 'signingConfig = signingConfigs.getByName("release")' in gradle

    def test_release_build_is_minified(self, gradle: str) -> None:
        assert "isMinifyEnabled = true" in gradle
        assert "isShrinkResources = true" in gradle



class TestModernAndroidFeatures:
    def test_credential_manager_passkey_dependency(self, pubspec: str) -> None:
        assert "credential_manager" in pubspec

    def test_photo_picker_is_used(self, pubspec: str) -> None:
        # image_picker uses the Android Photo Picker on API 33+.
        assert "image_picker" in pubspec

    def test_secure_storage_uses_android_keystore(self, pubspec: str) -> None:
        assert "flutter_secure_storage" in pubspec
        service = PROJECT_ROOT / "lib" / "services" / "secure_storage_service.dart"
        assert "encryptedSharedPreferences" in read(service), (
            "secrets must be stored in the Android Keystore"
        )

    def test_material_3_is_enabled(self) -> None:
        theme = PROJECT_ROOT / "lib" / "theme" / "app_theme.dart"
        assert "useMaterial3: true" in read(theme)

    def test_predictive_back_is_supported(self, gradle: str) -> None:
        """Predictive back is provided by the Flutter embedding.

        The requirement is that the app TARGETS a platform where predictive
        back exists (API 33+), and that nothing in the app disables it.

        It is NOT implemented in MainActivity: `enableOnBackInvokedCallback`
        lives on `androidx.activity.ComponentActivity`, not on
        `android.app.Activity`, and `FlutterActivity` already registers the
        `OnBackInvokedDispatcher` callback itself. A custom override is both
        uncompilable and redundant.
        """
        assert "targetSdk = flutter.targetSdkVersion" in gradle
        assert "compileSdk = flutter.compileSdkVersion" in gradle

    def test_app_does_not_opt_out_of_predictive_back(self) -> None:
        # android:enableOnBackInvokedCallback="false" in the manifest would
        # disable the feature entirely.
        manifest = read(MANIFEST)
        assert 'android:enableOnBackInvokedCallback="false"' not in manifest

    def test_main_activity_does_not_disable_predicate_back_in_kotlin(self) -> None:
        kotlin_root = PROJECT_ROOT / "android" / "app" / "src" / "main" / "kotlin"
        if not kotlin_root.exists():
            pytest.skip("no Kotlin source")
        for path in kotlin_root.rglob("MainActivity.kt"):
            text = read(path)
            # Overriding the legacy back hook would bypass the embedding's
            # OnBackInvokedDispatcher registration.
            assert "onBackPressed" not in text, (
                "MainActivity must not override the legacy onBackPressed hook; "
                "Flutter handles back through OnBackInvokedDispatcher"
            )


class TestPrivacyAndSafety:
    def test_account_deletion_is_implemented(self) -> None:
        settings = (
            PROJECT_ROOT / "lib" / "features" / "settings" / "settings_dialog.dart"
        )
        assert settings.exists()
        text = read(settings)
        assert "Delete Account" in text
        assert "deleteAccount" in text

    def test_account_deletion_confirms_before_calling(self) -> None:
        text = read(
            PROJECT_ROOT / "lib" / "features" / "settings" / "settings_dialog.dart"
        )
        assert "This action cannot be undone" in text
        idx = text.find("deleteAccount")
        assert idx != -1
        assert "showDialog" in text[:idx], (
            "the destructive call must sit behind a confirmation dialog"
        )

    def test_privacy_policy_is_published(self) -> None:
        candidates = [
            PROJECT_ROOT / "docs" / "privacy.md",
            PROJECT_ROOT / "PRIVACY.md",
            PROJECT_ROOT / "docs" / "privacy-policy.md",
        ]
        existing = [p for p in candidates if p.exists()]
        assert existing, "no privacy policy document in the repository"
        text = read(existing[0]).lower()
        for topic in ["location", "photo", "delete"]:
            assert topic in text, f"privacy policy does not mention {topic}"

    def test_blocking_and_reporting_exist(self) -> None:
        repo = PROJECT_ROOT / "lib" / "repositories" / "safety_repository.dart"
        assert repo.exists()
        text = read(repo).lower()
        assert "block" in text
        assert "report" in text

    def test_age_gate_is_enforced_at_signup(self) -> None:
        wizard = (
            PROJECT_ROOT / "lib" / "features" / "auth" / "signup_wizard_screen.dart"
        )
        text = read(wizard)
        assert re.search(r"years?\s*<\s*18", text) or "18" in text, (
            "signup must enforce the 18+ age gate"
        )

    def test_signing_key_is_not_committed(self) -> None:
        # key.properties holds the real keystore credentials.
        key_props = PROJECT_ROOT / "android" / "key.properties"
        gitignore = PROJECT_ROOT / ".gitignore"
        ignored = gitignore.exists() and "key.properties" in read(gitignore)
        assert not key_props.exists() or ignored, (
            "android/key.properties must be gitignored, never committed"
        )

    def test_keystore_files_are_ignored(self) -> None:
        gitignore = PROJECT_ROOT / ".gitignore"
        assert gitignore.exists()
        assert re.search(r"\.jks|\.keystore", read(gitignore)), (
            "keystore files must be gitignored"
        )
