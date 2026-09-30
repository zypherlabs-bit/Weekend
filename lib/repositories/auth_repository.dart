import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import '../services/passkey_service.dart';

// Supabase's native passkey API is still marked `@experimental` upstream. It is
// a deliberate, reviewed dependency of Weekend's passkey support, so the
// opt-in is granted once here rather than at every call site.
// ignore_for_file: experimental_member_use

/// Data source for authentication, sessions and Supabase MFA (TOTP 2FA).
///
/// 2FA uses Supabase Auth's native MFA implementation:
/// enroll -> challenge -> verify. No secret ever leaves Supabase except the
/// single enrollment payload shown once to the enrolling user; the client
/// never persists raw TOTP secrets.
class AuthRepository {
  SupabaseClient? get _client => SupabaseConfig.client;

  /// Sign up with email + password.
  ///
  /// [emailRedirectTo] is passed straight through to Supabase. GoTrue only
  /// honours it when the URL is present in the project's
  /// *Authentication -> URL Configuration -> Redirect URLs* allow-list;
  /// otherwise it silently falls back to the project's Site URL.
  ///
  /// LIVE-ONLY: throws [StateError] when no backend is configured instead of
  /// silently returning. The old silent return made signup look accepted
  /// ("check your email") while nothing was ever sent.
  Future<void> signUpWithEmail(
    String email,
    String password,
    String fullName, {
    String? emailRedirectTo,
  }) async {
    final client = _client;
    if (client == null) {
      throw StateError(
        'Weekend is not connected to a backend. '
        'Build with SUPABASE_URL and SUPABASE_ANON_KEY to enable accounts.',
      );
    }
    await client.auth.signUp(
      email: email,
      password: password,
      data: {'full_name': fullName},
      emailRedirectTo: emailRedirectTo,
    );
  }

  /// Re-send the signup confirmation email for an account that has not been
  /// confirmed yet. Supabase performs the send; nothing is minted client-side.
  Future<void> resendSignupConfirmation(
    String email, {
    String? emailRedirectTo,
  }) async {
    final client = _client;
    if (client == null) {
      throw StateError(
        'Weekend is not connected to a backend. '
        'Build with SUPABASE_URL and SUPABASE_ANON_KEY to enable accounts.',
      );
    }
    await client.auth.resend(
      email: email,
      type: OtpType.signup,
      emailRedirectTo: emailRedirectTo,
    );
  }

  Future<void> signInWithEmail(String email, String password) async {
    final client = _client;
    if (client == null) {
      throw StateError(
        'Weekend is not connected to a backend. '
        'Build with SUPABASE_URL and SUPABASE_ANON_KEY to enable accounts.',
      );
    }
    await client.auth.signInWithPassword(email: email, password: password);
  }

  Future<void> signInAnonymously() async {
    final client = _client;
    if (client == null) {
      throw StateError(
        'Weekend is not connected to a backend. '
        'Build with SUPABASE_URL and SUPABASE_ANON_KEY to enable accounts.',
      );
    }
    await client.auth.signInAnonymously();
  }

  Future<void> signOut() async {
    final client = _client;
    if (client == null) return;
    await client.auth.signOut();
  }

  /// Sign out everywhere (revoke all other sessions).
  Future<void> signOutAllDevices() async {
    final client = _client;
    if (client == null) return;
    await client.auth.signOut(scope: SignOutScope.global);
  }

  Future<void> resetPassword(String email) async {
    final client = _client;
    if (client == null) return;
    await client.auth.resetPasswordForEmail(email);
  }

  Future<void> updatePassword(String newPassword) async {
    final client = _client;
    if (client == null) return;
    await client.auth.updateUser(UserAttributes(password: newPassword));
  }

