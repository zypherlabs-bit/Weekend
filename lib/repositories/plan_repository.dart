import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';

class PlanRepository {
  Future<List<WeekendPlan>> fetchPlans(String userId) async {
    try {
      final plans = await Supabase.instance.client
          .from('plans')
          .select()
          .order('created_at', ascending: false);
      
      return (plans as List).map((plan) {
        return WeekendPlan(
          id: plan['id'],
          creatorId: plan['creator_id'],
          creatorName: plan['creator_name'] ?? 'Unknown',
          creatorPhoto: plan['creator_photo'] ?? '',
          title: plan['title'] ?? '',
          category: plan['category'] ?? 'Coffee',
          venue: plan['venue'] ?? '',
          time: plan['time'] ?? '',
          description: plan['description'] ?? '',
          isJoined: false,
        );
      }).toList();
    } catch (e) {
      return [];
    }
  }

  Future<void> createPlan({
    required String userId,
    required String title,
    required String category,
    required String venue,
    required String time,
    required String description,
  }) async {
    await Supabase.instance.client.from('plans').insert({
      'creator_id': userId,
      'title': title,
      'category': category,
      'venue': venue,
      'time': time,
      'description': description,
      'privacy_level': 'public',
    });
  }

  Future<void> togglePlanJoin(String userId, String planId, String userName) async {
    final existing = await Supabase.instance.client
        .from('plan_participants')
        .select()
        .eq('plan_id', planId)
        .eq('user_id', userId)
        .maybeSingle();
    
    if (existing != null) {
      await Supabase.instance.client
          .from('plan_participants')
          .delete()
          .eq('plan_id', planId)
          .eq('user_id', userId);
    } else {
      await Supabase.instance.client.from('plan_participants').insert({
        'plan_id': planId,
        'user_id': userId,
      });
    }
  }
}
