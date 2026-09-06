import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';

class DiscoveryRepository {
  Future<List<UserProfile>> loadDiscoveryProfiles({
    String userId = '',
    double maxDistanceKm = 50.0,
    int limit = 20,
    int offset = 0,
    String mode = 'nearby',
  }) async {
    try {
      final profiles = await Supabase.instance.client
          .from('profiles')
          .select()
          .neq('id', userId)
          .order('last_active_at', ascending: false)
          .limit(limit);
      
      return (profiles as List).map((profile) {
        return UserProfile(
          id: profile['id'] ?? '',
          name: profile['display_name'] ?? 'Unknown',
          age: 25,
          gender: profile['gender'] ?? 'Prefer not to say',
          photos: const [],
          city: profile['city'] ?? '',
          distanceKm: 0,
          bio: profile['bio'] ?? '',
          occupation: '',
          education: '',
          relationshipIntent: profile['relationship_intent'] ?? 'Dating',
          interests: const [],
          favoritePlaces: const [],
          languages: const [],
          prompts: const [],
          isPhotoVerified: profile['verification_status'] == 'verified',
          trustScore: profile['trust_score'] ?? 50,
          crossedPathsCount: 0,
          favoriteMusic: '',
          idealWeekend: '',
          referralCode: '',
        );
      }).toList();
    } catch (e) {
      return [];
    }
  }

  Future<List<UserProfile>> getNearbyUsers(
    double userLat,
    double userLon, {
    double maxDistanceKm = 10.0,
    int limit = 50,
  }) async {
    try {
      final profiles = await Supabase.instance.client
          .from('profiles')
          .select('id, display_name, gender, city, bio, relationship_intent, verification_status, trust_score, last_active_at')
          .neq('id', '')
          .order('last_active_at', ascending: false)
          .limit(limit);
      
      return (profiles as List).map((row) {
        return UserProfile(
          id: row['id'] ?? '',
          name: row['display_name'] ?? 'Unknown',
          age: 25,
          gender: row['gender'] ?? 'Prefer not to say',
          photos: const [],
          city: row['city'] ?? '',
          distanceKm: 0,
          bio: row['bio'] ?? '',
          occupation: '',
          education: '',
          relationshipIntent: row['relationship_intent'] ?? 'Dating',
          interests: const [],
          favoritePlaces: const [],
          languages: const [],
          prompts: const [],
          isPhotoVerified: row['verification_status'] == 'verified',
          trustScore: row['trust_score'] ?? 50,
          crossedPathsCount: 0,
          referralCode: '',
        );
      }).toList();
    } catch (e) {
      return [];
    }
  }

  Future<void> updateLocation(String userId, double lat, double lon, String city) async {
    try {
      await Supabase.instance.client
          .from('profiles')
          .update({
            'latitude': lat,
            'longitude': lon,
            'city': city,
            'last_active_at': DateTime.now().toIso8601String(),
          })
          .eq('id', userId);
    } catch (e) {
      // ignore
    }
  }
}
