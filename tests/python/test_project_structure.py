"""Project structure, Flutter configuration and Android configuration checks.

All checks here are STATIC (they read the repository) except
``test_flutter_analyze_clean``, which executes the Dart analyzer and is
therefore RUNTIME evidence. None of them claim that a feature works.
"""

from __future__ import annotations

import re

from weekend_checks import (
    REPO_ROOT,
    CheckResult,
    Evidence,
    Status,
    read_text,
    run_tool,
)


# ---------------------------------------------------------------------------
# Project structure
# ---------------------------------------------------------------------------

REQUIRED_TOP_LEVEL = [
    "pubspec.yaml",
    "analysis_options.yaml",
    "README.md",
    "LICENSE",
    "android",
    "lib",
    "supabase",
    "test",
]


def test_project_structure() -> CheckResult:
    """Every required top-level artefact is present."""
    missing = [p for p in REQUIRED_TOP_LEVEL if not (REPO_ROOT / p).exists()]
    return CheckResult(
        name="Project structure",
        status=Status.PASS if not missing else Status.FAIL,
        evidence=Evidence.STATIC,
        detail="all present" if not missing else f"missing: {', '.join(missing)}",
    )


def test_dart_source_exists() -> CheckResult:
    """The lib/ tree actually contains Dart source."""
    sources = list((REPO_ROOT / "lib").rglob("*.dart"))
    return CheckResult(
        name="Dart source present",
        status=Status.PASS if sources else Status.FAIL,
        evidence=Evidence.STATIC,
        detail=f"{len(sources)} files",
    )


def test_flutter_tests_present() -> CheckResult:
    """The repository ships Flutter tests rather than relying on none."""
    tests = list((REPO_ROOT / "test").glob("*_test.dart"))
    return CheckResult(
        name="Flutter tests present",
        status=Status.PASS if tests else Status.FAIL,
        evidence=Evidence.STATIC,
        detail=f"{len(tests)} test files",
    )


# ---------------------------------------------------------------------------
# Flutter configuration
# ---------------------------------------------------------------------------

def test_pubspec_is_valid() -> CheckResult:
    """pubspec.yaml declares a name, a version, an SDK constraint and M3."""
    import re

    text = read_text(REPO_ROOT / "pubspec.yaml")
    if not text:
        return CheckResult(
            name="pubspec.yaml",
            status=Status.FAIL,
            evidence=Evidence.STATIC,
            detail="file missing",
        )
    problems = []
    if not re.search(r"^name:\s*\w+", text, re.M):
        problems.append("no name")
    if not re.search(r"^version:\s*\d+\.\d+\.\d+", text, re.M):
        problems.append("no semantic version")
    if "sdk:" not in text:
        problems.append("no sdk constraint")
    if "uses-material-design" not in text:
        problems.append("material design disabled")
    return CheckResult(
        name="pubspec.yaml",
        status=Status.PASS if not problems else Status.FAIL,
        evidence=Evidence.STATIC,
        detail="valid" if not problems else "; ".join(problems),
    )


def test_supabase_flutter_version_supports_passkeys() -> CheckResult:
    """supabase_flutter is new enough to expose client.auth.passkey.

    The native passkey API (startRegistration / verifyAuthentication) was
    added in supabase_flutter 2.15.0. An older pin is a silent break: the
    ceremony could never run even though the rest of the app works.
    """
    import re

    text = read_text(REPO_ROOT / "pubspec.yaml")
    m = re.search(r"^\s*supabase_flutter:\s*\^?(\d+)\.(\d+)\.(\d+)", text, re.M)
    if not m:
        return CheckResult(
            name="supabase_flutter >= 2.15",
            status=Status.FAIL,
            evidence=Evidence.STATIC,
            detail="not declared",
        )
    major, minor, _ = (int(g) for g in m.groups())
    ok = (major, minor) >= (2, 15)
    return CheckResult(
        name="supabase_flutter >= 2.15",
        status=Status.PASS if ok else Status.FAIL,
        evidence=Evidence.STATIC,
        detail=f"{major}.{minor}" + ("" if ok else " - too old for passkeys"),
    )


def test_no_placeholder_implementations() -> CheckResult:
    """Critical features are not stubbed with empty TODO bodies."""
    import re

    offenders: list[str] = []
    todo_only = re.compile(
        r"(TODO|FIXME)[^\n]*\n\s*(Future<[^>]*>|void|Widget|String)\s+\w+\([^)]*\)\s*\{\s*\}",
        re.M,
    )
    for path in (REPO_ROOT / "lib").rglob("*.dart"):
        text = read_text(path)
        if text and todo_only.search(text):
            offenders.append(str(path.relative_to(REPO_ROOT)))
    return CheckResult(
        name="No placeholder implementations",
        status=Status.PASS if not offenders else Status.FAIL,
        evidence=Evidence.STATIC,
        detail="none found" if not offenders else "; ".join(offenders[:5]),
    )


# ---------------------------------------------------------------------------
# Android configuration
# ---------------------------------------------------------------------------

def test_android_project_present() -> CheckResult:
    """The Android host project and its Gradle wiring exist."""
    needed = [
        "android/build.gradle.kts",
        "android/app/build.gradle.kts",
        "android/app/src/main/AndroidManifest.xml",
        "android/gradle/wrapper/gradle-wrapper.properties",
    ]
    missing = [n for n in needed if not (REPO_ROOT / n).exists()]
    return CheckResult(
        name="Android project present",
        status=Status.PASS if not missing else Status.FAIL,
        evidence=Evidence.STATIC,
        detail="ok" if not missing else f"missing: {', '.join(missing)}",
    )


