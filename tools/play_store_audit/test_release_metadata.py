"""Release metadata audit.

Verifies version codes, version names, package IDs, and metadata consistency
between pubspec.yaml, build.gradle.kts, and the AndroidManifest.
"""
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
MANIFEST = ROOT / "android" / "app" / "src" / "main" / "AndroidManifest.xml"
GRADLE = ROOT / "android" / "app" / "build.gradle.kts"
PUBSPEC = ROOT / "pubspec.yaml"


def _read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def _merged_manifest() -> Path:
    candidates = [
        ROOT / "build" / "app" / "intermediates" / "merged_manifest" / "release" / "processReleaseMainManifest" / "AndroidManifest.xml",
        ROOT / "build" / "app" / "intermediates" / "merged_manifests" / "release" / "processReleaseManifest" / "AndroidManifest.xml",
    ]
    for c in candidates:
        if c.exists():
            return c
    return MANIFEST


class TestReleaseMetadata:
    def test_application_id_matches_com_zypherlabs_weekend(self) -> None:
        m = re.search(r"applicationId\s*=\s*\"([^\"]+)\"", _read(GRADLE))
        assert m, "applicationId not found in build.gradle.kts"
        app_id = m.group(1)
        assert app_id == "com.zypherlabs.weekend", f"Application ID is {app_id}, expected com.zypherlabs.weekend"

    def test_namespace_matches_application_id(self) -> None:
        ns = re.search(r"namespace\s*=\s*\"([^\"]+)\"", _read(GRADLE))
        app = re.search(r"applicationId\s*=\s*\"([^\"]+)\"", _read(GRADLE))
        assert ns and app
        assert ns.group(1) == app.group(1), (
            "namespace and applicationId must match or R classes break"
        )

    def test_version_name_and_code_consistent(self) -> None:
        vm = re.search(r"^version:\s*(\S+)\+(\d+)", _read(PUBSPEC), re.MULTILINE)
        assert vm, "pubspec.yaml has no `version: x.y.z+build` line"
        version_name = vm.group(1)
        version_code_from_pubspec = int(vm.group(2))

        cm = re.search(r"versionCode\s*=\s*(\d+)", _read(GRADLE))
        if cm:
            version_code_from_gradle = int(cm.group(1))
            assert version_code_from_gradle == version_code_from_pubspec, (
                f"versionCode mismatch: gradle={version_code_from_gradle}, "
                f"pubspec={version_code_from_pubspec}"
            )
        else:
            assert "versionCode = flutter.versionCode" in _read(GRADLE)

        # Version name should be semver-like
        assert re.fullmatch(r"\d+\.\d+\.\d+", version_name) or "." in version_name, (
            f"versionName {version_name!r} does not look like semver"
        )

    def test_manifest_package_matches_application_id(self) -> None:
        """Android manifest package attribute should match applicationId."""
        manifest = _read(_merged_manifest())
        m = re.search(r"package\s*=\s*\"([^\"]+)\"", manifest)
        g = re.search(r"applicationId\s*=\s*\"([^\"]+)\"", _read(GRADLE))
        assert g, "applicationId not found"
        if m:
            assert m.group(1) == g.group(1), (
                f"Manifest package {m.group(1)} != applicationId {g.group(1)}"
            )

    def test_min_sdk_declared_in_manifest(self) -> None:
        manifest = _read(_merged_manifest())
        m = re.search(r"android:minSdkVersion\s*=\s*\"(\d+)\"", manifest)
        assert m, "minSdkVersion not declared in manifest"
        min_sdk = int(m.group(1))
        gradle_m = re.search(r"minSdk\s*=\s*(\d+)", _read(GRADLE))
        if gradle_m:
            gradle_min = int(gradle_m.group(1))
            # Manifest minSdk should not be higher than Gradle minSdk
            assert min_sdk <= gradle_min, (
                f"Manifest minSdk {min_sdk} > Gradle minSdk {gradle_min}"
            )

    def test_target_sdk_declared_in_manifest(self) -> None:
        manifest = _read(_merged_manifest())
        m = re.search(r"android:targetSdkVersion\s*=\s*\"(\d+)\"", manifest)
        assert m, "targetSdkVersion not declared in manifest"
        manifest_target = int(m.group(1))
        assert manifest_target >= 35, (
            f"targetSdkVersion {manifest_target} below Play requirement"
        )
        gradle_m = re.search(r"targetSdk\s*=\s*flutter.targetSdkVersion", _read(GRADLE))
        assert gradle_m, "targetSdk not set to flutter.targetSdkVersion in gradle"
