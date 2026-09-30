import 'profile_schema.dart';

/// Immutable description of an ADVANCED SEARCH request.
///
/// Every field maps 1:1 to a parameter of the `search_profiles` Postgres
/// function, which is where the filters are actually enforced. The client
/// never filters a downloaded list itself - it sends this and renders exactly
/// what the database returns.
///
/// `null` / empty means "not filtered". There is deliberately no "ignore age"
/// escape hatch: [ageMin] and [ageMax] are a hard filter, and a profile whose
/// age is unknown is excluded rather than silently passed.
class SearchFilters {
  /// Maximum distance from the search origin, in kilometres.
  final double maxDistanceKm;

  /// Explicit search origin, used by Travel and Explore. When null the
  /// database uses the seeker's own stored position.
  ///
  /// These are the SEEKER's coordinates (or a destination they typed and the
  /// app geocoded). No other user's coordinates ever reach the client.
  final double? searchLat;
  final double? searchLon;

  /// Free-text city, kept for display and for the city hard filter.
  final String? searchCity;

  /// Genders to show.
  final List<String> genders;

  /// Who the seeker is interested in. Same vocabulary as [genders].
  final List<String> interestedIn;

  final int? ageMin;
  final int? ageMax;

  final List<String> relationshipIntents;
  final List<String> cities;
  final List<String> interests;
  final List<String> languages;

  final String? smoking;
  final String? drinking;
  final String? exercise;
  final String? children;
  final String? pets;

  /// Include profiles the user has already liked, passed or matched.
  ///
  /// Off by default: those are excluded from the deck. Turning it on is how
  /// the user searches a wider population deliberately.
  final bool includeDealt;

  const SearchFilters({
    this.maxDistanceKm = 50,
    this.searchLat,
    this.searchLon,
    this.searchCity,
    this.genders = const [],
    this.interestedIn = const [],
    this.ageMin,
    this.ageMax,
    this.relationshipIntents = const [],
    this.cities = const [],
    this.interests = const [],
    this.languages = const [],
    this.smoking,
    this.drinking,
    this.exercise,
    this.children,
    this.pets,
    this.includeDealt = false,
  });

  /// True when the user has narrowed the search in any way.
  bool get hasActiveFilters =>
      genders.isNotEmpty ||
      interestedIn.isNotEmpty ||
      ageMin != null ||
      ageMax != null ||
      relationshipIntents.isNotEmpty ||
      cities.isNotEmpty ||
      interests.isNotEmpty ||
      languages.isNotEmpty ||
      smoking != null ||
      drinking != null ||
      exercise != null ||
      children != null ||
      pets != null;

  /// A short human summary for the "N filters active" affordance.
  int get activeFilterCount {
    var n = 0;
    if (genders.isNotEmpty) n++;
    if (interestedIn.isNotEmpty) n++;
    if (ageMin != null || ageMax != null) n++;
    if (relationshipIntents.isNotEmpty) n++;
    if (cities.isNotEmpty) n++;
    if (interests.isNotEmpty) n++;
    if (languages.isNotEmpty) n++;
    if (smoking != null) n++;
    if (drinking != null) n++;
    if (exercise != null) n++;
    if (children != null) n++;
    if (pets != null) n++;
    return n;
  }

  /// Reset everything except the radius and the chosen origin, which are the
  /// user's discovery context rather than a filter.
  SearchFilters cleared() => SearchFilters(
    maxDistanceKm: maxDistanceKm,
    searchLat: searchLat,
    searchLon: searchLon,
    searchCity: searchCity,
  );

  SearchFilters copyWith({
    double? maxDistanceKm,
    double? searchLat,
    double? searchLon,
    String? searchCity,
    List<String>? genders,
    List<String>? interestedIn,
    int? ageMin,
    int? ageMax,
    List<String>? relationshipIntents,
    List<String>? cities,
    List<String>? interests,
    List<String>? languages,
    String? smoking,
    String? drinking,
    String? exercise,
    String? children,
    String? pets,
    bool? includeDealt,
    bool clearAge = false,
    bool clearSmoking = false,
    bool clearDrinking = false,
    bool clearExercise = false,
    bool clearChildren = false,
    bool clearPets = false,
    bool clearSearchCity = false,
  }) {
    return SearchFilters(
      maxDistanceKm: maxDistanceKm ?? this.maxDistanceKm,
      searchLat: searchLat ?? this.searchLat,
      searchLon: searchLon ?? this.searchLon,
      searchCity: clearSearchCity ? null : (searchCity ?? this.searchCity),
      genders: genders ?? this.genders,
      interestedIn: interestedIn ?? this.interestedIn,
      ageMin: clearAge ? null : (ageMin ?? this.ageMin),
      ageMax: clearAge ? null : (ageMax ?? this.ageMax),
      relationshipIntents: relationshipIntents ?? this.relationshipIntents,
      cities: cities ?? this.cities,
      interests: interests ?? this.interests,
      languages: languages ?? this.languages,
      smoking: clearSmoking ? null : (smoking ?? this.smoking),
      drinking: clearDrinking ? null : (drinking ?? this.drinking),
      exercise: clearExercise ? null : (exercise ?? this.exercise),
      children: clearChildren ? null : (children ?? this.children),
      pets: clearPets ? null : (pets ?? this.pets),
      includeDealt: includeDealt ?? this.includeDealt,
    );
  }

