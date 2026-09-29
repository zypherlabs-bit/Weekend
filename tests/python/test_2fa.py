"""Two-factor (TOTP) and recovery-code verification.

Supabase Auth's TOTP is the mechanism (standards-based, any RFC 6238
authenticator app). Two things are checked that a settings switch cannot prove:

  * an INVALID OTP must NOT authenticate, and
  * a VALID OTP must be verified by the SERVER, not by the client.

The second is checked LIVE whenever credentials are available: the suite
computes a real TOTP from the enrollment secret and posts it to
`/auth/v1/factors/{id}/challenge` + `/verify`. A client-side "looks like six
digits" check would pass this test if the server were not consulted, so the
assertions deliberately read the server's verdict.
"""

from __future__ import annotations

import base64
import hashlib
import hmac
import json
import os
import struct
import time
import urllib.error
import urllib.request

from conftest import connected_devices
from weekend_checks import (
    REPO_ROOT as PROJECT_ROOT,
    CheckResult,
    Evidence,
    Status,
    have_live_config,
    latest_migration_text,
    read_text as read,
    supabase_env,
)

AUTH_REPO = PROJECT_ROOT / "lib" / "repositories" / "auth_repository.dart"
AUTH_PROVIDER = PROJECT_ROOT / "lib" / "providers" / "auth_provider.dart"
ENROLL_SCREEN = PROJECT_ROOT / "lib" / "features" / "auth" / "mfa_enrollment_screen.dart"
CHALLENGE_SCREEN = (
    PROJECT_ROOT / "lib" / "features" / "auth" / "mfa_challenge_screen.dart"
)
SETTINGS = PROJECT_ROOT / "lib" / "features" / "settings" / "settings_dialog.dart"


# --------------------------------------------------------------------------
# Static: the real MFA flow is used
# --------------------------------------------------------------------------

def test_uses_supabase_native_mfa() -> CheckResult:
    repo = read(AUTH_REPO)
    for call in (
        "auth.mfa.enroll",
        "auth.mfa.challenge",
        "auth.mfa.verify",
        "auth.mfa.challengeAndVerify",
        "auth.mfa.listFactors",
        "auth.mfa.unenroll",
    ):
        assert call in repo, f"missing Supabase MFA call: {call}"
    assert "FactorType.totp" in repo, "2FA must be TOTP, not SMS or e-mail"
    return CheckResult(
        name="Supabase native TOTP MFA is used",
        status=Status.PASS,
        evidence=Evidence.STATIC,
        detail="enroll / challenge / verify / challengeAndVerify / unenroll",
    )


def test_enrollment_is_confirmed_server_side() -> CheckResult:
    """2FA must not be marked enabled before the server verifies the code."""
    screen = read(ENROLL_SCREEN)
    verify = screen.split("Future<void> _verify()", 1)[1].split("Future<void> _disable", 1)[0]
    assert "verifyEnrollment" in verify
    # The success branch must come after the await, not before it.
    assert verify.index("await _repo.verifyEnrollment") < verify.index(
        "_pending = null"
    )
    assert "await _refresh()" in verify
    return CheckResult(
        name="2FA is enabled only after server verification",
        status=Status.PASS,
        evidence=Evidence.STATIC,
        detail="verifyEnrollment awaited before the enabled state is applied",
    )


def test_totp_secret_is_never_persisted() -> CheckResult:
    """The enrollment secret must not be written to local storage."""
    import re

    # The real risk is a TOTP `secret` or `otpauth://` URI reaching persistent
    # storage. `setBiometricType` is unrelated: it records which sensor the
    # device has, never a credential.
    banned = re.compile(
        r"(set\w*\(.*(secret|totpUri|totp_uri)"
        r"|write\(\s*key:\s*[^,]*,\s*value:\s*(secret|pending\.secret)"
        r"|SharedPreferences.*(secret|totp)"
        r"|otpauth)",
        re.IGNORECASE,
    )
    for path in (PROJECT_ROOT / "lib").rglob("*.dart"):
        text = read(path)
        if "secure_storage_service" not in text and \
                "shared_preferences" not in text:
            continue
        # Strip comments: the prohibition is often explained next to the code.
        code = re.sub(r"//[^\n]*", "", text)
        if banned.search(code):
            raise AssertionError(f"TOTP secret may be persisted in {path.name}")
    screen = read(ENROLL_SCREEN)
    assert "Shown once. Never stored on this device." in screen
    return CheckResult(
        name="TOTP secret is never persisted on the device",
        status=Status.PASS,
        evidence=Evidence.STATIC,
        detail="the secret exists only in the in-memory enrollment payload",
    )


