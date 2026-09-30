// Tests for the DateIdeasRepository and the generateDateIdeas provider method.
//
// The Supabase client is not available in the unit-test environment, so these
// tests assert the guards that must hold when the backend is absent: a fetch
// must return an honest empty result, never fabricated date ideas.
import 'package:flutter_test/flutter_test.dart';

import 'package:weekend/config/supabase_config.dart';
import 'package:weekend/repositories/date_ideas_repository.dart';

void main() {
  group('SupabaseConfig live-only guarantee', () {
    test('is unconfigured in the test environment', () {
      expect(SupabaseConfig.isConfigured, isFalse,
          reason:
              'dart-defines must not be present when running unit tests');
      expect(SupabaseConfig.client, isNull);
    });
  });

  group('DateIdeasRepository.fetchDateIdeas', () {
    test('returns empty fallback when no backend is configured', () async {
      final repo = DateIdeasRepository();
      final (ideas, source) = await repo.fetchDateIdeas(
        city: 'Pune',
        userInterests: ['Coffee', 'Music'],
        partnerInterests: ['Art', 'Travel'],
      );

      expect(ideas, isEmpty,
          reason: 'A missing backend must never fabricate date ideas');
      expect(source, 'fallback');
    });

    test('returns empty fallback with empty interests', () async {
      final repo = DateIdeasRepository();
      final (ideas, source) = await repo.fetchDateIdeas(
        city: '',
      );

      expect(ideas, isEmpty);
      expect(source, 'fallback');
    });
  });
}
