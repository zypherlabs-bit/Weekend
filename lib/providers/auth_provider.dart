import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';

final supabaseProvider = Provider<Supabase>((ref) {
  return Supabase.instance;
});

final authStateProvider = StateNotifierProvider<AuthNotifier, WeekendAuthState>((ref) {
  return AuthNotifier();
});

class AuthNotifier extends StateNotifier<WeekendAuthState> {
  AuthNotifier() : super(const WeekendAuthState(isLoading: true)) {
    _checkSession();
  }

  Future<void> _checkSession() async {
    try {
      final session = Supabase.instance.client.auth.currentSession;
      final user = Supabase.instance.client.auth.currentUser;
      
      if (user != null && session != null) {
        state = WeekendAuthState(
          isAuthenticated: true,
          isLoading: false,
          user: UserProfile(
            id: user.id,
            name: user.userMetadata?['full_name'] ?? 'User',
            age: 18,
            gender: 'Prefer not to say',
            photos: const [],
            city: '',
          ),
          session: session.accessToken,
          emailVerified: user.emailConfirmedAt != null,
        );
      } else {
        state = const WeekendAuthState(isLoading: false, isAuthenticated: false);
      }
    } catch (e) {
      state = WeekendAuthState(
        isLoading: false,
        isAuthenticated: false,
        error: 'Could not restore session. Please sign in again.',
      );
    }
  }

  Future<void> signUpWithEmail(String email, String password, String fullName) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final response = await Supabase.instance.client.auth.signUp(
        email: email,
        password: password,
        data: {'full_name': fullName},
      );
      
      if (response.user != null) {
        state = state.copyWith(
          isLoading: false,
          isAuthenticated: response.user!.emailConfirmedAt != null,
          user: UserProfile(
            id: response.user!.id,
            name: fullName,
            age: 18,
            gender: 'Prefer not to say',
            photos: const [],
            city: '',
          ),
          emailVerified: response.user!.emailConfirmedAt != null,
        );
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
    state = state.copyWith(isLoading: true, error: null);
    try {
      final response = await Supabase.instance.client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      
      if (response.user != null) {
        state = state.copyWith(
          isLoading: false,
          isAuthenticated: true,
          user: UserProfile(
            id: response.user!.id,
            name: response.user!.userMetadata?['full_name'] ?? 'User',
            age: 18,
            gender: 'Prefer not to say',
            photos: const [],
            city: '',
          ),
          session: response.session?.accessToken,
          emailVerified: response.user!.emailConfirmedAt != null,
        );
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
    state = state.copyWith(isLoading: true, error: null);
    try {
      final response = await Supabase.instance.client.auth.signInAnonymously();
      
      if (response.user != null) {
        state = state.copyWith(
          isLoading: false,
          isAuthenticated: true,
          user: UserProfile(
            id: response.user!.id,
            name: 'User',
            age: 18,
            gender: 'Prefer not to say',
            photos: const [],
            city: '',
          ),
          session: response.session?.accessToken,
          emailVerified: true,
        );
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
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (e) {
      // ignore
    }
    state = const WeekendAuthState(isAuthenticated: false, isLoading: false);
  }

  Future<void> resetPassword(String email) async {
    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(email);
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }
}
