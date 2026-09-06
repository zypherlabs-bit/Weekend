import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';

class ProfileRepository {
  Future<UserProfile?> fetchUserProfile(String userId) async {
    try {
      final response = await Supabase.instance.client
          .from('profiles')
          .select()
          .eq('id', userId)
          .single();
      
      return UserProfile(
        id: response['id'] ?? userId,
        name: response['display_name'] ?? 'User',
        age: 18,
        gender: response['gender'] ?? 'Prefer not to say',
        photos: const [],
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
        isPhotoVerified: response['verification_status'] == 'verified',
        trustScore: response['trust_score'] ?? 50,
        crossedPathsCount: 0,
        favoriteMusic: '',
        idealWeekend: '',
        referralCode: '',
      );
    } catch (e) {
      return null;
    }
  }

  Future<List<String>> fetchProfilePhotos(String userId) async {
    try {
      final response = await Supabase.instance.client
          .from('profile_photos')
          .select('photo_url')
          .eq('user_id', userId)
          .eq('moderation_status', 'approved');
      
      return (response as List)
          .map((photo) => photo['photo_url'] as String)
          .toList();
    } catch (e) {
      return [];
    }
  }

  Future<void> updateProfile(UserProfile profile) async {
    await Supabase.instance.client
        .from('profiles')
        .update({
          'display_name': profile.name,
          'bio': profile.bio,
          'city': profile.city,
          'gender': profile.gender,
          'relationship_intent': profile.relationshipIntent,
        })
        .eq('id', profile.id);
  }

  Future<String> uploadProfilePhoto(String userId, Uint8List bytes, bool isPrimary) async {
    final fileName = 'photo_${DateTime.now().millisecondsSinceEpoch}.webp';
    final path = '$userId/$fileName';
    
    await Supabase.instance.client.storage
        .from('profile-photos')
        .uploadBinary(path, bytes, fileOptions: FileOptions(contentType: 'image/webp'));
    
    final publicUrl = Supabase.instance.client.storage
        .from('profile-photos')
        .getPublicUrl(path);
    
    await Supabase.instance.client.from('profile_photos').insert({
      'user_id': userId,
      'photo_url': publicUrl,
      'storage_path': path,
      'is_primary': isPrimary,
      'moderation_status': 'pending',
    });
    
    return publicUrl;
  }
}
