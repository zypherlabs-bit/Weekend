import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekend/models/models.dart';
import 'package:weekend/widgets/ad_card.dart';

void main() {
  final testAd = Advertisement(
    id: 'ad1',
    campaignId: 'c1',
    title: 'Test Ad Title',
    description: 'This is a test ad description',
    imageUrl: 'https://example.com/ad_image.png',
    ctaText: 'Learn More',
    destinationUrl: 'https://example.com',
  );

  group('AdCard', () {
    testWidgets('renders ADVERTISEMENT badge', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdCard(ad: testAd),
          ),
        ),
      );

      expect(find.text('ADVERTISEMENT'), findsOneWidget);
    });

    testWidgets('renders ad title and description', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdCard(ad: testAd),
          ),
        ),
      );

      expect(find.text('Test Ad Title'), findsOneWidget);
      expect(find.text('This is a test ad description'), findsOneWidget);
    });

    testWidgets('renders CTA button with ctaText', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdCard(ad: testAd),
          ),
        ),
      );

      expect(find.text('Learn More'), findsOneWidget);
      final buttonFinder = find.ancestor(
        of: find.text('Learn More'),
        matching: find.byType(ElevatedButton),
      );
      expect(buttonFinder, findsOneWidget);
    });

    testWidgets('renders Sponsored label at bottom', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdCard(ad: testAd),
          ),
        ),
      );

      expect(find.text('Sponsored'), findsOneWidget);
    });

    testWidgets('calls onReport when menu report selected', (WidgetTester tester) async {
      bool reportCalled = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdCard(
              ad: testAd,
              onReport: () => reportCalled = true,
            ),
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.text('Report advertisement'));
      await tester.pump();

      expect(reportCalled, true);
    });

    testWidgets('calls onHide when menu hide selected', (WidgetTester tester) async {
      bool hideCalled = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdCard(
              ad: testAd,
              onHide: () => hideCalled = true,
            ),
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.text('Hide this advertisement'));
      await tester.pump();

      expect(hideCalled, true);
    });

    testWidgets('loads image from network', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdCard(ad: testAd),
          ),
        ),
      );

      expect(find.byType(CachedNetworkImage), findsOneWidget);
    });

    testWidgets('handles null callbacks gracefully', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdCard(ad: testAd),
          ),
        ),
      );

      expect(find.byType(AdCard), findsOneWidget);
    });
  });
}