def test_android_sdk_levels() -> CheckResult:
    """minSdk is declared and is high enough for Credential Manager.

    Passkeys need API 24+. A lower floor would compile but the ceremony would
    fail at runtime on those devices.
    """
    import re

    text = read_text(REPO_ROOT / "android" / "app" / "build.gradle.kts")
    m = re.search(r"minSdk\s*=\s*(\d+)", text)
    if not m:
        return CheckResult(
            name="Android SDK levels",
            status=Status.FAIL,
            evidence=Evidence.STATIC,
            detail="minSdk not declared",
        )
    min_sdk = int(m.group(1))
    ok = min_sdk >= 24
    return CheckResult(
        name="Android SDK levels",
        status=Status.PASS if ok else Status.FAIL,
        evidence=Evidence.STATIC,
        detail=f"minSdk {min_sdk}" + ("" if ok else " (needs >= 24)"),
    )


def test_android_permissions() -> CheckResult:
    """The manifest declares the permissions the features actually need."""
    manifest = read_text(
        REPO_ROOT / "android" / "app" / "src" / "main" / "AndroidManifest.xml"
    )
    required = [
        "android.permission.INTERNET",
        "android.permission.ACCESS_COARSE_LOCATION",
        "android.permission.ACCESS_FINE_LOCATION",
        "android.permission.USE_BIOMETRIC",
        "android.permission.POST_NOTIFICATIONS",
    ]
    missing = [p for p in required if p not in manifest]
    return CheckResult(
        name="Android permissions",
        status=Status.PASS if not missing else Status.FAIL,
        evidence=Evidence.STATIC,
        detail="all declared" if not missing else f"missing: {', '.join(missing)}",
    )


def test_no_background_location_permission() -> CheckResult:
    """Background location is NOT requested.

    Weekend's discovery model is while-in-use nearby search. Requesting
    background location would be an unjustified privacy overreach and a Play
    Store review risk, so its absence is asserted.
    """
    manifest = read_text(
        REPO_ROOT / "android" / "app" / "src" / "main" / "AndroidManifest.xml"
    )
    has = "ACCESS_BACKGROUND_LOCATION" in manifest
    return CheckResult(
        name="No background location",
        status=Status.PASS if not has else Status.FAIL,
        evidence=Evidence.STATIC,
        detail="while-in-use only" if not has else "background location declared",
    )


def test_cleartext_traffic_disabled() -> CheckResult:
    """The app refuses cleartext HTTP."""
    manifest = read_text(
        REPO_ROOT / "android" / "app" / "src" / "main" / "AndroidManifest.xml"
    )
    ok = 'android:usesCleartextTraffic="false"' in manifest
    return CheckResult(
        name="Cleartext traffic disabled",
        status=Status.PASS if ok else Status.FAIL,
        evidence=Evidence.STATIC,
        detail="https only" if ok else "not enforced",
    )


def test_credential_manager_dependency() -> CheckResult:
    """Credential Manager is a declared runtime dependency."""
    text = read_text(REPO_ROOT / "pubspec.yaml")
    ok = "credential_manager" in text
    return CheckResult(
        name="Credential Manager dependency",
        status=Status.PASS if ok else Status.FAIL,
        evidence=Evidence.STATIC,
        detail="declared" if ok else "not declared",
    )


def test_flutter_analyze_clean() -> CheckResult:
    """RUNTIME: `flutter analyze` reports no issues.

    Executes the Dart analyzer, so this is RUNTIME evidence rather than a
    static file read.
    """
    code, out = run_tool(["flutter", "analyze"], timeout=600)
    clean = code == 0 and "No issues found" in out
    detail = "no issues" if clean else out.strip().splitlines()[-1][:120]
    return CheckResult(
        name="flutter analyze",
        status=Status.PASS if clean else Status.FAIL,
        evidence=Evidence.RUNTIME,
        detail=detail,
    )


def test_flutter_tests_pass() -> CheckResult:
    """RUNTIME: `flutter test` passes."""
    code, out = run_tool(["flutter", "test", "--reporter", "compact"], timeout=900)
    ok = code == 0 and "All tests passed" in out
    tail = [ln for ln in out.splitlines() if ln.strip()][-1:] if out.strip() else [""]
    return CheckResult(
        name="flutter test",
        status=Status.PASS if ok else Status.FAIL,
        evidence=Evidence.RUNTIME,
        detail="all passed" if ok else (tail[0][-100:] if tail else "no output"),
    )

def test_no_dummy_authentication() -> CheckResult:
    """Authentication never fabricates a session on failure.

    A sign-in that reports success without a real Supabase session is the most
    damaging thing this app could do, so it is checked explicitly.
    """
    auth = read_text(REPO_ROOT / "lib" / "repositories" / "auth_repository.dart")
    if not auth:
        return CheckResult(
            name="No dummy authentication",
            status=Status.FAIL,
            evidence=Evidence.STATIC,
            detail="auth_repository.dart missing",
        )
    problems = []
    # The critical guarantee is that a passkey sign-in cannot report success
    # without a real server-issued session. `deletePasskey` legitimately returns
    # an unconditional success (the DELETE already succeeded), so an
    # unconditional `.success(` is NOT on its own a defect - the check is
    # whether the sign-in path can reach success with a null session.
    signin_requires_session = bool(
        re.search(
            r"if \(session == null\)[\s\S]{0,200}?\.failure\(", auth
        )
    )
    if not signin_requires_session:
        problems.append("sign-in can succeed without a session")
    if "signInWithEmail" not in auth:
        problems.append("no email sign-in")
    return CheckResult(
        name="No dummy authentication",
        status=Status.PASS if not problems else Status.FAIL,
        evidence=Evidence.STATIC,
        detail="real sessions only" if not problems else "; ".join(problems),
    )
