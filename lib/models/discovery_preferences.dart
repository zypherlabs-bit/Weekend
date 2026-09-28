import 'package:flutter/material.dart';

/// How a distance preference is interpreted against candidate profiles.
enum LocationMode {
  /// Restrict to profiles within the selected radius of the viewer.
  nearby('nearby', 'Nearby', Icons.near_me_rounded),

  /// Restrict to the viewer's own city, ignoring radius.
  currentCity('current_city', 'Current city', Icons.location_city_rounded),

  /// Restrict to a city the user explicitly picked.
  selectedCity('selected_city', 'Selected city', Icons.map_rounded),

  /// Ignore distance entirely and rank by soft signals.
  explore('explore', 'Explore', Icons.travel_explore_rounded),

  /// Temporarily widen the radius without losing the other filters.
  travel('travel', 'Travel', Icons.flight_takeoff_rounded);

  const LocationMode(this.wireValue, this.label, this.icon);

  /// Value sent to / returned from the `search_profiles` RPC.
  final String wireValue;
  final String label;
  final IconData icon;

  static LocationMode fromWire(String? value) => LocationMode.values.firstWhere(
    (m) => m.wireValue == value,
    orElse: () => LocationMode.nearby,
  );
}

/// Discovery preferences the user sets on the **Preferred Match** screen.
///
/// Every field here is a HARD filter: the server returns a profile only when
/// ALL of the values the user actually set are satisfied. There is no
/// "close enough", no percentage threshold and no client-side post-filtering
/// that could quietly widen a selection.
///
/// A `null`/empty value means "not restricted on this dimension" — that is
/// the only way a filter is skipped. It never means "matches anything".
class DiscoveryPreferences {
  /// Which genders to show. Empty = every gender.
  final List<String> genders;

  /// Inclusive age range. `null` on either end leaves that end open.
  final int? ageMin;
  final int? ageMax;

  /// Maximum discovery radius in kilometres. `null` = no distance limit.
  final double? maxDistanceKm;

  /// Exact city to restrict to (case-insensitive match). `null` = any city.
  final String? city;

  /// Relationship intents to show. Empty = any intent.
  final List<String> relationshipIntents;

  /// Interests a candidate must have ALL of. Empty = no interest filter.
  final List<String> interests;

  /// Languages a candidate must speak. Empty = no language filter.
  final List<String> languages;

  /// Lifestyle values a candidate must match exactly. Keys with an empty
  /// string are ignored, so a cleared control never filters anyone out.
  final Map<String, String> lifestyle;

  /// How distance is interpreted.
  final LocationMode locationMode;

  static const int kMinimumAge = 18;
  static const int kMaximumAge = 100;
  static const double kMaximumDistanceKm = 500;

  const DiscoveryPreferences({
    this.genders = const [],
    this.ageMin,
    this.ageMax,
    this.maxDistanceKm,
    this.city,
    this.relationshipIntents = const [],
    this.interests = const [],
    this.languages = const [],
    this.lifestyle = const {},
    this.locationMode = LocationMode.nearby,
  });

  /// Neutral starting point. Deliberately unrestrictive so a new user is
  /// never shown an empty deck because of filters they never chose.
  const DiscoveryPreferences.unrestricted()
    : genders = const [],
      ageMin = kMinimumAge,
      ageMax = kMaximumAge,
      maxDistanceKm = 50,
      city = null,
      relationshipIntents = const [],
      interests = const [],
      languages = const [],
      lifestyle = const {},
      locationMode = LocationMode.nearby;

  bool get hasAnyFilter =>
      genders.isNotEmpty ||
      ageMin != null ||
      ageMax != null ||
      maxDistanceKm != null ||
      isCityRestricted ||
      relationshipIntents.isNotEmpty ||
      interests.isNotEmpty ||
      languages.isNotEmpty ||
      lifestyle.isNotEmpty;

  /// True when a city filter is actually constraining results. A blank or
  /// whitespace-only value counts as "not set", matching [normalized], so the
  /// empty state never claims a city restriction the server is not applying.
  bool get isCityRestricted {
    final c = city;
    return c != null && c.trim().isNotEmpty;
  }

  /// How many hard filters are currently narrowing the results. Shown in the
  /// UI so the user can see exactly what is constraining the deck.
  int get activeFilterCount {
    var n = 0;
    if (genders.isNotEmpty) n++;
    if (ageMin != null || ageMax != null) n++;
    if (maxDistanceKm != null) n++;
    if (isCityRestricted) n++;
    if (relationshipIntents.isNotEmpty) n++;
    if (interests.isNotEmpty) n++;
    if (languages.isNotEmpty) n++;
    if (lifestyle.isNotEmpty) n++;
    return n;
  }

