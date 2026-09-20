import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekend/widgets/weekend_design_system.dart';
import 'package:weekend/widgets/weekend_empty_state.dart';
import 'package:weekend/widgets/weekend_states.dart';

void main() {
  group('Weekend design system', () {
    testWidgets('WeekendCard renders its child', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: WeekendCard(child: Text('card body'))),
        ),
      );
      expect(find.text('card body'), findsOneWidget);
    });

    testWidgets('WeekendGlass renders its child', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: WeekendGlass(child: Text('glass body'))),
        ),
      );
      expect(find.text('glass body'), findsOneWidget);
    });

    testWidgets('WeekendEmptyState renders copy and action', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WeekendEmptyState(
              icon: Icons.search_off_rounded,
              title: 'Empty title',
              subtitle: 'Empty subtitle',
              actionLabel: 'Retry',
              onAction: () => tapped = true,
            ),
          ),
        ),
      );

      expect(find.text('Empty title'), findsOneWidget);
      expect(find.text('Empty subtitle'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      expect(tapped, isTrue);
    });

    testWidgets('WeekendErrorState renders message and retries', (tester) async {
      var retried = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WeekendErrorState(
              message: 'Something failed',
              onRetry: () => retried = true,
            ),
          ),
        ),
      );

      expect(find.text('Something failed'), findsOneWidget);
      await tester.tap(find.text('Try again'));
      expect(retried, isTrue);
    });
  });
}
