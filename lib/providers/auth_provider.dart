import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';

import '../models/models.dart';
import '../repositories/auth_repository.dart';

final supabaseProvider = Provider<SupabaseClient?>((ref) {
  return SupabaseConfig.client;
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository();
});

/// Short-lived in-memory rate limiter for MFA verification attempts.
/// 5 attempts per factor per 5 minutes, then the UI must cool down.
class MfaAttemptLimiter {
  static const int maxAttempts = 5;
  static const Duration window = Duration(minutes: 5);
  static const Duration lockout = Duration(minutes: 5);
  final Map<String, List<DateTime>> _attempts = {};
  final Map<String, DateTime> _lockedUntil = {};

  bool isLockedOut(String factorId) {
    final until = _lockedUntil[factorId];
    if (until == null) return false;
    if (DateTime.now().isAfter(until)) {
      _lockedUntil.remove(factorId);
      return false;
    }
    return true;
  }

  DateTime? lockedUntil(String factorId) => _lockedUntil[factorId];

  bool registerAttempt(String factorId) {
    final now = DateTime.now();
    final list = _attempts.putIfAbsent(factorId, () => []);
    list.removeWhere((t) => now.difference(t) > window);
    list.add(now);
    if (list.length >= maxAttempts) {
      _lockedUntil[factorId] = now.add(lockout);
      list.clear();
      return false;
    }
    return true;
  }

  int remainingAttempts(String factorId) {
    final list = _attempts[factorId] ?? [];
    list.removeWhere((t) => DateTime.now().difference(t) > window);
    return (maxAttempts - list.length).clamp(0, maxAttempts);
  }

  void reset(String factorId) {
    _attempts.remove(factorId);
    _lockedUntil.remove(factorId);
  }
}

final authStateProvider = StateNotifierProvider<AuthNotifier, WeekendAuthState>(
  (ref) {
    return AuthNotifier(ref.watch(authRepositoryProvider));
  },
);

class AuthNotifier extends StateNotifier<WeekendAuthState> {
  final AuthRepository _repo;
  final MfaAttemptLimiter attemptLimiter = MfaAttemptLimiter();

  AuthNotifier(this._repo)
      : super(const WeekendAuthState(isLoading: true)) {
    _listenToAuthChanges();
    _checkSession();
  }

  SupabaseClient? get _client => SupabaseConfig.client;

  StreamSubscription<AuthState>? _authSubscription;

  /// Sign-up wizard answers (birthday / gender / goal) waiting for a session
  /// to write them to `profiles`, plus the account they belong to.
  Map<String, String>? _pendingSignupDetails;
  String? _pendingSignupUserId;

  /// Mirror Supabase's own session stream.
  ///
  /// A session can appear outside this widget tree — the user confirms their
  /// address in a browser and returns to the app, a token is refreshed, or the
  /// account is revoked on another device. Listening to the SDK keeps the app
  /// state in step with the real session instead of guessing.
  void _listenToAuthChanges() {
    final client = _client;
    if (client == null) return;
    _authSubscription = client.auth.onAuthStateChange.listen(
      _handleAuthStateChange,
      onError: (Object _, StackTrace __) {},
    );
  }