  /// Human-readable summary used in the "no results" empty state, so the
  /// user can see precisely which constraints produced an empty deck.
  List<String> get activeFilterLabels => [
    if (genders.isNotEmpty) 'Gender: ${genders.join(', ')}',
    if (ageMin != null || ageMax != null)
      'Age: ${ageMin ?? kMinimumAge}–${ageMax ?? kMaximumAge}',
    if (maxDistanceKm != null) 'Within ${_formatKm(maxDistanceKm!)}',
    if (isCityRestricted) 'City: $city',
    if (relationshipIntents.isNotEmpty)
      'Looking for: ${relationshipIntents.join(', ')}',
    if (interests.isNotEmpty) 'Interests: ${interests.join(', ')}',
    if (languages.isNotEmpty) 'Languages: ${languages.join(', ')}',
    for (final e in lifestyle.entries)
      if (e.value.trim().isNotEmpty) '${_labelForKey(e.key)}: ${e.value}',
  ];

  static String _formatKm(double km) =>
      km >= kMaximumDistanceKm ? 'unlimited' : '${km.round()} km';

  static String _labelForKey(String key) => switch (key) {
    'smoking' => 'Smoking',
    'drinking' => 'Drinking',
    'exercise' => 'Exercise',
    'pets' => 'Pets',
    'children' => 'Children',
    _ => key,
  };

  /// Normalised copy: the age range is ordered and clamped to sane bounds,
  /// and empty lifestyle entries are dropped so a cleared control never
  /// excludes every profile.
  DiscoveryPreferences normalized() {
    var min = ageMin;
    var max = ageMax;
    if (min != null && min < kMinimumAge) min = kMinimumAge;
    if (max != null && max > kMaximumAge) max = kMaximumAge;
    if (min != null && max != null && min > max) {
      final t = min;
      min = max;
      max = t;
    }
    return DiscoveryPreferences(
      genders: genders,
      ageMin: min,
      ageMax: max,
      maxDistanceKm: maxDistanceKm,
      city: (city != null && city!.trim().isNotEmpty) ? city!.trim() : null,
      relationshipIntents: relationshipIntents,
      interests: interests,
      languages: languages,
      lifestyle: {
        for (final e in lifestyle.entries)
          if (e.value.trim().isNotEmpty) e.key: e.value.trim(),
      },
      locationMode: locationMode,
    );
  }

  DiscoveryPreferences copyWith({
    List<String>? genders,
    int? ageMin,
    int? ageMax,
    double? maxDistanceKm,
    String? city,
    bool clearCity = false,
    List<String>? relationshipIntents,
    List<String>? interests,
    List<String>? languages,
    Map<String, String>? lifestyle,
    LocationMode? locationMode,
  }) {
    return DiscoveryPreferences(
      genders: genders ?? this.genders,
      ageMin: ageMin ?? this.ageMin,
      ageMax: ageMax ?? this.ageMax,
      maxDistanceKm: maxDistanceKm ?? this.maxDistanceKm,
      city: clearCity ? null : (city ?? this.city),
      relationshipIntents: relationshipIntents ?? this.relationshipIntents,
      interests: interests ?? this.interests,
      languages: languages ?? this.languages,
      lifestyle: lifestyle ?? this.lifestyle,
      locationMode: locationMode ?? this.locationMode,
    );
  }

  /// Wire format for the `search_profiles` RPC. A dimension the user did not
  /// restrict is sent as `null` (SQL "no restriction"), never as a sentinel
  /// value the server would have to guess the intent of.
  Map<String, dynamic> toRpcParams(
    String userId, {
    int page = 1,
    int pageSize = 20,
  }) {
    final p = normalized();
    return {
      'p_user_id': userId,
      'p_genders': p.genders.isEmpty ? null : p.genders,
      'p_age_min': p.ageMin,
      'p_age_max': p.ageMax,
      'p_max_distance_km': p.maxDistanceKm,
      'p_city': p.city,
      'p_relationship_intents': p.relationshipIntents.isEmpty
          ? null
          : p.relationshipIntents,
      'p_interests': p.interests.isEmpty ? null : p.interests,
      'p_languages': p.languages.isEmpty ? null : p.languages,
      'p_lifestyle': p.lifestyle.isEmpty ? null : p.lifestyle,
      'p_location_mode': p.locationMode.wireValue,
      'p_page': page,
      'p_page_size': pageSize,
    };
  }

  Map<String, dynamic> toJson() => {
    'genders': genders,
    'ageMin': ageMin,
    'ageMax': ageMax,
    'maxDistanceKm': maxDistanceKm,
    'city': city,
    'relationshipIntents': relationshipIntents,
    'interests': interests,
    'languages': languages,
    'lifestyle': lifestyle,
    'locationMode': locationMode.name,
  };

