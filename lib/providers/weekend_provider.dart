import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';
import '../repositories/discovery_repository.dart';
import '../repositories/profile_repository.dart';
import '../repositories/ad_repository.dart';
import '../services/location_service.dart';

final weekendProvider = StateNotifierProvider<WeekendNotifier, WeekendState>((ref) {
  return WeekendNotifier(
    discoveryRepository: DiscoveryRepository(),
    profileRepository: ProfileRepository(),
    adRepository: AdRepository(),
  );
});

final locationPreferencesProvider =
    StateProvider<LocationPreferences>((ref) {
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
          'https://images.unsplash.com/photo-1539571696357-5a69c17a67c6?auto=format&fit=crop&w=800&q=80'
        ],
        city: 'Pune',
        distanceKm: 0,
        bio: 'Tech builder, specialty coffee addict, and spontaneous weekend trekker.',
        occupation: 'Software Developer',
        education: 'University Graduate',
        relationshipIntent: 'Dating & Weekend Plans',
        interests: const ['Specialty Coffee', 'Hiking', 'Indie Music', 'Cycling', 'Travel', 'F1'],
        favoritePlaces: const ['Blue Tokai Cafe', 'Koregaon Park', 'ARAI Hills'],
        languages: const ['English', 'Hindi'],
        prompts: const [
          ProfilePrompt(prompt: 'My ideal weekend is...', answer: 'Trying a new brunch spot followed by an outdoor trek.'),
          ProfilePrompt(prompt: 'Let\'s go...', answer: 'To that hidden sourdough bakery in Camp!'),
        ],
        isPhotoVerified: true,
        trustScore: 98,
        crossedPathsCount: 7,
        favoriteMusic: 'Coldplay, Prateek Kuhad, Tame Impala',
        idealWeekend: 'Acoustic gigs & hill climbs',
        referralCode: 'WEEKEND-MX07',
      ),
      referralData: const ReferralData(code: 'WEEKEND-MX07'),
      selectedMode: DiscoveryMode.FOR_YOU,
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
      recentMatchCelebration: recentMatchCelebration ?? this.recentMatchCelebration,
      dateIdeas: dateIdeas ?? this.dateIdeas,
      isGeneratingDateIdeas: isGeneratingDateIdeas ?? this.isGeneratingDateIdeas,
      swipedProfileIds: swipedProfileIds ?? this.swipedProfileIds,
      locationPreferences: locationPreferences ?? this.locationPreferences,
      feedItems: feedItems ?? this.feedItems,
      crossedPaths: crossedPaths ?? this.crossedPaths,
    );
  }
}

class WeekendNotifier extends StateNotifier<WeekendState> {
  final DiscoveryRepository _discoveryRepo;
  final ProfileRepository _profileRepo;
  final AdRepository _adRepo;

  WeekendNotifier({
    required DiscoveryRepository discoveryRepository,
    required ProfileRepository profileRepository,
    required AdRepository adRepository,
  })  : _discoveryRepo = discoveryRepository,
        _profileRepo = profileRepository,
        _adRepo = adRepository,
        super(WeekendState.initial());

  void selectDiscoveryMode(DiscoveryMode mode) {
    state = state.copyWith(selectedMode: mode);
  }

  Future<void> loadDiscoveryProfiles() async {
    final userId = Supabase.instance.client.auth.currentUser?.id ?? 'user_me';
    final prefs = state.locationPreferences;

    final mode = _modeToString(state.selectedMode);
    final profiles = await _discoveryRepo.loadDiscoveryProfiles(
      userId: userId,
      maxDistanceKm: prefs.discoveryRadiusKm.toDouble(),
      limit: 20,
      mode: mode,
    );

    final enriched = await Future.wait(profiles.map((p) async {
      final photos = await _discoveryRepo.fetchProfilePhotos(p.id);
      return p.copyWith(photos: photos);
    }));

    state = state.copyWith(deckProfiles: enriched, swipedProfileIds: const []);
  }

