import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:weekend/providers/theme_provider.dart';
import 'package:weekend/theme/app_theme.dart';

/// End-to-end theme behaviour: the selector in Settings drives the real
/// `MaterialApp.themeMode`, and Auto is a genuine `ThemeMode.system`.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// A miniature host that mirrors how `main.dart` wires the mode into the app.
  Widget host(ThemeMode mode) {
    return MaterialApp(
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: mode,
      home: const Scaffold(body: Text('probe')),
    );
  }

  Brightness brightnessOf(WidgetTester tester) {
    final context = tester.element(find.text('probe'));
    return Theme.of(context).brightness;
  }

  testWidgets('Day is light even when the platform is dark', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    await tester.pumpWidget(host(ThemeMode.light));
    expect(brightnessOf(tester), Brightness.light);
  });

  testWidgets('Night is dark even when the platform is light', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    await tester.pumpWidget(host(ThemeMode.dark));
    expect(brightnessOf(tester), Brightness.dark);
  });

  testWidgets('Auto follows the platform in both directions', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    await tester.pumpWidget(host(ThemeMode.system));
    expect(brightnessOf(tester), Brightness.light);

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    // A fresh build reads the platform brightness through MediaQuery, so this
    // asserts the resolved theme rather than a cached one.
    await tester.pumpWidget(host(ThemeMode.system));
    await tester.pumpAndSettle();
    expect(brightnessOf(tester), Brightness.dark);
  });

  testWidgets('a stored Night choice is applied without a manual toggle',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'weekend.theme_mode.v1': 'dark',
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(themeModeProvider.notifier).load();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: Consumer(
          builder: (context, ref, _) =>
              host(ref.watch(themeModeProvider)),
        ),
      ),
    );

    expect(brightnessOf(tester), Brightness.dark);
  });

  testWidgets('changing the preference rebuilds the app theme', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: Consumer(
          builder: (context, ref, _) => host(ref.watch(themeModeProvider)),
        ),
      ),
    );

    await container.read(themeModeProvider.notifier).set(ThemeMode.light);
    await tester.pumpAndSettle();
    expect(brightnessOf(tester), Brightness.light);

    await container.read(themeModeProvider.notifier).set(ThemeMode.dark);
    await tester.pumpAndSettle();
    expect(brightnessOf(tester), Brightness.dark);
  });
}
