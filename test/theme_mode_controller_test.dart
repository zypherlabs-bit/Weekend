import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:weekend/providers/theme_provider.dart';
import 'package:weekend/theme/app_theme.dart';

/// Day / Night / Auto is a real, persisted, reactive preference.
///
/// The defect this pins down: a "Dark Mode" switch existed in Settings that
/// flipped a local boolean nobody read, and `MaterialApp` hardcoded
/// `ThemeMode.system`. Choosing a theme did nothing and was forgotten on the
/// next launch.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('persistence', () {
    test('an empty store means Auto (follow the system)', () async {
      final controller = ThemeModeController();
      await controller.load();
      expect(controller.state, ThemeMode.system);
    });

    test('a stored choice is restored before the first frame', () async {
      SharedPreferences.setMockInitialValues({
        'weekend.theme_mode.v1': 'light',
      });
      final controller = ThemeModeController();
      await controller.load();
      expect(controller.state, ThemeMode.light);
    });

    test('dark survives a round trip through storage', () async {
      final controller = ThemeModeController();
      await controller.set(ThemeMode.dark);

      final restored = ThemeModeController();
      await restored.load();
      expect(restored.state, ThemeMode.dark);
    });

    test('auto is stored as "system", not as the current brightness', () async {
      final controller = ThemeModeController();
      await controller.set(ThemeMode.dark);
      await controller.set(ThemeMode.system);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('weekend.theme_mode.v1'), 'system');

      final restored = ThemeModeController();
      await restored.load();
      expect(restored.state, ThemeMode.system);
    });

    test('a future or corrupt value falls back to Auto instead of throwing',
        () async {
      SharedPreferences.setMockInitialValues({
        'weekend.theme_mode.v1': 'sepia',
      });
      final controller = ThemeModeController();
      await controller.load();
      expect(controller.state, ThemeMode.system);
    });
  });

  group('reactivity', () {
    test('the provider state changes immediately on set', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final seen = <ThemeMode>[];
      container.listen(themeModeProvider, (_, next) => seen.add(next));

      await container.read(themeModeProvider.notifier).set(ThemeMode.light);
      await container.read(themeModeProvider.notifier).set(ThemeMode.dark);

      expect(container.read(themeModeProvider), ThemeMode.dark);
      expect(seen, [ThemeMode.light, ThemeMode.dark]);
    });

    test('setting the same mode twice does not notify twice', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      var notifications = 0;
      container.listen(themeModeProvider, (_, __) => notifications++);

      final notifier = container.read(themeModeProvider.notifier);
      await notifier.set(ThemeMode.light);
      await notifier.set(ThemeMode.light);

      expect(notifications, 1);
    });
  });

  group('the palette follows the mode', () {
    test('Day is light and Night is dark', () {
      expect(AppTheme.lightTheme.brightness, Brightness.light);
      expect(AppTheme.darkTheme.brightness, Brightness.dark);
    });

    test('both palettes expose readable on-surface contrast', () {
      for (final theme in [AppTheme.lightTheme, AppTheme.darkTheme]) {
        final scheme = theme.colorScheme;
        final ratio = _contrastRatio(scheme.onSurface, scheme.surface);
        expect(
          ratio,
          greaterThan(4.5),
          reason: 'onSurface on surface must clear WCAG AA ($ratio)',
        );
      }
    });

    test('glass surfaces are translucent so the atmosphere shows through', () {
      for (final theme in [AppTheme.lightTheme, AppTheme.darkTheme]) {
        expect(
          theme.colorScheme.surfaceContainerHigh.a,
          lessThan(1.0),
          reason: 'frosted cards must not be fully opaque',
        );
      }
    });
  });
}

/// WCAG relative-luminance contrast ratio, used to prove the palettes are
/// readable rather than merely different.
double _contrastRatio(Color a, Color b) {
  final first = _relativeLuminance(a);
  final second = _relativeLuminance(b);
  final lighter = first > second ? first : second;
  final darker = first > second ? second : first;
  return (lighter + 0.05) / (darker + 0.05);
}

double _relativeLuminance(Color color) {
  double linear(double value) {
    return value <= 0.03928
        ? value / 12.92
        : math.pow((value + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * linear(color.r) +
      0.7152 * linear(color.g) +
      0.0722 * linear(color.b);
}
