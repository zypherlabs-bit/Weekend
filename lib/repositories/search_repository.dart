import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import '../models/discovery_preferences.dart';
import '../models/models.dart';
import '../services/photo_url_service.dart';

/// Outcome of a [SearchRepository.search] call.
///
/// [noResultsBecauseFiltered] is deliberately distinct from a transport
/// error: the "no profiles match all your preferences" empty state and the
/// "check your connection" error state must not look the same.
class DiscoverySearchResult {
  final List<UserProfile> profiles;
  final String? error;
  final bool noResultsBecauseFiltered;
  final int page;
  final bool hasMore;

  const DiscoverySearchResult({
    this.profiles = const [],
    this.error,
    this.noResultsBecauseFiltered = false,
    this.page = 1,
    this.hasMore = false,
  });

  bool get isSuccess => error == null;
}

/// Server-side, 100%-hard-filter profile search.
///
/// This class performs **no** client-side filtering. Every criterion the user
/// selected is sent to the `search_profiles` SECURITY DEFINER RPC, which
/// excludes any candidate that fails even one required check. Re-filtering
/// here would be redundant at best and would mask a server bug at worst, so
/// rows are mapped and returned exactly as received.
class SearchRepository {
  SupabaseClient? get _client => SupabaseConfig.client;

  /// Run a filtered search.
  ///
  /// [preferences] is sent verbatim. Dimensions the user left unset are
  /// transmitted as SQL `null`, which the RPC treats as "no restriction" —
  /// never as "match anything".
  Future<DiscoverySearchResult> search(
    String userId,
    DiscoveryPreferences preferences, {
    int page = 1,
    int pageSize = 20,
  }) async {
    final client = _client;
    if (client == null) {
      return const DiscoverySearchResult(
        error:
            'Weekend is not connected to a backend. Rebuild with '
            'SUPABASE_URL and SUPABASE_ANON_KEY to search profiles.',
      );
    }
    if (userId.isEmpty || userId == 'me' || userId == 'unauthenticated') {
      return const DiscoverySearchResult(
        error: 'You are not signed in, so profiles cannot be searched.',
      );
    }

    final effective = preferences.normalized();

    try {
      final result = await client.rpc(
        'search_profiles',
        params: effective.toRpcParams(userId, page: page, pageSize: pageSize),
      );

      final rows = (result as List?) ?? const [];

      // Resolve private storage paths to signed URLs in one batch rather
      // than per card.
      final paths = <String>{
        for (final row in rows)
          if ((row['primary_photo_path'] as String?)?.isNotEmpty ?? false)
            row['primary_photo_path'] as String,
      };
      final photoUrls = await PhotoUrlService.resolve(paths.toList());

      final profiles = <UserProfile>[];
      for (final row in rows) {
        final path = row['primary_photo_path'] as String? ?? '';
        final distanceKm = (row['distance_km'] as num?)?.toDouble();
        final url = photoUrls[path];
        profiles.add(
          UserProfile(
            id: row['profile_id'] as String? ?? '',
            // A blank name shows a neutral placeholder rather than an
            // invented one; the RPC already excludes empty names, so this is
            // only a defensive default.
            name: _displayName(row['display_name']),
            // The RPC returns NULL for an unknown date of birth. That stays 0
            // ("not stated") - never a fabricated age.
            age: (row['age'] as num?)?.toInt() ?? 0,
            gender: row['gender'] as String? ?? '',
            photos: url == null ? const [] : [url],
            city: row['city'] as String? ?? '',
            distanceKm: distanceKm == null ? 0 : distanceKm.round(),
            distanceDisplay: distanceKm == null
                ? ''
                : _formatDistance(distanceKm),
            bio: row['bio'] as String? ?? '',
            relationshipIntent: row['relationship_intent'] as String? ?? '',
            interests:
                (row['interests'] as List?)?.map((e) => e.toString()).toList() ??
                const [],
            isPhotoVerified: row['is_photo_verified'] as bool? ?? false,
            trustScore: (row['trust_score'] as num?)?.toInt() ?? 0,
            // Ranking is a soft signal only; never shown as a compatibility
            // percentage.
            compatibilityExplanation: '',
          ),
        );
      }

      return DiscoverySearchResult(
        profiles: profiles,
        page: page,
        hasMore: rows.length >= pageSize,
        noResultsBecauseFiltered: rows.isEmpty,
      );
    } on PostgrestException catch (e) {
      return DiscoverySearchResult(error: _rpcErrorMessage(e.message));
    } catch (_) {
      return const DiscoverySearchResult(
        error: 'Could not load profiles. Check your connection and try again.',
      );
    }
  }


