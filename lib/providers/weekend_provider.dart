import 'package:flutter/foundation.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import '../models/models.dart';
import '../services/demo_data.dart';

import '../repositories/discovery_repository.dart';
import '../repositories/profile_repository.dart';
import '../repositories/ad_repository.dart';
import '../services/location_service.dart';

final weekendProvider = StateNotifierProvider<WeekendNotifier, WeekendState>((
  ref,
) {
  return WeekendNotifier(
    discoveryRepository: DiscoveryRepository(),
    profileRepository: ProfileRepository(),
    adRepository: AdRepository(),
  );
});

final locationPreferencesProvider = StateProvider<LocationPreferences>((ref) {
  return const LocationPreferences();
});

final adConfigProvider = StateProvider<AdConfig>((ref) {
  return const AdConfig();
});

class WeekendState {
  final UserProfile currentUser;
  final List<UserProfile> deckProfiles;
  final List<MatchItem> matches;
  final Map<String, List<ChatMessage>> chatMessages;
  final List<WeekendPlan> plans;
  final ReferralData referralData;
  final DiscoveryMode selectedMode;
  final int maxDistanceKm;
  final List<String> likedProfiles;
  final Set<String> blockedUserIds;
  final UserProfile? recentMatchCelebration;
  final List<DateIdea> dateIdeas;
  final bool isGeneratingDateIdeas;
  final List<String> swipedProfileIds;
  final LocationPreferences locationPreferences;
  final List<Advertisement?> feedItems;
  final List<CrossedPath> crossedPaths;

  const WeekendState({
    required this.currentUser,
    this.deckProfiles = const [],
    this.matches = const [],
    this.chatMessages = const {},
    this.plans = const [],
    required this.referralData,
    required this.selectedMode,
    this.maxDistanceKm = 25,
    this.likedProfiles = const [],
    this.blockedUserIds = const {},
    this.recentMatchCelebration,
    this.dateIdeas = const [],
    this.isGeneratingDateIdeas = false,
    this.swipedProfileIds = const [],
    this.locationPreferences = const LocationPreferences(),
    this.feedItems = const [],
    this.crossedPaths = const [],
  });

  factory WeekendState.initial() {
    return WeekendState(
      currentUser: UserProfile(
        id: 'user_me',
        name: 'Max',
        age: 26,
        gender: 'Man',
        photos: const [
          'https://images.unsplash.com/photo-1539571696357-5a69c17a67c6?auto=format&fit=crop&w=800&q=80',
        ],
        city: 'Pune',
        distanceKm: 0,
        bio:
            'Tech builder, specialty coffee addict, and spontaneous weekend trekker.',
        occupation: 'Software Developer',
        education: 'University Graduate',
        relationshipIntent: 'Dating & Weekend Plans',
        interests: const [
          'Specialty Coffee',
          'Hiking',
          'Indie Music',
          'Cycling',
          'Travel',
          'F1',
        ],
        favoritePlaces: const [
          'Blue Tokai Cafe',
          'Koregaon Park',
          'ARAI Hills',
        ],
        languages: const ['English', 'Hindi'],
        prompts: const [
          ProfilePrompt(
            prompt: 'My ideal weekend is...',
            answer: 'Trying a new brunch spot followed by an outdoor trek.',
          ),
          ProfilePrompt(
            prompt: 'Let\'s go...',
            answer: 'To that hidden sourdough bakery in Camp!',
          ),
        ],
        isPhotoVerified: true,
        trustScore: 98,
        crossedPathsCount: 7,
        favoriteMusic: 'Coldplay, Prateek Kuhad, Tame Impala',
        idealWeekend: 'Acoustic gigs & hill climbs',
        referralCode: 'WEEKEND-MX07',
      ),
      referralData: const ReferralData(code: 'WEEKEND-MX07'),
      selectedMode: DiscoveryMode.forYou,
    );
  }