  Future<void> _handleAuthStateChange(AuthState data) async {
    // A primary (aal1) session must never satisfy a pending 2FA step-up.
    if (state.needsMfaChallenge) return;

    final session = data.session;
    final user = session?.user;

    if (data.event == AuthChangeEvent.signedOut || user == null) {
      if (state.isAuthenticated || state.awaitingEmailConfirmation) {
        state = const WeekendAuthState(isLoading: false);
      }
      return;
    }

    final confirmed = user.emailConfirmedAt != null;

    // First time this app instance sees the session: adopt it, then let the
    // router decide between Personal Details and home.
    if (!state.isAuthenticated) {
      final needsSetup = await _profileNeedsSetup(user.id);
      state = state.copyWith(
        isAuthenticated: true,
        isLoading: false,
        user: _profileFromAuth(user, 'User'),
        session: session!.accessToken,
        emailVerified: confirmed,
        awaitingEmailConfirmation: false,
        clearPendingEmail: true,
        needsProfileSetup: needsSetup,
        needsMfaChallenge: false,
        clearError: true,
      );
      await _applyPendingSignupDetails(user.id);
      await _refreshMfaFlag();
      await _loadLocationPreferences(user.id);
      return;
    }

    if (confirmed && !state.emailVerified) {
      state = state.copyWith(emailVerified: true);
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _authSubscription = null;
    super.dispose();
  }

  UserProfile _profileFromAuth(User user, String fallbackName) {
    return UserProfile(
      id: user.id,
      name: user.userMetadata?['full_name'] ?? fallbackName,
      age: user.userMetadata?['age'] as int? ?? 18,
      gender: user.userMetadata?['gender'] as String? ?? 'Prefer not to say',
      photos: const [],
      city: '',
    );
  }

  Future<void> _checkSession() async {
    try {
      final client = _client;

      if (client == null) {
        // Unconfigured mode: no persisted session, so the user starts
        // unauthenticated and proceeds through onboarding → auth.
        state = const WeekendAuthState(isLoading: false, isAuthenticated: false);
        return;
      }
      final session = client.auth.currentSession;

      final user = client.auth.currentUser;

      if (user != null && session != null) {
        final needsSetup = await _profileNeedsSetup(user.id);
        state = WeekendAuthState(
          isAuthenticated: true,
          isLoading: false,

          user: _profileFromAuth(user, 'User'),
          session: session.accessToken,
          emailVerified: user.emailConfirmedAt != null,
          needsProfileSetup: needsSetup,
        );
      } else {
        state = const WeekendAuthState(
          isLoading: false,
          isAuthenticated: false,
        );
      }
    } catch (e) {
      state = WeekendAuthState(
        isLoading: false,
        isAuthenticated: false,
        error: 'Could not restore session. Please sign in again.',
      );
    }
  }

  Future<void> _refreshMfaFlag() async {
    try {
      final enabled = await _repo.isMfaEnabled();
      state = state.copyWith(mfaEnabled: enabled);
    } catch (_) {
      // Best effort; MFA flag stays as-is.
    }
  }

  Future<void> signUpWithEmail(
    String email,
    String password,
    String fullName, {
    DateTime? dateOfBirth,
    String? gender,
    String? relationshipIntent,
  }) async {
    // A fresh attempt always owns the wizard-answer stash from here on.
    _pendingSignupDetails = null;
    _pendingSignupUserId = null;
    final client = _client;
    if (client == null) {
      state = state.copyWith(
        isLoading: false,
        error:
            'Weekend is not connected to a backend. '
            'Build with SUPABASE_URL and SUPABASE_ANON_KEY to enable accounts.',
      );
      return;
    }
    state = state.copyWith(
      isLoading: true,
      clearError: true,
      awaitingEmailConfirmation: false,
      clearPendingEmail: true,
    );

    try {
      // Wizard answers ride along in the signup metadata so the
      // handle_new_user trigger (migration 015) persists them even if the app
      // is killed before the confirmation link is opened. The goal is safe to
      // include now too: 015 corrected the relationship-intent CHECK typo
      // that used to abort the trigger's profile insert.
      final metadata = <String, String>{'full_name': fullName};
      if (dateOfBirth != null) {
        metadata['date_of_birth'] = _dateOnly(dateOfBirth);
      }
      if (gender != null) metadata['gender'] = gender;
      if (relationshipIntent != null && relationshipIntent.isNotEmpty) {
        metadata['relationship_intent'] = relationshipIntent;
      }
      final response = await client.auth.signUp(
        email: email,
        password: password,
        data: metadata,
        emailRedirectTo: SupabaseConfig.emailRedirectOrNull,
      );

      if (response.user == null) {
        state = state.copyWith(
          isLoading: false,
          isAuthenticated: false,
          error: 'Signup could not be completed. Please try again.',
        );
        return;
      }

      // The wizard's answers are held until a session exists to write them
      // with (immediately below, or after the confirmation link later).
      final pending = <String, String>{
        if (dateOfBirth != null) 'date_of_birth': _dateOnly(dateOfBirth),
        if (gender != null) 'gender': gender,
        if (relationshipIntent != null)
          'relationship_intent': relationshipIntent,
      };
      _pendingSignupDetails = pending.isEmpty ? null : pending;
      _pendingSignupUserId = pending.isEmpty ? null : response.user!.id;

      // The SDK returns a session only when Supabase actually issued one. With
      // email confirmation enabled (mailer_autoconfirm = false) the account is
      // created but no session exists until the user confirms.
      final session = response.session;
      if (session == null) {
        state = state.copyWith(
          isLoading: false,
          isAuthenticated: false,
          needsProfileSetup: false,
          emailVerified: false,
          awaitingEmailConfirmation: true,
          pendingEmail: email,
          user: _profileFromAuth(response.user!, fullName),
          clearError: true,
        );
        return;
      }

      final needsSetup = await _profileNeedsSetup(response.user!.id);
      state = state.copyWith(
        isLoading: false,
        isAuthenticated: true,
        needsProfileSetup: needsSetup,
        emailVerified: response.user!.emailConfirmedAt != null,
        awaitingEmailConfirmation: false,
        clearPendingEmail: true,
        user: _profileFromAuth(response.user!, fullName),
        session: session.accessToken,
        clearError: true,
      );
      if (response.user != null) {
        await _applyPendingSignupDetails(response.user!.id);
      }
      await _refreshMfaFlag();
      await _loadLocationPreferences(response.user!.id);
    } catch (e) {
      // The account was never created — drop any wizard answers so they can
      // not leak into a later sign-in of a different account.
      _pendingSignupDetails = null;
      _pendingSignupUserId = null;
      state = state.copyWith(
        isLoading: false,
        isAuthenticated: false,
        error: _readableAuthError(e),
      );
    }
  }

  /// Re-send the confirmation mail for the pending signup.
  ///
  /// Supabase's built-in mailer is rate limited, so a successful call is not a
  /// delivery guarantee; the returned string is what the UI should tell the
  /// user.
  Future<String> resendConfirmationEmail() async {
    final client = _client;
    final email = state.pendingEmail;
    if (client == null || email == null || email.isEmpty) {
      return 'No pending signup to resend.';
    }
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _repo.resendSignupConfirmation(
        email,
        emailRedirectTo: SupabaseConfig.emailRedirectOrNull,
      );
      state = state.copyWith(isLoading: false);
      return 'Confirmation email requested for $email.';
    } catch (e) {
      final message = _readableAuthError(e);
      state = state.copyWith(isLoading: false, error: message);
      return message;
    }
  }

