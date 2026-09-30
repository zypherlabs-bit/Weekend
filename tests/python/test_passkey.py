"""Passkey (WebAuthn via Android Credential Manager) verification.

Static checks prove the code is written and configured. They are reported
separately from the runtime and device evidence, and the device section is
ALWAYS honest: a static pass is never allowed to imply a passkey was created
or used on a phone.
"""

from __future__ import annotations

import re

import pytest

from conftest import connected_devices
from weekend_checks import (
    REPO_ROOT as PROJECT_ROOT,
    CheckResult,
    Evidence,
    Status,
    have_live_config,
    management_token,
    read_text as read,
    supabase_env,
)

PASSKEY_SERVICE = PROJECT_ROOT / "lib" / "services" / "passkey_service.dart"
AUTH_REPO = PROJECT_ROOT / "lib" / "repositories" / "auth_repository.dart"
MANIFEST = PROJECT_ROOT / "android" / "app" / "src" / "main" / "AndroidManifest.xml"
GRADLE = PROJECT_ROOT / "android" / "app" / "build.gradle.kts"
PUBSPEC = PROJECT_ROOT / "pubspec.yaml"


# --------------------------------------------------------------------------
# Static: the ceremony is really wired
# --------------------------------------------------------------------------

def test_credential_manager_dependency_present() -> CheckResult:
    """The Android Credential Manager plugin must be a real dependency."""
    pub = read(PUBSPEC)
    assert "credential_manager:" in pub, "credential_manager is not a dependency"
    return CheckResult(
        name="Credential Manager dependency declared",
        status=Status.PASS,
        evidence=Evidence.STATIC,
        detail="credential_manager is in pubspec.yaml dependencies",
    )


def test_credential_manager_is_initialised() -> CheckResult:
    """The plugin handle must be CONSTRUCTED before any ceremony runs.

    `credential_manager` 5.x registers its platform implementation inside the
    `CredentialManager()` constructor - `registerWith()` is never called from a
    static member. Reading `CredentialManagerPlatform.instance` without having
    constructed the handle throws

        Assertion failed: CredentialManagerPlatform.instance has not been
        initialized

    which is exactly the "the passkey button does nothing" symptom observed on
    device (2026-09-29 logcat). The fix is to build the handle, so the test
    asserts the handle exists and that no raw platform accessor is used.
    """
    src = read(PASSKEY_SERVICE)
    assert "CredentialManager()" in src, (
        "passkey_service never constructs CredentialManager(); without it the "
        "plugin is never registered and every ceremony throws"
    )
    assert "ensureInitialized" in src, "no shared init future / guard"
    # A raw platform accessor means the registration path was bypassed again.
    # Comments are stripped first: this file documents the old failure in prose
    # that names `CredentialManagerPlatform.instance`, which would otherwise
    # match itself.
    code = re.sub(r"//.*?$", "", src, flags=re.M)
    assert "CredentialManagerPlatform.instance" not in code, (
        "passkey_service reaches for CredentialManagerPlatform.instance "
        "directly; the platform impl is only registered by constructing "
        "CredentialManager()"
    )
    repo = read(AUTH_REPO)
    assert "PasskeyService.instance.createCredential" in repo
    assert "PasskeyService.instance.getCredential" in repo
    assert "CredentialManagerPlatform.instance" not in repo, (
        "auth_repository calls CredentialManagerPlatform directly; ceremony "
        "handling belongs in PasskeyService"
    )
    return CheckResult(
        name="Credential Manager registered before ceremonies",
        status=Status.PASS,
        evidence=Evidence.STATIC,
        detail=(
            "PasskeyService.ensureInitialized() constructs CredentialManager() "
            "then inits; both ceremonies go through the cached handle"
        ),
    )


def test_uses_supabase_native_passkey_api() -> CheckResult:
    """Must use the standards-based WebAuthn endpoints, not a parallel scheme."""
    repo = read(AUTH_REPO)
    for call in (
        "auth.passkey.startRegistration",
        "auth.passkey.verifyRegistration",
        "auth.passkey.startAuthentication",
        "auth.passkey.verifyAuthentication",
    ):
        assert call in repo, f"missing Supabase passkey call: {call}"
    return CheckResult(
        name="Supabase native WebAuthn API used",
        status=Status.PASS,
        evidence=Evidence.STATIC,
        detail="startRegistration/verifyRegistration/startAuthentication/verifyAuthentication",
    )