  String _modeToString(DiscoveryMode mode) {
    switch (mode) {
      case DiscoveryMode.NEARBY:
        return 'nearby';
      case DiscoveryMode.CROSSED_PATHS:
        return 'crossed_paths';
      case DiscoveryMode.GLOBAL:
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
    final userId = Supabase.instance.client.auth.currentUser?.id ?? 'user_me';
    final prefs = state.locationPreferences;
    try {
      await Supabase.instance.client
          .from('user_settings')
          .update({
            'max_distance_km': prefs.discoveryRadiusKm,
          })
          .eq('user_id', userId);
    } catch (e) {
      // ignore
    }
  }

  Future<void> updateLocationIfNeeded() async {
    final prefs = state.locationPreferences;
    if (!prefs.locationDiscoveryEnabled && !prefs.nearbyDiscoveryEnabled) return;

    final position = await LocationService.getCurrentPosition();
    if (position == null) return;

    final city = await LocationService.getCityName(
      position.latitude, position.longitude,
    ) ?? 'Unknown';

    final userId = Supabase.instance.client.auth.currentUser?.id ?? 'user_me';
    await _discoveryRepo.updateLocation(
      userId: userId,
      lat: position.latitude,
      lon: position.longitude,
      city: city,
    );

    final crossed = await _discoveryRepo.fetchCrossedPaths(userId);
    state = state.copyWith(crossedPaths: crossed);
  }

  Future<void> loadCrossedPaths() async {
    final userId = Supabase.instance.client.auth.currentUser?.id ?? 'user_me';
    final crossed = await _discoveryRepo.fetchCrossedPaths(userId);
    state = state.copyWith(crossedPaths: crossed);
  }

  Future<void> swipeRight(UserProfile profile, {bool isStandOut = false}) async {
    final userId = Supabase.instance.client.auth.currentUser?.id ?? 'user_me';

    if (isStandOut) {
      try {
        await Supabase.instance.client.from('likes').insert({
          'liker_id': userId,
          'liked_id': profile.id,
          'is_stand_out': true,
        });
      } catch (e) {
        // ignore for demo
      }
    } else {
      try {
        await Supabase.instance.client.from('likes').insert({
          'liker_id': userId,
          'liked_id': profile.id,
        });

        final existingLike = await Supabase.instance.client
            .from('likes')
            .select()
            .eq('liker_id', profile.id)
            .eq('liked_id', userId)
            .maybeSingle();

        if (existingLike != null) {
          state = state.copyWith(
            recentMatchCelebration: profile,
          );
        }
      } catch (e) {
        // ignore for demo
      }
    }

    state = state.copyWith(
      deckProfiles: state.deckProfiles.where((p) => p.id != profile.id).toList(),
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
    final userId = Supabase.instance.client.auth.currentUser?.id ?? 'user_me';
    final newMsg = ChatMessage(
      id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
      senderId: userId,
      text: text,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );

    final updatedMessages = Map<String, List<ChatMessage>>.from(state.chatMessages);
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

  Future<void> createPlan(String title, String category, String venue, String time, String description) async {
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
              ? plan.participants.where((p) => p != state.currentUser.name).toList()
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

  void setDateIdeas(List<DateIdea> ideas) {
    state = state.copyWith(dateIdeas: ideas, isGeneratingDateIdeas: false);
  }

  void setIsGeneratingDateIdeas(bool value) {
    state = state.copyWith(isGeneratingDateIdeas: value);
  }

  Future<void> loadReferralData() async {
    final userId = Supabase.instance.client.auth.currentUser?.id ?? 'user_me';
    try {
      final data = await Supabase.instance.client.rpc('get_referral_stats', params: {
        'p_user_id': userId,
      });

      if (data != null && (data as List).isNotEmpty) {
        final row = data.first as Map<String, dynamic>;
        state = state.copyWith(
          referralData: ReferralData(
            code: row['referral_code'] as String? ?? state.referralData.code,
            invitedCount: row['invited_count'] as int? ?? 0,
            verifiedCount: row['verified_count'] as int? ?? 0,
            badgeTitle: row['badge_title'] as String? ?? 'New Pioneer',
            achievementTier: row['achievement_tier'] as String? ?? 'Bronze Contributor',
            linkUrl: row['link_url'] as String? ?? state.referralData.linkUrl,
          ),
        );
      }
    } catch (e) {
      // ignore
    }
  }
}