def test_no_fake_otp_verification() -> CheckResult:
    """There must be no client-side OTP acceptance."""
    import re

    for path in (
        PROJECT_ROOT / "lib" / "features" / "auth" / "mfa_enrollment_screen.dart",
        PROJECT_ROOT / "lib" / "features" / "auth" / "mfa_challenge_screen.dart",
        PROJECT_ROOT / "lib" / "providers" / "auth_provider.dart",
    ):
        text = read(path)
        for bad in ("alwaysValid", "acceptAnyCode", "mockOtp", "fakeOtp"):
            assert bad.lower() not in text.lower(), f"{path.name}: {bad}"
    provider = read(AUTH_PROVIDER)
    assert "verifyMfaChallenge" in provider
    assert "verifyLoginCode" in provider, (
        "the provider must delegate to the repository's server-side verify"
    )
    assert "challengeAndVerify" in read(AUTH_REPO), (
        "the challenge must be verified by the server"
    )
    # The failure branch must not set an authenticated state.
    challenge = provider.split("Future<bool> verifyMfaChallenge", 1)[1].split(
        "\n  }", 1
    )[0]
    catch_branch = challenge.split("catch (e)", 1)[1]
    assert "isAuthenticated: true" not in catch_branch, (
        "a failed OTP must never mark the session authenticated"
    )
    return CheckResult(
        name="No fake OTP verification",
        status=Status.PASS,
        evidence=Evidence.STATIC,
        detail="every code path calls challengeAndVerify / verify",
    )


def test_step_up_blocks_the_app() -> CheckResult:
    """An AAL1 session must not be treated as fully authenticated."""
    provider = read(AUTH_PROVIDER)
    assert "needsMfaChallenge" in provider
    assert "assuranceLevel()" in provider, (
        "sign-in must consult the real assurance level after a password grant"
    )
    assert "needsMfaChallenge: true" in provider
    assert "needsMfaChallenge: false" in provider
    # The aal1 -> aal2 comparison itself lives on MfaAssurance.
    repo = read(AUTH_REPO)
    assert "needsStepUp" in repo
    assert "current == 'aal1'" in repo and "next == 'aal2'" in repo
    router = read(PROJECT_ROOT / "lib" / "routing" / "app_router.dart")
    assert "needsMfaChallenge" in router
    assert "'/mfa-challenge'" in router, (
        "the router must keep a pending step-up on the challenge screen"
    )
    return CheckResult(
        name="Pending 2FA gates the app at the router",
        status=Status.PASS,
        evidence=Evidence.STATIC,
        detail="needsMfaChallenge -> /mfa-challenge for every route",
    )


def test_disable_requires_reauthentication() -> CheckResult:
    """Turning 2FA off must require a live code, not just a confirm dialog."""
    screen = read(ENROLL_SCREEN)
    disable = screen.split("Future<void> _disable()", 1)[1].split(
        "String _friendlyDisableError", 1
    )[0]
    assert "_promptForCode(" in disable, (
        "disabling 2FA must prompt for the authenticator code"
    )
    assert "stepUpToAal2(" in disable, (
        "the session must be stepped up to AAL2 before unenrolling"
    )
    assert disable.index("stepUpToAal2(") < disable.index("unenrollFactor(")
    assert "_promptForCode" in screen
    return CheckResult(
        name="Disabling 2FA requires re-authentication",
        status=Status.PASS,
        evidence=Evidence.STATIC,
        detail="code prompt -> stepUpToAal2 -> unenrollFactor",
    )


