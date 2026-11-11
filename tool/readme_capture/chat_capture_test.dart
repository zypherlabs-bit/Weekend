// README capture for the chat screen.
//
// The chat transcript is delivered by Supabase over PostgREST and Realtime,
// so this capture needs a reachable backend. The fixture server in
// `fixtures.dart` answers the two PostgREST reads the chat screen performs
// and speaks enough of the Phoenix protocol to accept the Realtime join.
//
// The compile-time defines point the app's Supabase client at the fixture
// server. They are fake loopback values and are never shipped:
//
//   flutter test tool/readme_capture/chat_capture_test.dart --update-goldens \
//     --dart-define=SUPABASE_URL=http://127.0.0.1:54123 \
//     --dart-define=SUPABASE_ANON_KEY=sb_fixture_readme_capture

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:weekend/config/supabase_config.dart';
import 'package:weekend/features/chat/chat_screen.dart';
import 'package:weekend/models/models.dart';
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

  setUpAll(() {
    HttpOverrides.global = null;
    _mockPathProvider();
    _mockAppLinks();
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('chat', (tester) async {
    tester.view.physicalSize = captureSize * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    late FixtureServer server;
    await tester.runAsync(() async {
      server = await FixtureServer.start(port: 54123);
    });

    await tester.runAsync(() async {
      await Supabase.initialize(
        url: SupabaseConfig.url,
        publishableKey: SupabaseConfig.anonKey,
      );
      // Open the Realtime socket from the real async zone. The chat screen
      // joins the channel while it is built, and a handshake started there
      // would never complete on the test's fake clock.
      // ignore: invalid_use_of_internal_member
      await Supabase.instance.client.realtime.connect();
    });

    final match = MatchItem(
      id: 'match_0',
      user: demoProfile(0, photos: ['${server.baseUrl}/avatar_sc.png']),
      matchedAt: 1767225600000,
      lastMessage: 'Then it is a plan. I will make one so others can join.',
      lastMessageTime: '2m',
      unreadCount: 0,
      sharedInterests: const ['Coffee', 'Live music'],
      suggestedStarter: 'Ask about the rooftop',
      conversationId: 'conv_0',
      initiationStatus: 'active',
      windowEndsAtMs: 1767830400000,
    );

    final state = WeekendState(
      currentUser: demoCurrentUser(),
      matches: [match],
      referralData: const ReferralData(code: 'WEEKEND-ALEX'),
      selectedMode: DiscoveryMode.forYou,
    );

    await tester.runAsync(loadRealFonts);
    await tester.pumpWidget(const SizedBox.shrink());
    final context = tester.element(find.byType(SizedBox));
    await tester.runAsync(
      () => precacheFixtures(context, ['${server.baseUrl}/avatar_sc.png']),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          weekendProvider.overrideWith((ref) => _FakeNotifier(state)),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.darkTheme,
          home: WeekendAtmosphere(
            child: Scaffold(body: ChatScreen(match: match)),
          ),
        ),
      ),
    );
    await tester.pump();

    // The transcript is fetched over the network and the Realtime socket has
    // to complete its handshake. Each round trip needs a real event loop
    // turn followed by a flush of the test's microtask queue, so the capture
    // alternates between the two until the transcript is on screen.
    for (var round = 0; round < 8; round++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
    }

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('$readmeRawDir/chat.png'),
    );

    // Tear the tree down, then close the Realtime socket so the heartbeat
    // timer does not outlive the test.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.runAsync(() async {
      await Supabase.instance.client.realtime.disconnect();
      await server.close();
    });
    await tester.pump(const Duration(seconds: 20));
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

/// `Supabase.initialize` registers a deep-link listener through `app_links`.
/// The plugin has no implementation inside the test runner, so the event
/// channel is acknowledged instead of throwing.
void _mockAppLinks() {
  const channel = 'com.llfbandit.app_links/events';
  const codec = StandardMethodCodec();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMessageHandler(channel, (message) async {
        final call = codec.decodeMethodCall(message);
        if (call.method == 'listen' || call.method == 'cancel') {
          return codec.encodeSuccessEnvelope(null);
        }
        return null;
      });
}
