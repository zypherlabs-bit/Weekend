import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';

/// Data source for authentication, sessions and Supabase MFA (TOTP 2FA).
///
/// 2FA uses Supabase Auth's native MFA implementation:
/// enroll → challenge → verify. No secret ever leaves Supabase except the
/// single enrollment payload shown once to the enrolling user; the client
/// never persists raw TOTP secrets.
class AuthRepository {
  SupabaseClient? get _client => SupabaseConfig.client;
  Future<void> signUpWithEmail(
    String email,
    String password,
    String fullName,
  ) async {
    final client = _client;
    if (client == null) return;
    await client.auth.signUp(
      email: email,
      password: password,
      data: {'full_name': fullName},
    );
  }

  Future<void> signInWithEmail(String email, String password) async {
    final client = _client;
    if (client == null) return;
    await client.auth.signInWithPassword(email: email, password: password);
  }

  Future<void> signInAnonymously() async {
    final client = _client;
    if (client == null) return;
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

