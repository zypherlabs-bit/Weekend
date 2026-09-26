import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekend/main.dart';

void main() {
  const backendMissing =
      'Weekend is not connected to a backend. '
      'Build with SUPABASE_URL and SUPABASE_ANON_KEY to enable accounts.';

  Future<void> openWizard(WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: WeekendApp()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.drag(find.byType(PageView), const Offset(-500, 0));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    await tester.drag(find.byType(PageView), const Offset(-500, 0));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    await tester.tap(find.text('Get Started'));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    expect(find.text('Step 1 of 6'), findsOneWidget);
  }

  testWidgets('wizard walks all six steps; failure keeps the user on step 6',
      (WidgetTester tester) async {
    await openWizard(tester);

    // Step 1 — empty email is rejected, then a valid one advances.
    await tester.tap(find.text('Next'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Step 1 of 6'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).first, 'ada@example.com');
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    // Step 2 — password.
    expect(find.text('Step 2 of 6'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).first, 'secret123');
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    // Step 3 — name.
    expect(find.text('Step 3 of 6'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).first, 'Ada Lovelace');
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    // Step 4 — birthday via the date picker (initialDate is 18+).
    expect(find.text('Step 4 of 6'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.cake_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    // Step 5 — gender.
    expect(find.text('Step 5 of 6'), findsOneWidget);
    await tester.tap(find.text('Non-binary'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    // Step 6 — goal, then create. Demo mode has no backend, so the notifier
    // reports an error: the wizard must STAY on step 6 (regression test for
    // users being pushed back to the start of sign-up).
    expect(find.text('Step 6 of 6'), findsOneWidget);
    await tester.tap(find.text('Dating'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create Account'));
    await tester.pumpAndSettle();

    expect(find.text(backendMissing), findsWidgets);
    expect(find.text('Step 6 of 6'), findsOneWidget);
    expect(find.text('Welcome to Weekend'), findsNothing);

    // Flush the validation snackbar timer before teardown.
    await tester.pump(const Duration(seconds: 8));
    await tester.pumpAndSettle();
  });

  testWidgets('wizard back arrow on step 1 returns to onboarding',
      (WidgetTester tester) async {
    await openWizard(tester);
    await tester.tap(find.byIcon(Icons.arrow_back_ios_new));
    await tester.pumpAndSettle();
    expect(find.text('Welcome to Weekend'), findsOneWidget);
  });

  testWidgets('sign-in screen offers only email/password and passkey',
      (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: WeekendApp()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Welcome to Weekend'), findsOneWidget);
    await tester.tap(find.text('Already have an account? Sign in'));
    await tester.pumpAndSettle();

    expect(find.text('Welcome Back'), findsOneWidget);
    expect(find.text('Sign in with Passkey'), findsOneWidget);
    expect(find.text("Don't have an account? Sign up"), findsOneWidget);
    // Guest browsing moved to onboarding; sign-in is exactly two methods.
    expect(find.text('Explore as Guest'), findsNothing);
    expect(find.text('Create Account'), findsNothing);
  });
}
