// README screenshot harness.
//
// Renders the real Weekend screens with synthetic data and writes them to
// `assets/readme/raw/` as golden images. The screens are the production
// widgets - only the Riverpod state is replaced - so every capture is a
// genuine render of the shipped UI.
//
// Run from the repository root:
//
//   flutter test tool/readme_capture/screens_capture_test.dart --update-goldens
//
// The chat screen needs a reachable backend (the transcript arrives over
// PostgREST), so it lives in `chat_capture_test.dart` and runs separately.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekend/features/discovery/discover_screen.dart';
import 'package:weekend/features/discovery/explore_screen.dart';
import 'package:weekend/features/home/home_screen.dart';
import 'package:weekend/features/plans/plans_screen.dart';
import 'package:weekend/features/profile/profile_screen.dart';
import 'package:weekend/features/safety/safety_center_screen.dart';
import 'package:weekend/models/models.dart';
import 'package:weekend/providers/feature_providers.dart';
import 'package:weekend/providers/weekend_provider.dart';
import 'package:weekend/repositories/date_ideas_repository.dart';
import 'package:weekend/repositories/discovery_repository.dart';
import 'package:weekend/repositories/match_repository.dart';
import 'package:weekend/repositories/message_repository.dart';
import 'package:weekend/repositories/plan_repository.dart';
import 'package:weekend/repositories/profile_repository.dart';
import 'package:weekend/repositories/safety_repository.dart';
import 'package:weekend/theme/app_theme.dart';
import 'package:weekend/widgets/weekend_design_system.dart';

