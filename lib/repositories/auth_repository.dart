import 'dart:convert';
import 'dart:developer';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:credential_manager/credential_manager.dart';
import '../config/supabase_config.dart';

/// Data source for authentication, sessions and Supabase MFA (TOTP 2FA).
///
/// 2FA uses Supabase Auth's native MFA implementation:
/// enroll → challenge → verify. No secret ever leaves Supabase except the
/// single enrollment payload shown once to the enrolling user; the client
/// never persists raw TOTP secrets.
class AuthRepository {
  SupabaseClient? get _client => SupabaseConfig.client;

  /// The relying party ID for WebAuthn (matches the app's domain).
  static const String _rpName = 'Weekend';

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

  /// Challenge + verify during login when AAL1 → AAL2 is required.
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

  // ----------------------------------------------------------- PASSKEYS (WebAuthn via Credential Manager)

  /// Register a new passkey for sign-up.
  /// Returns the authenticated session on success.
  Future<PasskeyRegistrationResult> signUpWithPasskey({
    required String email,
    required String fullName,
  }) async {
    final client = _client;
    if (client == null) {
      return PasskeyRegistrationResult(
        success: false,
        error: 'Weekend is not connected to a backend.',
      );
    }

    try {
      // Step 1: Get registration options from Supabase
      final registrationOptions = await _getPasskeyRegistrationOptions(email, fullName);
      if (registrationOptions == null) {
        return PasskeyRegistrationResult(
          success: false,
          error: 'Failed to get registration options from server.',
        );
      }

      // Step 2: Create passkey using platform authenticator (Android Credential Manager)
      final credential = await _createPasskeyCredential(registrationOptions);
      if (credential == null) {
        return PasskeyRegistrationResult(
          success: false,
          error: 'Passkey creation was cancelled or failed.',
        );
      }

      // Step 3: Verify registration with Supabase
      final session = await _verifyPasskeyRegistration(
        email: email,
        fullName: fullName,
        credential: credential,
      );

      return PasskeyRegistrationResult(
        success: true,
        session: session,
      );
    } on CredentialException catch (e) {
      if (e.code == 601) {
        return PasskeyRegistrationResult(success: false, error: 'User cancelled passkey creation');
      }
      return PasskeyRegistrationResult(success: false, error: 'Passkey creation failed: ${e.message}');
    } catch (e) {
      return PasskeyRegistrationResult(
        success: false,
        error: 'Passkey registration failed: ${e.toString()}',
      );
    }
  }

  /// Sign in with an existing passkey.
  /// Returns the authenticated session on success.
  Future<PasskeyAuthenticationResult> signInWithPasskey() async {
    final client = _client;
    if (client == null) {
      return PasskeyAuthenticationResult(
        success: false,
        error: 'Weekend is not connected to a backend.',
      );
    }

    try {
      // Step 1: Get authentication options from Supabase
      final authenticationOptions = await _getPasskeyAuthenticationOptions();
      if (authenticationOptions == null) {
        return PasskeyAuthenticationResult(
          success: false,
          error: 'No passkey found. Please sign up first.',
        );
      }

      // Step 2: Get passkey assertion using platform authenticator
      final credential = await _getPasskeyAssertion(authenticationOptions);
      if (credential == null) {
        return PasskeyAuthenticationResult(
          success: false,
          error: 'Passkey authentication was cancelled or failed.',
        );
      }

      // Step 3: Verify assertion with Supabase
      final session = await _verifyPasskeyAuthentication(credential);

      return PasskeyAuthenticationResult(
        success: true,
        session: session,
      );
    } on CredentialException catch (e) {
      if (e.code == 201 || e.code == 601) {
        return PasskeyAuthenticationResult(success: false, error: 'User cancelled passkey authentication');
      }
      return PasskeyAuthenticationResult(success: false, error: 'Passkey authentication failed: ${e.message}');
    } catch (e) {
      return PasskeyAuthenticationResult(
        success: false,
        error: 'Passkey sign-in failed: ${e.toString()}',
      );
    }
  }

  /// Get passkey registration options from Supabase Auth.
  Future<CredentialCreationOptions?> _getPasskeyRegistrationOptions(
    String email,
    String fullName,
  ) async {
    final client = _client;
    if (client == null) return null;

    try {
      final response = await client.auth.mfa.enroll(
        factorType: FactorType.webauthn,
        issuer: _rpName,
        friendlyName: email,
      );

      // The Supabase MFA enroll response for WebAuthn contains the credential creation options
      // We need to extract them from the response
      final webAuthnData = _extractWebAuthnData(response);
      if (webAuthnData == null) {
        log('WebAuthn data not found in MFA enroll response');
        return null;
      }

      return CredentialCreationOptions.fromJson(webAuthnData);
    } catch (e) {
      log('Failed to get passkey registration options: $e');
      return null;
    }
  }

