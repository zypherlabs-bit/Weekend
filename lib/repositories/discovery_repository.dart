import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';

import '../models/models.dart';

import '../services/location_service.dart';
import '../services/photo_url_service.dart';

class DiscoveryRepository {
  /// The live Supabase client, or `null` in offline demo mode.
  SupabaseClient? get _client => SupabaseConfig.client;


  /// Load profiles using the privacy-safe server-side RPC.
  /// The RPC `get_nearby_profiles` computes distance server-side and never
  /// exposes raw coordinates to the client.
  Future<List<UserProfile>> loadDiscoveryProfiles({
    required String userId,
    double maxDistanceKm = 50.0,
    int limit = 20,
    int offset = 0,
    String mode = 'nearby',
    double? userLat,
    double? userLon,
    List<String> preferredGenders = const [],
    int ageMin = 18,
    int ageMax = 65,
  }) async {
    final client = _client;

    if (client == null) return const [];

    try {
      final result = await client.rpc(
        'get_nearby_profiles',
        params: {
          'p_user_id': userId,
          'p_limit': limit,
          'p_offset': offset,
          'p_max_distance_km': maxDistanceKm,
          'p_preferred_genders': preferredGenders,
          'p_age_min': ageMin,
          'p_age_max': ageMax,
          'p_discovery_mode': mode,
        },
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
        final distanceKm = (row['distance_km'] as num?)?.toDouble() ?? 0.0;
        final isVerified = row['is_photo_verified'] as bool? ?? false;
        final trustScore = row['trust_score'] as int? ?? 50;
        final compatibilityScore =
            (row['compatibility_score'] as num?)?.toDouble() ?? 0.0;
        final photoPath = row['primary_photo_path'] as String? ?? '';
        final photoUrl = photoUrls[photoPath];

        return UserProfile(
          id: row['profile_id'] as String? ?? '',
          name: row['display_name'] as String? ?? 'Unknown',
          age: row['age'] as int? ?? 25,
          gender: row['gender'] as String? ?? 'Prefer not to say',
          photos: photoUrl == null ? const [] : [photoUrl],
          city: row['city'] as String? ?? '',
          distanceKm: distanceKm.round(),
          distanceDisplay: LocationService.formatDistanceWithAway(distanceKm),
          bio: row['bio'] as String? ?? '',
          occupation: '',
          education: '',
          relationshipIntent: row['relationship_intent'] as String? ?? 'Dating',
          interests: interests,
          favoritePlaces: const [],
          languages: const [],
          prompts: const [],
          isPhotoVerified: isVerified,
          trustScore: trustScore,
          crossedPathsCount: 0,
          favoriteMusic: '',
          idealWeekend: '',
          referralCode: '',
          commonInterests: interests.take(3).toList(),
          weekendAvailability: const {},
          voiceIntroUrl: '',
          compatibilityExplanation: _buildCompatibilityExplanation(
            distanceKm,
            isVerified,
            trustScore,
            compatibilityScore,
          ),
        );
      }).toList();
    } catch (e) {
      return [];
    }
  }

  String _buildCompatibilityExplanation(
    double distanceKm,
    bool isVerified,
    int trustScore,
    double compatibilityScore,
  ) {
    final parts = <String>[];
    if (distanceKm < 5) {
      parts.add('Nearby');
    } else if (distanceKm < 25) {
      parts.add('${distanceKm.round()} km away');
    } else {
      parts.add('${distanceKm.round()} km from you');
    }
    if (isVerified) parts.add('verified');
    if (trustScore > 80) parts.add('high trust');
    return parts.join(' • ');
  }

  /// Fetch profile photos from the privacy-safe storage bucket.
  /// Only approved, moderated photos are returned, as short-lived signed
  /// URLs minted by the `get-photo-urls` Edge Function.
  Future<List<String>> fetchProfilePhotos(String userId) async {
    final client = _client;

    if (client == null) return const [];

    try {
      final response = await client
          .from('profile_photos')
          .select('storage_path')
          .eq('user_id', userId)
          .eq('moderation_status', 'approved')
          .order('is_primary', ascending: false)
          .order('created_at', ascending: false);

      final paths = (response as List)
          .map((photo) => photo['storage_path'] as String? ?? '')
          .where((path) => path.isNotEmpty)
          .toList();

      final resolved = await PhotoUrlService.resolve(paths);
      return [
        for (final p in paths)
          if (resolved.containsKey(p)) resolved[p]!,
      ];
    } catch (e) {
      return [];
    }
  }

  /// Fetch a single profile with full details including photos and interests.
  Future<UserProfile?> fetchFullProfile(
    String userId,
    String currentUserId,
  ) async {
    final client = _client;

    if (client == null) return null;

    try {
      final profile = await client
          .from('profiles')
          .select(
            'id, display_name, gender, city, locality, country, bio, relationship_intent, is_photo_verified, trust_score, last_active_at',
          )
          .eq('id', userId)
          .maybeSingle();

      if (profile == null) return null;

      final photos = await fetchProfilePhotos(userId);

      final interests = await fetchUserInterests(userId);

      final commonInterests = await _fetchCommonInterests(
        userId,
        currentUserId,
      );

      final distanceKm = await _computeDistance(currentUserId, userId);

      return UserProfile(
        id: profile['id'] as String? ?? userId,
        name: profile['display_name'] as String? ?? 'Unknown',
        age: 25,
        gender: profile['gender'] as String? ?? 'Prefer not to say',
        photos: photos,
        city: profile['city'] as String? ?? '',
        distanceKm: distanceKm.round(),
        distanceDisplay: LocationService.formatDistanceWithAway(distanceKm),
        bio: profile['bio'] as String? ?? '',
        occupation: '',
        education: '',
        relationshipIntent:
            profile['relationship_intent'] as String? ?? 'Dating',
        interests: interests,
        favoritePlaces: const [],
        languages: const [],
        prompts: const [],
        isPhotoVerified: profile['is_photo_verified'] as bool? ?? false,
        trustScore: profile['trust_score'] as int? ?? 50,
        crossedPathsCount: 0,
        favoriteMusic: '',
        idealWeekend: '',
        referralCode: '',
        commonInterests: commonInterests,
        weekendAvailability: const {},
        voiceIntroUrl: '',
        compatibilityExplanation: '',
      );
    } catch (e) {
      return null;
    }
  }

  Future<List<String>> fetchUserInterests(String userId) async {
    final client = _client;

    if (client == null) return const [];

    try {
      final result = await client.rpc(
        'get_user_interests',
        params: {'p_user_id': userId},
      );

      if (result == null) return [];
      return (result as List)
          .map((row) => row['name'] as String? ?? '')
          .toList();
    } catch (e) {
      return [];
    }
  }

  Future<List<String>> _fetchCommonInterests(
    String userId,
    String otherUserId,
  ) async {
    final client = _client;
    if (client == null) return const [];
    try {
      final result = await client.rpc(
        'get_user_interests',
        params: {'p_user_id': userId},
      );

      final otherResult = await client.rpc(
        'get_user_interests',
        params: {'p_user_id': otherUserId},
      );

      if (result == null || otherResult == null) return [];

      final userInterests = (result as List)
          .map((row) => row['name'] as String? ?? '')
          .toSet();
      final otherInterests = (otherResult as List)
          .map((row) => row['name'] as String? ?? '')
          .toSet();

      return userInterests.intersection(otherInterests).toList()..sort();
    } catch (e) {
      return [];
    }
  }

  Future<double> _computeDistance(String userId, String otherUserId) async {
    final client = _client;

    if (client == null) return 0.0;

    try {
      final result = await client.rpc(
        'get_nearby_profiles',
        params: {
          'p_user_id': userId,
          'p_limit': 1,
          'p_offset': 0,
          'p_max_distance_km': 10000,
          'p_preferred_genders': <String>[],
          'p_age_min': 18,
          'p_age_max': 100,
          'p_discovery_mode': 'nearby',
        },
      );

      final profiles = result as List;
      final match = profiles.firstWhere(
        (p) => p['profile_id'] == otherUserId,
        orElse: () => null,
      );

      if (match != null) {
        return (match['distance_km'] as num?)?.toDouble() ?? 0.0;
      }
      return 0.0;
    } catch (e) {
      return 0.0;
    }
  }

  /// Update the user's location in Supabase (privacy-safe: stores
  /// raw coordinates for distance computation AND geohash bucket for
  /// crossed-paths detection).
  Future<void> updateLocation({
    required String userId,
    required double lat,
    required double lon,
    required String city,
    String? locality,
    String? country,
  }) async {
    final client = _client;

    if (client == null) return;

    try {
      final geohash = Geohash.encode(lat, lon, precision: 7);
      final approximate = LocationService.toApproximateCoordinates(
        lat,
        lon,
        2.0,
      );

      await client
          .from('profiles')
          .update({
            'latitude': approximate.$1,
            'longitude': approximate.$2,
            'city': city,
            'locality': locality,
            'country': country,
            'last_active_at': DateTime.now().toIso8601String(),
          })
          .eq('id', userId);

      await client.from('user_location_buckets').upsert({
        'user_id': userId,
        'geohash_7': geohash,
        'city': city,
        'locality': locality,
        'country': country,
        'updated_at': DateTime.now().toIso8601String(),
      });

      await computeCrossedPaths(userId, geohash, city, locality, country);
    } catch (e) {
      // ignore
    }
  }

  /// Trigger crossed-paths computation via server-side RPC.
  Future<void> computeCrossedPaths(
    String userId,
    String geohash,
    String? city,
    String? locality,
    String? country,
  ) async {
    final client = _client;

    if (client == null) return;

    try {
      await client.rpc(
        'compute_crossed_paths',
        params: {
          'p_user_id': userId,
          'p_geohash': geohash,
          'p_city': city,
          'p_locality': locality,
          'p_country': country,
        },
      );
    } catch (e) {
      // ignore
    }
  }

  /// Fetch crossed paths for the current user.
  Future<List<CrossedPath>> fetchCrossedPaths(String userId) async {
    final client = _client;

    if (client == null) return const [];

    try {
      final result = await client
          .from('crossed_paths')
          .select()
          .eq('user_a_id', userId)
          .order('last_crossed_at', ascending: false)
          .limit(50);

      return (result as List).map((row) {
        return CrossedPath(
          userBId: row['user_b_id'] as String? ?? '',
          crossCount: row['cross_count'] as int? ?? 1,
          lastCrossedAt: DateTime.parse(
            row['last_crossed_at'] as String? ??
                DateTime.now().toIso8601String(),
          ),
        );
      }).toList();
    } catch (e) {
      return [];
    }
  }

  /// Fetch nearby profiles for the cross-paths discovery mode.
  Future<List<UserProfile>> getNearbyForCrossedPaths(
    String userId,
    double lat,
    double lon, {
    int limit = 20,
  }) async {
    return loadDiscoveryProfiles(
      userId: userId,
      maxDistanceKm: 5,
      limit: limit,
      mode: 'crossed_paths',
    );
  }

  /// Fetch profiles in global mode (no distance filter).
  Future<List<UserProfile>> getGlobalProfiles({
    required String userId,
    int limit = 20,
    String? city,
  }) async {
    final client = _client;

    if (client == null) return const [];

    try {
      if (city != null) {
        final result = await client
            .from('profiles')
            .select(
              'id, display_name, gender, city, bio, relationship_intent, verification_status, trust_score, last_active_at',
            )
            .eq('city', city)
            .neq('id', userId)
            .order('last_active_at', ascending: false)
            .limit(limit);

        return _mapGlobalProfiles(result as List, userId);
      }

      return loadDiscoveryProfiles(
        userId: userId,
        maxDistanceKm: 10000,
        limit: limit,
        mode: 'global',
      );
    } catch (e) {
      return [];
    }
  }

  List<UserProfile> _mapGlobalProfiles(List<dynamic> rows, String userId) {
    return rows.map((row) {
      return UserProfile(
        id: row['id'] as String? ?? '',
        name: row['display_name'] as String? ?? 'Unknown',
        age: 25,
        gender: row['gender'] as String? ?? 'Prefer not to say',
        photos: const [],
        city: row['city'] as String? ?? '',
        distanceKm: 0,
        distanceDisplay: '',
        bio: row['bio'] as String? ?? '',
        relationshipIntent: row['relationship_intent'] as String? ?? 'Dating',
        isPhotoVerified: row['verification_status'] == 'verified',
        trustScore: row['trust_score'] as int? ?? 50,
        commonInterests: const [],
        weekendAvailability: const {},
        voiceIntroUrl: '',
        compatibilityExplanation: 'From ${row['city'] ?? 'your area'}',
      );
    }).toList();
  }
}