import 'fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The widget-test binding installs an HttpOverrides that rejects every
  // request. The capture harness serves its own fixture images over
  // loopback, so the real transport is restored here.
  setUpAll(() {
    HttpOverrides.global = null;
    _mockPathProvider();
  });

  /// The fixture server has to live in the real async zone: a socket bound
  /// inside the widget test's fake clock never sees its events.
  ///
  /// The port is fixed so `flutter_cache_manager` reuses the file it stored
  /// for the same URL, and the screen's own image request resolves from disk
  /// instead of a second network round trip.
  Future<FixtureServer> startServer(WidgetTester tester) async {
    late FixtureServer fixture;
    await tester.runAsync(() async {
      fixture = await FixtureServer.start(port: 54124);
    });
    return fixture;
  }

  Future<void> stopServer(WidgetTester tester, FixtureServer fixture) async {
    await tester.runAsync(() => fixture.close());
  }

  Future<void> settle(WidgetTester tester) async {
    // `cached_network_image` does not override `==`, so every widget builds
    // its own image provider and loads the file itself. Those requests start
    // on the test's fake clock, so each round trip needs a real event loop
    // turn followed by a flush of the microtask queue.
    for (var round = 0; round < 6; round++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 250)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// Warms the image cache and loads the real fonts before the screen is
  /// built, so every capture paints on the first frame.
  Future<void> prepare(WidgetTester tester, List<String> imageUrls) async {
    await tester.runAsync(loadRealFonts);
    await tester.pumpWidget(const SizedBox.shrink());
    final context = tester.element(find.byType(SizedBox));
    await tester.runAsync(() => precacheFixtures(context, imageUrls));
  }

  /// `flutter_cache_manager` schedules a 10 second cache-cleanup timer the
  /// first time an image is cached, and the HTTP client keeps a 15 second
  /// idle-connection timer. Both have to be flushed before the test ends or
  /// the runner reports a pending timer.
  Future<void> flushCacheTimer(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 20));
  }

  Widget host(
    Widget child, {
    List<Override> overrides = const [],
    Brightness brightness = Brightness.dark,
  }) {
    return ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: brightness == Brightness.dark
            ? AppTheme.darkTheme
            : AppTheme.lightTheme,
        home: WeekendAtmosphere(child: child),
      ),
    );
  }

  group('README screen captures', () {
    testWidgets('discover', (tester) async {
      tester.view.physicalSize = captureSize * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      final server = await startServer(tester);
      final base = server.baseUrl;

      final state = WeekendState(
        currentUser: demoCurrentUser(photos: ['$base/avatar_ar.png']),
        deckProfiles: [
          demoProfile(0, photos: ['$base/card_sc.png']),
          demoProfile(1, photos: ['$base/card_np.png']),
          demoProfile(2, photos: ['$base/card_dr.png']),
        ],
        plans: [demoPlan(0)],
        referralData: const ReferralData(code: 'WEEKEND-ALEX'),
        selectedMode: DiscoveryMode.forYou,
        locationPreferences: const LocationPreferences(discoveryRadiusKm: 25),
      );

      await prepare(tester, [
        '$base/avatar_ar.png',
        '$base/card_sc.png',
        '$base/card_np.png',
        '$base/card_dr.png',
      ]);

      await tester.pumpWidget(
        host(
          const Scaffold(body: _CaptureDiscoverScreen()),
          overrides: [
            weekendProvider.overrideWith((ref) => _FakeNotifier(state)),
            surgeProvider.overrideWith((ref) => _FakeSurgeNotifier()),
          ],
        ),
      );
      await settle(tester);

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('$readmeRawDir/discover.png'),
      );

      // DiscoverScreen starts the ad timer; dispose the tree so the timer is
      // cancelled before the test ends.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await flushCacheTimer(tester);
      await stopServer(tester, server);
    });

    testWidgets('explore', (tester) async {
      tester.view.physicalSize = captureSize * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      final server = await startServer(tester);
      final base = server.baseUrl;

      final state = WeekendState(
        currentUser: demoCurrentUser(),
        deckProfiles: [
          demoProfile(0, photos: ['$base/avatar_sc.png']),
          demoProfile(1, photos: ['$base/avatar_np.png']),
          demoProfile(2, photos: ['$base/avatar_dr.png']),
        ],
        crossedPaths: [demoCrossedPath(0), demoCrossedPath(1)],
        referralData: const ReferralData(code: 'WEEKEND-ALEX'),
        selectedMode: DiscoveryMode.nearby,
      );

      await prepare(tester, [
        '$base/avatar_sc.png',
        '$base/avatar_np.png',
        '$base/avatar_dr.png',
      ]);

      await tester.pumpWidget(
        host(
          const Scaffold(body: ExploreScreen()),
          overrides: [
            weekendProvider.overrideWith((ref) => _FakeNotifier(state)),
          ],
        ),
      );
      await settle(tester);

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('$readmeRawDir/explore.png'),
      );
      await flushCacheTimer(tester);
      await stopServer(tester, server);
    });

    testWidgets('matches', (tester) async {
      tester.view.physicalSize = captureSize * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      final server = await startServer(tester);
      final base = server.baseUrl;

      final state = WeekendState(
        currentUser: demoCurrentUser(),
        matches: [
          demoMatch(0, photos: ['$base/avatar_sc.png']),
          demoMatch(1, photos: ['$base/avatar_np.png']),
          demoMatch(2, photos: ['$base/avatar_dr.png']),
        ],
        referralData: const ReferralData(code: 'WEEKEND-ALEX'),
        selectedMode: DiscoveryMode.forYou,
      );

      await prepare(tester, [
        '$base/avatar_sc.png',
        '$base/avatar_np.png',
        '$base/avatar_dr.png',
      ]);

      await tester.pumpWidget(
        host(
          const Scaffold(body: MatchesScreen()),
          overrides: [
            weekendProvider.overrideWith((ref) => _FakeNotifier(state)),
          ],
        ),
      );
      await settle(tester);

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('$readmeRawDir/matches.png'),
      );
      await flushCacheTimer(tester);
      await stopServer(tester, server);
    });

    testWidgets('profile', (tester) async {
      tester.view.physicalSize = captureSize * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      final server = await startServer(tester);
      final base = server.baseUrl;

      final state = WeekendState(
        currentUser: demoCurrentUser(photos: ['$base/avatar_ar.png']),
        referralData: const ReferralData(code: 'WEEKEND-ALEX'),
        selectedMode: DiscoveryMode.forYou,
      );

      await prepare(tester, ['$base/avatar_ar.png']);

      await tester.pumpWidget(
        host(
          const Scaffold(body: ProfileScreen()),
          overrides: [
            weekendProvider.overrideWith((ref) => _FakeNotifier(state)),
          ],
        ),
      );
      await settle(tester);

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('$readmeRawDir/profile.png'),
      );
      await flushCacheTimer(tester);
      await stopServer(tester, server);
    });

    testWidgets('plans', (tester) async {
      tester.view.physicalSize = captureSize * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      final server = await startServer(tester);

      final state = WeekendState(
        currentUser: demoCurrentUser(),
        plans: [demoPlan(0), demoPlan(1), demoPlan(2), demoPlan(3)],
        referralData: const ReferralData(code: 'WEEKEND-ALEX'),
        selectedMode: DiscoveryMode.forYou,
      );

      await tester.pumpWidget(
        host(
          const Scaffold(body: PlansScreen()),
          overrides: [
            weekendProvider.overrideWith((ref) => _FakeNotifier(state)),
          ],
        ),
      );
      await settle(tester);

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('$readmeRawDir/plans.png'),
      );
      await flushCacheTimer(tester);
      await stopServer(tester, server);
    });
    testWidgets('safety', (tester) async {
      tester.view.physicalSize = captureSize * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      final server = await startServer(tester);
      final base = server.baseUrl;

      final state = WeekendState(
        currentUser: demoCurrentUser(photos: ['$base/avatar_ar.png']),
        referralData: const ReferralData(code: 'WEEKEND-ALEX'),
        selectedMode: DiscoveryMode.forYou,
      );

      await prepare(tester, ['$base/avatar_ar.png']);

      await tester.pumpWidget(
        host(
          const Scaffold(body: SafetyCenterScreen()),
          overrides: [
            weekendProvider.overrideWith((ref) => _FakeNotifier(state)),
          ],
        ),
      );
      await settle(tester);

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('$readmeRawDir/safety.png'),
      );
      await flushCacheTimer(tester);
      await stopServer(tester, server);
    });
  });
}