  /// Get passkey authentication options from Supabase Auth.
  Future<CredentialLoginOptions?> _getPasskeyAuthenticationOptions() async {
    final client = _client;
    if (client == null) return null;

    try {
      // For sign-in, we need to list factors and challenge the webauthn factor
      final factors = await client.auth.mfa.listFactors();
      
      // Check if webauthn factors exist (they might be in a different field)
      final webauthnFactors = _getWebAuthnFactors(factors);
      
      if (webauthnFactors.isEmpty) {
        // No registered passkey - this is expected for new users
        return null;
      }

      // Challenge the first verified webauthn factor
      final factor = webauthnFactors.first;
      final challenge = await client.auth.mfa.challenge(factorId: factor.id);

      // Extract credential request options from challenge response
      final requestOptions = _extractCredentialRequestOptions(challenge);
      if (requestOptions == null) {
        log('Credential request options not found in MFA challenge response');
        return null;
      }

      return CredentialLoginOptions.fromJson(requestOptions);
    } catch (e) {
      log('Failed to get passkey authentication options: $e');
      return null;
    }
  }

  /// Extract WebAuthn data from MFA enroll response.
  Map<String, dynamic>? _extractWebAuthnData(dynamic response) {
    try {
      // The response structure varies by Supabase client version
      // Try to find the webauthn credential creation options
      if (response is Map) {
        // Check for webAuthn field
        if (response.containsKey('webAuthn')) {
          final webauthn = response['webAuthn'];
          if (webauthn is Map && webauthn.containsKey('credentialCreationOptions')) {
            final options = webauthn['credentialCreationOptions'];
            if (options is String) {
              return jsonDecode(options) as Map<String, dynamic>;
            } else if (options is Map<String, dynamic>) {
              return options;
            }
          }
        }
        // Check for credentialCreationOptions directly
        if (response.containsKey('credentialCreationOptions')) {
          final options = response['credentialCreationOptions'];
          if (options is String) {
            return jsonDecode(options) as Map<String, dynamic>;
          } else if (options is Map<String, dynamic>) {
            return options;
          }
        }
      }
      
      // Try to access via reflection/dynamic
      final webauthn = response.webAuthn;
      if (webauthn != null) {
        final options = webauthn.credentialCreationOptions;
        if (options is String) {
          return jsonDecode(options) as Map<String, dynamic>;
        } else if (options is Map<String, dynamic>) {
          return options;
        }
      }
    } catch (e) {
      log('Error extracting WebAuthn data: $e');
    }
    return null;
  }

  /// Extract WebAuthn factors from MFA list factors response.
  List<dynamic> _getWebAuthnFactors(dynamic factors) {
    try {
      // Try to access webAuthn field
      final webauthn = factors.webAuthn;
      if (webauthn is List) {
        return webauthn.where((f) => f.status == FactorStatus.verified).toList();
      }
      
      // Check if it's a Map with webAuthn key
      if (factors is Map && factors.containsKey('webAuthn')) {
        final list = factors['webAuthn'];
        if (list is List) {
          return list.where((f) => f['status'] == 'verified' || f.status == FactorStatus.verified).toList();
        }
      }
    } catch (e) {
      log('Error extracting WebAuthn factors: $e');
    }
    return [];
  }

  /// Extract credential request options from MFA challenge response.
  Map<String, dynamic>? _extractCredentialRequestOptions(dynamic challenge) {
    try {
      // Check for credentialRequestOptions field
      if (challenge is Map && challenge.containsKey('credentialRequestOptions')) {
        final options = challenge['credentialRequestOptions'];
        if (options is String) {
          return jsonDecode(options) as Map<String, dynamic>;
        } else if (options is Map<String, dynamic>) {
          return options;
        }
      }
      
      // Try dynamic access
      final options = challenge.credentialRequestOptions;
      if (options is String) {
        return jsonDecode(options) as Map<String, dynamic>;
      } else if (options is Map<String, dynamic>) {
        return options;
      }
    } catch (e) {
      log('Error extracting credential request options: $e');
    }
    return null;
  }

  /// Create a passkey credential using Android Credential Manager.
  Future<PublicKeyCredential?> _createPasskeyCredential(
    CredentialCreationOptions options,
  ) async {
    try {
      final credentialManager = CredentialManagerPlatform.instance;
      final credential = await credentialManager.savePasskeyCredentials(request: options);
      return credential;
    } on CredentialException catch (e) {
      if (e.code == 601) {
        throw PasskeyException('User cancelled passkey creation');
      }
      throw PasskeyException('Failed to create passkey: ${e.message}');
    } catch (e) {
      throw PasskeyException('Passkey creation error: $e');
    }
  }