  WeekendState copyWith({
    UserProfile? currentUser,
    List<UserProfile>? deckProfiles,
    List<MatchItem>? matches,
    Map<String, List<ChatMessage>>? chatMessages,
    List<WeekendPlan>? plans,
    ReferralData? referralData,
    DiscoveryMode? selectedMode,
    int? maxDistanceKm,
    List<String>? likedProfiles,
    Set<String>? blockedUserIds,
    UserProfile? recentMatchCelebration,
    List<DateIdea>? dateIdeas,
    bool? isGeneratingDateIdeas,
    List<String>? swipedProfileIds,
    LocationPreferences? locationPreferences,
    List<Advertisement?>? feedItems,
    List<CrossedPath>? crossedPaths,
  }) {
    return WeekendState(
      currentUser: currentUser ?? this.currentUser,
      deckProfiles: deckProfiles ?? this.deckProfiles,
      matches: matches ?? this.matches,
      chatMessages: chatMessages ?? this.chatMessages,
      plans: plans ?? this.plans,
      referralData: referralData ?? this.referralData,
      selectedMode: selectedMode ?? this.selectedMode,
      maxDistanceKm: maxDistanceKm ?? this.maxDistanceKm,
      likedProfiles: likedProfiles ?? this.likedProfiles,
      blockedUserIds: blockedUserIds ?? this.blockedUserIds,
      recentMatchCelebration:
          recentMatchCelebration ?? this.recentMatchCelebration,
      dateIdeas: dateIdeas ?? this.dateIdeas,
      isGeneratingDateIdeas:
          isGeneratingDateIdeas ?? this.isGeneratingDateIdeas,
      swipedProfileIds: swipedProfileIds ?? this.swipedProfileIds,
      locationPreferences: locationPreferences ?? this.locationPreferences,
      feedItems: feedItems ?? this.feedItems,
      crossedPaths: crossedPaths ?? this.crossedPaths,
    );
  }
}

class WeekendNotifier extends StateNotifier<WeekendState> {
  final DiscoveryRepository _discoveryRepo;

  WeekendNotifier({
    required DiscoveryRepository discoveryRepository,
    required ProfileRepository profileRepository,
    required AdRepository adRepository,
  }) : _discoveryRepo = discoveryRepository,

       super(WeekendState.initial()) {
    _seedDemoIfNeeded();
  }
  SupabaseClient? get _client => SupabaseConfig.client;

  bool get _isDemo => !SupabaseConfig.isConfigured;

  void _seedDemoIfNeeded() {
    if (_isDemo) {
      state = state.copyWith(
        deckProfiles: DemoData.sampleDeck(),
        matches: DemoData.sampleMatches(state.currentUser),
        chatMessages: DemoData.sampleMessages(),
        plans: DemoData.samplePlans(),
        crossedPaths: DemoData.sampleCrossedPaths(),
      );
    }
  }

  void selectDiscoveryMode(DiscoveryMode mode) {
    state = state.copyWith(selectedMode: mode);
  }

  Future<void> loadDiscoveryProfiles() async {
    final userId = SupabaseConfig.currentUserId;

    final prefs = state.locationPreferences;

    final mode = _modeToString(state.selectedMode);

    if (_isDemo) {
      state = state.copyWith(
        deckProfiles: DemoData.sampleDeck(),
        swipedProfileIds: const [],
      );
      return;
    }
    final client = _client;

    if (client == null) return;

    final profiles = await _discoveryRepo.loadDiscoveryProfiles(
      userId: userId,
      maxDistanceKm: prefs.discoveryRadiusKm.toDouble(),
      limit: 20,
      mode: mode,
    );

    final enriched = await Future.wait(
      profiles.map((p) async {
        final photos = await _discoveryRepo.fetchProfilePhotos(p.id);
        return p.copyWith(photos: photos);
      }),
    );

    state = state.copyWith(deckProfiles: enriched, swipedProfileIds: const []);
  }

  String _modeToString(DiscoveryMode mode) {
    switch (mode) {
      case DiscoveryMode.nearby:
        return 'nearby';
      case DiscoveryMode.crossedPaths:
        return 'crossed_paths';
      case DiscoveryMode.global:
        return 'global';
      default:
        return 'for_you';
    }
  }

  void setMaxDistance(int km) {
    state = state.copyWith(maxDistanceKm: km);
  }

  void setLocationPreferences(LocationPreferences prefs) {
    state = state.copyWith(locationPreferences: prefs);
  }

  void setDiscoveryRadius(int km) {
    state = state.copyWith(
      locationPreferences: state.locationPreferences.copyWith(
        discoveryRadiusKm: km,
      ),
    );
  }

  Future<void> saveLocationPreferences() async {
    final client = _client;

    if (client == null) return;

    final userId = SupabaseConfig.currentUserId;

    final prefs = state.locationPreferences;
    try {
      await client
          .from('user_settings')
          .update({'max_distance_km': prefs.discoveryRadiusKm})
          .eq('user_id', userId);
    } catch (e) {
      // ignore
    }
  }