/// A notifier that holds the fixture state and never talks to a backend.
class _FakeNotifier extends WeekendNotifier {
  _FakeNotifier(WeekendState state)
    : super(
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

/// The Discover header shows the surge banner when the server reports an
/// active surge. The capture keeps it off so the promotional frame does not
/// advertise a live event that does not exist.
class _FakeSurgeNotifier extends SurgeNotifier {
  _FakeSurgeNotifier() {
    state = const SurgeState(active: false);
  }
}

/// `DiscoverScreen` calls `ref.listen` from `initState`. Riverpod and the
/// Flutter framework both guard that with debug-only assertions - the
/// shipped release build runs the very same code with the assertions
/// stripped, which is why the app works on device.
///
/// The capture harness resolves the container without registering an
/// inherited-widget dependency, which is what the release build effectively
/// does. Nothing about the screen's own rendering changes, so the capture
/// still shows exactly what the release build shows.
class _CaptureElement extends ConsumerStatefulElement {
  _CaptureElement(super.widget);

  final List<ProviderSubscription<Object?>> _captureSubscriptions = [];

  @override
  bool get debugDoingBuild => true;

  @override
  void listen<T>(
    ProviderListenable<T> provider,
    void Function(T? previous, T value) listener, {
    void Function(Object error, StackTrace stackTrace)? onError,
  }) {
    final container = ProviderScope.containerOf(this, listen: false);
    _captureSubscriptions.add(
      container.listen<T>(provider, listener, onError: onError),
    );
  }

  @override
  void unmount() {
    for (final subscription in _captureSubscriptions) {
      subscription.close();
    }
    _captureSubscriptions.clear();
    super.unmount();
  }
}

/// [DiscoverScreen] rendered through [_CaptureElement].
class _CaptureDiscoverScreen extends DiscoverScreen {
  const _CaptureDiscoverScreen();

  @override
  ConsumerStatefulElement createElement() => _CaptureElement(this);
}

/// `cached_network_image` asks the platform for a cache directory before it
/// downloads anything. There is no platform implementation inside the test
/// runner, so the channel is answered with a temporary directory.
void _mockPathProvider() {
  final directory = Directory.systemTemp.createTempSync('weekend_readme');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => directory.path,
      );
}
