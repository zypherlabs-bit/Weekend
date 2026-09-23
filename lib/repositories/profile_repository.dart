import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import '../models/models.dart';
import '../services/photo_url_service.dart';

class ProfileRepository {
  SupabaseClient? get _client => SupabaseConfig.client;

  /// Fetch the real profile row for [userId].
  ///
  /// Column list is explicit because raw location columns on `profiles` are
  /// not grantable to clients (migration 006) — a `select *` would fail.
  Future<UserProfile?> fetchUserProfile(String userId) async {
    final client = _client;

    if (client == null) return null;

    try {
      final response = await client
          .from('profiles')
          .select(
            'id, display_name, date_of_birth, gender, bio, city, '
            'relationship_intent, occupation, education, favorite_music, '
            'ideal_weekend, verification_status, is_photo_verified, '
            'trust_score, referral_code',
          )
          .eq('id', userId)
          .single();

      final dateOfBirth = DateTime.tryParse(
        response['date_of_birth'] as String? ?? '',
      );

      // Resolve approved photos (private bucket -> signed URLs).
      final photoUrls = await fetchProfilePhotos(userId);

      return UserProfile(
        id: response['id'] ?? userId,
        name: response['display_name'] ?? 'User',
        age: dateOfBirth == null
            ? 18
            : DateTime.now().difference(dateOfBirth).inDays ~/ 365,
        gender: response['gender'] ?? 'Prefer not to say',
        photos: photoUrls,
        city: response['city'] ?? '',
        distanceKm: 0,
        bio: response['bio'] ?? '',
        occupation: response['occupation'] ?? '',
        education: response['education'] ?? '',
        relationshipIntent: response['relationship_intent'] ?? 'Dating',
        interests: const [],
        favoritePlaces: const [],
        languages: const [],
        prompts: const [],
        isPhotoVerified:
            (response['is_photo_verified'] as bool? ?? false) ||
            response['verification_status'] == 'verified',
        trustScore: response['trust_score'] ?? 50,
        crossedPathsCount: 0,
        favoriteMusic: response['favorite_music'] ?? '',
        idealWeekend: response['ideal_weekend'] ?? '',
        referralCode: response['referral_code'] ?? '',
      );
    } catch (e) {
      return null;
    }
  }

  Future<List<String>> fetchProfilePhotos(String userId) async {
    final client = _client;

    if (client == null) return const [];

    try {
      final response = await client
          .from('profile_photos')
          .select('storage_path')
          .eq('user_id', userId)
          .eq('moderation_status', 'approved');

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

  Future<void> updateProfile(UserProfile profile) async {
    final client = _client;

    if (client == null) return;

    try {
      await client
          .from('profiles')
          .update({
            'display_name': profile.name,

            'bio': profile.bio,

            'city': profile.city,

            'gender': profile.gender,

            'relationship_intent': profile.relationshipIntent,

            'occupation': profile.occupation,

            'education': profile.education,

            'favorite_music': profile.favoriteMusic,

            'ideal_weekend': profile.idealWeekend,
          })
          .eq('id', profile.id);
    } catch (e) {
      // ignore
    }
  }

  Future<String> uploadProfilePhoto(
    String userId,
    Uint8List bytes,
    bool isPrimary,
  ) async {
    final client = _client;
    if (client == null) return '';
    // ImageOptimizer encodes JPEG; the extension/content type must match or
    // the bucket's allowed_mime_types check rejects the upload.
    final fileName = 'photo_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final path = '$userId/$fileName';

    await client.storage
        .from('profile-photos')
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: 'image/jpeg'),
        );

    // The bucket is private: store the storage PATH (never a public URL) so
    // the client can mint short-lived signed URLs on demand.
    await client.from('profile_photos').insert({
      'user_id': userId,
      'photo_url': path,
      'storage_path': path,
      'is_primary': isPrimary,
      // moderation_status is decided server-side (see migration 011).
    });

    return path;
  }
}