  /// Delete the current user's account through the `account-deletion` Edge
  /// Function. The privileged cleanup (auth user, profile rows, storage
  /// objects, sessions) runs server-side; the client only forwards the
  /// caller's own access token so the function can verify identity.
  ///
  /// [password] is REQUIRED. The edge function performs a real credential
  /// check and returns 401 without it: deletion is irreversible and destroys
  /// the profile, photos, matches and the entire message history, so a live -
  /// and frequently cached - session token is not sufficient proof that the
  /// person at the keyboard owns the account. It previously read `password`
  /// from the body and never verified it.
  ///
  /// Returns `true` when the backend confirms deletion. Throws on failure so
  /// the UI can surface the real backend error instead of a fake success.
  Future<bool> deleteAccount({
    required String password,
    String reason = 'user_request',
  }) async {
    final client = _client;
    if (client == null) return false;
    final session = client.auth.currentSession;
    final userId = client.auth.currentUser?.id;
    if (session == null || userId == null) return false;
    final response = await client.functions.invoke(
      'account-deletion',
      body: {'userId': userId, 'reason': reason, 'password': password},
    );
    final data = response.data;
    if (data is Map<String, dynamic>) {
      if (data['success'] == true) return true;
      final error = data['error']?.toString() ?? 'Account deletion failed.';
      throw Exception(error);
    }
    return response.status == 200;
  }

  // ---------------------------------------------------------------- MFA/2FA

  /// List enrolled MFA factors for the current user.
  Future<MFAFactors> listFactors() async {
    final client = _client;
    if (client == null) return MFAFactors.empty;
    try {
      final response = await client.auth.mfa.listFactors();
      final verified = response.totp
          .where((f) => f.status == FactorStatus.verified)
          .toList();
      return MFAFactors(all: response.all, verifiedTotp: verified);
    } catch (_) {
      return MFAFactors.empty;
    }
  }

  /// True when at least one verified TOTP factor exists.
  Future<bool> isMfaEnabled() async {
    final factors = await listFactors();
    return factors.verifiedTotp.isNotEmpty;
  }

  /// Returns the current/next authenticator assurance levels.
  MfaAssurance? assuranceLevel() {
    final client = _client;
    if (client == null) return null;
    try {
      final response = client.auth.mfa.getAuthenticatorAssuranceLevel();
      return MfaAssurance(
        current: response.currentLevel?.name,
        next: response.nextLevel?.name,
      );
    } catch (_) {
      return null;
    }
  }

  /// Begin TOTP enrollment. Returns the factor id + TOTP uri/secret/QR payload
  /// to present to the user exactly once.
  Future<MfaEnrollment?> enrollTotp({
    String issuer = 'Weekend',
    String? friendlyName,
  }) async {
    final client = _client;
    if (client == null) return null;
    final response = await client.auth.mfa.enroll(
      factorType: FactorType.totp,
      issuer: issuer,
      friendlyName: friendlyName ?? 'Weekend authenticator',
    );
    final totp = response.totp;
    return MfaEnrollment(
      factorId: response.id,
      totpUri: totp?.uri ?? '',
      secret: totp?.secret ?? '',
      qrCode: totp?.qrCode ?? '',
    );
  }

  /// Verify a freshly enrolled factor with the 6-digit code from the
  /// authenticator app. On success the session is promoted to AAL2.
  Future<bool> verifyEnrollment({
    required String factorId,
    required String code,
  }) async {
    final client = _client;
    if (client == null) return false;
    final challenge = await client.auth.mfa.challenge(factorId: factorId);
    await client.auth.mfa.verify(
      factorId: factorId,
      challengeId: challenge.id,
      code: code.trim(),
    );
    return true;
  }

  /// Challenge + verify during login when AAL1 â†’ AAL2 is required.
  Future<bool> verifyLoginCode({
    required String factorId,
    required String code,
  }) async {
    final client = _client;
    if (client == null) return false;
    await client.auth.mfa.challengeAndVerify(
      factorId: factorId,
      code: code.trim(),
    );
    return true;
  }

  /// Remove an MFA factor (requires an AAL2 session for verified factors).
  ///
  /// GoTrue itself enforces the AAL2 requirement for a verified factor, so an
  /// attacker holding only a stolen AAL1 session cannot silently remove the
  /// second factor. [verifyLoginCode] / [stepUpToAal2] are the supported way to
  /// reach AAL2 first.
  Future<void> unenrollFactor(String factorId) async {
    final client = _client;
    if (client == null) return;
    await client.auth.mfa.unenroll(factorId);
  }