  /// Wire format for the `search_profiles` RPC.
  ///
  /// Empty arrays stay empty (the function treats that as "no filter"); nulls
  /// stay null so the function's own default applies. Nothing is invented
  /// here - the database re-validates every value.
  Map<String, dynamic> toRpcParams(
    String userId, {
    int limit = 20,
    int offset = 0,
  }) {
    return <String, dynamic>{
      'p_user_id': userId,
      'p_limit': limit,
      'p_offset': offset,
      'p_max_distance_km': maxDistanceKm,
      'p_search_lat': searchLat,
      'p_search_lon': searchLon,
      'p_search_city': searchCity,
      'p_genders': genders,
      'p_age_min': ageMin,
      'p_age_max': ageMax,
      'p_interested_in': interestedIn,
      'p_relationship_intents': relationshipIntents,
      'p_cities': cities,
      'p_interests': interests,
      'p_languages': languages,
      'p_smoking': smoking,
      'p_drinking': drinking,
      'p_exercise': exercise,
      'p_children': children,
      'p_pets': pets,
      'p_include_dealt': includeDealt,
    };
  }

  @override
  bool operator ==(Object other) =>
      other is SearchFilters &&
      other.maxDistanceKm == maxDistanceKm &&
      other.searchLat == searchLat &&
      other.searchLon == searchLon &&
      other.searchCity == searchCity &&
      _listEquals(other.genders, genders) &&
      _listEquals(other.interestedIn, interestedIn) &&
      other.ageMin == ageMin &&
      other.ageMax == ageMax &&
      _listEquals(other.relationshipIntents, relationshipIntents) &&
      _listEquals(other.cities, cities) &&
      _listEquals(other.interests, interests) &&
      _listEquals(other.languages, languages) &&
      other.smoking == smoking &&
      other.drinking == drinking &&
      other.exercise == exercise &&
      other.children == children &&
      other.pets == pets &&
      other.includeDealt == includeDealt;

  @override
  int get hashCode => Object.hash(
    maxDistanceKm,
    searchLat,
    searchLon,
    searchCity,
    Object.hashAll(genders),
    Object.hashAll(interestedIn),
    ageMin,
    ageMax,
    Object.hashAll(relationshipIntents),
    Object.hashAll(cities),
    Object.hashAll(interests),
    Object.hashAll(languages),
    smoking,
    drinking,
    exercise,
    children,
    pets,
    includeDealt,
  );
}