  factory DiscoveryPreferences.fromJson(Map<String, dynamic> json) {
    List<String> strList(String key) =>
        (json[key] as List?)?.map((e) => e.toString()).toList() ?? const [];
    return DiscoveryPreferences(
      genders: strList('genders'),
      ageMin: (json['ageMin'] as num?)?.toInt(),
      ageMax: (json['ageMax'] as num?)?.toInt(),
      maxDistanceKm: (json['maxDistanceKm'] as num?)?.toDouble(),
      city: json['city'] as String?,
      relationshipIntents: strList('relationshipIntents'),
      interests: strList('interests'),
      languages: strList('languages'),
      lifestyle:
          (json['lifestyle'] as Map?)?.map(
            (k, v) => MapEntry(k.toString(), v.toString()),
          ) ??
          const {},
      locationMode: LocationMode.values.firstWhere(
        (m) => m.name == json['locationMode'],
        orElse: () => LocationMode.nearby,
      ),
    );
  }

  /// Case-insensitive on every textual dimension so a round-trip through
  /// JSON does not look like a change and re-query the server.
  @override
  bool operator ==(Object other) {
    if (other is! DiscoveryPreferences) return false;
    return _eqList(other.genders, genders) &&
        other.ageMin == ageMin &&
        other.ageMax == ageMax &&
        other.maxDistanceKm == maxDistanceKm &&
        _eqText(other.city, city) &&
        _eqList(other.relationshipIntents, relationshipIntents) &&
        _eqList(other.interests, interests) &&
        _eqList(other.languages, languages) &&
        other.locationMode == locationMode &&
        other.lifestyle.length == lifestyle.length &&
        other.lifestyle.entries.every((e) => _eqText(lifestyle[e.key], e.value));
  }

  static bool _eqList(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_eqText(a[i], b[i])) return false;
    }
    return true;
  }

  static bool _eqText(String? a, String? b) =>
      (a ?? '').trim().toLowerCase() == (b ?? '').trim().toLowerCase();

  @override
  int get hashCode => Object.hash(
    Object.hashAll(genders.map((e) => e.toLowerCase())),
    ageMin,
    ageMax,
    maxDistanceKm,
    city?.toLowerCase(),
    Object.hashAll(relationshipIntents.map((e) => e.toLowerCase())),
    Object.hashAll(interests.map((e) => e.toLowerCase())),
    Object.hashAll(languages.map((e) => e.toLowerCase())),
    locationMode,
    Object.hashAll(
      lifestyle.entries.map((e) => '${e.key}=${e.value.toLowerCase()}'),
    ),
  );
}

/// Canonical option lists for the Preferred Match screen.
///
/// These mirror the CHECK constraints on `public.profiles` (migration 015
/// fixed the relationship-intent typo) and the lifestyle CHECKs added in
/// migration 020. A value outside these lists would be rejected by the
/// database, so the UI cannot offer one.
class PreferredMatchOptions {
  static const List<String> genders = [
    'Woman',
    'Man',
    'Non-binary',
    'Prefer not to say',
  ];

  static const List<String> relationshipIntents = [
    'Long-term relationship',
    'Dating',
    'Dating & Weekend Plans',
    'New people & Friendships',
  ];

  static const List<String> interests = [
    'Specialty Coffee',
    'Hiking',
    'Indie Music',
    'Cycling',
    'Travel',
    'F1',
    'Photography',
    'Plant Parenting',
    'Matcha',
    'Coffee Roasting',
    'Jazz',
    'Baking',
    'Books',
    'Vintage Shopping',
    'Fusion Cooking',
    'Gallery Hopping',
    'Acoustic Gigs',
    'Hill Climbs',
    'Brunch Spots',
    'Waterfall Treks',
    'Cinema',
    'Live Music',
    'Running',
    'Yoga',
    'Board Games',
  ];

  static const List<String> languages = [
    'English',
    'Hindi',
    'Marathi',
    'Bengali',
    'Telugu',
    'Tamil',
    'Kannada',
    'Malayalam',
    'Gujarati',
    'Punjabi',
    'Spanish',
    'French',
    'German',
    'Portuguese',
    'Japanese',
  ];

  /// Distance choices shown as a segmented control.
  static const List<double> distancesKm = [10, 25, 50, 100];

  /// Option values per lifestyle key, matching the SQL CHECK constraints.
  static const Map<String, List<String>> lifestyle = {
    'smoking': ['Never', 'Occasionally', 'Often', 'Prefer not to say'],
    'drinking': ['Never', 'Socially', 'Often', 'Prefer not to say'],
    'exercise': ['Rarely', 'Sometimes', 'Regularly', 'Prefer not to say'],
    'pets': ['None', 'Dog', 'Cat', 'Both', 'Other', 'Prefer not to say'],
    'children': ['No', 'Want later', 'Have', 'Prefer not to say'],
  };

  static const Map<String, String> lifestyleLabels = {
    'smoking': 'Smoking',
    'drinking': 'Drinking',
    'exercise': 'Exercise',
    'pets': 'Pets',
    'children': 'Children',
  };
}