  /// The verified TOTP factor, or null when 2FA is off.
  Future<Factor?> verifiedTotpFactor() async {
    final client = _client;
    if (client == null) return null;
    if (client.auth.currentSession == null) return null;
    try {
      // `listFactors` returns a wrapper with per-type buckets in this SDK.
      final response = await client.auth.mfa.listFactors();
      for (final factor in response.totp) {
        if (factor.factorType == FactorType.totp &&
            factor.status == FactorStatus.verified) {
          return factor;
        }
      }
    } catch (_) {
      // A transient failure must not be reported as "2FA disabled"; callers
      // treat null as unknown and keep their current UI state.
      return null;
    }
    return null;
  }

  /// Step the current session up to AAL2 with a code from the authenticator.
  ///
  /// Used both at login and as the re-authentication gate in front of a
  /// sensitive action (disabling 2FA, deleting a passkey).
  Future<bool> stepUpToAal2({
    required String factorId,
    required String code,
  }) async {
    final client = _client;
    if (client == null) return false;
    await client.auth.mfa.challengeAndVerify(
      factorId: factorId,
      code: code.trim(),
    );
    return true;
  }

  // ------------------------------------------------------- 2FA RECOVERY
  // Supabase Auth's TOTP has no recovery-code primitive, so Weekend
  // implements one server-side (migration 025). Codes are generated by
  // Postgres, stored only as a salted SHA-256, and invalidated on use.

  /// Issue a fresh set of recovery codes, invalidating any previous set.
  ///
  /// The plaintext codes exist only in the returned list and in memory. They
  /// are never logged and never written to local storage.
  Future<List<MfaRecoveryCode>> generateRecoveryCodes({int count = 8}) async {
    final client = _client;
    if (client == null) return const [];
    final rows = await client.rpc(
      'generate_mfa_recovery_codes',
      params: {'p_count': count},
    );
    final list = (rows as List?) ?? const [];
    return list
        .whereType<Map<String, dynamic>>()
        .map(
          (row) => MfaRecoveryCode(
            code: (row['code'] ?? '').toString(),
            label: (row['label'] ?? '').toString(),
          ),
        )
        .where((c) => c.code.isNotEmpty)
        .toList(growable: false);
  }

  /// Spend one recovery code.
  ///
  /// Returns false for an unknown, already-used or malformed code - the
  /// server answers identically for every failure so the response cannot be
  /// used to probe which codes exist.
  Future<bool> consumeRecoveryCode(String code) async {
    final client = _client;
    if (client == null) return false;
    final result = await client.rpc(
      'consume_mfa_recovery_code',
      params: {'p_code': code},
    );
    return result == true;
  }

  /// How many unused recovery codes remain.
  Future<int> recoveryCodeCount() async {
    final client = _client;
    if (client == null) return 0;
    try {
      final result = await client.rpc('mfa_recovery_code_count');
      return (result as num?)?.toInt() ?? 0;
    } catch (_) {
      return 0;
    }
  }

  // ----------------------------------------------------------- PASSKEYS
  // -----------------------------------------------------------
  // Standards-based WebAuthn through Supabase Auth's native passkey API
  // (`client.auth.passkey.*`) and Android Credential Manager:
  //
  //   1. startRegistration / startAuthentication  -> server issues a challenge
  //   2. Android Credential Manager ceremony       -> the device signs it
  //   3. verifyRegistration / verifyAuthentication-> server validates and
  //                                                  returns a real session
  //
  // All platform plumbing (Credential Manager init, option shaping, error
  // mapping, credential serialisation) lives in `PasskeyService`. This class
  // only sequences the server steps, so there is exactly one place where a
  // credential can be produced and exactly one where a session is obtained.
  //
  // NOTHING here fabricates a session. `success: true` is returned only when
  // GoTrue itself returned one.
  //
  // Server prerequisites (verified live against this project):
  //   * Authentication -> Passkeys -> Enable Passkey authentication
  //   * a WebAuthn relying-party ID (`webauthn_rp_id`)
  //   * Digital Asset Links at https://<rp-id>/.well-known/assetlinks.json
  //     naming `com.weekend.app` plus the SHA-256 of the signing certificate.
  //     Android Credential Manager refuses a passkey whose RP cannot be
  //     associated with this app, which surfaces as an opaque provider error.