bool _listEquals(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// One page of search results plus the metadata the UI needs.
class SearchResults {
  final List<UserProfile> profiles;

  /// True when the server returned fewer rows than requested, i.e. the end of
  /// the result set was reached.
  final bool reachedEnd;

  const SearchResults({required this.profiles, required this.reachedEnd});
}

class ProfilePrompt {
  /// Stable id from [ProfileSchema]. Empty for a legacy answer stored before
  /// the catalogue existed; [questionText] then falls back to [prompt].
  final String id;

  /// The question as displayed. Kept alongside the id so re-wording the
  /// catalogue never rewrites what the user actually answered.
  final String prompt;

  final String answer;

  const ProfilePrompt({
    required this.prompt,
    required this.answer,
    this.id = '',
  });

  /// The question to render, preferring the live catalogue text.
  String get questionText => ProfileSchema.promptQuestion(id, prompt);

  ProfilePrompt copyWith({String? id, String? prompt, String? answer}) {
    return ProfilePrompt(
      id: id ?? this.id,
      prompt: prompt ?? this.prompt,
      answer: answer ?? this.answer,
    );
  }

  Map<String, dynamic> toJson() => {
    if (id.isNotEmpty) 'id': id,
    'prompt': prompt,
    'answer': answer,
  };

  factory ProfilePrompt.fromJson(Map<String, dynamic> json) => ProfilePrompt(
    id: (json['id'] as String?) ?? '',
    // Tolerate a missing key rather than throwing on a malformed row, which
    // would break the whole deck for one bad record.
    prompt: (json['prompt'] as String?) ?? '',
    answer: (json['answer'] as String?) ?? '',
  );
}

class UserProfile {
  final String id;
  final String name;
  final int age;
  final String gender;
  final List<String> photos;
  final String city;
  final int distanceKm;
  final String bio;
  final String occupation;
  final String education;
  final String relationshipIntent;
  final List<String> interests;
  final List<String> favoritePlaces;
  final List<String> languages;
  final List<ProfilePrompt> prompts;
  final bool isPhotoVerified;
  final int trustScore;
  final int crossedPathsCount;
  final String favoriteMusic;
  final String idealWeekend;
  final String referralCode;
  final List<String> commonInterests;
  final Map<String, bool> weekendAvailability;
  final String voiceIntroUrl;
  final String compatibilityExplanation;
  final String distanceDisplay;

  /// Lifestyle attributes. Each maps to a `profiles` column with a CHECK
  /// constraint; the accepted values live in [ProfileSchema.lifestyleFields]
  /// so the model and the picker can never disagree.
  final String? smoking;
  final String? drinking;
  final String? exercise;
  final String? pets;
  final String? children;

  /// Height in centimetres, or null when not stated.
  final int? heightCm;

  const UserProfile({
    required this.id,
    required this.name,
    required this.age,
    required this.gender,
    required this.photos,
    required this.city,
    this.distanceKm = 0,
    this.bio = '',
    this.occupation = '',
    this.education = '',
    this.relationshipIntent = 'Dating',
    this.interests = const [],
    this.favoritePlaces = const [],
    this.languages = const [],
    this.prompts = const [],
    this.isPhotoVerified = true,
    this.trustScore = 96,
    this.crossedPathsCount = 0,
    this.favoriteMusic = '',
    this.idealWeekend = '',
    this.referralCode = '',
    this.commonInterests = const [],
    this.weekendAvailability = const {},
    this.voiceIntroUrl = '',
    this.compatibilityExplanation = '',
    this.distanceDisplay = '',
    this.smoking,
    this.drinking,
    this.exercise,
    this.pets,
    this.children,
    this.heightCm,
  });
  UserProfile copyWith({
    String? id,
    String? name,
    int? age,
    String? gender,
    List<String>? photos,
    String? city,
    int? distanceKm,
    String? bio,
    String? occupation,
    String? education,
    String? relationshipIntent,
    List<String>? interests,
    List<String>? favoritePlaces,
    List<String>? languages,
    List<ProfilePrompt>? prompts,
    bool? isPhotoVerified,
    int? trustScore,
    int? crossedPathsCount,
    String? favoriteMusic,
    String? idealWeekend,
    String? referralCode,
    List<String>? commonInterests,
    Map<String, bool>? weekendAvailability,
    String? voiceIntroUrl,
    String? compatibilityExplanation,
    String? distanceDisplay,
    String? smoking,
    String? drinking,
    String? exercise,
    String? pets,
    String? children,
    int? heightCm,
  }) {
    return UserProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      age: age ?? this.age,
      gender: gender ?? this.gender,
      photos: photos ?? this.photos,
      city: city ?? this.city,
      distanceKm: distanceKm ?? this.distanceKm,
      bio: bio ?? this.bio,
      occupation: occupation ?? this.occupation,
      education: education ?? this.education,
      relationshipIntent: relationshipIntent ?? this.relationshipIntent,
      interests: interests ?? this.interests,
      favoritePlaces: favoritePlaces ?? this.favoritePlaces,
      languages: languages ?? this.languages,
      prompts: prompts ?? this.prompts,
      isPhotoVerified: isPhotoVerified ?? this.isPhotoVerified,
      trustScore: trustScore ?? this.trustScore,
      crossedPathsCount: crossedPathsCount ?? this.crossedPathsCount,
      favoriteMusic: favoriteMusic ?? this.favoriteMusic,
      idealWeekend: idealWeekend ?? this.idealWeekend,
      referralCode: referralCode ?? this.referralCode,
      commonInterests: commonInterests ?? this.commonInterests,
      weekendAvailability: weekendAvailability ?? this.weekendAvailability,
      voiceIntroUrl: voiceIntroUrl ?? this.voiceIntroUrl,
      compatibilityExplanation:
          compatibilityExplanation ?? this.compatibilityExplanation,
      distanceDisplay: distanceDisplay ?? this.distanceDisplay,
      smoking: smoking ?? this.smoking,
      drinking: drinking ?? this.drinking,
      exercise: exercise ?? this.exercise,
      pets: pets ?? this.pets,
      children: children ?? this.children,
      heightCm: heightCm ?? this.heightCm,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'age': age,
    'gender': gender,
    'photos': photos,
    'city': city,
    'distanceKm': distanceKm,
    'bio': bio,
    'occupation': occupation,
    'education': education,
    'relationshipIntent': relationshipIntent,
    'interests': interests,
    'favoritePlaces': favoritePlaces,
    'languages': languages,
    'prompts': prompts.map((p) => p.toJson()).toList(),
    'isPhotoVerified': isPhotoVerified,
    'trustScore': trustScore,
    'crossedPathsCount': crossedPathsCount,
    'favoriteMusic': favoriteMusic,
    'idealWeekend': idealWeekend,
    'referralCode': referralCode,
    'commonInterests': commonInterests,
    'weekendAvailability': weekendAvailability,
    'voiceIntroUrl': voiceIntroUrl,
    'compatibilityExplanation': compatibilityExplanation,
    'distanceDisplay': distanceDisplay,
  };
  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
    id: json['id'] as String,
    name: json['name'] as String,
    age: json['age'] as int,
    gender: json['gender'] as String,
    photos: List<String>.from(json['photos'] as List),
    city: json['city'] as String,
    distanceKm: json['distanceKm'] as int? ?? 0,
    bio: json['bio'] as String? ?? '',
    occupation: json['occupation'] as String? ?? '',
    education: json['education'] as String? ?? '',
    relationshipIntent: json['relationshipIntent'] as String? ?? 'Dating',
    interests: List<String>.from(json['interests'] as List? ?? []),
    favoritePlaces: List<String>.from(json['favoritePlaces'] as List? ?? []),
    languages: List<String>.from(json['languages'] as List? ?? []),
    prompts: (json['prompts'] as List? ?? [])
        .map((p) => ProfilePrompt.fromJson(p))
        .toList(),
    isPhotoVerified: json['isPhotoVerified'] as bool? ?? true,
    trustScore: json['trustScore'] as int? ?? 96,
    crossedPathsCount: json['crossedPathsCount'] as int? ?? 0,
    favoriteMusic: json['favoriteMusic'] as String? ?? '',
    idealWeekend: json['idealWeekend'] as String? ?? '',
    referralCode: json['referralCode'] as String? ?? '',
    commonInterests: List<String>.from(json['commonInterests'] as List? ?? []),
    weekendAvailability: Map<String, bool>.from(
      json['weekendAvailability'] as Map? ?? {},
    ),
    voiceIntroUrl: json['voiceIntroUrl'] as String? ?? '',
    compatibilityExplanation: json['compatibilityExplanation'] as String? ?? '',
    distanceDisplay: json['distanceDisplay'] as String? ?? '',
  );
}

