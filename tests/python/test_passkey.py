"""Passkey / Credential Manager checks.

Three distinct claims are kept separate on purpose:

1. STATIC - the repository contains a real, standards-based WebAuthn
   implementation wired to Supabase's native passkey API.
2. RUNTIME - the ceremony endpoint responds on the live project (this proves
   the project has passkeys enabled, not that a human used one).
3. DEVICE - a passkey was actually created and used on physical Android
   hardware. This is ALWAYS reported as NOT VERIFIED unless a device evidence
   file from a real run exists. It is never reported as PASS from a static
   read or from a successful build.
"""

from __future__ import annotations

import re
import urllib.error
import urllib.request

from weekend_checks import (
    REPO_ROOT,
    CheckResult,
    Evidence,
    Status,
    device_connected,
    device_evidence,
    have_live_config,
    read_text,
    supabase_env,
)

AUTH_REPO = REPO_ROOT / "lib" / "repositories" / "auth_repository.dart"


def _auth_text() -> str:
    return read_text(AUTH_REPO)


def test_credential_manager_integration() -> CheckResult:
    """STATIC: Credential Manager drives the WebAuthn ceremonies."""
    text = _auth_text()
    ok = (
        "CredentialManagerPlatform" in text
        and "savePasskeyCredentials" in text
        and "getCredentials" in text
    )
    return CheckResult(
        name="Credential Manager integration",
        status=Status.PASS if ok else Status.FAIL,
        evidence=Evidence.STATIC,
        detail="create + get wired" if ok else "ceremony calls missing",
    )


def test_supabase_native_passkey_api() -> CheckResult:
    """STATIC: the real Supabase passkey API is used, not an MFA workaround.

    Supabase's native API is `client.auth.passkey.*`. The broken pattern this
    replaces drove the WebAuthn *MFA factor* API (`mfa.enroll(factorType:
    webauthn)`), which requires an already-authenticated session and therefore
    cannot work during sign-up or usernameless sign-in.
    """
    text = _auth_text()
    uses_native = all(
        m in text
        for m in (
            "auth.passkey.startRegistration",
            "auth.passkey.verifyRegistration",
            "auth.passkey.startAuthentication",
            "auth.passkey.verifyAuthentication",
        )
    )
    # The repository also supports genuine TOTP MFA, so a plain `mfa.enroll`
    # is legitimate. Only the *WebAuthn factor* usage is the broken pattern,
    # and it must appear in code, not in an explanatory comment.
    code_only = re.sub(r"//.*?$", "", text, flags=re.M)
    uses_mfa_workaround = (
        "FactorType.webauthn" in code_only or "factorType: FactorType.webauthn" in code_only
    )
    if uses_native and not uses_mfa_workaround:
        status, detail = Status.PASS, "native passkey API"
    elif uses_mfa_workaround:
        status, detail = Status.FAIL, "uses the session-gated MFA webauthn API"
    else:
        status, detail = Status.FAIL, "passkey ceremony not found"
    return CheckResult(
        name="Supabase native passkey API",
        status=status,
        evidence=Evidence.STATIC,
        detail=detail,
    )


def test_passkey_challenge_handling() -> CheckResult:
    """STATIC: challenge id and credential are sent to the server to verify.

    A flow that verifies locally, or omits the challenge, is not WebAuthn.
    """
    text = _auth_text()
    ok = "challengeId" in text and "credential" in text
    return CheckResult(
        name="Challenge/response handling",
        status=Status.PASS if ok else Status.FAIL,
        evidence=Evidence.STATIC,
        detail="challengeId + credential sent" if ok else "missing",
    )


def test_no_fake_biometric_implementation() -> CheckResult:
    """STATIC: no simulated passkey that fakes success without a ceremony."""
    text = _auth_text()
    problems = []
    if re.search(r"bool\s+_?passkey\s*=\s*true", text, re.I):
        problems.append("boolean flag")
    if "fakePasskey" in text or "mockPasskey" in text:
        problems.append("mock credential")
    if "signInWithPasskey" in text and "verifyAuthentication" not in text:
        problems.append("no server verification")
    return CheckResult(
        name="No fake biometric logic",
        status=Status.PASS if not problems else Status.FAIL,
        evidence=Evidence.STATIC,
        detail="real ceremony" if not problems else "; ".join(problems),
    )


