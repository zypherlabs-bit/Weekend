import 'package:flutter_test/flutter_test.dart';
import 'package:weekend/models/models.dart';

/// Contract tests for the feature models added with the unified
/// discovery/entitlements work (migrations 031-033). The models are the
/// boundary between the server RPCs and the UI, so every default must be
/// honest: unknown stays empty/zero/neutral, never a plausible fake.
void main() {
  group('MatchItem lifecycle fields', () {
    test('defaults keep legacy backends rendering honestly', () {
      const match = MatchItem(id: 'm1', user: UserProfile(
        id: 'u2',
        name: 'Ada',
        age: 29,
        gender: 'Woman',
        photos: ['https://x/p'],
        city: 'Boulder',
      ));
      expect(match.conversationId, '');
      expect(match.initiationStatus, '');
      expect(match.windowEndsAtMs, 0);
      expect(match.awayMessage, '');
    });

    test('copyWith only overrides the requested fields', () {
      const match = MatchItem(
        id: 'm1',
        user: UserProfile(id: 'u2', name: 'Ada', age: 29, gender: 'Woman', photos: [], city: ''),
        initiationStatus: 'awaiting_you',
        windowEndsAtMs: 1729000000000,
        awayMessage: 'Hiking!',
      );
      final cleared = match.copyWith(awayMessage: '');
      expect(cleared.awayMessage, '');
      expect(cleared.initiationStatus, 'awaiting_you');
      expect(cleared.windowEndsAtMs, 1729000000000);
    });
  });

  group('ChatMessage risk flags', () {
    test('defaults to no flags so an older backend shows no warnings', () {
      const message = ChatMessage(id: 'm', senderId: 'u2', text: 'hi');
      expect(message.riskFlags, isEmpty);
    });

    test('preserves the server-computed flags verbatim', () {
      final message = ChatMessage(
        id: 'm',
        senderId: 'u2',
        text: 'send me 500\$',
        riskFlags: ['url_present', 'money_request'],
      );
      expect(message.riskFlags, ['url_present', 'money_request']);
    });
  });

  group('ReceivedLike', () {
    test('note defaults to empty and isPriority needs weight >= 2', () {
      const normal = ReceivedLike(profile: UserProfile(
        id: 'u2', name: 'Ada', age: 30, gender: 'Woman', photos: [], city: '',
      ));
      expect(normal.note, '');
      expect(normal.isPriority, isFalse);

      const priority = ReceivedLike(
        profile: UserProfile(
          id: 'u2', name: 'Ada', age: 30, gender: 'Woman', photos: [], city: '',
        ),
        priorityWeight: 3,
        note: 'You look like trouble',
      );
      expect(priority.isPriority, isTrue);
      expect(priority.note, 'You look like trouble');
    });
  });

  group('SupportTicket.fromJson', () {
    test('maps a server-confirmed ticket row', () {
      final ticket = SupportTicket.fromJson(const {
        'id': 't-1',
        'subject': 'Cannot upload photos',
        'category': 'technical',
        'status': 'open',
        'priority': 'normal',
        'created_at': '2026-10-19T10:00:00.000Z',
        'updated_at': '2026-10-19T10:00:00.000Z',
      });
      expect(ticket.id, 't-1');
      expect(ticket.subject, 'Cannot upload photos');
      expect(ticket.category, 'technical');
      expect(ticket.status, 'open');
      expect(ticket.createdAtMs, isNonZero);
    });

    test('degrades to neutral values instead of throwing', () {
      final ticket = SupportTicket.fromJson(const {});
      expect(ticket.id, '');
      expect(ticket.status, 'open');
      expect(ticket.priority, 'normal');
      expect(ticket.createdAtMs, 0);
    });
  });

  group('PhotoInsights.fromJson', () {
    test('surface the insufficient-sample state truthfully', () {
      final insights = PhotoInsights.fromJson(const {
        'window_days': 30,
        'minimum_required_impressions': 30,
        'photos': [
          {
            'photo_id': 'p1',
            'storage_path': 'u/photos/a.jpg',
            'is_primary': true,
            'impressions_30d': 4,
            'unique_viewers_30d': 3,
            'sufficient_data': false,
          },
          {
            'photo_id': 'p2',
            'storage_path': 'u/photos/b.jpg',
            'is_primary': false,
            'impressions_30d': 88,
            'unique_viewers_30d': 41,
            'sufficient_data': true,
          },
        ],
      });
      expect(insights.photos, hasLength(2));
      expect(insights.photos[0].hasSufficientData, isFalse, reason:
          'a photo with 4 impressions must never be presented as meaningful');
      expect(insights.photos[1].impressions30d, 88);
      expect(insights.photos[1].isPrimary, isFalse);
    });

    test('empty or malformed payloads degrade to no insights', () {
      final insights = PhotoInsights.fromJson(const {});
      expect(insights.windowDays, 30);
      expect(insights.photos, isEmpty);
    });
  });

  group('SpotlightStatus.fromJson', () {
    test('an inactive window parses inactive', () {
      final status = SpotlightStatus.fromJson(const {'active': false});
      expect(status.active, isFalse);
      expect(status.endsAt, isNull);
    });

    test('an active window keeps the server deadline', () {
      final status = SpotlightStatus.fromJson(const {
        'active': true,
        'ends_at': '2026-10-20T02:00:00.000Z',
        'activations_last_30_days': 2,
      });
      expect(status.active, isTrue);
      expect(status.endsAt, DateTime.parse('2026-10-20T02:00:00.000Z'));
      expect(status.activationsLast30Days, 2);
    });
  });

  group('SurgeState.fromJson', () {
    test('inactive default and threshold passthrough', () {
      expect(SurgeState.fromJson(const {}).active, isFalse);
      final surge = SurgeState.fromJson(const {
        'active': true,
        'city': 'Boulder',
        'threshold': 42,
        'ends_at': '2026-10-19T23:00:00.000Z',
      });
      expect(surge.city, 'Boulder');
      expect(surge.threshold, 42);
      expect(surge.active, isTrue);
    });
  });

  group('EntitlementEntry.fromJson', () {
    test('all-free default grants parse as active system grants', () {
      final entry = EntitlementEntry.fromJson(const {
        'feature': 'spotlight',
        'granted_at': '2026-10-01T00:00:00.000Z',
        'active': true,
      });
      expect(entry.feature, 'spotlight');
      expect(entry.active, isTrue);
      expect(entry.expiresAt, isNull, reason:
          'system_free grants never expire');
    });
  });

  group('OpeningMove.fromJson', () {
    test('slots parse with the server sort order', () {
      final move = OpeningMove.fromJson(const {
        'id': 'om-1',
        'sort_order': 2,
        'prompt': 'Best local food spots?',
        'photo_id': 'p-9',
      });
      expect(move.sortOrder, 2);
      expect(move.prompt, 'Best local food spots?');
      expect(move.photoId, 'p-9');
    });

    test('a missing prompt stays blank rather than rendering placeholder text',
        () {
      final move = OpeningMove.fromJson(const {'sort_order': 1});
      expect(move.prompt, '');
      expect(move.id, '');
    });
  });
}