class WeekendPlan {
  final String id;
  final String creatorId;
  final String creatorName;
  final String creatorPhoto;
  final String title;
  final String category;
  final String venue;
  final String time;
  final String description;
  final List<String> participants;
  final bool isJoined;
  const WeekendPlan({
    required this.id,
    required this.creatorId,
    required this.creatorName,
    required this.creatorPhoto,
    required this.title,
    required this.category,
    required this.venue,
    required this.time,
    required this.description,
    this.participants = const [],
    this.isJoined = false,
  });
  WeekendPlan copyWith({
    String? id,
    String? creatorId,
    String? creatorName,
    String? creatorPhoto,
    String? title,
    String? category,
    String? venue,
    String? time,
    String? description,
    List<String>? participants,
    bool? isJoined,
  }) {
    return WeekendPlan(
      id: id ?? this.id,
      creatorId: creatorId ?? this.creatorId,
      creatorName: creatorName ?? this.creatorName,
      creatorPhoto: creatorPhoto ?? this.creatorPhoto,
      title: title ?? this.title,
      category: category ?? this.category,
      venue: venue ?? this.venue,
      time: time ?? this.time,
      description: description ?? this.description,
      participants: participants ?? this.participants,
      isJoined: isJoined ?? this.isJoined,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'creatorId': creatorId,
    'creatorName': creatorName,
    'creatorPhoto': creatorPhoto,
    'title': title,
    'category': category,
    'venue': venue,
    'time': time,
    'description': description,
    'participants': participants,
    'isJoined': isJoined,
  };
  factory WeekendPlan.fromJson(Map<String, dynamic> json) => WeekendPlan(
    id: json['id'] as String,
    creatorId: json['creatorId'] as String,
    creatorName: json['creatorName'] as String,
    creatorPhoto: json['creatorPhoto'] as String? ?? '',
    title: json['title'] as String,
    category: json['category'] as String,
    venue: json['venue'] as String,
    time: json['time'] as String,
    description: json['description'] as String,
    participants: List<String>.from(json['participants'] as List? ?? []),
    isJoined: json['isJoined'] as bool? ?? false,
  );
}

class MatchItem {
  final String id;
  final UserProfile user;
  final int matchedAt;
  final String lastMessage;
  final String lastMessageTime;
  final int unreadCount;
  final List<String> sharedInterests;
  final String suggestedStarter;
  const MatchItem({
    required this.id,
    required this.user,
    this.matchedAt = 0,
    this.lastMessage = '',
    this.lastMessageTime = 'Just now',
    this.unreadCount = 0,
    this.sharedInterests = const [],
    this.suggestedStarter = '',
  });
  MatchItem copyWith({
    String? id,
    UserProfile? user,
    int? matchedAt,
    String? lastMessage,
    String? lastMessageTime,
    int? unreadCount,
    List<String>? sharedInterests,
    String? suggestedStarter,
  }) {
    return MatchItem(
      id: id ?? this.id,
      user: user ?? this.user,
      matchedAt: matchedAt ?? this.matchedAt,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageTime: lastMessageTime ?? this.lastMessageTime,
      unreadCount: unreadCount ?? this.unreadCount,
      sharedInterests: sharedInterests ?? this.sharedInterests,
      suggestedStarter: suggestedStarter ?? this.suggestedStarter,
    );
  }
}

/// A non-mutual like this user received.
///
/// Surfaced by `get_received_likes` (migration 026). This is a genuinely new
/// capability rather than a reshuffle of existing data: nothing in the app read
/// inbound likes before, and `likes.is_stand_out` was a write-only column that
/// no query ever selected.
class ReceivedLike {
  final UserProfile profile;
  final bool isStandOut;
  final DateTime? likedAt;

  const ReceivedLike({
    required this.profile,
    this.isStandOut = false,
    this.likedAt,
  });
}

/// One entry in the notification centre.
///
/// Backed by the `notifications` table, which had no client surface at all
/// before migration 026: the repository that read it was never called from
/// anywhere, so the only two notification types the database ever produced were
/// shown as transient system toasts and then lost.
class AppNotification {
  final String id;
  final String type;
  final String title;
  final String body;
  final Map<String, dynamic> payload;
  final bool isRead;
  final DateTime? createdAt;

