import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import '../models/models.dart';
import '../services/photo_url_service.dart';
import 'profile_save_error.dart';

/// Values the `profiles.gender` CHECK constraint accepts (migration 001).
const Set<String> kAllowedGenders = {
  'Man',
  'Woman',
  'Non-binary',
  'Prefer not to say',
};

/// Values the `profiles.relationship_intent` CHECK constraint accepts
/// (migration 015; the pre-015 typo'd label was migrated away).
const Set<String> kAllowedRelationshipIntents = {
  'Dating',
  'Long-term relationship',
  'New people & Friendships',
  'Dating & Weekend Plans',
};

/// Builds the editable-columns payload for a profile save.
///
/// * Text fields are trimmed.
/// * CHECK-constrained columns are only included when the value is in the
///   allowed set; an invalid/empty value is **omitted** instead of written as
///   NULL, so a save can neither violate a constraint nor erase good data
///   that a placeholder model carried.
/// * `id` is never part of the payload: ownership is always the authenticated
///   session's id, applied by the store (see [ProfileStore.insertOwn]).
@visibleForTesting
Map<String, dynamic> buildProfilePayload(UserProfile profile) {
  String clean(String value) => value.trim();
  String? oneOf(String value, Set<String> allowed) {
    final v = value.trim();
    return allowed.contains(v) ? v : null;
  }

  final payload = <String, dynamic>{
    'display_name': clean(profile.name),
    'bio': clean(profile.bio),
    'city': clean(profile.city),
    'occupation': clean(profile.occupation),
    'education': clean(profile.education),
    'favorite_music': clean(profile.favoriteMusic),
    'ideal_weekend': clean(profile.idealWeekend),
  };
  final gender = oneOf(profile.gender, kAllowedGenders);
  if (gender != null) payload['gender'] = gender;
  final intent = oneOf(profile.relationshipIntent, kAllowedRelationshipIntents);
  if (intent != null) payload['relationship_intent'] = intent;
  return payload;
}

/// The persistence operations the profile-save flow needs.
///
/// Extracted behind this seam so the orphan-recovery orchestration
/// ([saveProfileWithRecovery]) can be unit-tested without a live Supabase
/// client — the unit-test environment has none. Every method is scoped to a
/// single `authId`: there is deliberately no "update any row" operation.
abstract class ProfileStore {
  /// UPDATE rows where `id == authId`; returns the rows actually changed
  /// (PostgREST answers a zero-row UPDATE with an empty list, not an error).
  Future<List<Map<String, dynamic>>> updateOwn(
    String authId,
    Map<String, dynamic> payload,
  );

  /// The caller's own profile id if the row exists, otherwise null.
  Future<Map<String, dynamic>?> fetchOwn(String authId);

  /// INSERT a row for `authId` (the store — not the caller — sets `id`).
  Future<Map<String, dynamic>> insertOwn(
    String authId,
    Map<String, dynamic> payload,
  );
}

/// [ProfileStore] backed by the real Supabase client.
class SupabaseProfileStore implements ProfileStore {
  SupabaseProfileStore(this._client);

  final SupabaseClient _client;

  @override
  Future<List<Map<String, dynamic>>> updateOwn(
    String authId,
    Map<String, dynamic> payload,
  ) async {
    final rows = await _client
        .from('profiles')
        .update(payload)
        .eq('id', authId)
        .select('id')
        .limit(1);
    return rows;
  }

  @override
  Future<Map<String, dynamic>?> fetchOwn(String authId) async {
    final rows = await _client
        .from('profiles')
        .select('id')
        .eq('id', authId)
        .limit(1);
    if (rows.isEmpty) return null;
    return rows.first;
  }

  @override
  Future<Map<String, dynamic>> insertOwn(
    String authId,
    Map<String, dynamic> payload,
  ) async {
    // `id` comes from the session-derived argument, never from the payload.
    final rows = await _client
        .from('profiles')
        .insert({...payload, 'id': authId})
        .select('id')
        .limit(1);
    if (rows.isEmpty) return const <String, dynamic>{};
    return rows.first;
  }
}

