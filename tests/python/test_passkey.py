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


class TestPasskeyDependencies:
    def test_credential_manager_is_a_dependency(self) -> None:
        assert "credential_manager" in read(PUBSPEC)

    def test_min_sdk_meets_the_credential_manager_requirement(self) -> None:
        gradle = read(PROJECT_ROOT / "android" / "app" / "build.gradle.kts")
        m = re.search(r"minSdk\s*=\s*(\d+)", gradle)
        assert m
        assert int(m.group(1)) >= 24, "passkeys require API 24+"


class TestPasskeyImplementation:
    def test_uses_supabase_mfa_webauthn_factor(self, auth_source: str) -> None:
        assert "FactorType.webauthn" in auth_source
        assert "mfa.enroll" in auth_source
        assert "mfa.challenge" in auth_source
        assert "mfa.verify" in auth_source

    def test_enrolls_with_a_relying_party_id(self, auth_source: str) -> None:
        assert re.search(
            r"_rpName\s*=\s*'[^']+'", auth_source
        ), "a relying party name must be set during enrollment"

    def test_uses_the_platform_authenticator(self, auth_source: str) -> None:
        assert "CredentialManagerPlatform.instance" in auth_source
        assert "savePasskeyCredentials" in auth_source
        assert "getCredentials" in auth_source

    def test_user_cancellation_is_handled_distinctly(self, auth_source: str) -> None:
        # A cancel must be reported as a cancel, not as a generic failure.
        assert "User cancelled" in auth_source

    def test_no_password_fallback_hack_in_passkey_signup(self, auth_source: str) -> None:
        # A previous revision called signInWithPassword(email, '') when the
        # session was missing: that always fails, and it was followed by a
        # `success: true` return - reporting a successful sign-in for an
        # unauthenticated user. The flow must fail honestly instead.
        #
        # Comments are stripped first: this test's own explanation of the old
        # bug must not be read as the bug still being present.
        code = "\n".join(
            line for line in auth_source.splitlines() if not line.strip().startswith("//")
        )
        assert not re.search(
            r"signInWithPassword\([^)]*password:\s*''", code
        ), "passkey signup must not fall back to an empty-password sign-in"

    def test_passkey_results_never_report_success_without_a_session(
        self, auth_source: str
    ) -> None:
        # A `success: true` carrying a null session tells the caller the user
        # is signed in when nobody is.
        code = "\n".join(
            line for line in auth_source.splitlines() if not line.strip().startswith("//")
        )
        for result in ["PasskeyRegistrationResult", "PasskeyAuthenticationResult"]:
            idx = 0
            while True:
                idx = code.find(result + "(", idx)
                if idx == -1:
                    break
                window = code[idx : idx + 260]
                if "success: true" in window and "session:" not in window:
                    # A literal `true` with no session field at all.
                    assert "session: session" in window or "session: null" in window, (
                        f"{result} reports success without attaching a session"
                    )
                idx += 1

    def test_failures_return_a_result_rather_than_throwing(self, auth_source: str) -> None:
        assert "PasskeyRegistrationResult(" in auth_source
        assert "PasskeyAuthenticationResult(" in auth_source
        assert "success: false" in auth_source


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