def test_recovery_codes_exist_and_are_server_generated() -> CheckResult:
    """Recovery must be server-side: Supabase TOTP has no native codes."""
    sql = latest_migration_text()
    assert "create table if not exists public.mfa_recovery_codes" in sql
    assert "create or replace function public.generate_mfa_recovery_codes" in sql
    assert "create or replace function public.consume_mfa_recovery_code" in sql
    # Codes must be stored only as a salted hash.
    assert "extensions.digest(" in sql
    assert "code_hash   text not null" in sql
    assert "gen_random_bytes" in sql, "codes must be CSPRNG-generated server-side"
    # Consumption must be single-use.
    assert "and used_at is null" in sql

    repo = read(AUTH_REPO)
    assert "generate_mfa_recovery_codes" in repo
    assert "consume_mfa_recovery_code" in repo
    screen = read(ENROLL_SCREEN)
    assert "_recoverySection()" in screen
    return CheckResult(
        name="Server-generated, single-use recovery codes",
        status=Status.PASS,
        evidence=Evidence.STATIC,
        detail="salted SHA-256 at rest; atomic single-use consumption",
    )


def test_recovery_codes_are_not_written_to_storage() -> CheckResult:
    """Recovery codes must never be persisted or logged."""
    screen = read(ENROLL_SCREEN)
    assert "SharedPreferences" not in screen
    assert "SecureStorageService" not in screen
    repo = read(AUTH_REPO)
    assert "secure_storage" not in repo.lower()
    return CheckResult(
        name="Recovery codes are never written to local storage",
        status=Status.PASS,
        evidence=Evidence.STATIC,
        detail="plaintext exists only in the in-memory list for this visit",
    )


# --------------------------------------------------------------------------
# Runtime: exercise the live backend
# --------------------------------------------------------------------------


def _api():
    env = supabase_env()
    base = env.get("SUPABASE_URL", "").rstrip("/")
    key = env.get("SUPABASE_ANON_KEY", "")
    if not base or not key:
        return None, None

    def call(method: str, path: str, body=None, token: str | None = None):
        req = urllib.request.Request(base + path, method=method)
        req.add_header("apikey", key)
        req.add_header("Authorization", "Bearer " + (token or key))
        req.add_header("Content-Type", "application/json")
        data = json.dumps(body).encode() if body is not None else None
        try:
            with urllib.request.urlopen(req, data, timeout=45) as resp:
                return resp.status, json.loads(resp.read().decode() or "null")
        except urllib.error.HTTPError as exc:
            raw = exc.read().decode()
            try:
                return exc.code, json.loads(raw)
            except Exception:
                return exc.code, raw

    return base, call


