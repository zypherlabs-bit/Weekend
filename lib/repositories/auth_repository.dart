import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';

class AuthRepository {
  Future<void> signUpWithEmail(String email, String password, String fullName) async {
    await Supabase.instance.client.auth.signUp(
      email: email,
      password: password,
      data: {'full_name': fullName},
    );
  }

  Future<void> signInWithEmail(String email, String password) async {
    await Supabase.instance.client.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  Future<void> signInAnonymously() async {
    await Supabase.instance.client.auth.signInAnonymously();
  }

  Future<void> signOut() async {
    await Supabase.instance.client.auth.signOut();
  }

  Future<void> resetPassword(String email) async {
    await Supabase.instance.client.auth.resetPasswordForEmail(email);
  }
}