  /// Get a passkey assertion using Android Credential Manager.
  Future<PublicKeyCredential?> _getPasskeyAssertion(
    CredentialLoginOptions options,
  ) async {
    try {
      final credentialManager = CredentialManagerPlatform.instance;
      final credentials = await credentialManager.getCredentials(passKeyOption: options);
      return credentials.publicKeyCredential;
    } on CredentialException catch (e) {
      if (e.code == 201 || e.code == 601) {
        throw PasskeyException('User cancelled passkey authentication');
      }
      throw PasskeyException('Failed to get passkey assertion: ${e.message}');
    } catch (e) {
      throw PasskeyException('Passkey authentication error: $e');
    }
  }

  /// Verify passkey registration with Supabase.
  Future<Session?> _verifyPasskeyRegistration({
    required String email,
    required String fullName,
    required PublicKeyCredential credential,
  }) async {
    final client = _client;
    if (client == null) return null;

    try {
      final response = credential.response;
      if (response == null) {
        throw PasskeyException('Invalid credential response: missing response');
      }

      final attestationObject = response.attestationObject;
      final clientDataJSON = response.clientDataJSON;
      
      if (attestationObject == null || clientDataJSON == null) {
        throw PasskeyException('Invalid credential response: missing attestation or clientDataJSON');
      }

      final body = {
        'factor_type': 'webauthn',
        'attestation': attestationObject,
        'client_data_json': clientDataJSON,
        'email': email,
        'data': {'full_name': fullName},
      };

      final session = await _completePasskeyRegistrationViaRest(body);
      return session;
    } catch (e) {
      log('Passkey registration verification failed: $e');
      rethrow;
    }
  }

  /// Verify passkey authentication with Supabase.
  Future<Session?> _verifyPasskeyAuthentication(
    PublicKeyCredential credential,
  ) async {
    final client = _client;
    if (client == null) return null;

    try {
      final response = credential.response;
      if (response == null) {
        throw PasskeyException('Invalid credential response: missing response');
      }

      final authenticatorData = response.authenticatorData;
      final clientDataJSON = response.clientDataJSON;
      final signature = response.signature;
      final credentialId = credential.id;

      if (authenticatorData == null || clientDataJSON == null || signature == null || credentialId == null) {
        throw PasskeyException('Invalid credential response: missing required fields');
      }

      final body = {
        'factor_type': 'webauthn',
        'authenticator_data': authenticatorData,
        'client_data_json': clientDataJSON,
        'signature': signature,
        'credential_id': credentialId,
      };

      final session = await _completePasskeyAuthenticationViaRest(body);
      return session;
    } catch (e) {
      log('Passkey authentication verification failed: $e');
      rethrow;
    }
  }

  /// Complete passkey registration via Supabase REST API.
  Future<Session?> _completePasskeyRegistrationViaRest(
    Map<String, dynamic> body,
  ) async {
    final client = _client;
    if (client == null) return null;

    final response = await client.functions.invoke(
      'passkey-register',
      body: body,
    );

    if (response.data is Map<String, dynamic>) {
      final data = response.data as Map<String, dynamic>;
      if (data['access_token'] != null && data['refresh_token'] != null) {
        await client.auth.setSession(
          data['refresh_token'],
          accessToken: data['access_token'],
        );
        return client.auth.currentSession;
      }
    }
    return null;
  }

  /// Complete passkey authentication via Supabase REST API.
  Future<Session?> _completePasskeyAuthenticationViaRest(
    Map<String, dynamic> body,
  ) async {
    final client = _client;
    if (client == null) return null;

    final response = await client.functions.invoke(
      'passkey-authenticate',
      body: body,
    );

    if (response.data is Map<String, dynamic>) {
      final data = response.data as Map<String, dynamic>;
      if (data['access_token'] != null && data['refresh_token'] != null) {
        await client.auth.setSession(
          data['refresh_token'],
          accessToken: data['access_token'],
        );
        return client.auth.currentSession;
      }
    }
    return null;
  }
}

/// Result of passkey registration.
class PasskeyRegistrationResult {
  final bool success;
  final String? error;
  final Session? session;

  const PasskeyRegistrationResult({
    required this.success,
    this.error,
    this.session,
  });
}

/// Result of passkey authentication.
class PasskeyAuthenticationResult {
  final bool success;
  final String? error;
  final Session? session;

  const PasskeyAuthenticationResult({
    required this.success,
    this.error,
    this.session,
  });
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