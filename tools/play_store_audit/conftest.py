"""Shared fixtures and configuration for the Play Store audit suite."""
from __future__ import annotations

import pytest
from pathlib import Path


def pytest_configure(config):
    """Configure pytest for the audit suite."""
    # Add any shared setup here


@pytest.fixture(scope="module")
def project_root() -> Path:
    """Return the root of the Weekend repository."""
    return Path(__file__).resolve().parent.parent.parent


@pytest.fixture(scope="module")
def manifest(project_root: Path) -> str:
    """Read the AndroidManifest.xml file."""
    manifest_path = project_root / "android" / "app" / "src" / "main" / "AndroidManifest.xml"
    assert manifest_path.exists(), "AndroidManifest.xml not found"
    return manifest_path.read_text()


@pytest.fixture(scope="module")
def gradle(project_root: Path) -> str:
    """Read the build.gradle.kts file."""
    gradle_path = project_root / "android" / "app" / "build.gradle.kts"
    assert gradle_path.exists(), "build.gradle.kts not found"
    return gradle_path.read_text()


@pytest.fixture(scope="module")
def pubspec(project_root: Path) -> str:
    """Read the pubspec.yaml file."""
    pubspec_path = project_root / "pubspec.yaml"
    assert pubspec_path.exists(), "pubspec.yaml not found"
    return pubspec_path.read_text()


@pytest.fixture(scope="module")
def artifacts_dir(project_root: Path) -> Path:
    """Return the build/release directory."""
    return project_root / "build" / "release"


@pytest.fixture(scope="module")
def key_props(project_root: Path) -> str | None:
    """Read android/key.properties if it exists."""
    kp = project_root / "android" / "key.properties"
    if kp.exists():
        return kp.read_text()
    return None