  /// Write wizard answers captured during sign-up to `profiles` once the
  /// user id has a session. Retried on the next session adoption on failure.
  Future<void> _applyPendingSignupDetails(String userId) async {
    final details = _pendingSignupDetails;
    final client = _client;
    if (details == null || details.isEmpty || client == null) return;
    if (_pendingSignupUserId != userId) {
      // The stash belongs to a different account (or a stale attempt): the
      // signup metadata written at signUpWithEmail time is its fallback.
      _pendingSignupDetails = null;
      _pendingSignupUserId = null;
      return;
    }
    try {
      await client.from('profiles').update(details).eq('id', userId);
      _pendingSignupDetails = null;
      _pendingSignupUserId = null;
    } catch (_) {
      // Keep the stash; the next session adoption retries.
    }
  }

  String _dateOnly(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  /// Clear a displayed error (e.g. when the user switches forms).
  void dismissError() {
    if (state.error == null) return;
    state = state.clearError();
  }

  /// Turn SDK errors into user-facing text without leaking credentials.
  String _readableAuthError(Object e) {
    if (e is AuthException) {
      final code = e.code ?? '';
      if (code == 'email_not_confirmed') {
        return 'This email is not confirmed yet. Open the link we emailed you.';
      }
      if (code == 'invalid_credentials') {
        return 'Incorrect email or password.';
      }
      if (code == 'user_already_exists' || code == 'email_exists') {
        return 'An account with this email already exists. Try signing in.';
      }
      if (code == 'over_email_send_rate_limit' ||
          code == 'over_request_rate_limit') {
        return 'Too many emails requested. Please wait a few minutes.';
      }
      if (code == 'email_address_invalid') {
        return 'That email address was rejected. Please use a different one.';
      }
      if (code == 'signup_disabled') {
        return 'New signups are currently disabled.';
      }
      return e.message;
    }
    if (e is AuthRetryableFetchException) {
      return 'Could not reach Weekend. Check your connection and try again.';
    }
    return e.toString().replaceAll('Exception: ', '');
  }

  /// Explains a passkey failure without dumping a raw SDK/Edge Function error
  /// at the user.
  ///
  /// The `passkey-register` / `passkey-authenticate` Edge Functions are not
  /// deployed on the live project, so GoTrue answers 404. That is surfaced as a
  /// clear "unavailable, use your password" message instead of pretending the
  /// passkey flow worked.
  String _readablePasskeyError(Object e, String action) {
    final text = e.toString();
    if (text.contains('404') ||
        text.contains('FunctionsHttpError') ||
        text.contains('not found') ||
        text.contains('not deployed')) {
      return 'Passkey $action is not available right now. '
          'Please sign in with your email and password instead.';
    }
    if (text.contains('401') || text.contains('Unauthorized')) {
      return 'That passkey could not be verified. Please try again.';
    }
    return _readableAuthError(e);
  }

  Future<void> signInWithEmail(String email, String password) async {
    final client = _client;
    if (client == null) {
      state = state.copyWith(
        isLoading: false,
        error:
            'Weekend is not connected to a backend. '
            'Build with SUPABASE_URL and SUPABASE_ANON_KEY to enable accounts.',
      );
      return;
    }
    // Start clean: no stale MFA gate or error from a previous attempt.
    state = state.copyWith(
      isLoading: true,
      clearError: true,
      needsMfaChallenge: false,
      awaitingEmailConfirmation: false,
      clearPendingEmail: true,
    );

    try {
      final response = await client.auth.signInWithPassword(
        email: email,
        password: password,
      );

      if (response.user != null) {
        // Step-up check: AAL1 session with verified factors → 2FA challenge.
        final assurance = _repo.assuranceLevel();
        if (assurance != null && assurance.needsStepUp) {
          state = state.copyWith(
            isLoading: false,
            isAuthenticated: false,
            needsMfaChallenge: true,
            mfaEnabled: true,
            user: _profileFromAuth(response.user!, 'User'),
            session: response.session?.accessToken,
            emailVerified: response.user!.emailConfirmedAt != null,
          );
          return;
        }
        state = state.copyWith(
          isLoading: false,
          isAuthenticated: true,

          user: _profileFromAuth(response.user!, 'User'),
          session: response.session?.accessToken,
          emailVerified: response.user!.emailConfirmedAt != null,
          needsMfaChallenge: false,
          needsProfileSetup: await _profileNeedsSetup(response.user!.id),
          clearError: true,
        );

        await _refreshMfaFlag();
        await _loadLocationPreferences(response.user!.id);
      } else {
        state = state.copyWith(isLoading: false, isAuthenticated: false);
      }
    } catch (e) {
      // An account that exists but was never confirmed is not a credential
      // failure: route the user to the confirmation step instead of showing a
      // dead-end error.
      if (e is AuthException && e.code == 'email_not_confirmed') {
        state = state.copyWith(
          isLoading: false,
          isAuthenticated: false,
          needsMfaChallenge: false,
          awaitingEmailConfirmation: true,
          pendingEmail: email,
          clearError: true,
        );
        return;
      }
      state = state.copyWith(
        isLoading: false,
        isAuthenticated: false,
        needsMfaChallenge: false,
        error: _readableAuthError(e),
      );
    }
  }

  /// Verify the pending MFA challenge after primary sign-in.
  /// Returns true on success (caller navigates to /home).
  Future<bool> verifyMfaChallenge(String code) async {
    final client = _client;
    if (client == null) return false;
    final factors = await _repo.listFactors();
    if (factors.verifiedTotp.isEmpty) {
      state = state.copyWith(error: 'No two-factor method is enrolled.');
      return false;
    }
    final factorId = factors.verifiedTotp.first.id;
    if (attemptLimiter.isLockedOut(factorId)) {
      final until = attemptLimiter.lockedUntil(factorId);
      state = state.copyWith(
        error: 'Too many attempts. Try again after ${until != null ? '${until.difference(DateTime.now()).inMinutes + 1} min' : 'a few minutes'}.',
      );
      return false;
    }
    state = state.copyWith(isLoading: true, error: null);
    try {
      await _repo.verifyLoginCode(factorId: factorId, code: code);
      attemptLimiter.reset(factorId);
      final user = client.auth.currentUser;
      final session = client.auth.currentSession;
      state = state.copyWith(
        isLoading: false,
        isAuthenticated: true,
        needsMfaChallenge: false,
        mfaEnabled: true,
        user: user != null ? _profileFromAuth(user, 'User') : state.user,
        session: session?.accessToken ?? state.session,
        emailVerified: user?.emailConfirmedAt != null || state.emailVerified,
        needsProfileSetup:
            user != null ? await _profileNeedsSetup(user.id) : false,
      );
      if (user != null) await _loadLocationPreferences(user.id);
      return true;
    } catch (e) {
      final allowed = attemptLimiter.registerAttempt(factorId);
      final remaining = attemptLimiter.remainingAttempts(factorId);
      state = state.copyWith(
        isLoading: false,
        error: allowed
            ? 'Incorrect or expired code. $remaining attempt(s) left before a short lockout.'
            : 'Too many incorrect attempts. Two-factor verification is locked for 5 minutes.',
      );
      return false;
    }
  }

  Future<void> signInAnonymously() async {
    final client = _client;
    if (client == null) {
      state = state.copyWith(
        isLoading: false,
        error:
            'Weekend is not connected to a backend. '
            'Build with SUPABASE_URL and SUPABASE_ANON_KEY to enable accounts.',
      );
      return;
    }
    state = state.copyWith(isLoading: true, error: null);

    try {
      final response = await client.auth.signInAnonymously();

      if (response.user != null) {
        final needsSetup = await _profileNeedsSetup(response.user!.id);
        state = state.copyWith(
          isLoading: false,
          isAuthenticated: true,

          user: _profileFromAuth(response.user!, 'User'),
          session: response.session?.accessToken,
          emailVerified: true,
          needsProfileSetup: needsSetup,
        );
      } else {
        state = state.copyWith(isLoading: false, isAuthenticated: false);
      }
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        isAuthenticated: false,
        error: e.toString(),
      );
    }
  }