/// Saves [payload] for [authId], recovering from a missing profile row.
///
/// Flow:
/// ```text
/// UPDATE ... WHERE id = authId
///   ├── rows returned ──────────────────► success
///   └── 0 rows (PostgREST 200 [], the reported Edit Profile failure)
///         ├── row confirmed missing ───► INSERT (RLS: own id only) ► success
///         ├── row exists ──────────────► PROFILE_UPDATE_NO_ROW (honest failure)
///         └── INSERT raced (23505) ────► retry UPDATE once
/// ```
///
/// [authId] must come from the authenticated session; the payload never
/// carries an id, so a client cannot file a profile under another user.
/// Returns the number of rows written. Throws [ProfileSaveException] with a
/// classified failure — never reports success for an unchanged database.
Future<int> saveProfileWithRecovery({
  required ProfileStore store,
  required String authId,
  required Map<String, dynamic> payload,
}) async {
  try {
    // 1. Normal path: the profile row exists.
    final rows = await store.updateOwn(authId, payload);
    if (rows.isNotEmpty) return rows.length;

    // 2. Zero rows matched. Confirm the row is genuinely missing before
    //    inserting — a stale or filtered write must not fabricate data.
    final existing = await store.fetchOwn(authId);
    if (existing != null) {
      throw const ProfileSaveException(
        ProfileSaveFailure.noRow,
        stage: 'profiles.update',
      );
    }

    // 3. Orphaned auth user: create the missing row under our own id.
    Map<String, dynamic> inserted;
    try {
      inserted = await store.insertOwn(authId, payload);
    } on ProfileSaveException {
      rethrow;
    } catch (e) {
      final raced = e is PostgrestException && e.code == '23505';
      if (!raced) {
        final classified = classifyProfileSaveError(
          e,
          stage: 'profiles.insert',
        );
        classified.log(e.runtimeType.toString());
        throw classified;
      }
      // A concurrent save inserted the row first: retry the UPDATE once.
      final retried = await store.updateOwn(authId, payload);
      if (retried.isNotEmpty) return retried.length;
      throw const ProfileSaveException(
        ProfileSaveFailure.noRow,
        stage: 'profiles.insert.retry',
      );
    }

    // 4. Verify the persisted row really belongs to this session's user.
    if (inserted['id'] == authId) return 1;
    throw const ProfileSaveException(
      ProfileSaveFailure.noRow,
      stage: 'profiles.insert.verify',
    );
  } on ProfileSaveException {
    rethrow;
  } catch (e) {
    final classified = classifyProfileSaveError(e, stage: 'profiles.save');
    classified.log(e.runtimeType.toString());
    throw classified;
  }
}

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
        // Never a fabricated "User": an empty name stays empty so the UI can
        // show the real "add your name" prompt.
        name: (response['display_name'] as String? ?? '').trim(),
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

  /// Persist the authenticated user's editable profile columns.
  ///
  /// Always targets the id from the Supabase **auth session**, never an id
  /// carried on the [UserProfile] instance: app state can hold the neutral
  /// `WeekendState.initial()` placeholder (`id == 'me'`) when the profile has
  /// not loaded yet, and updating that would silently write to zero rows.
  ///
  /// A zero-row UPDATE (PostgREST `200 []` — the reported Edit Profile
  /// failure) no longer ends the save: [saveProfileWithRecovery] confirms the
  /// row is missing and creates it under the session's own id first. The
  /// returned count is always > 0 on success; a save that changed nothing
  /// throws a classified [ProfileSaveException] instead of reporting success.
  ///
  /// Throws [ProfileSaveException] (classified: RLS / constraint / validation
  /// / network / auth / no-row) when the backend rejects the write, and
  /// [StateError] when the app is not configured with live credentials.
  Future<int> updateProfile(UserProfile profile) async {
    final client = _client;
    if (client == null) {
      throw StateError(SupabaseConfig.configError);
    }
    final authId = client.auth.currentUser?.id;
    if (authId == null || authId == 'unauthenticated' || authId == 'me') {
      const error = ProfileSaveException(
        ProfileSaveFailure.auth,
        stage: 'auth.session',
      );
      error.log('no authenticated user');
      throw error;
    }

    return saveProfileWithRecovery(
      store: SupabaseProfileStore(client),
      authId: authId,
      payload: buildProfilePayload(profile),
    );
  }

  /// Upload a profile photo for the authenticated user and register it in
  /// `profile_photos`.
  ///
  /// Order is deliberate: the Storage object is written first, then the
  /// database row. Nothing is treated as "uploaded" until **both** steps have
  /// returned, and the returned value is the private storage *path* (the
  /// bucket is private, so a public URL could never render).
  ///
  /// Throws on any failure so the UI can show the real error. No local file
  /// path is ever stored or returned.
  Future<String> uploadProfilePhoto(
    String userId,
    Uint8List bytes,
    bool isPrimary,
  ) async {
    // Payload validation first: it needs no network and gives the clearest
    // error for the two cases that used to surface much later as an
    // unexplained Storage rejection.
    if (bytes.isEmpty) {
      throw ArgumentError('The selected image is empty.');
    }
    // A truncated or non-image payload would be rejected by the bucket's
    // allowed_mime_types check anyway; fail early with a clear message.
    if (!_looksLikeImage(bytes)) {
      throw ArgumentError(
        'That file is not a readable image. Please choose a JPG, PNG or WebP.',
      );
    }

    final client = _client;
    if (client == null) {
      throw StateError(SupabaseConfig.configError);
    }
    // Ignore any caller-supplied id: the upload is always filed under the
    // signed-in user, matching the Storage RLS folder policy.
    final authId = client.auth.currentUser?.id;
    if (authId == null || authId == 'unauthenticated' || authId == 'me') {
      throw StateError('You are not signed in, so the photo was not uploaded.');
    }

    // ImageOptimizer encodes JPEG; the extension/content type must match or
    // the bucket's allowed_mime_types check rejects the upload.
    final fileName = 'photo_${DateTime.now().microsecondsSinceEpoch}.jpg';
    final path = '$authId/$fileName';

    // Storage upload errors surface as opaque "server error" messages in the
    // UI. Map the common cases (bucket missing / RLS folder mismatch /
    // oversized payload) to actionable text so the user is not stuck.
    try {
      await client.storage
          .from(SupabaseConfig.storageBucket)
          .uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
              contentType: 'image/jpeg',
              upsert: false,
            ),
          );
    } catch (e) {
      throw StateError(_storageErrorMessage(e));
    }

    try {
      // The bucket is private: store the storage PATH (never a public URL) so
      // the client can mint short-lived signed URLs on demand.
      // moderation_status is intentionally omitted: the server decides it
      // (006 demands 'pending' when that trigger is active, 011 rewrites it
      // to the launch default). Sending it from the client risks a trigger
      // rejection that looks like a server error.
      await client.from('profile_photos').insert({
        'user_id': authId,
        'photo_url': path,
        'storage_path': path,
        'is_primary': isPrimary,
        'file_size_bytes': bytes.length,
        'mime_type': 'image/jpeg',
      });
    } catch (e) {
      // The object exists but is unregistered: remove it so the bucket does
      // not accumulate unreferenced private files, then report the real
      // failure instead of a misleading success.
      try {
        await client.storage.from(SupabaseConfig.storageBucket).remove([path]);
      } catch (_) {
        // Best effort cleanup; the original error is what matters.
      }
      Error.throwWithStackTrace(
        StateError(_photoRowErrorMessage(e)),
        StackTrace.current,
      );
    }

    return path;
  }

  /// Map a Storage upload failure to actionable text.
  ///
  /// supabase_flutter surfaces bucket/RLS/size rejections as opaque
  /// `StorageException`s whose message the Edit Profile screen would otherwise
  /// show verbatim ("server error"). The mapping below keeps the ownership
  /// model intact — the fix is always on the caller's request, never a
  /// policy bypass.
  static String _storageErrorMessage(Object e) {
    final msg = e.toString().toLowerCase();
    if (msg.contains('bucket') && msg.contains('not found')) {
      return 'Photo storage is not set up yet (missing profile-photos bucket). '
          'Please try again later.';
    }
    if (msg.contains('row-level security') ||
        msg.contains('rls') ||
        msg.contains('policy') ||
        msg.contains('not authorized') ||
        msg.contains('forbidden')) {
      return 'Photo upload was rejected: please sign out and sign back in, '
          'then try again.';
    }
    if (msg.contains('too large') ||
        msg.contains('payload') ||
        msg.contains('file size') ||
        msg.contains('limit')) {
      return 'That photo is too large. Please choose a smaller image.';
    }
    if (msg.contains('mime') ||
        msg.contains('content-type') ||
        msg.contains('content type')) {
      return 'That file is not a supported image. Please choose a JPG, PNG or WebP.';
    }
    return 'The photo could not be uploaded. Check your connection and try again.';
  }

  /// Map a `profile_photos` insert failure to actionable text.
  ///
  /// The two live causes are a missing profile row (the `user_id` FK points at
  /// `profiles`, which the signup trigger may not have created yet) and an
  /// RLS rejection (the session's `auth.uid()` differs from the upload
  /// folder). Both are reported instead of the raw PostgREST message.
  static String _photoRowErrorMessage(Object e) {
    final msg = e.toString().toLowerCase();
    if (msg.contains('foreign key') ||
        msg.contains('violates foreign key') ||
        msg.contains('23503')) {
      return 'Your profile is not ready yet. Please save your details first, '
          'then add a photo.';
    }
    if (msg.contains('row-level security') ||
        msg.contains('rls') ||
        msg.contains('policy') ||
        msg.contains('42501') ||
        msg.contains('not authorized')) {
      return 'The photo was uploaded but could not be linked to your profile. '
          'Please sign out and sign back in, then try again.';
    }
    if (msg.contains('moderation_status') ||
        msg.contains('moderation')) {
      return 'The photo was uploaded but could not be approved automatically. '
          'Please try again.';
    }
    return 'The photo was uploaded but could not be saved to your profile. '
        'Please try again.';
  }

  /// Cheap magic-byte sniff for JPEG/PNG/WebP so an invalid file is rejected
  /// before it reaches Storage.
  static bool _looksLikeImage(Uint8List b) {
    if (b.length < 12) return false;
    bool startsWith(List<int> sig) {
      for (var i = 0; i < sig.length; i++) {
        if (b[i] != sig[i]) return false;
      }
      return true;
    }

    return startsWith([0xFF, 0xD8, 0xFF]) || // JPEG
        startsWith([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) || // PNG
        startsWith([
          0x52, 0x49, 0x46, 0x46, // RIFF
          0x57, 0x45, 0x42, 0x50, // WEBP
        ]);
  }
}
