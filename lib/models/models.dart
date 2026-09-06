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
  factory ProfilePrompt.fromJson(Map<String, dynamic> json) =>
      ProfilePrompt(prompt: json['prompt'] as String, answer: json['answer'] as String);
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
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id, 'name': name, 'age': age, 'gender': gender, 'photos': photos,
    'city': city, 'distanceKm': distanceKm, 'bio': bio, 'occupation': occupation,
    'education': education, 'relationshipIntent': relationshipIntent,
    'interests': interests, 'favoritePlaces': favoritePlaces, 'languages': languages,
    'prompts': prompts.map((p) => p.toJson()).toList(),
    'isPhotoVerified': isPhotoVerified, 'trustScore': trustScore,
    'crossedPathsCount': crossedPathsCount, 'favoriteMusic': favoriteMusic,
    'idealWeekend': idealWeekend, 'referralCode': referralCode,
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
    prompts: (json['prompts'] as List? ?? []).map((p) => ProfilePrompt.fromJson(p)).toList(),
    isPhotoVerified: json['isPhotoVerified'] as bool? ?? true,
    trustScore: json['trustScore'] as int? ?? 96,
    crossedPathsCount: json['crossedPathsCount'] as int? ?? 0,
    favoriteMusic: json['favoriteMusic'] as String? ?? '',
    idealWeekend: json['idealWeekend'] as String? ?? '',
    referralCode: json['referralCode'] as String? ?? '',
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
    'id': id, 'creatorId': creatorId, 'creatorName': creatorName,
    'creatorPhoto': creatorPhoto, 'title': title, 'category': category,
    'venue': venue, 'time': time, 'description': description,
    'participants': participants, 'isJoined': isJoined,
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
  FOR_YOU('For You'),
  NEARBY('Nearby'),
  CROSSED_PATHS('Crossed Paths'),
  INTERESTS('Interests'),
  WEEKEND_PLANS('Plans'),
  GLOBAL('Global');

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