  const AppNotification({
    required this.id,
    required this.type,
    this.title = '',
    this.body = '',
    this.payload = const {},
    this.isRead = false,
    this.createdAt,
  });

  factory AppNotification.fromRow(Map<String, dynamic> row) {
    // `data` is jsonb; a malformed or absent value must not take down the
    // whole list, so it degrades to an empty payload.
    final rawData = row['data'];
    Map<String, dynamic> payload = const {};
    if (rawData is Map) {
      final inner = rawData['payload'];
      if (inner is Map) {
        payload = Map<String, dynamic>.from(inner);
      } else {
        payload = Map<String, dynamic>.from(rawData);
      }
    }

    return AppNotification(
      id: row['id'] as String? ?? '',
      type: row['type'] as String? ?? 'safety_alert',
      title: row['title'] as String? ?? '',
      body: row['body'] as String? ?? '',
      payload: payload,
      isRead: row['is_read'] as bool? ?? false,
      createdAt: DateTime.tryParse(row['created_at'] as String? ?? ''),
    );
  }

  AppNotification copyWith({bool? isRead}) {
    return AppNotification(
      id: id,
      type: type,
      title: title,
      body: body,
      payload: payload,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt,
    );
  }

  /// The user id this notification is about, when it names one.
  String? get targetUserId {
    final id = payload['user_id'];
    return id is String && id.isNotEmpty ? id : null;
  }

  String? get targetMatchId {
    final id = payload['match_id'];
    return id is String && id.isNotEmpty ? id : null;
  }

  String? get targetConversationId {
    final id = payload['conversation_id'];
    return id is String && id.isNotEmpty ? id : null;
  }
}

class ChatMessage {
  final String id;
  final String senderId;
  final String text;
  final int timestamp;
  final String? translatedText;
  final bool isTranslated;
  final bool isRead;
  const ChatMessage({
    required this.id,
    required this.senderId,
    required this.text,
    this.timestamp = 0,
    this.translatedText,
    this.isTranslated = false,
    this.isRead = true,
  });
  ChatMessage copyWith({
    String? id,
    String? senderId,
    String? text,
    int? timestamp,
    String? translatedText,
    bool? isTranslated,
    bool? isRead,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      senderId: senderId ?? this.senderId,
      text: text ?? this.text,
      timestamp: timestamp ?? this.timestamp,
      translatedText: translatedText ?? this.translatedText,
      isTranslated: isTranslated ?? this.isTranslated,
      isRead: isRead ?? this.isRead,
    );
  }
}

class ReferralData {
  final String code;
  final int invitedCount;
  final int verifiedCount;
  final String badgeTitle;
  final String achievementTier;
  final String linkUrl;
  /// Counts, badge and link all come from the live `get_referral_stats`
  /// RPC — defaults are neutral so nothing fabricated can ever render.
  const ReferralData({
    required this.code,
    this.invitedCount = 0,
    this.verifiedCount = 0,
    this.badgeTitle = '',
    this.achievementTier = '',
    this.linkUrl = '',
  });
  ReferralData copyWith({
    String? code,
    int? invitedCount,
    int? verifiedCount,
    String? badgeTitle,
    String? achievementTier,
    String? linkUrl,
  }) {
    return ReferralData(
      code: code ?? this.code,
      invitedCount: invitedCount ?? this.invitedCount,
      verifiedCount: verifiedCount ?? this.verifiedCount,
      badgeTitle: badgeTitle ?? this.badgeTitle,
      achievementTier: achievementTier ?? this.achievementTier,
      linkUrl: linkUrl ?? this.linkUrl,
    );
  }
}

class DateIdea {
  final String title;
  final String venueType;
  final String description;
  final String estimatedBudget;
  final String conversationTip;
  const DateIdea({
    required this.title,
    required this.venueType,
    required this.description,
    required this.estimatedBudget,
    required this.conversationTip,
  });
  DateIdea copyWith({
    String? title,
    String? venueType,
    String? description,
    String? estimatedBudget,
    String? conversationTip,
  }) {
    return DateIdea(
      title: title ?? this.title,
      venueType: venueType ?? this.venueType,
      description: description ?? this.description,
      estimatedBudget: estimatedBudget ?? this.estimatedBudget,
      conversationTip: conversationTip ?? this.conversationTip,
    );
  }
}

enum DiscoveryMode {
  forYou('For You'),
  nearby('Nearby'),
  aroundMe('Around Me'),
  city('City'),
  global('Global'),
  travelMode('Travel Mode'),
  crossedPaths('Crossed Paths'),
  interests('Interests'),
  weekendPlans('Plans');

  final String title;
  const DiscoveryMode(this.title);
}

class WeekendAuthState {
  final bool isAuthenticated;
  final bool isLoading;
  final UserProfile? user;
  final String? session;
  final String? error;
  final bool emailVerified;
  final bool needsMfaChallenge;
  final bool mfaEnabled;
  final bool needsProfileSetup;

