import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:weekend/widgets/intro_video_player.dart';

/// A platform that always fails to create a controller, standing in for a
/// missing or corrupt bundled asset.
class _AlwaysFailingPlatform extends VideoPlayerPlatform {
  @override
  Future<void> init() async {}

  @override
  Future<int?> create(DataSource dataSource) async =>
      throw PlatformException(code: 'simulated_decode_failure');

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async =>
      throw PlatformException(code: 'simulated_decode_failure');

  @override
  Future<void> dispose(int id) async {}

  @override
  Future<void> setLooping(int id, bool looping) async {}

  @override
  Future<void> play(int id) async {}

  @override
  Future<void> pause(int id) async {}

  @override
  Future<void> setVolume(int id, double volume) async {}

  @override
  Future<void> setPlaybackSpeed(int id, double speed) async {}

  @override
  Widget buildView(int id) => const SizedBox.shrink();

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}
}

Future<void> _pumpPlayer(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 200,
          height: 300,
          child: IntroVideoPlayer(clip: kIntroClips[0]),
        ),
      ),
    ),
  );
  // Let the failed initialize() future settle.
  await tester.pumpAndSettle();
}

void main() {
  group('IntroClip catalogue', () {
    test('exposes exactly three clips', () {
      expect(kIntroClips, hasLength(3));
    });

    test('assets are unique and all under assets/videos/', () {
      final assets = kIntroClips.map((c) => c.asset).toList();
      expect(assets.toSet(), hasLength(3), reason: 'assets must be unique');
      for (final asset in assets) {
        expect(asset, startsWith('assets/videos/'));
        expect(asset, endsWith('.mp4'));
      }
    });

    test('every clip has user-facing copy', () {
      for (final c in kIntroClips) {
        expect(c.title.trim(), isNotEmpty);
        expect(c.caption.trim(), isNotEmpty);
      }
    });
  });

  group('IntroVideoPlayer failure handling', () {
    setUp(() {
      VideoPlayerPlatform.instance = _AlwaysFailingPlatform();
    });

    testWidgets('renders a fallback instead of throwing', (tester) async {
      await _pumpPlayer(tester);
      // The gradient fallback icon is shown in place of the clip.
      expect(find.byIcon(Icons.weekend_rounded), findsOneWidget);
    });

    testWidgets('a failed clip stops animating', (tester) async {
      await _pumpPlayer(tester);
      // Regression test: the loading spinner used to stay on screen forever
      // once a clip had failed, which meant the widget never settled and the
      // user was told we were still loading something that had already died.
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });
}
