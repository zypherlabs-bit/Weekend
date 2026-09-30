import 'package:flutter_test/flutter_test.dart';
import 'package:weekend/models/models.dart';
import 'package:weekend/repositories/match_repository.dart';
import 'package:weekend/repositories/safety_repository.dart';

/// Tests for the interaction surface added in migration 026: inbound likes, the
/// notification centre, and the three-way outcome a like can now have.
///
/// The theme of these tests is honesty of reporting. The original defect this
/// file exists to prevent is a client that tells the user something the server
/// never confirmed - a like reported as a match when it failed to insert, an
/// underage report filed as "impersonation", an error swallowed into an empty
/// list that then rendered as "no notifications".
void main() {
  group('AppNotification parsing', () {
    test('reads the nested payload written by the database triggers', () {
      final n = AppNotification.fromRow({
        'id': 'n1',
        'type': 'new_message',
        'title': 'New message',
        'body': 'Someone sent you a message',
        'data': {
          'payload': {'conversation_id': 'c-1', 'sender': 'u-2'},
        },
        'is_read': false,
        'created_at': '2026-09-30T10:00:00Z',
      });

      expect(n.id, 'n1');
      expect(n.type, 'new_message');
      expect(n.targetConversationId, 'c-1');
      expect(n.isRead, isFalse);
      expect(n.createdAt, isNotNull);
    });

    test('accepts a flat data object with no nested payload key', () {
      final n = AppNotification.fromRow({
        'id': 'n2',
        'type': 'new_like',
        'data': {'user_id': 'u-9', 'is_stand_out': true},
      });

      expect(n.targetUserId, 'u-9');
      expect(n.payload['is_stand_out'], isTrue);
    });

    test('a malformed or missing data column does not take down the list', () {
      // `data` is jsonb and a bad row must not be able to break the whole
      // notification screen.
      for (final bad in <Object?>[null, 'not a map', 42, <String>['a']]) {
        final n = AppNotification.fromRow({
          'id': 'n3',
          'type': 'new_match',
          'data': bad,
        });
        expect(n.payload, isEmpty, reason: 'data=$bad should degrade to {}');
        expect(n.id, 'n3');
      }
    });

    test('an unparseable created_at is null rather than throwing', () {
      final n = AppNotification.fromRow({
        'id': 'n4',
        'type': 'new_match',
        'created_at': 'not-a-timestamp',
      });
      expect(n.createdAt, isNull);
    });

    test('missing required columns fall back instead of throwing', () {
      final n = AppNotification.fromRow(<String, dynamic>{});
      expect(n.id, '');
      expect(n.isRead, isFalse);
      expect(n.targetUserId, isNull);
      expect(n.targetMatchId, isNull);
      expect(n.targetConversationId, isNull);
    });

    test('an empty-string target id is not treated as a destination', () {
      final n = AppNotification.fromRow({
        'id': 'n5',
        'type': 'new_message',
        'data': {
          'payload': {'conversation_id': ''},
        },
      });
      // An empty id would route to /chat/ which is not a conversation.
      expect(n.targetConversationId, isNull);
    });

    test('copyWith only changes read state', () {
      final original = AppNotification.fromRow({
        'id': 'n6',
        'type': 'new_match',
        'title': 'Title',
        'body': 'Body',
        'data': {
          'payload': {'match_id': 'm-1'},
        },
      });

      final read = original.copyWith(isRead: true);
      expect(read.isRead, isTrue);
      expect(read.id, original.id);
      expect(read.title, original.title);
      expect(read.body, original.body);
      expect(read.targetMatchId, 'm-1');
    });

    test('unreadCount counts only unread entries', () {
      final state = <AppNotification>[
        AppNotification.fromRow({'id': 'a', 'is_read': false}),
        AppNotification.fromRow({'id': 'b', 'is_read': true}),
        AppNotification.fromRow({'id': 'c', 'is_read': false}),
      ];
      expect(state.where((n) => !n.isRead).length, 2);
    });
  });

  group('Report category mapping', () {
    late SafetyRepository repo;

    setUp(() => repo = SafetyRepository());

    test('an underage concern gets its own bucket, not "impersonation"', () {
      // Migration 026 added `underage` to the report_type CHECK. Before that
      // this mapped to `impersonation`, so the most urgent category in a
      // dating app was indistinguishable from "this is a fake account" in the
      // moderation queue.
      expect(repo.mapReportType('Underage'), 'underage');
      expect(repo.mapReportType('This person is a minor'), 'underage');
      expect(repo.mapReportType('child'), 'underage');
      expect(repo.mapReportType('too young'), 'underage');
    });

    test('spam and scam are distinguishable', () {
      expect(repo.mapReportType('Spam'), 'spam');
      expect(repo.mapReportType('Scam'), 'scam');
      expect(repo.mapReportType('Asked me for money (scam)'), 'scam');
      // Deliberately conservative: a label the UI does not offer maps to the
      // generic bucket rather than being guessed at, so it can never fall
      // outside the schema's CHECK constraint. The verbatim label is still
      // preserved in the description for a human moderator.
      expect(repo.mapReportType('asked me for money'), 'profile');
    });

    test('unsafe behaviour is its own bucket', () {
      expect(repo.mapReportType('Unsafe behaviour'), 'unsafe_behavior');
      expect(repo.mapReportType('They made a threat'), 'unsafe_behavior');
    });

    test('the pre-existing buckets still map as they did', () {
      expect(repo.mapReportType('Harassment'), 'harassment');
      expect(repo.mapReportType('Fake profile'), 'impersonation');
      expect(repo.mapReportType('Inappropriate photo'), 'photo');
      expect(repo.mapReportType('Inappropriate content'), 'inappropriate_content');
      expect(repo.mapReportType('Rude message'), 'message');
    });

    test('an unrecognised reason falls back to "profile"', () {
      // It must still land inside the CHECK constraint rather than being sent
      // through verbatim and rejected by the server.
      expect(repo.mapReportType('   '), 'profile');
      expect(repo.mapReportType('something entirely new'), 'profile');
    });

    test('mapping is case-insensitive', () {
      expect(repo.mapReportType('SPAM'), 'spam');
      expect(repo.mapReportType('uNdErAgE'), 'underage');
    });
  });

  group('LikeOutcome is honest about what the server confirmed', () {
    // Without a configured backend every repository call short-circuits. That
    // is exactly the condition under which the old code reported success: it
    // returned `false` for a like and the caller could not tell "no match" from
    // "not recorded". The outcome enum makes the distinction unrepresentable
    // to get wrong.
    test('a like with no backend reports failed, never matched', () async {
      final repo = MatchRepository();
      final outcome = await repo.recordLike('me', 'them');

      expect(
        outcome,
        LikeOutcome.failed,
        reason: 'an unconfigured backend must never be reported as a match',
      );
      expect(outcome, isNot(LikeOutcome.matched));
    });

    test('recordPass with no backend completes without throwing', () async {
      final repo = MatchRepository();
      // Must not throw: the discovery card awaits this on every pass.
      await expectLater(repo.recordPass('me', 'them'), completes);
    });

    test('fetchMatches with no backend returns an empty list', () async {
      final repo = MatchRepository();
      expect(await repo.fetchMatches('me'), isEmpty);
    });

    test('fetchReceivedLikes with no backend returns an empty list', () async {
      final repo = MatchRepository();
      expect(await repo.fetchReceivedLikes(), isEmpty);
    });

    test('unmatchMatch with no backend reports false', () async {
      final repo = MatchRepository();
      expect(await repo.unmatchMatch('m-1'), isFalse);
    });

    test('the three outcomes are distinct values', () {
      // Guards against a refactor collapsing two of them, which would silently
      // restore the original bug.
      expect(LikeOutcome.values.length, 3);
      expect(LikeOutcome.matched, isNot(LikeOutcome.recorded));
      expect(LikeOutcome.recorded, isNot(LikeOutcome.failed));
      expect(LikeOutcome.matched, isNot(LikeOutcome.failed));
    });
  });

  group('ReceivedLike', () {
    test('carries the stand-out flag that was previously write-only', () {
      final like = ReceivedLike(
        profile: const UserProfile(id: 'u-1', name: 'Ada', age: 30, gender: 'Woman', photos: [], city: 'Lisbon'),
        isStandOut: true,
        likedAt: DateTime.utc(2026, 1, 1),
      );

      expect(like.isStandOut, isTrue);
      expect(like.profile.id, 'u-1');
      expect(like.likedAt, isNotNull);
    });

    test('defaults are inert rather than invented', () {
      final like = ReceivedLike(profile: const UserProfile(id: 'u-2', name: 'Grace', age: 28, gender: 'Man', photos: [], city: 'Porto'));
      expect(like.isStandOut, isFalse);
      expect(like.likedAt, isNull);
    });
  });
}