  /// True when Supabase accepted the signup but the account still has to be
  /// confirmed through the emailed link before a session is issued.
  ///
  /// This is a distinct state from [error]: nothing went wrong, the flow is
  /// simply waiting on the user. It mirrors the live project's real
  /// `mailer_autoconfirm` setting instead of inventing a verified flag.
  final bool awaitingEmailConfirmation;

  /// The address the confirmation mail was sent to (for resend / display).
  final String? pendingEmail;

  /// The password typed into the sign-up wizard, kept in memory only so the
  /// "I've confirmed" step can finish the sign-in without making the user
  /// type it a second time on the sign-in screen.
  ///
  /// This is deliberately never written to disk, never put in the
  /// [WeekendAuthState] persistence path, and is cleared the moment it is
  /// used (or the user leaves the confirmation step). It exists purely for
  /// the signup-continuation window.
  final String? pendingPassword;

  const WeekendAuthState({
    this.isAuthenticated = false,
    this.isLoading = false,
    this.user,
    this.session,
    this.error,
    this.emailVerified = false,
    this.needsMfaChallenge = false,
    this.mfaEnabled = false,
    this.needsProfileSetup = false,
    this.awaitingEmailConfirmation = false,
    this.pendingEmail,
    this.pendingPassword,
  });
  WeekendAuthState copyWith({
    bool? isAuthenticated,
    bool? isLoading,
    UserProfile? user,
    String? session,
    String? error,
    bool clearError = false,
    bool? emailVerified,
    bool? needsMfaChallenge,
    bool? mfaEnabled,
    bool? needsProfileSetup,
    bool? awaitingEmailConfirmation,
    String? pendingEmail,
    bool clearPendingEmail = false,
    String? pendingPassword,
    bool clearPendingPassword = false,
  }) {
    return WeekendAuthState(
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      isLoading: isLoading ?? this.isLoading,
      user: user ?? this.user,
      session: session ?? this.session,
      error: clearError ? null : (error ?? this.error),
      emailVerified: emailVerified ?? this.emailVerified,
      needsMfaChallenge: needsMfaChallenge ?? this.needsMfaChallenge,
      mfaEnabled: mfaEnabled ?? this.mfaEnabled,
      needsProfileSetup: needsProfileSetup ?? this.needsProfileSetup,
      awaitingEmailConfirmation:
          awaitingEmailConfirmation ?? this.awaitingEmailConfirmation,
      pendingEmail: clearPendingEmail ? null : (pendingEmail ?? this.pendingEmail),
      pendingPassword: clearPendingPassword
          ? null
          : (pendingPassword ?? this.pendingPassword),
    );
  }

  WeekendAuthState clearError() => WeekendAuthState(
        isAuthenticated: isAuthenticated,
        isLoading: isLoading,
        user: user,
        session: session,
        emailVerified: emailVerified,
        needsMfaChallenge: needsMfaChallenge,
        mfaEnabled: mfaEnabled,
        needsProfileSetup: needsProfileSetup,
        awaitingEmailConfirmation: awaitingEmailConfirmation,
        pendingEmail: pendingEmail,
        pendingPassword: pendingPassword,
      );
}

class Advertisement {
  final String id;
  final String campaignId;
  final String title;
  final String description;
  final String imageUrl;
  final String ctaText;
  final String destinationUrl;
  final String clickAction;
  final bool isActive;
  final int? width;
  final int? height;
  const Advertisement({
    required this.id,
    required this.campaignId,
    required this.title,
    required this.description,
    required this.imageUrl,
    required this.ctaText,
    required this.destinationUrl,
    this.clickAction = 'external_url',
    this.isActive = true,
    this.width,
    this.height,
  });
  Advertisement copyWith({
    String? id,
    String? campaignId,
    String? title,
    String? description,
    String? imageUrl,
    String? ctaText,
    String? destinationUrl,
    String? clickAction,
    bool? isActive,
    int? width,
    int? height,
  }) {
    return Advertisement(
      id: id ?? this.id,
      campaignId: campaignId ?? this.campaignId,
      title: title ?? this.title,
      description: description ?? this.description,
      imageUrl: imageUrl ?? this.imageUrl,
      ctaText: ctaText ?? this.ctaText,
      destinationUrl: destinationUrl ?? this.destinationUrl,
      clickAction: clickAction ?? this.clickAction,
      isActive: isActive ?? this.isActive,
      width: width ?? this.width,
      height: height ?? this.height,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'campaign_id': campaignId,
    'title': title,
    'description': description,
    'image_url': imageUrl,
    'cta_text': ctaText,
    'destination_url': destinationUrl,
    'click_action': clickAction,
    'is_active': isActive,
    'image_width': width,
    'image_height': height,
  };
  factory Advertisement.fromJson(Map<String, dynamic> json) => Advertisement(
    id: json['ad_id'] as String? ?? json['id'] as String? ?? '',
    campaignId: json['campaign_id'] as String? ?? '',
    title: json['title'] as String? ?? '',
    description: json['description'] as String? ?? '',
    imageUrl: json['image_url'] as String? ?? '',
    ctaText: json['cta_text'] as String? ?? 'Learn More',
    destinationUrl: json['destination_url'] as String? ?? '',
    clickAction: json['click_action'] as String? ?? 'external_url',
    isActive: json['is_active'] as bool? ?? true,
    width: json['image_width'] as int?,
    height: json['image_height'] as int?,
  );
}

class AdConfig {
  final int adIntervalSeconds;
  final int maxAdsPerHour;
  final String adPlaceholderText;
  final bool isAdvertisingEnabled;
  const AdConfig({
    this.adIntervalSeconds = 120,
    this.maxAdsPerHour = 10,
    this.adPlaceholderText = 'Sponsored',
    this.isAdvertisingEnabled = true,
  });
  AdConfig copyWith({
    int? adIntervalSeconds,
    int? maxAdsPerHour,
    String? adPlaceholderText,
    bool? isAdvertisingEnabled,
  }) {
    return AdConfig(
      adIntervalSeconds: adIntervalSeconds ?? this.adIntervalSeconds,
      maxAdsPerHour: maxAdsPerHour ?? this.maxAdsPerHour,
      adPlaceholderText: adPlaceholderText ?? this.adPlaceholderText,
      isAdvertisingEnabled: isAdvertisingEnabled ?? this.isAdvertisingEnabled,
    );
  }

