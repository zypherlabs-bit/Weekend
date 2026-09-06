import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';

class MatchRepository {
  Future<List<MatchItem>> fetchMatches(String userId) async {
    try {
      final matches = await Supabase.instance.client
          .from('matches')
          .select()
          .or('user_a_id.eq.$userId,user_b_id.eq.$userId')
          .order('created_at', ascending: false);
      
      final matchItems = <MatchItem>[];
      
      for (final match in (matches as List)) {
        final otherUserId = match['user_a_id'] == userId 
            ? match['user_b_id'] 
            : match['user_a_id'];
        
        final profileResponse = await Supabase.instance.client
            .from('profiles')
            .select()
            .eq('id', otherUserId)
            .single();
        
        final user = UserProfile(
          id: profileResponse['id'] ?? otherUserId,
          name: profileResponse['display_name'] ?? 'User',
          age: 25,
          gender: profileResponse['gender'] ?? 'Prefer not to say',
          photos: const [],
          city: profileResponse['city'] ?? '',
          distanceKm: 0,
          bio: profileResponse['bio'] ?? '',
          relationshipIntent: profileResponse['relationship_intent'] ?? 'Dating',
          isPhotoVerified: profileResponse['verification_status'] == 'verified',
          trustScore: profileResponse['trust_score'] ?? 50,
        );
        
        matchItems.add(MatchItem(
          id: match['id'],
          user: user,
          matchedAt: DateTime.parse(match['created_at']).millisecondsSinceEpoch,
        ));
      }
      
      return matchItems;
    } catch (e) {
      return [];
    }
  }

  Future<bool> swipeRight(String userId, String targetId, bool isStandOut) async {
    try {
      await Supabase.instance.client.from('likes').insert({
        'liker_id': userId,
        'liked_id': targetId,
        'is_stand_out': isStandOut,
      });
      
      final existingLike = await Supabase.instance.client
          .from('likes')
          .select()
          .eq('liker_id', targetId)
          .eq('liked_id', userId)
          .maybeSingle();
      
      if (existingLike != null) {
        await Supabase.instance.client.from('matches').insert({
          'user_a_id': userId,
          'user_b_id': targetId,
        });
        return true;
      }
      
      return false;
    } catch (e) {
      return false;
    }
  }

  Future<void> swipeLeft(String userId, String targetId) async {
    try {
      await Supabase.instance.client.from('passes').insert({
        'user_id': userId,
        'target_id': targetId,
      });
    } catch (e) {
      // ignore
    }
  }
}
