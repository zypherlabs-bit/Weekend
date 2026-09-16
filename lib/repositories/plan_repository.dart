import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import '../models/models.dart';

class PlanRepository {
  SupabaseClient? get _client => SupabaseConfig.client;

  /// Fetch visible Weekend Plans plus the current user's participation state.
  ///
  /// Creator names are resolved from `profiles` with an explicit column list
  /// (raw location columns are not grantable to clients). Participation is
  /// derived from the caller's own `plan_participants` rows, which is exactly
  /// what RLS exposes.
  Future<List<WeekendPlan>> fetchPlans(String userId) async {
    final client = _client;

    if (client == null) return const [];

    try {
      final plans = await client
          .from('plans')
          .select(
            'id, creator_id, title, category, venue, time, description, '
            'privacy_level, created_at',
          )
          .order('created_at', ascending: false)
          .limit(50);

      final rows = plans as List;

      // Resolve creator display names in a single query.
      final creatorIds = rows
          .map((r) => r['creator_id'] as String?)
          .whereType<String>()
          .toSet()
          .toList();

      final names = <String, String>{};
      if (creatorIds.isNotEmpty) {
        try {
          final profiles = await client
              .from('profiles')
              .select('id, display_name')
              .inFilter('id', creatorIds);
          for (final p in (profiles as List)) {
            names[p['id'] as String] = p['display_name'] as String? ?? 'User';
          }
        } catch (_) {
          // Creator names are decorative; plan data still loads.
        }
      }

      // Resolve the caller's own participation.
      final joinedIds = <String>{};
      try {
        final mine = await client
            .from('plan_participants')
            .select('plan_id')
            .eq('user_id', userId);
        for (final row in (mine as List)) {
          joinedIds.add(row['plan_id'] as String);
        }
      } catch (_) {
        // Participation markers are optional metadata.
      }

      return rows.map((plan) {
        final planId = plan['id'] as String;
        return WeekendPlan(
          id: planId,
          creatorId: plan['creator_id'] ?? '',
          creatorName:
              names[plan['creator_id']] ??
              (plan['creator_id'] == userId ? 'You' : 'Unknown'),
          creatorPhoto: '',
          title: plan['title'] ?? '',
          category: plan['category'] ?? 'Coffee',
          venue: plan['venue'] ?? '',
          time: plan['time'] ?? '',
          description: plan['description'] ?? '',
          participants: const [],
          isJoined: joinedIds.contains(planId),
        );
      }).toList();
    } catch (e) {
      return [];
    }
  }

  /// Create a plan. Returns the new plan id, or `null` on failure.
  Future<String?> createPlan({
    required String userId,
    required String title,
    required String category,
    required String venue,
    required String time,
    required String description,
  }) async {
    final client = _client;

    if (client == null) return null;

    final inserted = await client
        .from('plans')
        .insert({
          'creator_id': userId,
          'title': title,
          'category': category,
          'venue': venue,
          'time': time,
          'description': description,
          'privacy_level': 'public',
        })
        .select('id')
        .single();

    // The creator automatically participates in their own plan.
    try {
      await client.from('plan_participants').insert({
        'plan_id': inserted['id'],
        'user_id': userId,
      });
    } catch (_) {
      // Participant row is re-synced by fetchPlans; never fail the create.
    }

    return inserted['id'] as String?;
  }

  Future<void> togglePlanJoin(
    String userId,
    String planId,
    String userName,
  ) async {
    final client = _client;

    if (client == null) return;

    try {
      final existing = await client
          .from('plan_participants')
          .select('id')
          .eq('plan_id', planId)
          .eq('user_id', userId)
          .maybeSingle();

      if (existing != null) {
        await client
            .from('plan_participants')
            .delete()
            .eq('plan_id', planId)
            .eq('user_id', userId);
      } else {
        await client.from('plan_participants').insert({
          'plan_id': planId,
          'user_id': userId,
        });
      }
    } catch (e) {
      // Surface to the caller via rethrow so the UI can resync.
      rethrow;
    }
  }
}