  factory AdConfig.fromJson(Map<String, dynamic> json) => AdConfig(
    adIntervalSeconds: (json['ad_interval_seconds'] as int?) ?? 120,
    maxAdsPerHour: (json['max_ads_per_hour'] as int?) ?? 10,
    adPlaceholderText: (json['ad_placeholder_text'] as String?) ?? 'Sponsored',
    isAdvertisingEnabled: (json['is_advertising_enabled'] as bool?) ?? true,
  );
}

class AdState {
  final bool adTimerStarted;
  final int activeDiscoverySeconds;
  final bool adEligible;
  final bool adDisplayed;
  final String? adId;
  final String? adImpressionId;
  final bool adLoading;
  final String? adError;
  const AdState({
    this.adTimerStarted = false,
    this.activeDiscoverySeconds = 0,
    this.adEligible = false,
    this.adDisplayed = false,
    this.adId,
    this.adImpressionId,
    this.adLoading = false,
    this.adError,
  });
  AdState copyWith({
    bool? adTimerStarted,
    int? activeDiscoverySeconds,
    bool? adEligible,
    bool? adDisplayed,
    String? adId,
    String? adImpressionId,
    bool? adLoading,
    String? adError,
  }) {
    return AdState(
      adTimerStarted: adTimerStarted ?? this.adTimerStarted,
      activeDiscoverySeconds:
          activeDiscoverySeconds ?? this.activeDiscoverySeconds,
      adEligible: adEligible ?? this.adEligible,
      adDisplayed: adDisplayed ?? this.adDisplayed,
      adId: adId ?? this.adId,
      adImpressionId: adImpressionId ?? this.adImpressionId,
      adLoading: adLoading ?? this.adLoading,
      adError: adError ?? this.adError,
    );
  }

  bool get shouldShowAd => !adDisplayed && adEligible && adTimerStarted;
}

class CrossedPath {
  final String userBId;
  final int crossCount;
  final DateTime lastCrossedAt;
  final UserProfile? userProfile;
  const CrossedPath({
    required this.userBId,
    required this.crossCount,
    required this.lastCrossedAt,
    this.userProfile,
  });
}

class LocationPreferences {
  final bool locationDiscoveryEnabled;
  final bool crossedPathsEnabled;
  final bool showDistanceEnabled;
  final bool nearbyDiscoveryEnabled;
  final bool travelModeEnabled;
  final int discoveryRadiusKm;
  final String? travelModeCity;
  final double? travelModeLat;
  final double? travelModeLon;
  /// Gender preferences for discovery filtering.
  /// Empty list means no preference filter (show all genders).
  /// Values must match the gender options in the profiles table:
  /// 'Man', 'Woman', 'Non-binary', 'Prefer not to say'
  final List<String> preferredGenders;
  const LocationPreferences({
    this.locationDiscoveryEnabled = true,
    this.crossedPathsEnabled = true,
    this.showDistanceEnabled = true,
    this.nearbyDiscoveryEnabled = true,
    this.travelModeEnabled = false,
    this.discoveryRadiusKm = 25,
    this.travelModeCity,
    this.travelModeLat,
    this.travelModeLon,
    this.preferredGenders = const [],
  });
  LocationPreferences copyWith({
    bool? locationDiscoveryEnabled,
    bool? crossedPathsEnabled,
    bool? showDistanceEnabled,
    bool? nearbyDiscoveryEnabled,
    bool? travelModeEnabled,
    int? discoveryRadiusKm,
    String? travelModeCity,
    double? travelModeLat,
    double? travelModeLon,
    List<String>? preferredGenders,
  }) {
    return LocationPreferences(
      locationDiscoveryEnabled:
          locationDiscoveryEnabled ?? this.locationDiscoveryEnabled,
      crossedPathsEnabled: crossedPathsEnabled ?? this.crossedPathsEnabled,
      showDistanceEnabled: showDistanceEnabled ?? this.showDistanceEnabled,
      nearbyDiscoveryEnabled:
          nearbyDiscoveryEnabled ?? this.nearbyDiscoveryEnabled,
      travelModeEnabled: travelModeEnabled ?? this.travelModeEnabled,
      discoveryRadiusKm: discoveryRadiusKm ?? this.discoveryRadiusKm,
      travelModeCity: travelModeCity ?? this.travelModeCity,
      travelModeLat: travelModeLat ?? this.travelModeLat,
      travelModeLon: travelModeLon ?? this.travelModeLon,
      preferredGenders: preferredGenders ?? this.preferredGenders,
    );
  }