def test_challenge_handling_is_present() -> CheckResult:
    """The server challenge must be passed through to the platform."""
    src = read(PASSKEY_SERVICE)
    assert "creationOptionsFromJson" in src
    assert "loginOptionsFromJson" in src
    assert "start.options" in read(AUTH_REPO), "challenge options are not forwarded"
    return CheckResult(
        name="Server challenge forwarded to Credential Manager",
        status=Status.PASS,
        evidence=Evidence.STATIC,
        detail="creationOptionsFromJson / loginOptionsFromJson parse the GoTrue options",
    )


def test_user_verification_is_required() -> CheckResult:
    """userVerification must be `required`, not the server's `preferred`.

    `preferred` lets a device with no screen lock satisfy the ceremony, which
    is weaker than the guarantee the sign-up screen promises.
    """
    src = read(PASSKEY_SERVICE)
    assert src.count("userVerification: 'required'") >= 2, (
        "userVerification must be forced to 'required' on BOTH ceremonies"
    )
    assert "userVerification: 'preferred'" not in src
    return CheckResult(
        name="User verification required (not preferred)",
        status=Status.PASS,
        evidence=Evidence.STATIC,
        detail="forced to 'required' on registration and authentication",
    )


def test_fetch_options_are_passkey_only() -> CheckResult:
    """getCredentials must ask for a passkey only.

    The plugin's default also requests saved passwords and Google IDs, which
    can surface a password row instead of the passkey the user selected.
    """
    src = read(PASSKEY_SERVICE)
    assert "FetchOptionsAndroid(" in src
    assert "passwordCredential: false" in src
    assert "googleCredential: false" in src
    return CheckResult(
        name="Credential fetch is passkey-only",
        status=Status.PASS,
        evidence=Evidence.STATIC,
        detail="FetchOptionsAndroid(passKey: true, others false)",
    )


def test_no_fake_passkey_authentication() -> CheckResult:
    """No boolean may stand in for a credential or a session.

    This is the single most important static check in the file: a
    `passkeyAuthenticated = true` anywhere would make every other pass green
    while the app was completely insecure.
    """
    offenders: list[str] = []
    banned = (
        "passkeyAuthenticated",
        "passkey_authenticated",
        "fakePasskey",
        "simulatePasskey",
        "mockPasskey",
    )
    for path in list((PROJECT_ROOT / "lib").rglob("*.dart")) + [
        PASSKEY_SERVICE,
        AUTH_REPO,
    ]:
        text = read(path).lower()
        for needle in banned:
            if needle.lower() in text:
                offenders.append(f"{path.name}: {needle}")

    # A success must never be reachable without a credential from the platform.
    service = read(PASSKEY_SERVICE)
    assert "credentials.publicKeyCredential" in service, (
        "getCredential must inspect the returned PublicKeyCredential"
    )
    assert "if (publicKey == null)" in service, (
        "an empty credential must be a failure, not a success"
    )
    assert "return false" in service or "!ceremony.success" in read(AUTH_REPO)

    assert not offenders, f"fake passkey authentication found: {offenders}"
    return CheckResult(
        name="No simulated passkey authentication",
        status=Status.PASS,
        evidence=Evidence.STATIC,
        detail="success requires a real credential; empty credential is a failure",
    )


def test_no_hardcoded_credentials() -> CheckResult:
    """No service-role key or private key may live in the repo."""
    import re

    secret_patterns = [
        r"eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.",  # a JWT literal
        r"-----BEGIN [A-Z ]*PRIVATE KEY-----",
    ]
    hits: list[str] = []
    for path in (PROJECT_ROOT / "lib").rglob("*.dart"):
        text = read(path)
        for pattern in secret_patterns:
            if re.search(pattern, text):
                hits.append(path.name)
    assert not hits, f"credential-shaped literal in Dart source: {set(hits)}"
    return CheckResult(
        name="No hard-coded credentials in the app",
        status=Status.PASS,
        evidence=Evidence.STATIC,
        detail="no JWT or PEM literal under lib/",
    )


def test_session_is_required_for_success() -> CheckResult:
    """A sign-in without a session must be reported as a failure."""
    repo = read(AUTH_REPO)
    assert "if (session == null)" in repo, (
        "signInWithPasskey must fail when GoTrue returns no session"
    )
    assert "PasskeyOperationResult.failure(" in repo
    return CheckResult(
        name="Sign-in requires a server-issued session",
        status=Status.PASS,
        evidence=Evidence.STATIC,
        detail="null session -> PasskeyOperationResult.failure",
    )


