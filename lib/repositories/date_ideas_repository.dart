import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import '../models/models.dart';

/// Data source for AI-generated date ideas.
///
/// Calls the `date-ideas` Edge Function, which authenticates the caller against
/// the live session and returns three suggestions from Gemini (or four curated
/// fallbacks when the API key is absent or the request fails).
class DateIdeasRepository {
  SupabaseClient? get _client => SupabaseConfig.client;

  /// Fetch date ideas tuned to the shared interests of two users and a city.
  ///
  /// [userInterests] and [partnerInterests] drive the prompt sent to Gemini;
  /// [city] localises the suggestions. Any field may be empty — the Edge
  /// Function falls back to defaults when they are.
  ///
  /// Returns the ideas and the source label (`'gemini'` or `'fallback'`) so the
  /// UI can surface a fallback explanation when applicable.
  Future<(List<DateIdea>, String)> fetchDateIdeas({
    required String city,
    List<String> userInterests = const [],
    List<String> partnerInterests = const [],
  }) async {
    final client = _client;
    if (client == null) return (const <DateIdea>[], 'fallback');

    try {
      final response = await client.functions.invoke(
        'date-ideas',
        body: {
          'userInterests': userInterests,
          'partnerInterests': partnerInterests,
          'city': city,
        },
      );

      if (response.data == null) return (const <DateIdea>[], 'fallback');

      final data = response.data as Map<String, dynamic>;
      final source = (data['source'] as String?) ?? 'fallback';

      final rawIdeas = (data['ideas'] as List?) ?? const [];
      final ideas = <DateIdea>[
        for (final raw in rawIdeas)
          DateIdea(
            title: (raw['title'] as String? ?? '').trim(),
            venueType: (raw['venueType'] as String? ?? '').trim(),
            description: (raw['description'] as String? ?? '').trim(),
            estimatedBudget: (raw['estimatedBudget'] as String? ?? '').trim(),
            conversationTip: (raw['conversationTip'] as String? ?? '').trim(),
          )
      ];
      ideas.removeWhere((idea) => idea.title.isEmpty);

      return (ideas, source);
    } catch (e) {
      return (const <DateIdea>[], 'fallback');
    }
  }
}
