import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:credential_manager/credential_manager.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import '../config/supabase_config.dart';

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
  /// Returns `true` when the backend confirms deletion. Throws on failure so
  /// the UI can surface the real backend error instead of a fake success.
  Future<bool> deleteAccount({String reason = 'user_request'}) async {
    final client = _client;
    if (client == null) return false;
    final session = client.auth.currentSession;
    final userId = client.auth.currentUser?.id;
    if (session == null || userId == null) return false;
    final response = await client.functions.invoke(
      'account-deletion',
      body: {'userId': userId, 'reason': reason},
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
  Future<void> unenrollFactor(String factorId) async {
    final client = _client;
    if (client == null) return;
    await client.auth.mfa.unenroll(factorId);
  }

  // ----------------------------------------------------------- PASSKEYS (WebAuthn via Android Credential Manager)
  //
  // These use Supabase Auth's NATIVE passkey API (`client.auth.passkey.*`),
  // the standards-based WebAuthn flow:
  //
  //   1. startRegistration / startAuthentication   -> server issues a challenge
  //   2. Android Credential Manager ceremony      -> the device signs it
  //   3. verifyRegistration / verifyAuthentication -> server validates and
  //                                                    returns a real session
  //
  // The previous implementation in this file was NOT a passkey flow and could
  // never have worked. It drove the WebAuthn *MFA factor* API
  // (`mfa.enroll(factorType: webauthn)` / `mfa.listFactors()`), both of which
  // require an already-authenticated session - impossible during sign-up, and
  // impossible during sign-in because there is no session to list factors with.
  // It then posted the ceremony result to `passkey-register` /
  // `passkey-authenticate` Edge Functions that do not exist in this repository
  // (supabase/functions/ contains no such function), so the round trip could
  // only ever fail.
  //
  // Passkeys also require the project setting
  // Authentication -> Passkeys -> "Enable Passkey authentication" plus a
  // WebAuthn relying-party ID. Until that is configured the server answers
  // `passkey_disabled` and the user gets a clear message pointing at email
  // sign-in - never a fake success.

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
      final credential = await _runRegistrationCeremony(start.options);

      // Step 3 - server validates the attestation and stores the credential.
      final passkey = await client.auth.passkey.verifyRegistration(
        challengeId: start.challengeId,
        credential: credential,
      );
      return PasskeyOperationResult.success(
        message: 'Passkey added',
        passkeyId: passkey.id,
      );
    } on CredentialException catch (e) {
      return PasskeyOperationResult.failure(_credentialErrorMessage(e));
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
      final credential = await _runAuthenticationCeremony(start.options);

      // Step 3 - server validates the assertion and issues a real session,
      // which the SDK persists and broadcasts on the auth stream.
      final response = await client.auth.passkey.verifyAuthentication(
        challengeId: start.challengeId,
        credential: credential,
      );
      final session = response.session;
      if (session == null) {
        return const PasskeyOperationResult.failure(
          'Sign-in did not return a session. Please try again.',
        );
      }
      return PasskeyOperationResult.success(
        message: 'Signed in',
        session: session,
      );
    } on CredentialException catch (e) {
      return PasskeyOperationResult.failure(_credentialErrorMessage(e));
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

  /// True when this build can attempt a passkey ceremony at all.
  ///
  /// Credential Manager has no capability probe of its own, so this reports
  /// what is actually knowable client-side: that the platform plugin
  /// initialised and the Supabase client is configured. It is NOT a claim that
  /// a passkey is enrolled, nor that the project has passkeys enabled.
  static Future<bool> isPasskeySupported() async {
    if (!SupabaseConfig.isConfigured) return false;
    if (SupabaseConfig.client == null) return false;
    return defaultTargetPlatform == TargetPlatform.android;
  }

  // ---------------------------------------------------------------------
  // WebAuthn ceremonies
  // ---------------------------------------------------------------------

  /// `navigator.credentials.create()` equivalent on Android.
  ///
  /// Supabase returns W3C `PublicKeyCredentialCreationOptionsJSON` with
  /// base64url binary fields, which is the shape Android Credential Manager
  /// expects, so the options are handed over almost unchanged. The one
  /// adjustment is `userVerification`, forced to `required` so a passkey can
  /// never be created without a biometric / device-PIN check.
  Future<Map<String, dynamic>> _runRegistrationCeremony(
    Map<String, dynamic> options,
  ) async {
    final prepared = Map<String, dynamic>.from(options);
    final selection = Map<String, dynamic>.from(
      (options['authenticatorSelection'] as Map?) ?? const {},
    );
    selection['userVerification'] = 'required';
    prepared['authenticatorSelection'] = selection;

    final request = CredentialCreationOptions.fromJson(prepared);
    final credential = await CredentialManagerPlatform.instance
        .savePasskeyCredentials(request: request);
    return _credentialToJson(credential);
  }

  /// `navigator.credentials.get()` equivalent on Android.
  Future<Map<String, dynamic>> _runAuthenticationCeremony(
    Map<String, dynamic> options,
  ) async {
    final request = CredentialLoginOptions.fromJson(
      Map<String, dynamic>.from(options),
    );
    final result = await CredentialManagerPlatform.instance
        .getCredentials(passKeyOption: request);

    final credential = result.publicKeyCredential;
    if (credential == null) {
      throw PasskeyException('Passkey sign-in returned no credential.');
    }
    return _credentialToJson(credential);
  }

  /// Convert the plugin's credential into the W3C JSON shape GoTrue verifies.
  ///
  /// The plugin already returns camelCase field names matching
  /// `PublicKeyCredential.toJSON()`, so this is a straight serialisation.
  /// `authenticatorAttachment` is included because GoTrue's WebAuthn verifier
  /// reads it for the Android platform authenticator.
  Map<String, dynamic> _credentialToJson(PublicKeyCredential credential) {
    final response = credential.response;
    if (response == null) {
      throw PasskeyException('Malformed passkey response from the device.');
    }
    return <String, dynamic>{
      'id': credential.id,
      'rawId': credential.rawId ?? credential.id,
      'type': credential.type ?? 'public-key',
      'authenticatorAttachment':
          credential.authenticatorAttachment ?? 'platform',
      'response': <String, dynamic>{
        'clientDataJSON': response.clientDataJSON,
        'attestationObject': response.attestationObject,
        'authenticatorData': response.authenticatorData,
        'signature': response.signature,
        'userHandle': response.userHandle,
      },
      'clientExtensionResults':
          credential.clientExtensionResults?.toJson(),
    };
  }

  // ---------------------------------------------------------------------
  // Error mapping - never surface a raw SDK string to the user
  // ---------------------------------------------------------------------

  String _credentialErrorMessage(CredentialException e) {
    switch (e.code) {
      case 201: // no credential available
      case 601: // cancelled by the user
        return 'Passkey prompt cancelled.';
      case 602:
        return 'No passkey is set up on this device yet.';
      default:
        return 'Passkey could not be completed. Please try again.';
    }
  }

  /// Translate Supabase/GoTrue errors into wording that is safe to show and
  /// tells the user what to do next.
  String _mapPasskeyError(Object e) {
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
    if (text.contains('email_not_confirmed')) {
      return 'Confirm your email address before using a passkey.';
    }
    if (text.contains('user_banned')) {
      return 'This account is not available.';
    }
    // Deliberately generic: raw driver/SDK text can leak implementation detail.
    return 'Something went wrong with the passkey. Please try again.';
  }
}

/// Result of a passkey operation (register / sign in / delete).
class PasskeyOperationResult {
  final bool success;
  final String? error;
  final String message;
  final String? passkeyId;

  /// Present only after a successful sign-in or another server-issued session.
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
}