  static String _displayName(Object? raw) {
    final name = (raw as String? ?? '').trim();
    return name.isEmpty ? 'Weekend member' : name;
  }

  static String _formatDistance(double km) {
    if (km < 1) return '${(km * 1000).round()} m away';
    if (km < 10) return '${km.toStringAsFixed(1)} km away';
    return '${km.round()} km away';
  }

  /// Map an RPC failure to something the user can act on. The "not
  /// authorized" case is the assert_self guard firing, which means the
  /// session is no longer valid for this user.
  static String _rpcErrorMessage(String raw) {
    final msg = raw.toLowerCase();
    if (msg.contains('not authorized')) {
      return 'Your session expired. Please sign in again to search.';
    }
    if (msg.contains('does not exist') && msg.contains('function')) {
      return 'Profile search is unavailable on this backend yet. '
          'Please try again later.';
    }
    if (msg.contains('permission denied') || msg.contains('row-level security')) {
      return 'Profile search was blocked by security policy. Please sign in again.';
    }
    return 'Could not load profiles. Check your connection and try again.';
  }
}

/// Server-reported profile completeness, used to gate the "Start
/// Discovering" action and to render the "add N more photos" copy.
class ProfileCompletion {
  final bool profileExists;
  final int photoCount;
  final int minimumPhotos;
  final bool hasName;
  final bool hasBirthdate;
  final bool hasCity;
  final bool hasBio;

  const ProfileCompletion({
    required this.profileExists,
    required this.photoCount,
    required this.minimumPhotos,
    required this.hasName,
    required this.hasBirthdate,
    required this.hasCity,
    required this.hasBio,
  });

  /// Conservative default used when the backend cannot be reached. It
  /// mirrors the database rule (4) so the UI still communicates the
  /// requirement rather than silently allowing an incomplete profile.
  static const ProfileCompletion unknown = ProfileCompletion(
    profileExists: false,
    photoCount: 0,
    minimumPhotos: 4,
    hasName: false,
    hasBirthdate: false,
    hasCity: false,
    hasBio: false,
  );

  int get photosRemaining =>
      (minimumPhotos - photoCount).clamp(0, minimumPhotos);

  bool get meetsPhotoMinimum => photoCount >= minimumPhotos;

  /// True only when the user may be shown to other people: the server's
  /// minimum-photo rule plus the identity fields every profile needs.
  bool get isComplete => meetsPhotoMinimum && hasName && hasBirthdate && hasCity;

  factory ProfileCompletion.fromJson(Map<String, dynamic> json) {
    return ProfileCompletion(
      profileExists: json['profile_exists'] as bool? ?? false,
      photoCount: (json['photo_count'] as num?)?.toInt() ?? 0,
      minimumPhotos: (json['minimum_photos'] as num?)?.toInt() ?? 4,
      hasName: json['has_name'] as bool? ?? false,
      hasBirthdate: json['has_birthdate'] as bool? ?? false,
      hasCity: json['has_city'] as bool? ?? false,
      hasBio: json['has_bio'] as bool? ?? false,
    );
  }
}

/// Reads the server's view of the current user's profile completeness.
///
/// The client never treats its own constant as the source of truth:
/// [ProfileCompletion.minimumPhotos] is whatever the database reports, so the
/// UI and the discovery filter can never disagree about the rule.
class ProfileCompletionRepository {
  SupabaseClient? get _client => SupabaseConfig.client;

  Future<ProfileCompletion> fetch(String userId) async {
    final client = _client;
    if (client == null) return ProfileCompletion.unknown;
    if (userId.isEmpty || userId == 'me' || userId == 'unauthenticated') {
      return ProfileCompletion.unknown;
    }
    try {
      final result = await client.rpc(
        'get_my_profile_completion',
        params: {'p_user_id': userId},
      );
      if (result is Map<String, dynamic>) {
        return ProfileCompletion.fromJson(result);
      }
      return ProfileCompletion.unknown;
    } catch (_) {
      // A failed lookup must not trap the user; the screen falls back to the
      // locally-known photo count and keeps the requirement visible.
      return ProfileCompletion.unknown;
    }
  }
}
