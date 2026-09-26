// Regression tests for the production wiring fixes.
//
// These lock in the specific defects that made Edit Profile report success
// without saving, made photo uploads look successful when nothing was stored,
// and made several screens report "saved" for writes that were dropped.
//
// The Supabase client is not available in the unit-test environment, so these
// tests assert the guards that must hold when the backend is absent or the
// caller is not authenticated: a save/upload must FAIL LOUDLY rather than
// silently no-op. A silent no-op is exactly what the production bug was.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:weekend/config/supabase_config.dart';
import 'package:weekend/models/models.dart';
import 'package:weekend/repositories/profile_repository.dart';
import 'package:weekend/repositories/safety_repository.dart';
import 'package:weekend/repositories/match_repository.dart';

void main() {
  group('SupabaseConfig live-only guarantee', () {
    test('is unconfigured in the test environment', () {
      // Guards the rest of the suite: if a real URL were compiled in, the
      // "throws when unavailable" expectations below would be meaningless and
      // the tests would be talking to production.
      expect(SupabaseConfig.isConfigured, isFalse,
          reason: 'dart-defines must not be present when running unit tests');
      expect(SupabaseConfig.client, isNull);
    });

    test('configError explains the missing credentials', () {
      expect(SupabaseConfig.configError, contains('SUPABASE_URL'));
    });
  });

  group('ProfileRepository.updateProfile', () {
    test('throws instead of silently returning when no backend is configured',
        () async {
      final repo = ProfileRepository();
      // The previous implementation did `if (client == null) return;`, so a
      // save with no backend reported success and the user was told their
      // profile was updated when nothing was written.
      expect(
        () => repo.updateProfile(
          const UserProfile(
            id: 'me',
            name: '',
            age: 18,
            gender: 'Man',
            photos: [],
            city: '',
          ),
        ),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('ProfileRepository.uploadProfilePhoto', () {
    test('throws instead of returning an empty path when no backend', () async {
      final repo = ProfileRepository();
      // The old code returned '' and the caller showed "Photo uploaded!",
      // so an upload that never happened was reported as a success.
      expect(
        () => repo.uploadProfilePhoto('some-user', _onePixelJpeg(), true),
        throwsA(isA<StateError>()),
      );
    });

    test('rejects an empty payload', () async {
      final repo = ProfileRepository();
      expect(
        () => repo.uploadProfilePhoto('some-user', Uint8List(0), true),
        throwsA(anything),
      );
    });

    test('rejects a non-image payload before it reaches Storage', () async {
      final repo = ProfileRepository();
      expect(
        () => repo.uploadProfilePhoto(
          'some-user',
          Uint8List.fromList(List<int>.filled(32, 0x41)),
          true,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('SafetyRepository write paths report failures', () {
    test('blockUser throws without a backend', () async {
      final repo = SafetyRepository();
      expect(
        () => repo.blockUser('a', 'b'),
        throwsA(isA<StateError>()),
      );
    });

    test('unblockUser throws without a backend instead of silently succeeding',
        () async {
      final repo = SafetyRepository();
      // This used to swallow the error, and the UI then showed a green
      // "Unblocked: <id>" while the person remained blocked.
      expect(
        () => repo.unblockUser('a', 'b'),
        throwsA(isA<StateError>()),
      );
    });

    test('fetchBlockedUserIds throws without a backend', () async {
      final repo = SafetyRepository();
      // An empty list here would render as "you have not blocked anyone",
      // which is indistinguishable from a successful empty read.
      expect(
        () => repo.fetchBlockedUserIds('a'),
        throwsA(isA<StateError>()),
      );
    });

    test('reportUser throws without a backend', () async {
      final repo = SafetyRepository();
      expect(
        () => repo.reportUser('a', 'b', 'Harassment or bullying'),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('MatchRepository', () {
    test('fetchMatches returns an empty list, never fabricated matches',
        () async {
      final repo = MatchRepository();
      final matches = await repo.fetchMatches('some-user');
      expect(matches, isEmpty);
    });
  });
}

/// Smallest valid JPEG byte sequence (SOI + APP0/JFIF + EOI). Enough for the
/// magic-byte sniff in ProfileRepository; it is never actually uploaded in
/// these tests because the backend check happens first.
Uint8List _onePixelJpeg() {
  return Uint8List.fromList([
    0xFF, 0xD8, // SOI
    0xFF, 0xE0, 0x00, 0x10, // APP0
    0x4A, 0x46, 0x49, 0x46, 0x00, // "JFIF\0"
    0x01, 0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00,
    0xFF, 0xD9, // EOI
  ]);
}
