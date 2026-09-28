"""Passkey (WebAuthn) verification.

Passkeys need a physical Android device with a screen lock, so the parts
that can only be proven by running the app are reported as NOT VERIFIED by
the runner rather than silently claimed as passing.
"""

from __future__ import annotations

import re

import pytest

from conftest import PROJECT_ROOT, connected_devices, read

PUBSPEC = PROJECT_ROOT / "pubspec.yaml"
AUTH_REPO = PROJECT_ROOT / "lib" / "repositories" / "auth_repository.dart"
MANIFEST = PROJECT_ROOT / "android" / "app" / "src" / "main" / "AndroidManifest.xml"
MFA_SCREEN = PROJECT_ROOT / "lib" / "features" / "auth" / "mfa_challenge_screen.dart"


@pytest.fixture(scope="module")
def auth_source() -> str:
    assert AUTH_REPO.exists()
    return read(AUTH_REPO)


def _strip_comments(source: str) -> str:
    """Drop `//` comment lines so a test's own explanation of an old bug
    cannot be read as the bug still being present."""
    return "\n".join(
        line for line in source.splitlines() if not line.strip().startswith("//")
    )


class TestPasskeyDependencies:
    def test_credential_manager_is_a_dependency(self) -> None:
        assert "credential_manager" in read(PUBSPEC)

    def test_min_sdk_meets_the_credential_manager_requirement(self) -> None:
        gradle = read(PROJECT_ROOT / "android" / "app" / "build.gradle.kts")
        m = re.search(r"minSdk\s*=\s*(\d+)", gradle)
        assert m
        assert int(m.group(1)) >= 24, "passkeys require API 24+"


class TestPasskeyImplementation:
    """The passkey flow uses Supabase's NATIVE passkey API.

    An earlier revision drove the WebAuthn *MFA factor* API
    (`mfa.enroll(factorType: webauthn)` / `mfa.listFactors()`). Both require
    an already-authenticated session, which is impossible during sign-up and
    impossible during sign-in, so that flow could never have worked.
    """

    def test_uses_supabase_native_passkey_api(self, auth_source: str) -> None:
        assert "auth.passkey.startRegistration" in auth_source
        assert "auth.passkey.verifyRegistration" in auth_source
        assert "auth.passkey.startAuthentication" in auth_source
        assert "auth.passkey.verifyAuthentication" in auth_source

    def test_does_not_drive_the_mfa_factor_api_for_passkeys(
        self, auth_source: str
    ) -> None:
        # The MFA-factor path requires a session to exist first, so it cannot
        # bootstrap sign-in or sign-up.
        #
        # `mfa.listFactors()` still appears legitimately for TOTP 2FA
        # enrolment, so the check is scoped to the passkey section: the
        # WebAuthn enrolment and any passkey-time factor listing are banned,
        # a TOTP factor list is not.
        code = _strip_comments(auth_source)
        assert not re.search(
            r"mfa\.enroll\(\s*factorType:\s*FactorType\.webauthn", code
        ), "passkeys must use auth.passkey.*, not the MFA factor API"

        # Split on the RAW source: the section banner is itself a comment, so
        # it would be gone by the time the stripped copy is used.
        section = "PASSKEYS"
        if section in auth_source:
            passkey_section = auth_source.split(section, 1)[-1]
            passkey_section = _strip_comments(passkey_section)
            assert "mfa.listFactors" not in passkey_section, (
                "the passkey flow must not enumerate MFA factors"
            )
        else:
            pytest.skip("no passkey section marker to scope the check to")

    def test_uses_the_platform_authenticator(self, auth_source: str) -> None:
        assert "CredentialManagerPlatform.instance" in auth_source
        assert "savePasskeyCredentials" in auth_source
        assert "getCredentials" in auth_source

    def test_registration_requires_an_existing_session(self, auth_source: str) -> None:
        # Supabase cannot create a passkey for an account that does not exist
        # yet; pretending otherwise would be a fake success.
        assert re.search(
            r"currentSession\s*==\s*null[\s\S]{0,200}Sign in first", auth_source
        ), "registerPasskey must refuse without a session and say why"

    def test_failures_return_a_result_rather_than_throwing(self, auth_source: str) -> None:
        assert "PasskeyOperationResult.failure" in auth_source
        assert "PasskeyOperationResult.success" in auth_source
        # A missing server-side setting must produce a clear message, not a
        # fabricated success.
        assert "passkey_disabled" in auth_source


class TestPasskeyConfiguration:
    def test_relying_party_metadata_is_declared(self) -> None:
        manifest = read(MANIFEST)
        assert "android.credentials.webauthn.relying_party_id" in manifest

    def test_asset_links_host_is_declared(self) -> None:
        # Passkeys need digital asset links proving the app owns the domain;
        # without them the credential is not associated with this RP.
        manifest = read(MANIFEST)
        assert "autoVerify" in manifest, (
            "an App Links intent-filter is required for passkey association"
        )

    def test_credential_manager_queries_are_present(self) -> None:
        manifest = read(MANIFEST)
        assert "android.service.credentials.CredentialProviderService" in manifest
        assert "android.service.autofill.AutofillService" in manifest

    def test_mfa_challenge_screen_exists(self) -> None:
        assert MFA_SCREEN.exists(), "the MFA step-up screen is missing"


class TestPasskeyDeviceVerification:
    """These cannot be proven from source alone."""

    def test_passkey_registration_on_a_real_device(self) -> None:
        devices = connected_devices()
        if not devices:
            pytest.skip(
                "NOT VERIFIED: no physical Android device attached. Passkey "
                "registration requires a device with a screen lock and a "
                "registered credential."
            )
        # A device is present; the actual registration is exercised by the
        # device test plan, not by this static suite.
        pytest.skip(
            "NOT VERIFIED: passkey registration was not executed by this "
            "static suite even though a device is attached"
        )
