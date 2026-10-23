import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekend/features/profile/profile_viewer_screen.dart';
import 'package:weekend/models/models.dart';
import 'package:weekend/providers/weekend_provider.dart';
import 'package:weekend/repositories/date_ideas_repository.dart';
import 'package:weekend/repositories/discovery_repository.dart';
import 'package:weekend/repositories/match_repository.dart';
import 'package:weekend/repositories/message_repository.dart';
import 'package:weekend/repositories/plan_repository.dart';
import 'package:weekend/repositories/profile_repository.dart';
import 'package:weekend/repositories/safety_repository.dart';

/// A test [WeekendNotifier] that accepts a fixed [WeekendState].
class _TestWeekendNotifier extends WeekendNotifier {
  _TestWeekendNotifier(WeekendState state) : super(
    discoveryRepository: DiscoveryRepository(),
    profileRepository: ProfileRepository(),
    matchRepository: MatchRepository(),
    messageRepository: MessageRepository(),
    planRepository: PlanRepository(),
    safetyRepository: SafetyRepository(),
    dateIdeasRepository: DateIdeasRepository(),
    initialState: state,
  );
}

UserProfile _testUser({
  List<String> photos = const [],
  bool verified = false,
}) {
  return UserProfile(
    id: 'user_1',
    name: 'Alex',
    age: 26,
    gender: 'Male',
    photos: photos,
    city: 'Springfield',
    isPhotoVerified: verified,
  );
}

WeekendState _testState(UserProfile user) => WeekendState(
      currentUser: user,
      referralData: const ReferralData(code: ''),
      selectedMode: DiscoveryMode.forYou,
    );

void main() {
  group('ProfileViewerScreen', () {
    testWidgets('renders a PageView of photos when the user has photos',
        (tester) async {
      final state = _testState(
        _testUser(
          photos: [
            'https://example.com/photo1.jpg',
            'https://example.com/photo2.jpg',
          ],
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            weekendProvider.overrideWith((ref) => _TestWeekendNotifier(state)),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: ProfileViewerScreen(),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(PageView), findsOneWidget);
      expect(find.text('1/2'), findsOneWidget);
    });

    testWidgets('shows a placeholder icon when the user has no photos',
        (tester) async {
      final state = _testState(_testUser());

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            weekendProvider.overrideWith((ref) => _TestWeekendNotifier(state)),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: ProfileViewerScreen(),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byIcon(Icons.person_rounded), findsOneWidget);
    });

    testWidgets('displays the current user name and city in the details section',
        (tester) async {
      final state = _testState(
        _testUser(photos: ['https://example.com/photo1.jpg']),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            weekendProvider.overrideWith((ref) => _TestWeekendNotifier(state)),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: ProfileViewerScreen(),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Alex, 26'), findsOneWidget);
      expect(find.text('Springfield'), findsOneWidget);
    });

    testWidgets('shows a verified badge when the user is photo verified',
        (tester) async {
      final state = _testState(
        _testUser(
          photos: ['https://example.com/photo1.jpg'],
          verified: true,
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            weekendProvider.overrideWith((ref) => _TestWeekendNotifier(state)),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: ProfileViewerScreen(),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byIcon(Icons.verified_rounded), findsOneWidget);
    });

    testWidgets('renders a close button and supports pagination between photos',
        (tester) async {
      final state = _testState(
        _testUser(
          photos: [
            'https://example.com/photo1.jpg',
            'https://example.com/photo2.jpg',
            'https://example.com/photo3.jpg',
          ],
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            weekendProvider.overrideWith((ref) => _TestWeekendNotifier(state)),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: ProfileViewerScreen(),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('1/3'), findsOneWidget);
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);

      // Swipe horizontally to move to the second photo.
      final pageView = find.byType(PageView).first;
      await tester.fling(pageView, const Offset(-500, 0), 1000);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('2/3'), findsOneWidget);
    });
  });
}