  /// Register a passkey for the CURRENTLY SIGNED IN user.
  ///
  /// Supabase requires an existing, confirmed, non-anonymous account before a
  /// passkey can be created, so this is a post-sign-up step, not a way to
  /// create an account. Creating the account is [signUpWithEmail]'s job.
  Future<PasskeyOperationResult> registerPasskey({String? friendlyName}) async {
    final client = _client;
    if (client == null) {
      return const PasskeyOperationResult.failure(
        'Weekend is not connected to a backend.',
      );
    }
    if (client.auth.currentSession == null) {
      return const PasskeyOperationResult.failure(
        'Sign in first, then add a passkey.',
      );
    }

    try {
      // Step 1 - server challenge (W3C PublicKeyCredentialCreationOptionsJSON).
      final start = await client.auth.passkey.startRegistration(
        friendlyName: friendlyName,
      );

      // Step 2 - Android Credential Manager ceremony. The system prompts for
      // fingerprint / face / device PIN.
      final ceremony = await PasskeyService.instance.createCredential(
        start.options,
      );
      if (!ceremony.success || ceremony.credential == null) {
        return PasskeyOperationResult.failure(ceremony.message);
      }

      // Step 3 - server validates the attestation and stores the credential.
      final passkey = await client.auth.passkey.verifyRegistration(
        challengeId: start.challengeId,
        credential: PasskeyService.credentialToJson(ceremony.credential!),
      );
      return PasskeyOperationResult.success(
        message: 'Passkey added',
        passkeyId: passkey.id,
      );
    } catch (e) {
      return PasskeyOperationResult.failure(_mapPasskeyError(e));
    }
  }

  /// Sign in with a passkey (discoverable credential - no email required).
  Future<PasskeyOperationResult> signInWithPasskey() async {
    final client = _client;
    if (client == null) {
      return const PasskeyOperationResult.failure(
        'Weekend is not connected to a backend.',
      );
    }

    try {
      // Step 1 - server challenge. This endpoint is UNAUTHENTICATED, which is
      // exactly what makes usernameless sign-in possible.
      final start = await client.auth.passkey.startAuthentication();

      // Step 2 - Credential Manager picks the credential and signs the
      // challenge with user verification (biometrics or device PIN).
      final ceremony = await PasskeyService.instance.getCredential(
        start.options,
      );
      if (!ceremony.success || ceremony.credential == null) {
        return PasskeyOperationResult.failure(ceremony.message);
      }

      // Step 3 - server validates the assertion and issues a real session,
      // which the SDK persists and broadcasts on the auth stream.
      final response = await client.auth.passkey.verifyAuthentication(
        challengeId: start.challengeId,
        credential: PasskeyService.credentialToJson(ceremony.credential!),
      );
      final session = response.session;
      if (session == null) {
        // A verification that returned no session is NOT a sign-in. Reporting
        // success here would leave the app "authenticated" with no token.
        return const PasskeyOperationResult.failure(
          'Sign-in did not return a session. Please try again.',
        );
      }
      return PasskeyOperationResult.success(
        message: 'Signed in',
        session: session,
      );
    } catch (e) {
      return PasskeyOperationResult.failure(_mapPasskeyError(e));
    }
  }

  /// Passkeys registered to the signed-in user (Settings -> Passkeys).
  Future<List<Passkey>> listPasskeys() async {
    final client = _client;
    if (client == null) return const [];
    if (client.auth.currentSession == null) return const [];
    try {
      return await client.auth.passkey.list();
    } catch (_) {
      return const [];
    }
  }

  /// Remove a passkey from the signed-in user.
  Future<PasskeyOperationResult> deletePasskey(String passkeyId) async {
    final client = _client;
    if (client == null) {
      return const PasskeyOperationResult.failure(
        'Weekend is not connected to a backend.',
      );
    }
    try {
      await client.auth.passkey.delete(passkeyId: passkeyId);
      return const PasskeyOperationResult.success(message: 'Passkey removed');
    } catch (e) {
      return PasskeyOperationResult.failure(_mapPasskeyError(e));
    }
  }

  /// Whether this build can attempt a passkey ceremony at all.
  ///
  /// Reports only what is knowable client-side: a supported platform, an
  /// initialised Credential Manager and a configured Supabase client. It is NOT
  /// a claim that a passkey is enrolled, that the project has passkeys
  /// enabled, or that Digital Asset Links are published - none of those are
  /// observable from the device.
  static Future<bool> isPasskeySupported() async {
    if (!SupabaseConfig.isConfigured) return false;
    if (SupabaseConfig.client == null) return false;
    if (!PasskeyService.isSupportedPlatform) return false;
    return PasskeyService.instance.ensureInitialized();
  }

