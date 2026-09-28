"""Release configuration and GitHub release checks.

The GitHub release check is deliberately conservative: it reports NOT
VERIFIED unless a release asset can be downloaded AND its SHA-256 matches a
locally recorded hash. A published file with no matching local artifact is not
proof that the tested binary is the distributed one.
"""

from __future__ import annotations

import hashlib
import json
import urllib.request

from weekend_checks import (
    REPO_ROOT,
    CheckResult,
    Evidence,
    Status,
    device_connected,
    device_evidence,
    read_text,
    run_tool,
)

RELEASES_API = "https://api.github.com/repos/zypherlabs-bit/Weekend/releases"
REPO_API = "https://api.github.com/repos/zypherlabs-bit/Weekend"

#: Hash of the APK this workspace last verified locally, if recorded.
LOCAL_HASH_FILE = REPO_ROOT / "build" / "release" / "apk.sha256"


def test_release_workflow_exists() -> CheckResult:
    """STATIC: CI builds a release APK and refuses placeholder credentials."""
    wf = read_text(REPO_ROOT / ".github" / "workflows" / "release.yml")
    if not wf:
        return CheckResult(
            name="Release workflow",
            status=Status.FAIL,
            evidence=Evidence.STATIC,
            detail="release.yml missing",
        )
    builds = "flutter build apk --release" in wf
    live_only = "your-project-ref" in wf
    checksum = "shasum" in wf or "sha256" in wf.lower()
    ok = builds and live_only and checksum
    return CheckResult(
        name="Release workflow",
        status=Status.PASS if ok else Status.FAIL,
        evidence=Evidence.STATIC,
        detail="build + checksum + live-only guard" if ok else "incomplete",
    )


def test_signing_configured() -> CheckResult:
    """STATIC: release signing is wired, with a documented key template."""
    gradle = read_text(REPO_ROOT / "android" / "app" / "build.gradle.kts")
    has_signing = "signingConfigs" in gradle and "key.properties" in gradle
    has_example = (REPO_ROOT / "android" / "key.properties.example").exists()
    return CheckResult(
        name="Release signing config",
        status=Status.PASS if has_signing and has_example else Status.FAIL,
        evidence=Evidence.STATIC,
        detail=(
            "key.properties + example"
            if has_signing and has_example
            else "signing or example missing"
        ),
    )


def test_key_properties_not_committed() -> CheckResult:
    """STATIC: the real keystore properties file is not in the repository."""
    on_disk = (REPO_ROOT / "android" / "key.properties").exists()
    code, out = run_tool(["git", "ls-files", "android/key.properties"], timeout=60)
    tracked = code == 0 and "key.properties" in out
    return CheckResult(
        name="Keystore not committed",
        status=Status.PASS if not on_disk and not tracked else Status.FAIL,
        evidence=Evidence.STATIC,
        detail="git-ignored" if not on_disk and not tracked else "PRESENT IN REPO",
    )


def test_release_apk_built() -> CheckResult:
    """RUNTIME: a release APK exists in the build output."""
    apk = REPO_ROOT / "build" / "app" / "outputs" / "flutter-apk" / "app-release.apk"
    return CheckResult(
        name="Release APK built",
        status=Status.PASS if apk.exists() else Status.FAIL,
        evidence=Evidence.RUNTIME,
        detail=f"{apk.stat().st_size:,} bytes" if apk.exists() else "not built yet",
    )


def test_apk_checksum_recorded() -> CheckResult:
    """RUNTIME: a SHA-256 for the built APK is recorded locally."""
    if not LOCAL_HASH_FILE.exists():
        return CheckResult(
            name="APK checksum recorded",
            status=Status.FAIL,
            evidence=Evidence.RUNTIME,
            detail="no local hash file",
        )
    return CheckResult(
        name="APK checksum recorded",
        status=Status.PASS,
        evidence=Evidence.RUNTIME,
        detail=read_text(LOCAL_HASH_FILE).strip()[:32] + "...",
    )


def _latest_release() -> list[dict]:
    req = urllib.request.Request(
        RELEASES_API, headers={"Accept": "application/vnd.github+json"}
    )
    with urllib.request.urlopen(req, timeout=25) as resp:
        releases = json.loads(resp.read().decode("utf-8", "replace"))
    return releases


def test_latest_github_release_has_assets() -> CheckResult:
    """RUNTIME: the latest GitHub release publishes an APK and a checksum."""
    try:
        releases = _latest_release()
    except Exception as exc:  # noqa: BLE001
        return CheckResult(
            name="GitHub release assets",
            status=Status.NOT_VERIFIED,
            evidence=Evidence.RUNTIME,
            detail=f"unreachable: {type(exc).__name__}",
        )
    if not releases:
        return CheckResult(
            name="GitHub release assets",
            status=Status.NOT_VERIFIED,
            evidence=Evidence.RUNTIME,
            detail="no releases",
        )
    latest = releases[0]
    names = [a["name"] for a in latest.get("assets", [])]
    ok = any(n.endswith(".apk") for n in names) and any(
        n.endswith(".sha256") for n in names
    )
    return CheckResult(
        name="GitHub release assets",
        status=Status.PASS if ok else Status.FAIL,
        evidence=Evidence.RUNTIME,
        detail=f"{latest.get('tag_name')}: {', '.join(names) or 'none'}",
    )