  /// Sign up with a passkey (WebAuthn).
  Future<void> signUpWithPasskey({
    required String email,
    required String fullName,
  }) async {
    final client = _client;
    if (client == null) {
      state = state.copyWith(
        isLoading: false,
        error:
            'Weekend is not connected to a backend. '
            'Build with SUPABASE_URL and SUPABASE_ANON_KEY to enable accounts.',
      );
      return;
    }
    state = state.copyWith(isLoading: true, error: null);

    try {
      final result = await _repo.signUpWithPasskey(
        email: email,
        fullName: fullName,
      );

      if (result.success && result.session != null) {
        final user = client.auth.currentUser;
        state = state.copyWith(
          isLoading: false,
          isAuthenticated: true,
          user: user != null ? _profileFromAuth(user, fullName) : null,
          session: result.session!.accessToken,
          emailVerified: user?.emailConfirmedAt != null,
          needsProfileSetup: true,
        );
        if (user != null) await _loadLocationPreferences(user.id);
      } else {
        state = state.copyWith(
          isLoading: false,
          isAuthenticated: false,
          needsMfaChallenge: false,
          error: result.error ?? 'Passkey registration failed.',
        );
      }
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        isAuthenticated: false,
        error: _readablePasskeyError(e, 'registration'),
      );
    }
  }

  /// Sign in with a passkey (WebAuthn).
  Future<void> signInWithPasskey() async {
    final client = _client;
    if (client == null) {
      state = state.copyWith(
        isLoading: false,
        error:
            'Weekend is not connected to a backend. '
            'Build with SUPABASE_URL and SUPABASE_ANON_KEY to enable accounts.',
      );
      return;
    }
    state = state.copyWith(isLoading: true, error: null, needsMfaChallenge: false);

    try {
      final result = await _repo.signInWithPasskey();

      if (result.success && result.session != null) {
        final user = client.auth.currentUser;
        state = state.copyWith(
          isLoading: false,
          isAuthenticated: true,
          user: user != null ? _profileFromAuth(user, 'User') : null,
          session: result.session!.accessToken,
          emailVerified: user?.emailConfirmedAt != null,
          needsMfaChallenge: false,
          needsProfileSetup:
              user != null ? await _profileNeedsSetup(user.id) : true,
        );
        if (user != null) await _loadLocationPreferences(user.id);
      } else {
        state = state.copyWith(
          isLoading: false,
          isAuthenticated: false,
          needsMfaChallenge: false,
          error: result.error ?? 'Passkey sign-in failed.',
        );
      }
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        isAuthenticated: false,
        needsMfaChallenge: false,
        error: _readablePasskeyError(e, 'sign-in'),
      );
    }
  }

  Future<void> signOut() async {
    final client = _client;

    if (client != null) {
      try {
        await client.auth.signOut();
      } catch (e) {
        // ignore - best effort
      }
    }
    state = const WeekendAuthState(isAuthenticated: false, isLoading: false);
  }

  /// Sign out on all devices (revoke every session server-side).
  Future<void> signOutAllDevices() async {
    try {
      await _repo.signOutAllDevices();
    } catch (_) {
      // Best effort; still clear local state below.
    }
    state = const WeekendAuthState(isAuthenticated: false, isLoading: false);
  }

  Future<void> resetPassword(String email) async {
    final client = _client;

    if (client == null) {
      // Unconfigured mode: no backend to contact.
      return;
    }
    try {
      await client.auth.resetPasswordForEmail(
        email,
        redirectTo: SupabaseConfig.emailRedirectOrNull,
      );
    } catch (e) {
      state = state.copyWith(error: _readableAuthError(e));
    }
  }

  Future<void> updatePassword(String newPassword) async {
    try {
      await _repo.updatePassword(newPassword);
    } catch (e) {
      state = state.copyWith(error: e.toString());
      rethrow;
    }
  }

  /// Delete the current account via the server-side `account-deletion`
  /// function, then clear local auth state. Returns `true` when deleted.
  Future<bool> deleteAccount({String reason = 'user_request'}) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final deleted = await _repo.deleteAccount(reason: reason);
      if (!deleted) {
        state = state.copyWith(
          isLoading: false,
          error: 'Account deletion is unavailable without a backend connection.',
        );
        return false;
      }
      state = const WeekendAuthState(isAuthenticated: false, isLoading: false);
      return true;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString().replaceAll('Exception: ', ''),
      );
      return false;
    }
  }

  /// Cancel a pending MFA challenge (back to the sign-in screen).
  void cancelMfaChallenge() {
    final client = _client;
    try {
      client?.auth.signOut();
    } catch (_) {}
    state = const WeekendAuthState(isAuthenticated: false, isLoading: false);
  }

  Future<void> _loadLocationPreferences(String userId) async {
    final client = _client;

    if (client == null) return;

    try {
      final data = await client
          .from('user_settings')
          .select('max_distance_km, show_me_in_search')
          .eq('user_id', userId)
          .maybeSingle();

      if (data != null) {
        state = state.copyWith(
          user: state.user!.copyWith(
            distanceKm: data['max_distance_km'] as int? ?? 25,
          ),
        );
      }
    } catch (e) {
      // ignore
    }
  }

  /// True when the authenticated user's profile still needs Personal Details.
  ///
  /// A missing profile row (trigger not yet applied), an empty display name,
  /// or an empty city all count as incomplete. A failed lookup is treated as
  /// incomplete rather than silently letting an un-onboarded user into home.
  /// Anonymous guest sessions skip onboarding entirely.
  Future<bool> _profileNeedsSetup(String userId) async {
    final client = _client;
    if (client == null) return false;
    final user = client.auth.currentUser;
    if (user != null && user.isAnonymous) return false;
    try {
      final row = await client
          .from('profiles')
          .select('id, display_name, city')
          .eq('id', userId)
          .maybeSingle();
      if (row == null) return true;
      final name = (row['display_name'] as String?)?.trim() ?? '';
      final city = (row['city'] as String?)?.trim() ?? '';
      return name.isEmpty || city.isEmpty;
    } catch (_) {
      return true;
    }
  }

  /// Re-check profile completeness (called after Personal Details is saved).
  Future<void> refreshProfileSetup() async {
    final client = _client;
    final userId = client?.auth.currentUser?.id;
    if (userId == null) return;
    final needsSetup = await _profileNeedsSetup(userId);
    state = state.copyWith(needsProfileSetup: needsSetup);
  }
}
