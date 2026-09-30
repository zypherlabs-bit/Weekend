import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/supabase_config.dart';

/// Persisted Light / Dark / System selection.
///
/// The app hardcoded `ThemeMode.system` in `MaterialApp.router`, and the
/// "Dark Mode" switch in the settings dialog only flipped a local field that
/// nothing read - a control that looked real and did nothing. There was also
/// no persistence of any kind: the only SharedPreferences write in the whole
/// app was the discovery-preferences blob.
///
/// Read locally rather than from `user_settings` so the choice is available on
/// the very first frame. Reading it over the network instead would mean a
/// theme flash on every cold start. It is mirrored to
/// `user_settings.theme_preference` on change so the preference belongs to the
/// account and would restore on a new device.
class ThemeModeController extends StateNotifier<ThemeMode> {
  ThemeModeController() : super(ThemeMode.system);

  static const _prefsKey = 'weekend.theme_mode.v1';

  /// The valid values of `user_settings.theme_preference`, which predates this
  /// class and is not currently written by anything.
  static const _wireValue = {
    ThemeMode.light: 'light',
    ThemeMode.dark: 'dark',
    ThemeMode.system: 'system',
  };

  /// Load the stored preference. Called once before the first frame.
  ///
  /// A read failure falls back to [ThemeMode.system] rather than throwing: a
  /// corrupt preferences store must not stop the app from starting.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      switch (prefs.getString(_prefsKey)) {
        case 'light':
          state = ThemeMode.light;
        case 'dark':
          state = ThemeMode.dark;
        case 'system':
          state = ThemeMode.system;
        default:
          // First run, or a value from a future version. System is the safe
          // default because it follows the OS the user already configured.
          state = ThemeMode.system;
      }
    } catch (_) {
      state = ThemeMode.system;
    }
  }

  Future<void> set(ThemeMode mode) async {
    if (mode == state) return;
    state = mode;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, _wireValue[mode] ?? 'system');
    } catch (_) {
      // The in-memory value is still correct for this session; only the
      // persisted copy is lost, so this is not worth surfacing to the user.
    }

    unawaitedMirror(mode);
  }

  /// Best-effort write to the account so the choice follows the user.
  ///
  /// Failures are swallowed by design. Choosing a theme is a cosmetic action
  /// and must never surface an error dialog, and it must never block the
  /// toggle from taking effect immediately.
  void unawaitedMirror(ThemeMode mode) {
    final client = SupabaseConfig.client;
    final userId = SupabaseConfig.currentUserId;
    if (client == null) return;
    if (userId == 'me' || userId == 'unauthenticated') return;

    client
        .from('user_settings')
        .upsert({
          'user_id': userId,
          'theme_preference': _wireValue[mode] ?? 'system',
        }, onConflict: 'user_id')
        // The response is deliberately discarded: nothing in the UI waits on
        // this, and a failure here is not actionable.
        .then((_) {}, onError: (_) {});
  }
}

final themeModeProvider =
    StateNotifierProvider<ThemeModeController, ThemeMode>(
  (ref) => ThemeModeController(),
);

/// Read once during startup so the first frame already has the right theme.
final themeBootstrapProvider = FutureProvider<void>((ref) async {
  await ref.read(themeModeProvider.notifier).load();
});