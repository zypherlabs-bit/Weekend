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
    _checkSession();
  }

  SupabaseClient? get _client => SupabaseConfig.client;

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
        // Offline demo mode: no persisted session, so the user starts
        // unauthenticated and proceeds through onboarding → auth.
        state = const WeekendAuthState(isLoading: false, isAuthenticated: false);
        return;
      }
      final session = client.auth.currentSession;

      final user = client.auth.currentUser;

      if (user != null && session != null) {
        state = WeekendAuthState(
          isAuthenticated: true,
          isLoading: false,

          user: _profileFromAuth(user, 'User'),
          session: session.accessToken,
          emailVerified: user.emailConfirmedAt != null,
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
    String fullName,
  ) async {
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
      final response = await client.auth.signUp(
        email: email,
        password: password,
        data: {'full_name': fullName},
      );

      if (response.user != null) {
        final emailVerified = response.user!.emailConfirmedAt != null;

        state = state.copyWith(
          isLoading: false,

          isAuthenticated: emailVerified,

          emailVerified: emailVerified,
          user: _profileFromAuth(response.user!, fullName),
        );

        if (!emailVerified) {
          state = state.copyWith(
            error:
                'Please check your email to confirm your account before continuing.',
          );
        }
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
    // Start clean: no stale MFA gate from a previous attempt.
    state = state.copyWith(
      isLoading: true,
      error: null,
      needsMfaChallenge: false,
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
        );

        await _refreshMfaFlag();
        await _loadLocationPreferences(response.user!.id);
      } else {
        state = state.copyWith(isLoading: false, isAuthenticated: false);
      }
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        isAuthenticated: false,
        needsMfaChallenge: false,
        error: e.toString(),
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
        state = state.copyWith(
          isLoading: false,
          isAuthenticated: true,

          user: _profileFromAuth(response.user!, 'User'),
          session: response.session?.accessToken,
          emailVerified: true,
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
      // Demo mode: no backend to contact.
      return;
    }
    try {
      await client.auth.resetPasswordForEmail(email);
    } catch (e) {
      state = state.copyWith(error: e.toString());
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
}