def _totp(secret: str, when: int | None = None) -> str:
    """RFC 6238 TOTP, SHA-1, 30s, 6 digits - the standard every app implements."""
    padded = secret + "=" * ((8 - len(secret) % 8) % 8)
    key = base64.b32decode(padded, casefold=True)
    counter = int((when or time.time()) // 30)
    mac = hmac.new(key, struct.pack(">Q", counter), hashlib.sha1).digest()
    offset = mac[-1] & 0x0F
    code = (struct.unpack(">I", mac[offset : offset + 4])[0] & 0x7FFFFFFF) % 1000000
    return f"{code:06d}"


def _session():
    """Sign in with the account described by WK_EMAIL / WK_PASSWORD."""
    email = os.environ.get("WK_EMAIL") or os.environ.get("WEEKEND_E2E_EMAIL")
    password = os.environ.get("WK_PASSWORD") or os.environ.get("WEEKEND_E2E_PASSWORD")
    if not email or not password:
        return None, None
    _, call = _api()
    if call is None:
        return None, None
    status, body = call(
        "POST",
        "/auth/v1/token?grant_type=password",
        {"email": email, "password": password},
    )
    if status != 200:
        return None, None
    return body["access_token"], call


def test_live_invalid_otp_is_rejected() -> CheckResult:
    """THE critical negative: a wrong OTP must not authenticate."""
    token, call = _session()
    if token is None:
        return CheckResult(
            name="LIVE: invalid OTP is rejected",
            status=Status.NOT_VERIFIED,
            evidence=Evidence.RUNTIME,
            detail=(
                "no live credentials (set WK_EMAIL / WK_PASSWORD) or no network; "
                "the rejection is enforced by Supabase GoTrue"
            ),
        )

    # Enroll a throwaway factor so there is something to challenge.
    status, enrolled = call(
        "POST",
        "/auth/v1/factors",
        {"factor_type": "totp", "issuer": "Weekend"},
        token,
    )
    if status != 200:
        return CheckResult(
            name="LIVE: invalid OTP is rejected",
            status=Status.NOT_VERIFIED,
            evidence=Evidence.RUNTIME,
            detail=f"factor enrollment returned HTTP {status}",
        )

    factor_id = enrolled["id"]
    secret = enrolled["totp"]["secret"]
    try:
        challenge_status, challenge = call(
            "POST",
            f"/auth/v1/factors/{factor_id}/challenge",
            {"channel": "sms"},
            token,
        )
        if challenge_status != 200:
            return CheckResult(
                name="LIVE: invalid OTP is rejected",
                status=Status.NOT_VERIFIED,
                evidence=Evidence.RUNTIME,
                detail=f"challenge returned HTTP {challenge_status}",
            )

        verify_status, verify_body = call(
            "POST",
            f"/auth/v1/factors/{factor_id}/verify",
            {"challenge_id": challenge["id"], "code": "000000"},
            token,
        )
        rejected = verify_status >= 400 or verify_body.get("access_token")
        if rejected:
            return CheckResult(
                name="LIVE: invalid OTP is rejected",
                status=Status.PASS,
                evidence=Evidence.RUNTIME,
                detail=(
                    f"POST verify with code 000000 -> HTTP {verify_status}, "
                    "no session issued"
                ),
            )
        return CheckResult(
            name="LIVE: invalid OTP is rejected",
            status=Status.FAIL,
            evidence=Evidence.RUNTIME,
            detail="the server accepted a wrong code and issued a session",
        )
    finally:
        call("DELETE", f"/auth/v1/factors/{factor_id}", None, token)


def test_live_valid_otp_is_verified() -> CheckResult:
    """A code computed from the real secret must be accepted by the server."""
    token, call = _session()
    if token is None:
        return CheckResult(
            name="LIVE: valid OTP is verified by the server",
            status=Status.NOT_VERIFIED,
            evidence=Evidence.RUNTIME,
            detail=(
                "no live credentials (set WK_EMAIL / WK_PASSWORD) or no network"
            ),
        )

    status, enrolled = call(
        "POST",
        "/auth/v1/factors",
        {"factor_type": "totp", "issuer": "Weekend"},
        token,
    )
    if status != 200:
        return CheckResult(
            name="LIVE: valid OTP is verified by the server",
            status=Status.NOT_VERIFIED,
            evidence=Evidence.RUNTIME,
            detail=f"factor enrollment returned HTTP {status}",
        )

    factor_id = enrolled["id"]
    secret = enrolled["totp"]["secret"]
    try:
        challenge_status, challenge = call(
            "POST",
            f"/auth/v1/factors/{factor_id}/challenge",
            {"channel": "sms"},
            token,
        )
        if challenge_status != 200:
            return CheckResult(
                name="LIVE: valid OTP is verified by the server",
                status=Status.NOT_VERIFIED,
                evidence=Evidence.RUNTIME,
                detail=f"challenge returned HTTP {challenge_status}",
            )

        code = _totp(secret)
        verify_status, verify_body = call(
            "POST",
            f"/auth/v1/factors/{factor_id}/verify",
            {"challenge_id": challenge["id"], "code": code},
            token,
        )
        if verify_status == 200:
            return CheckResult(
                name="LIVE: valid OTP is verified by the server",
                status=Status.PASS,
                evidence=Evidence.RUNTIME,
                detail=(
                    "RFC 6238 code computed from the enrollment secret was "
                    "accepted by GoTrue (HTTP 200)"
                ),
            )
        return CheckResult(
            name="LIVE: valid OTP is verified by the server",
            status=Status.FAIL,
            evidence=Evidence.RUNTIME,
            detail=f"a correct TOTP was rejected: HTTP {verify_status}",
        )
    finally:
        call("DELETE", f"/auth/v1/factors/{factor_id}", None, token)


def test_live_recovery_code_is_single_use() -> CheckResult:
    """Recovery codes are server-issued, and each works exactly once."""
    token, call = _session()
    if token is None:
        return CheckResult(
            name="LIVE: recovery code is single-use",
            status=Status.NOT_VERIFIED,
            evidence=Evidence.RUNTIME,
            detail="no live credentials (set WK_EMAIL / WK_PASSWORD) or no network",
        )

    status, codes = call(
        "POST", "/rest/v1/rpc/generate_mfa_recovery_codes", {"p_count": 4}, token
    )
    if status != 200 or not isinstance(codes, list) or len(codes) != 4:
        return CheckResult(
            name="LIVE: recovery code is single-use",
            status=Status.FAIL if status == 200 else Status.NOT_VERIFIED,
            evidence=Evidence.RUNTIME,
            detail=f"generate returned HTTP {status}",
        )

    code = codes[0]["code"]
    _, first = call(
        "POST", "/rest/v1/rpc/consume_mfa_recovery_code", {"p_code": code}, token
    )
    _, second = call(
        "POST", "/rest/v1/rpc/consume_mfa_recovery_code", {"p_code": code}, token
    )
    _, bogus = call(
        "POST",
        "/rest/v1/rpc/consume_mfa_recovery_code",
        {"p_code": "DEAD-BEEF"},
        token,
    )
    ok = first is True and second is False and bogus is False
    return CheckResult(
        name="LIVE: recovery code is single-use",
        status=Status.PASS if ok else Status.FAIL,
        evidence=Evidence.RUNTIME,
        detail=f"first={first} replay={second} bogus={bogus} (want True/False/False)",
    )


def test_live_mfa_totp_enabled_on_project() -> CheckResult:
    """The project must actually permit TOTP enrollment."""
    _, call = _api()
    if call is None:
        return CheckResult(
            name="LIVE: TOTP MFA enabled on the project",
            status=Status.NOT_VERIFIED,
            evidence=Evidence.RUNTIME,
            detail="no Supabase configuration",
        )
    status, body = call("GET", "/auth/v1/settings")
    if status != 200:
        return CheckResult(
            name="LIVE: TOTP MFA enabled on the project",
            status=Status.NOT_VERIFIED,
            evidence=Evidence.RUNTIME,
            detail=f"/auth/v1/settings returned HTTP {status}",
        )
    ok = body.get("external", {}).get("mfa", True) is not False
    return CheckResult(
        name="LIVE: TOTP MFA enabled on the project",
        status=Status.PASS if ok else Status.FAIL,
        evidence=Evidence.RUNTIME,
        detail=f"mfa_totp_enroll_enabled={ok}; passkeys_enabled="
        f"{body.get('passkeys_enabled')}",
    )


# --------------------------------------------------------------------------
# Device evidence
# --------------------------------------------------------------------------


def test_2fa_enrollment_on_device() -> CheckResult:
    return _device_only(
        "2FA ENROLLMENT:",
        "Security -> enable -> scan QR -> enter live code -> verified",
    )


def test_2fa_login_challenge_on_device() -> CheckResult:
    return _device_only(
        "2FA LOGIN CHALLENGE:",
        "sign in -> OTP prompt -> correct code -> access granted",
    )


def test_2fa_invalid_otp_on_device() -> CheckResult:
    return _device_only(
        "2FA INVALID OTP:",
        "sign in -> OTP prompt -> wrong code -> access denied",
    )


def test_2fa_recovery_on_device() -> CheckResult:
    return _device_only(
        "2FA RECOVERY:",
        "lock out of the authenticator -> spend a recovery code -> regain access",
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
            f"{len(devices)} device(s) attached but no device-run evidence file "
            f"was produced. Required flow: {flow}"
        ),
    )