  Future<void> updateLocationIfNeeded() async {
    if (_isDemo) return;
    final prefs = state.locationPreferences;
    if (!prefs.locationDiscoveryEnabled && !prefs.nearbyDiscoveryEnabled) {
      return;
    }

    final position = await LocationService.getCurrentPosition();
    if (position == null) return;

    final city =
        await LocationService.getCityName(
          position.latitude,
          position.longitude,
        ) ??
        'Unknown';

    final userId = SupabaseConfig.currentUserId;

    await _discoveryRepo.updateLocation(
      userId: userId,
      lat: position.latitude,
      lon: position.longitude,
      city: city,
    );

    if (_isDemo) return;

    final crossed = await _discoveryRepo.fetchCrossedPaths(userId);
    state = state.copyWith(crossedPaths: crossed);
  }

  Future<void> loadCrossedPaths() async {
    if (_isDemo) return;

    final userId = SupabaseConfig.currentUserId;

    final crossed = await _discoveryRepo.fetchCrossedPaths(userId);
    state = state.copyWith(crossedPaths: crossed);
  }

  Future<void> swipeRight(
    UserProfile profile, {
    bool isStandOut = false,
  }) async {
    if (_isDemo) {
      state = state.copyWith(
        deckProfiles: state.deckProfiles
            .where((p) => p.id != profile.id)
            .toList(),
        likedProfiles: [...state.likedProfiles, profile.id],
        swipedProfileIds: [...state.swipedProfileIds, profile.id],
      );
      return;
    }
    final client = _client;

    if (client == null) return;

    final userId = SupabaseConfig.currentUserId;

    if (isStandOut) {
      try {
        await client.from('likes').insert({
          'liker_id': userId,
          'liked_id': profile.id,
          'is_stand_out': true,
        });
      } catch (e) {
        // ignore for demo
      }
    } else {
      try {
        await client.from('likes').insert({
          'liker_id': userId,
          'liked_id': profile.id,
        });

        final existingLike = await client
            .from('likes')
            .select()
            .eq('liker_id', profile.id)
            .eq('liked_id', userId)
            .maybeSingle();

        if (existingLike != null) {
          state = state.copyWith(recentMatchCelebration: profile);
        }
      } catch (e) {
        // ignore for demo
      }
    }

    state = state.copyWith(
      deckProfiles: state.deckProfiles
          .where((p) => p.id != profile.id)
          .toList(),
      likedProfiles: [...state.likedProfiles, profile.id],
      swipedProfileIds: [...state.swipedProfileIds, profile.id],
    );
  }

  void swipeLeft(String profileId) {
    state = state.copyWith(
      deckProfiles: state.deckProfiles.where((p) => p.id != profileId).toList(),
      swipedProfileIds: [...state.swipedProfileIds, profileId],
    );
  }

  void clearCelebration() {
    state = state.copyWith(recentMatchCelebration: null);
  }

  void insertAdvertisement(Advertisement ad) {
    final currentItems = List<Advertisement?>.from(state.feedItems);
    final adIndex = currentItems.indexWhere(
      (item) => item != null && item.id == ad.id,
    );

    if (adIndex == -1) {
      currentItems.insert(state.deckProfiles.length ~/ 3, ad);
    }

    state = state.copyWith(feedItems: currentItems);
  }

  void removeAdvertisement(String adId) {
    state = state.copyWith(
      feedItems: state.feedItems.where((item) => item?.id != adId).toList(),
    );
  }

  Future<void> sendMessage(String matchId, String text) async {
    final userId = SupabaseConfig.currentUserId;

    final newMsg = ChatMessage(
      id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
      senderId: userId,
      text: text,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );

    final updatedMessages = Map<String, List<ChatMessage>>.from(
      state.chatMessages,
    );
    updatedMessages[matchId] = [...(updatedMessages[matchId] ?? []), newMsg];

    state = state.copyWith(chatMessages: updatedMessages);
  }

  void openChat(MatchItem match) {
    // Handled by navigation
  }

  void closeChat() {
    // Handled by navigation
  }

  void blockUser(String userId) {
    state = state.copyWith(
      blockedUserIds: {...state.blockedUserIds, userId},
      deckProfiles: state.deckProfiles.where((p) => p.id != userId).toList(),
      matches: state.matches.where((m) => m.user.id != userId).toList(),
    );
  }

  void reportUser(String userId, String reason) {
    blockUser(userId);
  }

  Future<void> createPlan(
    String title,
    String category,
    String venue,
    String time,
    String description,
  ) async {
    final user = state.currentUser;
    final newPlan = WeekendPlan(
      id: 'plan_${DateTime.now().millisecondsSinceEpoch}',
      creatorId: user.id,
      creatorName: user.name,
      creatorPhoto: user.photos.firstOrNull ?? '',
      title: title,
      category: category,
      venue: venue,
      time: time,
      description: description,
      participants: [user.name],
      isJoined: true,
    );

    state = state.copyWith(plans: [newPlan, ...state.plans]);
  }