# --------------------------------------------------------------------------
# Static: release / build configuration
# --------------------------------------------------------------------------

def test_relying_party_id_is_derived_not_hardcoded() -> CheckResult:
    """The manifest RP must come from the build, not a literal domain."""
    manifest = read(MANIFEST)
    assert "${weekendRpId}" in manifest, (
        "AndroidManifest must use the ${weekendRpId} manifest placeholder"
    )
    assert 'android:value="weekend.app"' not in manifest, (
        "the parked weekend.app host is still hard-coded as the relying party"
    )
    gradle = read(GRADLE)
    assert "resolvePasskeyRpId" in gradle
    assert "manifestPlaceholders[\"weekendRpId\"]" in gradle
    return CheckResult(
        name="RP ID derived from the Supabase project at build time",
        status=Status.PASS,
        evidence=Evidence.STATIC,
        detail="build.gradle.kts resolvePasskeyRpId() -> ${weekendRpId}",
    )


def test_asset_links_tooling_exists() -> CheckResult:
    """The Digital Asset Links digest must be derivable from real keystores."""
    tool_path = PROJECT_ROOT / "tool" / "gen_assetlinks.py"
    tool = read(tool_path) if tool_path.exists() else None
    assert tool, "tool/gen_assetlinks.py is missing"
    assert "sha256_cert_fingerprints" in tool
    # A placeholder digest would make the statement look valid while never
    # matching any APK.
    assert "MISSING" in tool, "the generator must refuse to emit a placeholder digest"
    return CheckResult(
        name="Digital Asset Links generator present",
        status=Status.PASS,
        evidence=Evidence.STATIC,
        detail="tool/gen_assetlinks.py computes real keystore digests",
    )


def test_passkey_documentation_records_prerequisites() -> CheckResult:
    doc_path = PROJECT_ROOT / "docs" / "passkeys.md"
    doc = read(doc_path) if doc_path.exists() else None
    assert doc, "docs/passkeys.md is missing"
    assert "assetlinks.json" in doc
    return CheckResult(
        name="Passkey deployment prerequisites documented",
        status=Status.PASS,
        evidence=Evidence.STATIC,
        detail="docs/passkeys.md records the server config and the DAL step",
    )


# --------------------------------------------------------------------------
# Device: reported honestly, never inferred
# --------------------------------------------------------------------------

def test_passkey_signup_journey_exists() -> CheckResult:
    src = read(AUTH_REPO)
    assert "registerPasskey" in src
    assert "startRegistration" in src
    return CheckResult(
        name="Passkey registration journey implemented",
        status=Status.PASS,
        evidence=Evidence.STATIC,
        detail="registerPasskey() drives start -> ceremony -> verify",
    )


def test_passkey_signin_journey_exists() -> CheckResult:
    src = read(AUTH_REPO)
    assert "signInWithPasskey" in src
    assert "startAuthentication" in src
    return CheckResult(
        name="Passkey sign-in journey implemented",
        status=Status.PASS,
        evidence=Evidence.STATIC,
        detail="signInWithPasskey() drives start -> ceremony -> verify",
    )


def test_passkey_physical_device_registration() -> CheckResult:
    return _device_only(
        "PASSKEY PHYSICAL DEVICE REGISTRATION:",
        "create account -> passkey -> user verification -> session -> profile",
    )


def test_passkey_physical_device_signin() -> CheckResult:
    return _device_only(
        "PASSKEY PHYSICAL DEVICE SIGN-IN:",
        "sign out -> passkey -> user verification -> discover",
    )


def _device_only(label: str, flow: str) -> CheckResult:
    devices = connected_devices()
    if not devices:
        return CheckResult(
        name=label + " NOT VERIFIED",
            status=Status.NOT_VERIFIED,
            evidence=Evidence.DEVICE,
            detail=f"no physical Android device attached. Required flow: {flow}",
        )
    return CheckResult(
        name=label + " REQUIRES MANUAL RUN",
        status=Status.NOT_VERIFIED,
        evidence=Evidence.DEVICE,
        detail=(
            f"{len(devices)} device(s) attached but no signed device-run "
            f"evidence file was produced. Required flow: {flow}"
        ),
    )
