"""Verify the shipped release artifact carries the expected Android identity.

This is the check that closes the gap between "the Gradle file says X" and
"the binary that users install says X". The application ID is read back out
of the built APK's DEX files and manifest, so a stale or mis-merged manifest,
a renamed-but-not-repackaged build, or an R8 problem that strips the native
platform-channel handlers are all caught here.

The checks are skipped when no release artifact has been built yet, so the
suite stays runnable on a clean checkout.
"""
from __future__ import annotations

import os
import re
import subprocess
import zipfile
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent.parent

# The Android identity the project is migrating TO.
EXPECTED_PACKAGE = "com.zypherlabs.weekend"
# The identity being retired. It must not survive in a shipped artifact.
RETIRED_PACKAGE = "com.weekend.app"

APK_CANDIDATES = (
    ROOT / "build" / "app" / "outputs" / "flutter-apk" / "app-release.apk",
    ROOT / "build" / "app" / "outputs" / "apk" / "release" / "app-release.apk",
)

# Native classes that must survive R8 shrinking. The Dart side reaches
# VpnSecurityChannel through a string-named MethodChannel, which R8 cannot
# see, so the class and its channel-name constants must be kept.
EXPECTED_DESCRIPTORS = (
    f"L{EXPECTED_PACKAGE.replace('.', '/')}/MainActivity;",
    f"L{EXPECTED_PACKAGE.replace('.', '/')}/VpnSecurityChannel;",
)
EXPECTED_CHANNEL_STRINGS = (
    f"{EXPECTED_PACKAGE}/vpn_security",
    f"{EXPECTED_PACKAGE}/vpn_security_events",
)


def _find_apk() -> Path | None:
    for p in APK_CANDIDATES:
        if p.exists() and p.stat().st_size > 0:
            return p
    return None


def _build_tools_dir() -> Path | None:
    """Locate the Android SDK build-tools directory."""
    for env in ("ANDROID_SDK_ROOT", "ANDROID_HOME"):
        root = os.environ.get(env)
        if not root:
            continue
        bt = Path(root) / "build-tools"
        if bt.is_dir():
            versions = sorted(
                (d for d in bt.iterdir() if d.is_dir()),
                key=lambda d: [
                    int(p) for p in re.split(r"\D+", d.name) if p.isdigit()
                ],
            )
            if versions:
                return versions[-1]
    return None


def _aapt2() -> Path | None:
    """The aapt2 binary, if the Android SDK is available."""
    bt = _build_tools_dir()
    if bt is None:
        return None
    exe = bt / ("aapt2.exe" if os.name == "nt" else "aapt2")
    return exe if exe.exists() else None


def _badging(apk: Path) -> str:
    """`aapt2 dump badging` output for the APK."""
    aapt2 = _aapt2()
    if aapt2 is None:
        pytest.skip("Android SDK build-tools / aapt2 not found")
    out = subprocess.run(
        [str(aapt2), "dump", "badging", str(apk)],
        capture_output=True,
        text=True,
    ).stdout
    assert out, "aapt2 produced no output"
    return out


@pytest.fixture(scope="module")
def apk() -> Path:
    path = _find_apk()
    if path is None:
        pytest.skip("no release APK built; run `flutter build apk --release`")
    return path


@pytest.fixture(scope="module")
def apk_blobs(apk: Path) -> list[tuple[str, bytes]]:
    """Every DEX and text resource inside the APK."""
    blobs: list[tuple[str, bytes]] = []
    with zipfile.ZipFile(apk) as z:
        for name in z.namelist():
            if name.startswith("classes") and name.endswith(".dex"):
                blobs.append((name, z.read(name)))
            elif name.endswith((".xml", ".json", ".properties", ".txt")):
                try:
                    blobs.append((name, z.read(name)))
                except Exception:  # noqa: BLE001 - a bad entry must not abort the run
                    pass
    return blobs


class TestShippedApplicationId:
    """The application ID must be read back from the artifact, not from Gradle."""

    def test_aapt_reports_the_new_package(self, apk: Path) -> None:
        out = _badging(apk)
        m = re.search(r"package:\s+name='([^']+)'", out)
        assert m, f"could not read the package name from the APK:\n{out[:400]}"
        assert m.group(1) == EXPECTED_PACKAGE, (
            f"APK application ID is {m.group(1)}, expected {EXPECTED_PACKAGE}"
        )

    def test_launcher_activity_uses_the_new_package(self, apk: Path) -> None:
        out = _badging(apk)
        m = re.search(r"launchable-activity:\s+name='([^']+)'", out)
        assert m, f"no launchable activity found in the APK:\n{out[:400]}"
        assert m.group(1) == f"{EXPECTED_PACKAGE}.MainActivity", (
            f"launcher activity is {m.group(1)}, expected "
            f"{EXPECTED_PACKAGE}.MainActivity"
        )

    def test_app_label_is_still_weekend(self, apk: Path) -> None:
        out = _badging(apk)
        m = re.search(r"application-label:'([^']*)'", out)
        assert m, "no application label found"
        assert m.group(1) == "Weekend", (
            f"application label is {m.group(1)!r}, expected 'Weekend'"
        )


class TestRetiredPackageIsGone:
    """The old package name must not survive anywhere in the shipped binary."""

    def test_retired_package_is_absent(self, apk_blobs) -> None:
        found = [n for n, b in apk_blobs if RETIRED_PACKAGE.encode() in b]
        assert not found, (
            f"{RETIRED_PACKAGE} is still present in the release APK: {found}"
        )


class TestNativeChannelSurvivedShrinking:
    """R8 must not strip or rename the native platform-channel handlers."""

    def test_native_classes_are_present(self, apk_blobs) -> None:
        for descriptor in EXPECTED_DESCRIPTORS:
            found = [n for n, b in apk_blobs if descriptor.encode() in b]
            assert found, (
                f"{descriptor} is missing from the release APK - R8 removed or "
                f"renamed the native class"
            )

    def test_channel_names_are_present(self, apk_blobs) -> None:
        for name in EXPECTED_CHANNEL_STRINGS:
            found = [n for n, b in apk_blobs if name.encode() in b]
            assert found, (
                f"channel name {name!r} is missing from the release APK - the "
                f"Dart side would wait on a channel nobody serves"
            )
