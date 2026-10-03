import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';

class IcebreakerRepository {
  SupabaseClient? get _client => SupabaseConfig.client;

  /// Calls the `icebreaker` Edge Function to generate a conversation starter.
  ///
  /// Parameters:
  /// - userName: the current user's display name
  /// - matchName: the match's display name
  /// - sharedInterests: interests both users have in common
  /// - favoritePlace: a category/venue type preference (e.g. "cafe")
  ///
  /// Returns the generated icebreaker text, or a fallback if the function
  /// is unavailable or returns no text.
  Future<String> generateIcebreaker({
    required String userName,
    required String matchName,
    required List<String> sharedInterests,
    String favoritePlace = 'cafe',
  }) async {
    final client = _client;
    if (client == null) {
      return _fallback(matchName, sharedInterests);
    }

    try {
      final result = await client.functions.invoke(
        'icebreaker',
        body: {
          'userName': userName,
          'matchName': matchName,
          'sharedInterests': sharedInterests,
          'favoritePlace': favoritePlace,
        },
      );

      final data = result.data;
      if (data is Map<String, dynamic>) {
        final text = data['text'] as String?;
        if (text != null && text.isNotEmpty) return text;
      }
    } catch (_) {
      // Fall through to fallback
    }

    return _fallback(matchName, sharedInterests);
  }

  static String _fallback(String matchName, List<String> interests) {
    if (interests.isNotEmpty) {
      return 'You both love ${interests[0]}! Ask $matchName what got them into it or their favorite spot for it.';
    }
    return 'Ask $matchName about their ideal weekend adventure or their go-to coffee spot!';
  }
}