  Map<String, dynamic> toJson() => {
    'location_discovery_enabled': locationDiscoveryEnabled,
    'crossed_paths_enabled': crossedPathsEnabled,
    'show_distance_enabled': showDistanceEnabled,
    'nearby_discovery_enabled': nearbyDiscoveryEnabled,
    'travel_mode_enabled': travelModeEnabled,
    'discovery_radius_km': discoveryRadiusKm,
    'travel_mode_city': travelModeCity,
    'travel_mode_lat': travelModeLat,
    'travel_mode_lon': travelModeLon,
    'preferred_genders': preferredGenders,
  };
  factory LocationPreferences.fromJson(Map<String, dynamic> json) =>
      LocationPreferences(
        locationDiscoveryEnabled:
            (json['location_discovery_enabled'] as bool?) ?? true,
        crossedPathsEnabled: (json['crossed_paths_enabled'] as bool?) ?? true,
        showDistanceEnabled: (json['show_distance_enabled'] as bool?) ?? true,
        nearbyDiscoveryEnabled:
            (json['nearby_discovery_enabled'] as bool?) ?? true,
        travelModeEnabled: (json['travel_mode_enabled'] as bool?) ?? false,
        discoveryRadiusKm: (json['discovery_radius_km'] as int?) ?? 25,
        travelModeCity: json['travel_mode_city'] as String?,
        travelModeLat: (json['travel_mode_lat'] as num?)?.toDouble(),
        travelModeLon: (json['travel_mode_lon'] as num?)?.toDouble(),
        preferredGenders: (json['preferred_genders'] as List?)
                ?.map((g) => g.toString())
                .toList() ??
            [],
      );
}

class QRInvitation {
  final String inviteId;
  final String referralCode;
  final String inviterId;
  final String inviterName;
  final int version;
  final DateTime createdAt;
  final DateTime expiresAt;
  final String signature;
  const QRInvitation({
    required this.inviteId,
    required this.referralCode,
    required this.inviterId,
    required this.inviterName,
    required this.version,
    required this.createdAt,
    required this.expiresAt,
    required this.signature,
  });
  String toPayload() {
    return 'WEEKEND_INVITE|$inviteId|$referralCode|$inviterId|$inviterName|$version|${createdAt.millisecondsSinceEpoch}|${expiresAt.millisecondsSinceEpoch}|$signature';
  }

  factory QRInvitation.fromPayload(String payload) {
    try {
      final parts = payload.split('|');
      if (parts.length != 9 || parts[0] != 'WEEKEND_INVITE') {
        throw FormatException('Invalid QR invitation payload');
      }
      return QRInvitation(
        inviteId: parts[1],
        referralCode: parts[2],
        inviterId: parts[3],
        inviterName: parts[4],
        version: int.parse(parts[5]),
        createdAt: DateTime.fromMillisecondsSinceEpoch(int.parse(parts[6])),
        expiresAt: DateTime.fromMillisecondsSinceEpoch(int.parse(parts[7])),
        signature: parts[8],
      );
    } catch (e) {
      throw FormatException('Failed to parse QR invitation: $e');
    }
  }
  bool get isExpired => DateTime.now().isAfter(expiresAt);
  Map<String, dynamic> toJson() => {
    'invite_id': inviteId,
    'referral_code': referralCode,
    'inviter_id': inviterId,
    'inviter_name': inviterName,
    'version': version,
    'created_at': createdAt.toIso8601String(),
    'expires_at': expiresAt.toIso8601String(),
    'signature': signature,
  };
  factory QRInvitation.fromJson(Map<String, dynamic> json) => QRInvitation(
    inviteId: json['invite_id'] as String,
    referralCode: json['referral_code'] as String,
    inviterId: json['inviter_id'] as String,
    inviterName: json['inviter_name'] as String,
    version: json['version'] as int,
    createdAt: DateTime.parse(json['created_at'] as String),
    expiresAt: DateTime.parse(json['expires_at'] as String),
    signature: json['signature'] as String,
  );
}

class QRInvitationResult {
  final bool isValid;
  final QRInvitation? invitation;
  final String? errorMessage;
  const QRInvitationResult({
    required this.isValid,
    this.invitation,
    this.errorMessage,
  });
  factory QRInvitationResult.valid(QRInvitation invitation) =>
      QRInvitationResult(isValid: true, invitation: invitation);
  factory QRInvitationResult.invalid(String errorMessage) =>
      QRInvitationResult(isValid: false, errorMessage: errorMessage);
}
