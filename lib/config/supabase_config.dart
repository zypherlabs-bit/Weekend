import 'package:supabase_flutter/supabase_flutter.dart';

/// Central configuration for the Weekend backend (Supabase).
//
// The app supports two run modes:
///   1. **Live mode** — Supabase is configured via compile-time
///      `--dart-define=SUPABASE_URL=...` / `SUPABASE_ANON_KEY=...`. Auth,
///      database, storage and realtime features connect to the live project.
///   2. **Unconfigured mode** — no credentials are supplied (the test suite,
///      or a build without the dart-defines). Every backend call is
///      null-guarded and returns empty results — there is no sample or
///      fabricated data — so the app never invents content. No secret is ever
///      read from an un-trusted source.
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

  /// Optional production redirect target sent to Supabase with signup and
  /// password-reset emails (`--dart-define=AUTH_EMAIL_REDIRECT_URL=...`).
  ///
  /// GoTrue only honours this value when it is present in the project's
  /// *Authentication -> URL Configuration -> Redirect URLs* allow-list. When
  /// empty (the default) Supabase falls back to the project Site URL, which is
  /// GoTrue's documented behaviour — no redirect target is invented here.
  static const String emailRedirectUrl = String.fromEnvironment(
    'AUTH_EMAIL_REDIRECT_URL',
    defaultValue: '',
  );

  /// The redirect target to send, or `null` to let Supabase use its Site URL.
  static String? get emailRedirectOrNull =>
      emailRedirectUrl.trim().isEmpty ? null : emailRedirectUrl.trim();

  /// LIVE-ONLY GUARANTEE: release builds must never embed placeholder or
  /// non-production Supabase credentials. CI fails the build when the
  /// required secrets are absent (see .github/workflows/release.yml), and
  /// this assertion stops a misconfigured release binary from silently
  /// running against the wrong backend.
  static void assertLiveConfigured() {
    assert(
      isConfigured &&
          !url.contains('your-project-ref') &&
          !url.contains('localhost') &&
          !url.contains('127.0.0.1') &&
          !url.contains('10.0.2.2'),
      'LIVE Supabase credentials are missing. Build with '
      '--dart-define=SUPABASE_URL=https://<live-ref>.supabase.co '
      '--dart-define=SUPABASE_ANON_KEY=<live-anon-key>.',
    );
  }

  static bool get isConfigured =>
      url.isNotEmpty &&
      anonKey.isNotEmpty &&
      url != 'https://your-project-ref.supabase.co' &&
      anonKey != 'public-anon-key-here' &&
      url != '' &&
      anonKey != '';

  /// Returns a human-readable error message when the backend is not connected.
  static String get configError {
    if (url.isEmpty || anonKey.isEmpty) return 'SUPABASE_URL and SUPABASE_ANON_KEY are missing. Build with --dart-define flags.';
    if (url == 'https://your-project-ref.supabase.co') return 'SUPABASE_URL is still a placeholder. Replace with your real Supabase project URL from Dashboard → Project Settings → API.';
    if (anonKey == 'public-anon-key-here') return 'SUPABASE_ANON_KEY is still a placeholder. Replace with your real anon key from Dashboard → Project Settings → API.';
    return 'Backend configuration error.';
  }

  /// The live [SupabaseClient], or `null` when the app is unconfigured
  /// (tests, or a build without the SUPABASE dart-defines).
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
