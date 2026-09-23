import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:weekend/main.dart';

void main() {
  testWidgets('Weekend app launches', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: WeekendApp()));
    expect(find.byType(MaterialApp), findsOneWidget);
  });

  testWidgets('Demo mode: splash redirects to onboarding after session check',
      (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: WeekendApp()));
    await tester.pump();

    // In demo mode the auth check resolves near-instantly, so the GoRouter
    // redirect moves us from splash to onboarding quickly.
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Welcome to Weekend'), findsOneWidget);
  });

  testWidgets('Get Started button opens the sign-up form (no sign-in detour)',
      (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: WeekendApp()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Welcome to Weekend'), findsOneWidget);

    // Swipe through all onboarding pages.
    await tester.drag(find.byType(PageView), const Offset(-500, 0));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));

    await tester.drag(find.byType(PageView), const Offset(-500, 0));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));

    expect(find.text('Get Started'), findsOneWidget);
    await tester.tap(find.text('Get Started'));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));

    // "Get Started" means "create an account", so the auth screen opens
    // directly on the sign-up form. The user must not be sent through the
    // sign-in screen (nor a duplicate auth screen) first.
    expect(find.text('Create Account'), findsWidgets);
    expect(find.text('Welcome Back'), findsNothing);
  });
}