def test_digital_asset_links_declared() -> CheckResult:
    """STATIC: an autoVerify app-link host is declared for the RP domain.

    Android passkeys verify the relying party through Digital Asset Links
    served from that host, so the manifest needs an https intent-filter with
    autoVerify rather than a bare deep link.
    """
    manifest = read_text(
        REPO_ROOT / "android" / "app" / "src" / "main" / "AndroidManifest.xml"
    )
    ok = "android:autoVerify" in manifest and "https" in manifest
    return CheckResult(
        name="App Links configured",
        status=Status.PASS if ok else Status.FAIL,
        evidence=Evidence.STATIC,
        detail="autoVerify intent-filter present" if ok else "missing",
    )


def test_passkey_project_enabled_live() -> CheckResult:
    """RUNTIME: the live Supabase project has passkeys enabled.

    Calls the unauthenticated challenge endpoint. A 200 means the project
    setting is on. Anything else means the feature cannot work yet.
    """
    if not have_live_config():
        return CheckResult(
            name="Passkeys enabled on project",
            status=Status.NOT_VERIFIED,
            evidence=Evidence.RUNTIME,
            detail="no live credentials configured",
        )
    env = supabase_env()
    url = env["SUPABASE_URL"].rstrip("/")
    key = env["SUPABASE_ANON_KEY"]
    req = urllib.request.Request(
        f"{url}/auth/v1/passkeys/authentication/options",
        data=b"{}",
        headers={
            "apikey": key,
            "Authorization": f"Bearer {key}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=25) as resp:
            body = resp.read().decode("utf-8", "replace")
            ok = resp.status == 200 and "challenge_id" in body
            return CheckResult(
                name="Passkeys enabled on project",
                status=Status.PASS if ok else Status.FAIL,
                evidence=Evidence.RUNTIME,
                detail=(
                    "challenge endpoint returns a challenge"
                    if ok
                    else f"unexpected response {resp.status}"
                ),
            )
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", "replace")
        if "passkey_disabled" in body:
            return CheckResult(
                name="Passkeys enabled on project",
                status=Status.FAIL,
                evidence=Evidence.RUNTIME,
                detail="passkey_disabled - enable it in the dashboard",
            )
        return CheckResult(
            name="Passkeys enabled on project",
            status=Status.FAIL,
            evidence=Evidence.RUNTIME,
            detail=f"HTTP {exc.code}",
        )
    except Exception as exc:  # noqa: BLE001 - network conditions vary
        return CheckResult(
            name="Passkeys enabled on project",
            status=Status.NOT_VERIFIED,
            evidence=Evidence.RUNTIME,
            detail=f"unreachable: {type(exc).__name__}",
        )


def test_passkey_device_test() -> CheckResult:
    """DEVICE: a passkey was created and used on a physical Android device.

    Never reported as PASS from a static read, a successful compile or an
    emulator run. Requires a recorded device-evidence file.
    """
    evidence = device_evidence().get("passkey")
    if not evidence:
        connected = (
            "a device is attached" if device_connected() else "no physical device attached"
        )
        return CheckResult(
            name="PASSKEY DEVICE TEST",
            status=Status.NOT_VERIFIED,
            evidence=Evidence.DEVICE,
            detail=f"no device evidence recorded ({connected})",
        )
    ok = bool(evidence.get("registered")) and bool(evidence.get("signed_in"))
    return CheckResult(
        name="PASSKEY DEVICE TEST",
        status=Status.PASS if ok else Status.FAIL,
        evidence=Evidence.DEVICE,
        detail=(
            f"registered + signin on {evidence.get('device', 'device')}"
            if ok
            else "device run did not complete both steps"
        ),
    )