  /// Translate a Supabase/GoTrue error into wording that is safe to show and
  /// tells the user what to do next.
  ///
  /// Deliberately generic in the fallback: raw driver text can leak
  /// implementation detail, and an unmapped error must never be reported as a
  /// success.
  static String _mapPasskeyError(Object e) {
    if (e is PasskeyException) return e.message;
    final text = e.toString();
    if (text.contains('passkey_disabled')) {
      return 'Passkeys are not enabled for Weekend yet. '
          'Please use email and password to sign in.';
    }
    if (text.contains('webauthn_challenge_expired') ||
        text.contains('webauthn_challenge_not_found')) {
      return 'That passkey request timed out. Please try again.';
    }
    if (text.contains('webauthn_credential_not_found')) {
      return 'That passkey is not registered to this account.';
    }
    if (text.contains('webauthn_credential_exists')) {
      return 'This device already has a passkey for Weekend.';
    }
    if (text.contains('webauthn_verification_failed')) {
      return 'The passkey could not be verified. Please try again.';
    }
    if (text.contains('email_not_confirmed')) {
      return 'Confirm your email address before using a passkey.';
    }
    if (text.contains('user_banned')) {
      return 'This account is not available.';
    }
    if (text.contains('insufficient_aal') || text.contains('aal')) {
      return 'Two-factor verification is required before managing passkeys.';
    }
    return 'Something went wrong with the passkey. Please try again.';
  }
  /// Diagnostic snapshot for Settings -> Security. Contains no secrets and no
  /// key material; safe to log or display.
  static Map<String, String> passkeyDiagnostics() {
    return {
      'platform_supported': PasskeyService.isSupportedPlatform.toString(),
      'credential_manager_initialised':
          PasskeyService.instance.isInitialized.toString(),
      'supabase_configured': SupabaseConfig.isConfigured.toString(),
      'expected_rp_id': PasskeyService.expectedRpId,
    };
  }
}

/// Result of a passkey operation (register / sign in / delete).
class PasskeyOperationResult {
  final bool success;
  final String? error;
  final String message;
  final String? passkeyId;

  /// Present only after a successful sign-in or another server-issued session.
  /// Its presence - not `success` alone - is what proves the account was
  /// authenticated.
  final Session? session;

  const PasskeyOperationResult({
    required this.success,
    this.error,
    this.message = '',
    this.passkeyId,
    this.session,
  });

  const PasskeyOperationResult.success({
    required this.message,
    this.passkeyId,
    this.session,
  }) : success = true,
       error = null;

  const PasskeyOperationResult.failure(String this.error)
    : success = false,
      message = '',
      passkeyId = null,
      session = null;
}

/// Custom exception for passkey operations.
class PasskeyException implements Exception {
  final String message;
  const PasskeyException(this.message);

  @override
  String toString() => message;
}

/// Enrolled MFA factors for the current user.
class MFAFactors {
  final List<Factor> all;
  final List<Factor> verifiedTotp;
  const MFAFactors({required this.all, required this.verifiedTotp});
  static const empty = MFAFactors(all: [], verifiedTotp: []);
}

/// One-time TOTP enrollment payload (shown once, never persisted).
class MfaEnrollment {
  final String factorId;
  final String totpUri;
  final String secret;
  final String qrCode;
  const MfaEnrollment({
    required this.factorId,
    required this.totpUri,
    required this.secret,
    required this.qrCode,
  });
}

/// Assurance levels for the active session.
class MfaAssurance {
  final String? current;
  final String? next;
  const MfaAssurance({this.current, this.next});

  /// True when step-up (2FA challenge) is still required.
  bool get needsStepUp => current == 'aal1' && next == 'aal2';

  /// True when the session already satisfies the second factor.
  bool get isAal2 => current == 'aal2';
}

/// One recovery code, shown exactly once at generation time.
class MfaRecoveryCode {
  final String code;
  final String label;
  const MfaRecoveryCode({required this.code, required this.label});

  Map<String, dynamic> toJson() => {'code': code, 'label': label};
}