  void togglePlanJoin(String planId) {
    final updatedPlans = state.plans.map((plan) {
      if (plan.id == planId) {
        return plan.copyWith(
          isJoined: !plan.isJoined,
          participants: plan.isJoined
              ? plan.participants
                    .where((p) => p != state.currentUser.name)
                    .toList()
              : [...plan.participants, state.currentUser.name],
        );
      }
      return plan;
    }).toList();

    state = state.copyWith(plans: updatedPlans);
  }

  void resetDeck() {
    state = state.copyWith(deckProfiles: const []);
  }

  void dismissCelebration() {
    state = state.copyWith(recentMatchCelebration: null);
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

      // Update interests
      await client.from('user_interests').delete().eq('user_id', profile.id);
      for (final interest in profile.interests) {
        // Get or create interest
        final interestResult = await client
            .from('interests')
            .upsert({'name': interest})
            .select()
            .single();
        await client.from('user_interests').insert({
          'user_id': profile.id,
          'interest_id': interestResult['id'],
        });
      }

      // Update weekend availability in user_settings
      await client.from('user_settings').upsert({
        'user_id': profile.id,
        'weekend_availability': profile.weekendAvailability,
      });
      state = state.copyWith(currentUser: profile);
    } catch (e) {
      debugPrint('Failed to update profile: $e');
      rethrow;
    }
  }

  Future<void> refreshProfile() async {
    final client = _client;
    if (client == null) return;
    final userId = SupabaseConfig.currentUserId;
    try {
      final response = await client
          .from('profiles')
          .select(
            '''            id, display_name, gender, city, bio, relationship_intent,            occupation, education, favorite_music, ideal_weekend,            is_photo_verified, trust_score, last_active_at          ''',
          )
          .eq('id', userId)
          .maybeSingle();
      if (response != null) {
        final photos = await _discoveryRepo.fetchProfilePhotos(userId);
        final interests = await _discoveryRepo.fetchUserInterests(userId);
        final crossedPaths = await _discoveryRepo.fetchCrossedPaths(userId);
        final updatedUser = UserProfile(
          id: response['id'] as String? ?? userId,
          name: response['display_name'] as String? ?? 'User',
          age: 25,
          gender: response['gender'] as String? ?? 'Prefer not to say',
          photos: photos,
          city: response['city'] as String? ?? '',
          distanceKm: 0,
          bio: response['bio'] as String? ?? '',
          occupation: response['occupation'] as String? ?? '',
          education: response['education'] as String? ?? '',
          relationshipIntent:
              response['relationship_intent'] as String? ?? 'Dating',
          interests: interests,
          favoritePlaces: const [],
          languages: const [],
          prompts: const [],
          isPhotoVerified: response['is_photo_verified'] as bool? ?? false,
          trustScore: response['trust_score'] as int? ?? 50,
          crossedPathsCount: crossedPaths.length,
          favoriteMusic: response['favorite_music'] as String? ?? '',
          idealWeekend: response['ideal_weekend'] as String? ?? '',
          referralCode: state.currentUser.referralCode,
          commonInterests: const [],
          weekendAvailability: const {},
          voiceIntroUrl: '',
          compatibilityExplanation: '',
          distanceDisplay: '',
        );
        state = state.copyWith(currentUser: updatedUser);
      }
    } catch (e) {
      debugPrint('Failed to refresh profile: $e');
    }
  }

  void setDateIdeas(List<DateIdea> ideas) {
    state = state.copyWith(dateIdeas: ideas, isGeneratingDateIdeas: false);
  }

  void setIsGeneratingDateIdeas(bool value) {
    state = state.copyWith(isGeneratingDateIdeas: value);
  }

  Future<void> loadReferralData() async {
    if (_isDemo) return;

    final client = _client;

    if (client == null) return;

    final userId = SupabaseConfig.currentUserId;

    try {
      final data = await client.rpc(
        'get_referral_stats',
        params: {'p_user_id': userId},
      );

      if (data != null && (data as List).isNotEmpty) {
        final row = data.first as Map<String, dynamic>;
        state = state.copyWith(
          referralData: ReferralData(
            code: row['referral_code'] as String? ?? state.referralData.code,
            invitedCount: row['invited_count'] as int? ?? 0,
            verifiedCount: row['verified_count'] as int? ?? 0,
            badgeTitle: row['badge_title'] as String? ?? 'New Pioneer',
            achievementTier:
                row['achievement_tier'] as String? ?? 'Bronze Contributor',
            linkUrl: row['link_url'] as String? ?? state.referralData.linkUrl,
          ),
        );
      }
    } catch (e) {
      // ignore
    }
  }
}
