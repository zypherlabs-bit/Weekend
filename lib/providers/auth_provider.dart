import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';

import '../models/models.dart';

final supabaseProvider = Provider<SupabaseClient?>((ref) {
  return SupabaseConfig.client;
});

final authStateProvider = StateNotifierProvider<AuthNotifier, WeekendAuthState>(
  (ref) {
    return AuthNotifier();
  },
);

class AuthNotifier extends StateNotifier<WeekendAuthState> {
  AuthNotifier() : super(const WeekendAuthState(isLoading: true)) {
    _checkSession();
  }

  SupabaseClient? get _client => SupabaseConfig.client;

  bool get _isDemo => !SupabaseConfig.isConfigured;

  static UserProfile _demoUser(String name) => UserProfile(
    id: 'demo-user',
    name: name,
    age: 26,
    gender: 'Man',
    photos: const [
      'https://images.unsplash.com/photo-1539571696357-5a69c17a67c6?auto=format&fit=crop&w=800&q=80',
    ],
    city: 'Pune',
    relationshipIntent: 'Dating & Weekend Plans',
    interests: const ['Specialty Coffee', 'Hiking', 'Indie Music', 'Cycling'],
  );

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

  Future<void> signUpWithEmail(
    String email,
    String password,
    String fullName,
  ) async {
    if (_isDemo) {
      state = WeekendAuthState(
        isLoading: false,
        isAuthenticated: true,
        emailVerified: true,
        user: _demoUser(fullName.isEmpty ? 'Max' : fullName),
      );
      return;
    }
    state = state.copyWith(isLoading: true, error: null);

    try {
      final response = await _client!.auth.signUp(
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
    if (_isDemo) {
      state = WeekendAuthState(
        isLoading: false,
        isAuthenticated: true,
        emailVerified: true,
        user: _demoUser('Max'),
      );
      return;
    }
    state = state.copyWith(isLoading: true, error: null);

    try {
      final response = await _client!.auth.signInWithPassword(
        email: email,
        password: password,
      );

      if (response.user != null) {
        state = state.copyWith(
          isLoading: false,
          isAuthenticated: true,

          user: _profileFromAuth(response.user!, 'User'),
          session: response.session?.accessToken,
          emailVerified: response.user!.emailConfirmedAt != null,
        );

        await _loadLocationPreferences(response.user!.id);
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

  Future<void> signInAnonymously() async {
    if (_isDemo) {
      state = WeekendAuthState(
        isLoading: false,
        isAuthenticated: true,
        emailVerified: true,
        user: _demoUser('Max'),
      );
      return;
    }
    state = state.copyWith(isLoading: true, error: null);

    try {
      final response = await _client!.auth.signInAnonymously();

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
