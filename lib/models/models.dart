class ProfilePrompt {
  final String prompt;
  final String answer;
  const ProfilePrompt({required this.prompt, required this.answer});
  ProfilePrompt copyWith({String? prompt, String? answer}) {
    return ProfilePrompt(
      prompt: prompt ?? this.prompt,
      answer: answer ?? this.answer,
    );
  }

  Map<String, dynamic> toJson() => {'prompt': prompt, 'answer': answer};
  factory ProfilePrompt.fromJson(Map<String, dynamic> json) => ProfilePrompt(
    prompt: json['prompt'] as String,
    answer: json['answer'] as String,
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
  const ReferralData({
    required this.code,
    this.invitedCount = 7,
    this.verifiedCount = 5,
    this.badgeTitle = 'Founding Pioneer',
    this.achievementTier = 'Silver Ambassador',
    this.linkUrl = 'https://weekend.app/invite/',
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
  const WeekendAuthState({
    this.isAuthenticated = false,
    this.isLoading = false,
    this.user,
    this.session,
    this.error,
    this.emailVerified = false,
  });
  WeekendAuthState copyWith({
    bool? isAuthenticated,
    bool? isLoading,
    UserProfile? user,
    String? session,
    String? error,
    bool? emailVerified,
  }) {
    return WeekendAuthState(
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      isLoading: isLoading ?? this.isLoading,
      user: user ?? this.user,
      session: session ?? this.session,
      error: error ?? this.error,
      emailVerified: emailVerified ?? this.emailVerified,
    );
  }
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