def test_github_apk_hash_matches_local() -> CheckResult:
    """RUNTIME: the published APK's SHA-256 equals the locally built one.

    This is the check that proves the distributed artifact is the tested
    artifact. Without it, a green build proves nothing about what users get.
    """
    if not LOCAL_HASH_FILE.exists():
        return CheckResult(
            name="GitHub APK hash matches",
            status=Status.NOT_VERIFIED,
            evidence=Evidence.RUNTIME,
            detail="no local hash to compare against",
        )
    local = read_text(LOCAL_HASH_FILE).split()[0].strip().lower()

    try:
        releases = _latest_release()
        assets = releases[0].get("assets", []) if releases else []
        apk = next((a for a in assets if a["name"].endswith(".apk")), None)
        if apk is None:
            return CheckResult(
                name="GitHub APK hash matches",
                status=Status.NOT_VERIFIED,
                evidence=Evidence.RUNTIME,
                detail="no published APK",
            )
        with urllib.request.urlopen(apk["browser_download_url"], timeout=180) as r:
            digest = hashlib.sha256()
            while chunk := r.read(1 << 20):
                digest.update(chunk)
        remote = digest.hexdigest()
    except Exception as exc:  # noqa: BLE001
        return CheckResult(
            name="GitHub APK hash matches",
            status=Status.NOT_VERIFIED,
            evidence=Evidence.RUNTIME,
            detail=f"download failed: {type(exc).__name__}",
        )

    ok = remote == local
    return CheckResult(
        name="GitHub APK hash matches",
        status=Status.PASS if ok else Status.FAIL,
        evidence=Evidence.RUNTIME,
        detail=(
            "identical" if ok else f"local {local[:16]} != remote {remote[:16]}"
        ),
    )


def test_github_topics_legitimate() -> CheckResult:
    """STATIC: repository topics are descriptive, not competitor spam."""
    try:
        req = urllib.request.Request(
            REPO_API, headers={"Accept": "application/vnd.github+json"}
        )
        with urllib.request.urlopen(req, timeout=25) as resp:
            repo = json.loads(resp.read().decode("utf-8", "replace"))
    except Exception as exc:  # noqa: BLE001
        return CheckResult(
            name="GitHub topics legitimate",
            status=Status.NOT_VERIFIED,
            evidence=Evidence.RUNTIME,
            detail=f"unreachable: {type(exc).__name__}",
        )
    topics = [t.lower() for t in repo.get("topics", [])]
    if not topics:
        return CheckResult(
            name="GitHub topics legitimate",
            status=Status.NOT_VERIFIED,
            evidence=Evidence.RUNTIME,
            detail="no topics set",
        )
    banned = {"tinder", "bumble", "hinge", "badoo", "okcupid"}
    spam = [t for t in topics if t in banned]
    return CheckResult(
        name="GitHub topics legitimate",
        status=Status.PASS if not spam else Status.FAIL,
        evidence=Evidence.RUNTIME,
        detail=f"{len(topics)} topics" if not spam else f"competitor spam: {spam}",
    )


def test_readme_avoids_overclaiming() -> CheckResult:
    """STATIC: the README makes no absolute security claims."""
    readme = read_text(REPO_ROOT / "README.md").lower()
    banned_phrases = [
        "hack-proof",
        "hackproof",
        "ddos-proof",
        "100% secure",
        "completely secure",
        "unhackable",
        "perfect ai moderation",
    ]
    found = [p for p in banned_phrases if p in readme]
    return CheckResult(
        name="README avoids overclaiming",
        status=Status.PASS if not found else Status.FAIL,
        evidence=Evidence.STATIC,
        detail="realistic language" if not found else f"claims: {found}",
    )


def test_readme_documents_product() -> CheckResult:
    """STATIC: the README documents the differentiator and the privacy model."""
    readme = read_text(REPO_ROOT / "README.md").lower()
    ok = all(
        k in readme for k in ("passkey", "privacy", "location", "flutter", "supabase")
    )
    return CheckResult(
        name="README documents product",
        status=Status.PASS if ok else Status.FAIL,
        evidence=Evidence.STATIC,
        detail="passkey + privacy + stack" if ok else "sections missing",
    )


def test_physical_device_tests() -> CheckResult:
    """DEVICE: the app was exercised on real Android hardware.

    Never inferred from an emulator run. Emulator results do not demonstrate
    Credential Manager, a real biometric prompt or the Android Photo Picker.
    """
    checks = device_evidence().get("device_tests")
    if not checks:
        connected = (
            "a device is attached but no results recorded"
            if device_connected()
            else "no physical device attached"
        )
        return CheckResult(
            name="PHYSICAL DEVICE TESTS",
            status=Status.NOT_VERIFIED,
            evidence=Evidence.DEVICE,
            detail=connected,
        )
    passed = [k for k, v in checks.items() if v is True]
    failed = [k for k, v in checks.items() if v is False]
    if failed:
        return CheckResult(
            name="PHYSICAL DEVICE TESTS",
            status=Status.FAIL,
            evidence=Evidence.DEVICE,
            detail=f"{len(passed)} passed, failed: {', '.join(failed)}",
        )
    return CheckResult(
        name="PHYSICAL DEVICE TESTS",
        status=Status.PASS,
        evidence=Evidence.DEVICE,
        detail=f"{len(passed)} checks passed on device",
    )
