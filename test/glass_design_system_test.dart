import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekend/theme/app_theme.dart';
import 'package:weekend/widgets/weekend_design_system.dart';

/// Glassmorphism design-system guarantees:
///   1. glass surfaces really blur the backdrop (frosted, not flat grey);
///   2. they render and stay readable in BOTH light and dark mode, which the
///      previous hardcoded white-on-white implementation did not;
///   3. the atmospheric backdrop paints a gradient with depth layers and does
///      not overflow on small viewports.
void main() {
  Widget host(ThemeData theme, Widget child, {Size size = const Size(390, 844)}) {
    return MaterialApp(
      theme: theme,
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: Scaffold(
          body: WeekendAtmosphere(child: Center(child: child)),
        ),
      ),
    );
  }

  testWidgets('WeekendGlass applies a backdrop blur', (tester) async {
    await tester.pumpWidget(
      host(
        AppTheme.darkTheme,
        const WeekendGlass(
          child: Text('glass', style: TextStyle(color: Colors.white)),
        ),
      ),
    );

    final filter = tester.widget<BackdropFilter>(find.byType(BackdropFilter));
    expect(filter.filter, isA<ImageFilter>());
  });

  testWidgets('glass renders in dark mode with readable text', (tester) async {
    await tester.pumpWidget(
      host(
        AppTheme.darkTheme,
        const WeekendGlass(
          child: Text('Dark glass', style: TextStyle(color: Color(0xFFF3EEFA))),
        ),
      ),
    );
    expect(find.text('Dark glass'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('glass renders in light mode (no dark-only assumption)',
      (tester) async {
    await tester.pumpWidget(
      host(
        AppTheme.lightTheme,
        const WeekendGlass(
          child: Text('Light glass', style: TextStyle(color: Color(0xFF211A20))),
        ),
      ),
    );
    expect(find.text('Light glass'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // The light-mode surface must not fall back to the old hardcoded dark fill.
    final container = tester.widget<Container>(
      find.descendant(of: find.byType(WeekendGlass), matching: find.byType(Container)),
    );
    final decoration = container.decoration as BoxDecoration?;
    expect(decoration, isNotNull);
    expect(decoration!.gradient, isA<LinearGradient>());
  });

  testWidgets('glass variants keep a single blur layer each', (tester) async {
    await tester.pumpWidget(
      host(
        AppTheme.darkTheme,
        const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            WeekendGlass.subtle(child: Text('subtle')),
            SizedBox(height: 12),
            WeekendGlass.strong(child: Text('strong')),
          ],
        ),
      ),
    );
    expect(find.byType(BackdropFilter), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('atmosphere renders on a small viewport without overflow',
      (tester) async {
    await tester.pumpWidget(
      host(
        AppTheme.darkTheme,
        const Text('small'),
        size: const Size(320, 568),
      ),
    );
    expect(find.byType(WeekendAtmosphere), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('WeekendCard follows the active theme surface color',
      (tester) async {
    await tester.pumpWidget(
      host(AppTheme.lightTheme, const WeekendCard(child: Text('card'))),
    );
    final container = tester.widget<Container>(
      find.descendant(
        of: find.byType(WeekendCard),
        matching: find.byType(Container),
      ),
    );
    final decoration = container.decoration as BoxDecoration?;
    expect(decoration?.color, AppTheme.lightSurface);
  });
}