import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import '../models/models.dart';

/// Data source for likes, passes and matches.
///
/// Match creation is owned by the database: inserting a like fires the
/// `check_mutual_like` trigger which transactionally creates the match, the
/// conversation and its membership rows. The client therefore never writes to
/// `matches` (RLS forbids it) — it only observes the result.
class MatchRepository {
  SupabaseClient? get _client => SupabaseConfig.client;

  /// Load the signed-in user's matches via the privacy-safe server-side RPC.
  ///
  /// The RPC joins profiles, primary photos, interests and the last message in
  /// a single round trip and never exposes raw coordinates.
  Future<List<MatchItem>> fetchMatches(String userId) async {
    final client = _client;
    if (client == null) return const [];

    try {
      final result = await client.rpc(
        'get_matches_for_user',
        params: {'p_user_id': userId, 'p_limit': 50, 'p_offset': 0},
      );

      return (result as List).map((row) {
        final interests = (row['interests'] as List?)?.cast<String>() ?? [];
        final shared = (row['shared_interests'] as List?)?.cast<String>() ?? [];
        final lastMessageAt = row['last_message_time'] as String?;

        return MatchItem(
          id: row['match_id'] as String? ?? '',
          user: UserProfile(
            id: row['other_user_id'] as String? ?? '',
            name: row['display_name'] as String? ?? 'User',
            age: row['age'] as int? ?? 25,
            gender: row['gender'] as String? ?? 'Prefer not to say',
            photos: _photosFromUrl(row['primary_photo_url'] as String?),
            city: row['city'] as String? ?? '',
            distanceKm: (row['distance_km'] as num?)?.round() ?? 0,
            bio: row['bio'] as String? ?? '',
            relationshipIntent:
                row['relationship_intent'] as String? ?? 'Dating',
            interests: interests,
            isPhotoVerified: row['is_photo_verified'] as bool? ?? false,
            trustScore: row['trust_score'] as int? ?? 50,
            commonInterests: shared,
          ),
          matchedAt: DateTime.tryParse(
                row['matched_at'] as String? ?? '',
              )?.millisecondsSinceEpoch ??
              0,
          lastMessage: row['last_message_text'] as String? ?? '',
          lastMessageTime: lastMessageAt == null
              ? 'Just now'
              : _formatRelativeTime(DateTime.parse(lastMessageAt)),
          unreadCount: row['unread_count'] as int? ?? 0,
          sharedInterests: shared,
        );
      }).toList();
    } catch (e) {
      return [];
    }
  }

  /// Record a like. Returns `true` when the like completes a mutual match.
  ///
  /// Duplicate likes are absorbed gracefully: the `likes` table has a
  /// unique (liker_id, liked_id) constraint, so a repeated swipe is treated
  /// as a no-op instead of an error.
  Future<bool> recordLike(
    String userId,
    String targetId, {
    bool isStandOut = false,
  }) async {
    final client = _client;
    if (client == null) return false;

    try {
      await client.from('likes').insert({
        'liker_id': userId,
        'liked_id': targetId,
        'is_stand_out': isStandOut,
      });
    } catch (e) {
      // A unique-violation means this like already exists — that is fine.
      // Any other failure means the like was not recorded.
      if (!_isUniqueViolation(e)) return false;
    }

    // The trigger above creates the match when the like is mutual. Observe
    // the authoritative result from the database.
    try {
      final match = await client
          .from('matches')
          .select('id')
          .or('and(user_a_id.eq.$userId,user_b_id.eq.$targetId),and(user_a_id.eq.$targetId,user_b_id.eq.$userId)')
          .maybeSingle();
      return match != null;
    } catch (e) {
      return false;
    }
  }

  /// Record a pass. Duplicate passes are absorbed gracefully.
  Future<void> recordPass(String userId, String targetId) async {
    final client = _client;
    if (client == null) return;

    try {
      await client.from('passes').insert({
        'user_id': userId,
        'target_id': targetId,
      });
    } catch (e) {
      // Unique-violation (already passed) is fine; other errors are logged
      // upstream by the caller.
      if (!_isUniqueViolation(e)) rethrow;
    }
  }

  List<String> _photosFromUrl(String? url) =>
      (url == null || url.isEmpty) ? const [] : <String>[url];

  bool _isUniqueViolation(Object e) =>
      e.toString().contains('duplicate key') ||
      e.toString().contains('23505');

  String _formatRelativeTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

