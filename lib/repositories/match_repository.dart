import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import '../models/models.dart';
import '../services/photo_url_service.dart';

/// Data source for likes, passes and matches.
///
/// Match creation is owned by the database: inserting a like fires the
/// `check_mutual_like` trigger which transactionally creates the match, the
/// conversation and its membership rows. The client therefore never writes to
/// `matches` (RLS forbids it) — it only observes the result.
/// The result of a like, distinguishing "recorded, and it matched" from
/// "recorded, and it did not" from "not recorded at all".
///
/// A bare bool cannot express all three, and the difference matters: a failed
/// like has to put the card back on the deck, while a successful non-match has
/// to leave it gone. Collapsing them is how a card used to disappear after a
/// network error with no way to retry it.
enum LikeOutcome {
  /// The like was recorded and completed a match.
  matched,

  /// The like was recorded. No match yet.
  recorded,

  /// The like was not recorded. The caller should restore the card.
  failed,
}

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

      final rows = result as List;

      // Resolve private photo storage paths to signed URLs in one batch.
      final paths = rows
          .map((row) => row['primary_photo_path'] as String? ?? '')
          .where((p) => p.isNotEmpty)
          .toSet()
          .toList();
      final photoUrls = await PhotoUrlService.resolve(paths);

      return rows.map((row) {
        final interests = (row['interests'] as List?)?.cast<String>() ?? [];
        final shared = (row['shared_interests'] as List?)?.cast<String>() ?? [];
        final lastMessageAt = row['last_message_time'] as String?;
        final photoPath = row['primary_photo_path'] as String? ?? '';
        final photoUrl = photoUrls[photoPath];
        // Blank rather than a fabricated "User"/25 when the RPC returned no
        // name/age: an invented name on a dating card is worse than none.
        final name = (row['display_name'] as String? ?? '').trim();

        return MatchItem(
          id: row['match_id'] as String? ?? '',
          user: UserProfile(
            id: row['other_user_id'] as String? ?? '',
            name: name.isEmpty ? 'Weekend member' : name,
            age: row['age'] as int? ?? 0,
            gender: row['gender'] as String? ?? 'Prefer not to say',
            photos: photoUrl == null ? const [] : <String>[photoUrl],
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
          // An absent last message means "no messages yet" — reporting it as
          // "Just now" invented an activity timestamp that never happened.
          lastMessageTime: lastMessageAt == null
              ? 'No messages yet'
              : _formatRelativeTime(DateTime.parse(lastMessageAt)),
          unreadCount: row['unread_count'] as int? ?? 0,
          sharedInterests: shared,
        );
      }).toList();
    } catch (e) {
      return [];
    }
  }

  /// Record a like, reporting precisely what happened.
  ///
  /// Routed through the `record_like` RPC (migration 026) instead of an INSERT
  /// followed by a separate read of `matches`. That second query was both a
  /// round trip and a race: it reported a match whenever one happened to exist
  /// for the pair, including when *this* like had failed to insert at all.
  ///
  /// The RPC also refuses a like when either party has blocked the other. The
  /// `likes` INSERT policy only ever checked `liker_id = auth.uid()`, so
  /// blocking someone did not stop them being liked back.
  ///
  /// Duplicate likes are absorbed: `record_like` upserts, and the unique
  /// (liker_id, liked_id) constraint still backs that up.
  Future<LikeOutcome> recordLike(
    String userId,
    String targetId, {
    bool isStandOut = false,
  }) async {
    final client = _client;
    if (client == null) return LikeOutcome.failed;

    try {
      final result = await client.rpc(
        'record_like',
        params: {
          'p_target_id': targetId,
          'p_is_stand_out': isStandOut,
        },
      );

      final data = Map<String, dynamic>.from(result as Map);

      // `liked: false` means the server refused - it is distinct from
      // "liked, no match", which is a successful interaction.
      if (data['liked'] != true) return LikeOutcome.failed;
      return data['matched'] == true
          ? LikeOutcome.matched
          : LikeOutcome.recorded;
    } catch (_) {
      // A failed like must never be reported as a match, and must never be
      // silently treated as success either.
      return LikeOutcome.failed;
    }
  }

  /// Record a pass.
  ///
  /// Routed through `record_pass`, which is idempotent and additionally
  /// withdraws any outstanding like from this user to the same person — a pass
  /// that left a live like behind kept the target matchable.
  Future<void> recordPass(String userId, String targetId) async {
    final client = _client;
    if (client == null) return;

    await client.rpc('record_pass', params: {'p_target_id': targetId});
  }

  /// End a match and discard the conversation that came with it.
  ///
  /// There was no way to do this before: `matches` had SELECT-only RLS and no
  /// client call site existed anywhere. `unmatch_match` deletes the match
  /// (cascading to conversations, members and messages) and clears the like and
  /// pass rows for the pair, so a later like can genuinely re-match.
  ///
  /// Returns `false` when the match does not exist or is not this user's.
  Future<bool> unmatchMatch(String matchId) async {
    final client = _client;
    if (client == null) return false;

    final result = await client.rpc(
      'unmatch_match',
      params: {'p_match_id': matchId},
    );
    return result == true;
  }

  /// People who liked this user and did not become a match.
  ///
  /// This surface did not exist at any layer. The `likes` SELECT policy
  /// permitted reading inbound likes, but nothing ever queried it, so a
  /// one-sided like produced no notification and no UI anywhere in the app.
  ///
  /// Mutual likes are excluded server-side: those are matches and belong on the
  /// matches tab.
  Future<List<ReceivedLike>> fetchReceivedLikes({
    int limit = 50,
    int offset = 0,
  }) async {
    final client = _client;
    if (client == null) return const [];

    final result = await client.rpc(
      'get_received_likes',
      params: {'p_limit': limit, 'p_offset': offset},
    );

    final rows = result as List;
    final paths = rows
        .map((row) => row['primary_photo_path'] as String? ?? '')
        .where((p) => p.isNotEmpty)
        .toSet()
        .toList();
    final photoUrls = await PhotoUrlService.resolve(paths);

    return rows.map((row) {
      final photoPath = row['primary_photo_path'] as String? ?? '';
      final photoUrl = photoUrls[photoPath];
      // Blank rather than a fabricated name on a card, for the same reason
      // `fetchMatches` does it.
      final name = (row['display_name'] as String? ?? '').trim();

      return ReceivedLike(
        profile: UserProfile(
          id: row['other_user_id'] as String? ?? '',
          name: name.isEmpty ? 'Weekend member' : name,
          age: row['age'] as int? ?? 0,
          gender: row['gender'] as String? ?? 'Prefer not to say',
          photos: photoUrl == null ? const [] : <String>[photoUrl],
          city: row['city'] as String? ?? '',
          bio: row['bio'] as String? ?? '',
          relationshipIntent:
              row['relationship_intent'] as String? ?? 'Dating',
          isPhotoVerified: row['is_photo_verified'] as bool? ?? false,
          trustScore: row['trust_score'] as int? ?? 50,
        ),
        // Surfaced so the card can be marked: `is_stand_out` was a write-only
        // column that no query ever read back.
        isStandOut: row['is_stand_out'] as bool? ?? false,
        likedAt: DateTime.tryParse(row['liked_at'] as String? ?? ''),
      );
    }).toList();
  }

  String _formatRelativeTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

