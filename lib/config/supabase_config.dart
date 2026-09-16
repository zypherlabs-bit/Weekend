import 'package:supabase_flutter/supabase_flutter.dart';

/// Central configuration for the Weekend backend (Supabase).
//
//
// The app supports two run modes:
///   1. **Production mode** — Supabase is configured via compile-time
///      `--dart-define=SUPABASE_URL=...` / `SUPABASE_ANON_KEY=...`. Auth,
///      database, storage and realtime features connect to the live project.
///   2. **Offline demo mode** — no credentials are supplied. The app runs
///      purely on-device with sample data so the entire UI is navigable and
///      demonstrable without a backend. No secret is ever read from an
///      un-trusted source.
class SupabaseConfig {
  static const String url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: '',
  );
  static const String anonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: '',
  );
  static const String storageBucket = 'profile-photos';

  static bool get isConfigured =>
      url.isNotEmpty &&
      anonKey.isNotEmpty &&
      url != 'https://your-project-ref.supabase.co' &&
      anonKey != 'public-anon-key-here';

  /// The live [SupabaseClient], or `null` when running in offline demo mode.
  ///
  /// Accessing [Supabase.instance.client] before [Supabase.initialize] throws
  /// `SupabaseUninitializedError`. Every Supabase-dependent call site must
  /// guard against a `null` client rather than assuming it is initialized.
  static SupabaseClient? get client {
    if (!isConfigured) return null;
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  /// Returns the authenticated user id.
  ///
  /// Falls back to a neutral, non-personal sentinel when no client or session
  /// exists; call sites guard on [isConfigured]/[client] before using it.
  static String get currentUserId =>
      client?.auth.currentUser?.id ?? 'unauthenticated';
}
