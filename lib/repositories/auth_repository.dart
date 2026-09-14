import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';

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

  Future<void> resetPassword(String email) async {
    final client = _client;
    if (client == null) return;
    await client.auth.resetPasswordForEmail(email);
  }
}
