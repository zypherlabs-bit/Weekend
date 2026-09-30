import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import '../models/models.dart';
import '../models/profile_schema.dart';

import '../repositories/discovery_repository.dart';
import '../repositories/match_repository.dart';
import '../repositories/message_repository.dart';
import '../repositories/plan_repository.dart';
import '../repositories/profile_repository.dart';
import '../repositories/profile_save_error.dart';
import '../repositories/safety_repository.dart';
import '../repositories/date_ideas_repository.dart';
import '../services/location_service.dart';

final weekendProvider = StateNotifierProvider<WeekendNotifier, WeekendState>((
  ref,
) {
  return WeekendNotifier(
    discoveryRepository: DiscoveryRepository(),
    profileRepository: ProfileRepository(),
    matchRepository: MatchRepository(),
    messageRepository: MessageRepository(),
    planRepository: PlanRepository(),
    safetyRepository: SafetyRepository(),
    dateIdeasRepository: DateIdeasRepository(),
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
    // A neutral placeholder for the signed-in user. It carries no fabricated
    // personal data: the real profile is loaded from Supabase as soon as the
    // user is authenticated (see [WeekendNotifier.loadCurrentUser]).
    return WeekendState(
      currentUser: UserProfile(
        id: 'me',
        name: '',
        age: 18,
        gender: 'Prefer not to say',
        photos: const [],
        city: '',
        distanceKm: 0,
        bio: '',
        occupation: '',
        education: '',
        relationshipIntent: '',
        interests: const [],
        favoritePlaces: const [],
        languages: const [],
        prompts: const [],
        isPhotoVerified: false,
        trustScore: 50,
        crossedPathsCount: 0,
        favoriteMusic: '',
        idealWeekend: '',
        referralCode: '',
        commonInterests: const [],
        weekendAvailability: const {},
        voiceIntroUrl: '',
        compatibilityExplanation: '',
        distanceDisplay: '',
      ),
      referralData: const ReferralData(code: ''),
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
  final ProfileRepository _profileRepo;
  final MatchRepository _matchRepo;
  final MessageRepository _messageRepo;
  final PlanRepository _planRepo;
  final SafetyRepository _safetyRepo;
  final DateIdeasRepository _dateIdeasRepo;

  WeekendNotifier({
    required DiscoveryRepository discoveryRepository,
    required ProfileRepository profileRepository,
    required MatchRepository matchRepository,
    required MessageRepository messageRepository,
    required PlanRepository planRepository,
    required SafetyRepository safetyRepository,
    required DateIdeasRepository dateIdeasRepository,
  }) : _discoveryRepo = discoveryRepository,
       _profileRepo = profileRepository,
       _matchRepo = matchRepository,
       _messageRepo = messageRepository,
       _planRepo = planRepository,
       _safetyRepo = safetyRepository,
       _dateIdeasRepo = dateIdeasRepository,
       super(WeekendState.initial());

  SupabaseClient? get _client => SupabaseConfig.client;

  bool get _hasBackend => _client != null;

  /// Load the authenticated user's real profile from Supabase and replace the
  /// neutral placeholder. Never fabricates data when the fetch fails — the UI
  /// simply keeps showing whatever is genuinely known.
  /// Fetch and return the signed-in user's real profile row without touching
  /// the shared deck/feed state.
  ///
  /// Returns `null` when there is no session or the read fails, so callers can
  /// say "could not load" instead of rendering a placeholder as if it were the
  /// user's data.
  Future<UserProfile?> loadCurrentUserProfile() async {
    if (!_hasBackend) return null;
    final userId = SupabaseConfig.currentUserId;
    if (userId == 'unauthenticated' || userId == 'me') return null;
    return _profileRepo.fetchUserProfile(userId);
  }

  Future<void> loadCurrentUser() async {
    if (!_hasBackend) return;
    final userId = SupabaseConfig.currentUserId;
    try {
      final profile = await _profileRepo.fetchUserProfile(userId);
      if (profile == null) return;
      final photos = await _discoveryRepo.fetchProfilePhotos(userId);
      final interests = await _discoveryRepo.fetchUserInterests(userId);
      state = state.copyWith(
        currentUser: profile.copyWith(photos: photos, interests: interests),
      );
    } catch (e) {
      debugPrint('Failed to load current user profile: $e');
    }
  }

  /// Load the signed-in user's real matches from Supabase.
  Future<void> loadMatches() async {
    if (!_hasBackend) return;
    final userId = SupabaseConfig.currentUserId;
    try {
      final matches = await _matchRepo.fetchMatches(userId);
      state = state.copyWith(matches: matches);
    } catch (e) {
      debugPrint('Failed to load matches: $e');
    }
  }

  /// Load the signed-in user's real Weekend Plans from Supabase.
  Future<void> loadPlans() async {
    if (!_hasBackend) return;
    final userId = SupabaseConfig.currentUserId;
    try {
      final plans = await _planRepo.fetchPlans(userId);
      state = state.copyWith(plans: plans);
    } catch (e) {
      debugPrint('Failed to load plans: $e');
    }
  }

  void selectDiscoveryMode(DiscoveryMode mode) {
    state = state.copyWith(selectedMode: mode);
  }

  Future<void> loadDiscoveryProfiles() async {
    if (!_hasBackend) {
      // No backend configured: never fabricate profiles. The Discover screen
      // renders its genuine empty state.
      state = state.copyWith(deckProfiles: const [], swipedProfileIds: const []);
      return;
    }
    final userId = SupabaseConfig.currentUserId;

    final prefs = state.locationPreferences;

    final mode = _modeToString(state.selectedMode);

    final client = _client;

    if (client == null) return;

    try {
      final profiles = await _discoveryRepo.loadDiscoveryProfiles(
        userId: userId,
        maxDistanceKm: prefs.discoveryRadiusKm.toDouble(),
        limit: 20,
        mode: mode,
        preferredGenders: prefs.preferredGenders,
        ageMin: 18,
        ageMax: 100,
      );

      final enriched = await Future.wait(
        profiles.map((p) async {
          final photos = await _discoveryRepo.fetchProfilePhotos(p.id);
          return p.copyWith(photos: photos);
        }),
      );

      state = state.copyWith(
        deckProfiles: enriched,
        swipedProfileIds: const [],
      );
    } catch (e) {
      debugPrint('Failed to load discovery profiles: $e');
      state = state.copyWith(deckProfiles: const []);
    }
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

  void setPreferredGenders(List<String> genders) {
    state = state.copyWith(
      locationPreferences: state.locationPreferences.copyWith(
        preferredGenders: genders,
      ),
    );
  }

  /// Persist the in-memory location preferences to the live `user_settings`
  /// row. Rethrows on failure — the discovery filter sheet used to close as if
  /// the radius had been applied even when the write was dropped.
  Future<void> saveLocationPreferences() async {
    final client = _client;

    if (client == null) {
      throw StateError(SupabaseConfig.configError);
    }

    final userId = SupabaseConfig.currentUserId;
    if (userId == 'me' || userId == 'unauthenticated') {
      throw StateError('You are not signed in, so nothing was saved.');
    }

    final prefs = state.locationPreferences;
    await client
        .from('user_settings')
        .upsert({
          'user_id': userId,
          'max_distance_km': prefs.discoveryRadiusKm,
          'location_discovery_enabled': prefs.locationDiscoveryEnabled,
          'nearby_discovery_enabled': prefs.nearbyDiscoveryEnabled,
          'show_distance_enabled': prefs.showDistanceEnabled,
          'travel_mode_enabled': prefs.travelModeEnabled,
          'crossed_paths_enabled': prefs.crossedPathsEnabled,
        },
        // `user_settings` has a surrogate `id` primary key and a separate
        // `unique (user_id)`. With no conflict target, PostgREST targets the
        // PRIMARY KEY, so this became a plain INSERT on every call and hit
        // `user_settings_user_id_key` (23505). The discovery-radius write
        // therefore never persisted and the slider silently reset on next
        // launch - the exact failure the try/catch above was added to surface.
        onConflict: 'user_id')
        .select('user_id')
        .limit(1);
  }

  Future<void> updateLocationIfNeeded() async {
    if (!_hasBackend) return;
    final prefs = state.locationPreferences;
    if (!prefs.locationDiscoveryEnabled && !prefs.nearbyDiscoveryEnabled) {
      return;
    }

    final position = await LocationService.getCurrentPosition();
    if (position == null) return;

    // A failed reverse geocode must not persist the literal string
    // "Unknown" as the user's city: it becomes their real profile city and
    // feeds every city-filtered discovery query.
    final city = await LocationService.getCityName(
      position.latitude,
      position.longitude,
    );
    if (city == null || city.trim().isEmpty) return;

    final userId = SupabaseConfig.currentUserId;

    await _discoveryRepo.updateLocation(
      userId: userId,
      lat: position.latitude,
      lon: position.longitude,
      city: city.trim(),
    );

    final crossed = await _discoveryRepo.fetchCrossedPaths(userId);
    state = state.copyWith(crossedPaths: crossed);
  }

  Future<void> loadCrossedPaths() async {
    if (!_hasBackend) return;

    final userId = SupabaseConfig.currentUserId;

    final crossed = await _discoveryRepo.fetchCrossedPaths(userId);
    state = state.copyWith(crossedPaths: crossed);
  }

  /// Express interest in [profile]. Persists the like server-side and returns
  /// `true` when the like completes a mutual match (the match itself is
  /// created transactionally by the `check_mutual_like` database trigger).
  ///
  /// Duplicate submissions are guarded: a profile already swiped in this
  /// session is ignored, and a repeat like is absorbed by the database's
  /// unique constraint.
  Future<bool> swipeRight(
    UserProfile profile, {
    bool isStandOut = false,
  }) async {
    if (state.swipedProfileIds.contains(profile.id)) return false;

    // Optimistically remove the card so the UI stays responsive on slow
    // networks and the same card can never be submitted twice.
    state = state.copyWith(
      deckProfiles:
          state.deckProfiles.where((p) => p.id != profile.id).toList(),
      likedProfiles: [...state.likedProfiles, profile.id],
      swipedProfileIds: [...state.swipedProfileIds, profile.id],
    );

    if (!_hasBackend) return false;

    final userId = SupabaseConfig.currentUserId;

    try {
      final outcome = await _matchRepo.recordLike(
        userId,
        profile.id,
        isStandOut: isStandOut,
      );

      switch (outcome) {
        case LikeOutcome.matched:
          state = state.copyWith(recentMatchCelebration: profile);
          unawaited(loadMatches());
          return true;
        case LikeOutcome.recorded:
          return false;
        case LikeOutcome.failed:
          _restoreCard(profile);
          return false;
      }
    } catch (e) {
      debugPrint('Failed to record like for ${profile.id}: $e');
      _restoreCard(profile);
      return false;
    }
  }

  /// Put a card back at the front of the deck after the server rejected the
  /// interaction.
  ///
  /// The optimistic removal at the top of [swipeRight] removed the card from
  /// `deckProfiles` and added its id to `swipedProfileIds`. When the write
  /// fails, that state is a lie: the profile was never dealt with, yet it is
  /// unreachable for the rest of the session. Both halves are undone here, and
  /// the profile object is put back first in the deck so the user can act on it
  /// again without waiting for a refresh.
  void _restoreCard(UserProfile profile) {
    state = state.copyWith(
      deckProfiles: [
        profile,
        ...state.deckProfiles.where((p) => p.id != profile.id),
      ],
      likedProfiles:
          state.likedProfiles.where((id) => id != profile.id).toList(),
      swipedProfileIds:
          state.swipedProfileIds.where((id) => id != profile.id).toList(),
    );
  }

  /// Pass on a profile. The pass is persisted server-side so the profile
  /// stays excluded from future discovery results.
  Future<void> swipeLeft(String profileId) async {
    if (state.swipedProfileIds.contains(profileId)) return;

    // Held before the optimistic removal below. Once the card is out of
    // `deckProfiles` there is nothing left to restore it from, and the rollback
    // on a failed write would have nothing to put back.
    UserProfile? removed;
    for (final profile in state.deckProfiles) {
      if (profile.id == profileId) {
        removed = profile;
        break;
      }
    }

    state = state.copyWith(
      deckProfiles:
          state.deckProfiles.where((p) => p.id != profileId).toList(),
      swipedProfileIds: [...state.swipedProfileIds, profileId],
    );

    if (!_hasBackend) return;

    final userId = SupabaseConfig.currentUserId;

    try {
      await _matchRepo.recordPass(userId, profileId);
    } catch (e) {
      debugPrint('Failed to record pass for $profileId: $e');
      // Same honesty requirement as a like: if the pass was not recorded, the
      // profile is still in future results and the user should be able to pass
      // on it again rather than lose the card silently.
      final profile = removed;
      if (profile != null) {
        _restoreCard(profile);
      }
    }
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

  /// Persist a chat message through Supabase. Delivery to both participants
  /// happens via the Realtime stream; no local echo is fabricated here (the
  /// persisted row arrives through the subscription).
  Future<void> sendMessage(String matchId, String text) async {
    if (!_hasBackend) {
      // Without a backend the message cannot be delivered. Keep the local
      // echo so the chat UI remains functional for offline development, but
      // never pretend the message was delivered.
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
      updatedMessages[matchId] = [
        ...(updatedMessages[matchId] ?? []),
        newMsg,
      ];

      state = state.copyWith(chatMessages: updatedMessages);
      return;
    }

    await _messageRepo.sendMessage(matchId, text);
  }

  void openChat(MatchItem match) {
    // Handled by navigation
  }

  void closeChat() {
    // Handled by navigation
  }

  /// Block a user. Persisted to the `blocks` table; blocked users disappear
  /// from discovery and are prevented from messaging by server-side rules.
  ///
  /// Rethrows when the block could not be persisted. The UI used to close the
  /// sheet and stay silent while this only printed to the console, which made
  /// a failed block indistinguishable from a successful one.
  Future<void> blockUser(String userId) async {
    if (userId == 'me' || userId.isEmpty) return;

    // Persist first: the local state below is an optimistic mirror of the
    // database, never a substitute for it.
    if (_hasBackend) {
      await _safetyRepo.blockUser(SupabaseConfig.currentUserId, userId);
    }

    state = state.copyWith(
      blockedUserIds: {...state.blockedUserIds, userId},
      deckProfiles:
          state.deckProfiles.where((p) => p.id != userId).toList(),
      matches: state.matches.where((m) => m.user.id != userId).toList(),
    );
  }

  /// Report a user for [reason]. The report is persisted to the `reports`
  /// table for moderation, and the reported user is blocked as a safety
  /// measure.
  ///
  /// Rethrows when the report could not be persisted, so a caller never
  /// announces "Report submitted" for a write the server rejected.
  Future<void> reportUser(String userId, String reason) async {
    if (_hasBackend && userId != 'me' && userId.isNotEmpty) {
      await _safetyRepo.reportUser(
        SupabaseConfig.currentUserId,
        userId,
        reason,
      );
    }
    await blockUser(userId);
  }

  /// Remove a block previously created by the signed-in user.
  Future<void> unblockUser(String userId) async {
    if (_hasBackend && userId != 'me' && userId.isNotEmpty) {
      await _safetyRepo.unblockUser(SupabaseConfig.currentUserId, userId);
    }
    state = state.copyWith(
      blockedUserIds: {...state.blockedUserIds}..remove(userId),
    );
  }

  /// The users the signed-in user has blocked, read from the live `blocks`
  /// table. Returns an empty list when the backend is unreachable — callers
  /// must show that as "could not load", never as "no blocked users".
  Future<List<String>> loadBlockedUserIds() async {
    if (!_hasBackend) return const [];
    final userId = SupabaseConfig.currentUserId;
    if (userId == 'me' || userId == 'unauthenticated') return const [];
    final rows = await _safetyRepo.fetchBlockedUserIds(userId);
    state = state.copyWith(blockedUserIds: {...rows});
    return rows;
  }

  /// Create a Weekend Plan. Persisted to the `plans` table; the list is
  /// refreshed from the database so the UI always reflects real data.
  Future<void> createPlan(
    String title,
    String category,
    String venue,
    String time,
    String description,
  ) async {
    final user = state.currentUser;

    // Optimistic insert with a temporary id so the card appears instantly.
    final tempPlan = WeekendPlan(
      id: 'temp_${DateTime.now().millisecondsSinceEpoch}',
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

    state = state.copyWith(plans: [tempPlan, ...state.plans]);

    if (!_hasBackend) return;

    try {
      await _planRepo.createPlan(
        userId: SupabaseConfig.currentUserId,
        title: title,
        category: category,
        venue: venue,
        time: time,
        description: description,
      );
      await loadPlans();
    } catch (e) {
      // Roll the optimistic insert back so the UI never shows a plan that
      // was not actually created.
      state = state.copyWith(
        plans: state.plans.where((p) => p.id != tempPlan.id).toList(),
      );
      debugPrint('Failed to create plan: $e');
      rethrow;
    }
  }

  /// Join or leave a Weekend Plan. Persisted to `plan_participants` and
  /// re-synced from the database.
  Future<void> togglePlanJoin(String planId) async {
    if (planId.startsWith('temp_')) return;

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

    if (!_hasBackend) return;

    try {
      await _planRepo.togglePlanJoin(
        SupabaseConfig.currentUserId,
        planId,
        state.currentUser.name,
      );
      await loadPlans();
    } catch (e) {
      debugPrint('Failed to toggle plan join for $planId: $e');
      await loadPlans();
    }
  }

  void resetDeck() {
    state = state.copyWith(deckProfiles: const []);
  }

  void dismissCelebration() {
    state = state.copyWith(recentMatchCelebration: null);
  }

  /// Persist the signed-in user's profile to LIVE Supabase.
  ///
  /// The primary write goes through [ProfileRepository.updateProfile], which
  /// addresses the id from the Supabase **auth session** (never
  /// `profile.id` — `WeekendState.initial()` seeds the `'me'` placeholder)
  /// and recovers from a missing profile row by inserting it under the
  /// caller's own id. Any failure is rethrown as a classified
  /// [ProfileSaveException] so the UI can show actionable text, and local
  /// state only changes after the database confirmed the write.
  ///
  /// The bio is pre-checked against the 014 social-media policy RPC before
  /// anything is written so blocked content fails fast with a clear message.
  /// The database trigger stays the enforcement authority: if the RPC is
  /// unavailable the save proceeds and the trigger decides.
  ///
  /// The secondary writes (interests, weekend availability, restoring a
  /// missing `preferences` row) are reported instead of thrown: they used to
  /// run inside this same try/catch, so a single failing auxiliary write
  /// rolled back the *reported* outcome of a profile save that had in fact
  /// succeeded, leaving the user stuck on the screen with a "failed" message.
  /// The returned list is empty when every part persisted.
  /// The catalogue category for an interest name, or null when unknown.
  ///
  /// Keeps a newly-inserted interest grouped in the picker exactly like the
  /// seeded ones, so a name the user typed by hand still appears somewhere
  /// sensible instead of in a bare "Other" bucket.
  static String? _interestCategoryFor(String name) {
    for (final entry in ProfileSchema.interestCategories.entries) {
      if (entry.value.contains(name)) return entry.key;
    }
    return null;
  }

  Future<List<String>> updateProfile(UserProfile profile) async {
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

    // ---- Bio policy pre-check (014): fail fast, before any write. ----------
    final bio = profile.bio.trim();
    if (bio.isNotEmpty) {
      try {
        final detection = await client.rpc(
          'detect_social_media_in_text',
          params: {'p_text': bio},
        );
        if (detection is Map && detection['detected'] == true) {
          const error = ProfileSaveException(
            ProfileSaveFailure.validation,
            stage: 'bio.precheck',
          );
          error.log();
          throw error;
        }
      } on ProfileSaveException {
        rethrow;
      } catch (e) {
        // Pre-check unavailable (older backend) or transient failure: the
        // save proceeds and the server-side trigger enforces the policy.
        debugPrint('bio pre-check skipped (${e.runtimeType})');
      }
    }

    // ---- Primary write: the profile itself (with orphan recovery). ---------
    // Throws a classified ProfileSaveException; a save that changed nothing
    // is never reported as a success.
    await _profileRepo.updateProfile(profile);

    // ---- Secondary writes: reported, never silently swallowed. -------------
    final warnings = <String>[];

    try {
      // The delete runs UNCONDITIONALLY. It used to be guarded by
      // `interests.isNotEmpty`, so a user who deselected their last interest
      // kept it forever and was told nothing - the save silently no-opped for
      // the one field they actually changed.
      await client.from('user_interests').delete().eq('user_id', authId);
      for (final interest in profile.interests) {
        final trimmed = interest.trim();
        if (trimmed.isEmpty) continue;
        // The master list is shared, so an interest that does not exist yet has
        // to be created before it can be linked. That used to be
        //   client.from('interests').upsert({'name': ...}).select('id').single()
        // which was broken twice over:
        //   * `upsert` with no `id` cannot conflict on the primary key, so the
        //     second user to pick the same interest hit the unique violation on
        //     `name` and the whole interests block was reported as unsaved;
        //   * PostgREST expands it to INSERT ... ON CONFLICT DO UPDATE, which
        //     required an UPDATE policy on `interests` that migration 018
        //     opened to every signed-in user - anyone could rewrite any
        //     interest and change the chip on every profile that used it.
        //
        // `ensure_interest` get-or-creates atomically and never updates an
        // existing row, so both problems go away and the UPDATE grant is no
        // longer needed.
        final category = _interestCategoryFor(trimmed);
        final interestId = await client.rpc(
          'ensure_interest',
          params: {'p_name': trimmed, 'p_category': category},
        );

        if (interestId is! String || interestId.isEmpty) {
          throw StateError('interest_not_resolved');
        }

        await client.from('user_interests').insert({
          'user_id': authId,
          'interest_id': interestId,
        });
      }
    } catch (e) {
      // Code/type only: an interest name is user content, never logged.
      debugPrint(
        'interests write failed (${e.runtimeType}) '
        '${classifyProfileSaveError(e).code}',
      );
      warnings.add('Your interests were not saved.');
    }

    try {
      // Languages were editable in the profile model but never written, so the
      // value silently reverted on the next load.
      final languages = profile.languages
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toSet()
          .take(8)
          .toList(growable: false);
      if (languages.isNotEmpty && languages.length != profile.languages.length) {
        throw StateError('too many languages');
      }
      await client
          .from('profiles')
          .update({'languages': languages})
          .eq('id', authId);
    } catch (e) {
      debugPrint(
        'languages write failed (${e.runtimeType}) '
        '${classifyProfileSaveError(e).code}',
      );
      warnings.add('Your languages were not saved.');
    }

    try {
      // `onConflict: user_id` pins the upsert to the per-user unique row so
      // it can never target anything else.
      await client.from('user_settings').upsert(
        {
          'user_id': authId,
          'weekend_availability': profile.weekendAvailability,
        },
        onConflict: 'user_id',
      );
    } catch (e) {
      debugPrint(
        'weekend availability write failed (${e.runtimeType}) '
        '${classifyProfileSaveError(e).code}',
      );
      warnings.add('Your weekend availability was not saved.');
    }

    // The signup trigger creates this row, but an account orphaned before the
    // trigger existed would have `profiles` without `preferences`. Restore it
    // here so discovery preferences keep working for repaired accounts.
    try {
      final prefs = await client
          .from('preferences')
          .select('id')
          .eq('user_id', authId)
          .limit(1);
      if (prefs.isEmpty) {
        await client.from('preferences').insert({'user_id': authId});
      }
    } catch (e) {
      // A concurrent save inserting the same row (23505) is fine.
      final raced = e is PostgrestException && e.code == '23505';
      if (!raced) {
        debugPrint(
          'preferences restore failed (${e.runtimeType}) '
          '${classifyProfileSaveError(e).code}',
        );
        warnings.add('Your discovery preferences could not be restored.');
      }
    }

    state = state.copyWith(currentUser: profile.copyWith(id: authId));
    return warnings;
  }

  /// Reload the signed-in user's profile (and their just-uploaded photos) from
  /// LIVE Supabase.
  ///
  /// Every field comes from the database, including the age derived from
  /// `date_of_birth` and the weekend availability stored in `user_settings` —
  /// this replaced hard-coded placeholders that made a freshly saved profile
  /// render with stale or invented values.
  Future<void> refreshProfile() async {
    final client = _client;
    if (client == null) return;
    final userId = SupabaseConfig.currentUserId;
    if (userId == 'unauthenticated' || userId == 'me') return;
    try {
      final response = await client
          .from('profiles')
          .select(
            'id, display_name, date_of_birth, gender, city, bio, '
            'relationship_intent, occupation, education, favorite_music, '
            'ideal_weekend, is_photo_verified, trust_score, referral_code, '
            'last_active_at, prompts, languages, smoking, drinking, '
            'exercise, pets, children, height_cm',
          )
          .eq('id', userId)
          .maybeSingle();
      if (response == null) return;
      final photos = await _discoveryRepo.fetchProfilePhotos(userId);
      final interests = await _discoveryRepo.fetchUserInterests(userId);
      final crossedPaths = await _discoveryRepo.fetchCrossedPaths(userId);
      final dateOfBirth = DateTime.tryParse(
        response['date_of_birth'] as String? ?? '',
      );
      Map<String, bool> availability = {};
      try {
        final settings = await client
            .from('user_settings')
            .select('weekend_availability')
            .eq('user_id', userId)
            .maybeSingle();
        final raw = settings?['weekend_availability'];
        if (raw is Map) {
          availability = {
            for (final entry in raw.entries)
              if (entry.key is String) entry.key as String: entry.value == true,
          };
        }
      } catch (_) {
        // Non-critical: the chips simply render unselected.
      }
      final updatedUser = UserProfile(
        id: response['id'] as String? ?? userId,
        name: response['display_name'] as String? ?? '',
        age: dateOfBirth == null
            ? 18
            : DateTime.now().difference(dateOfBirth).inDays ~/ 365,
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
        languages:
            (response['languages'] as List?)?.map((e) => e.toString()).toList() ??
            const [],
        prompts: ProfileRepository.decodePrompts(response['prompts']),
        isPhotoVerified: response['is_photo_verified'] as bool? ?? false,
        trustScore: response['trust_score'] as int? ?? 50,
        crossedPathsCount: crossedPaths.length,
        favoriteMusic: response['favorite_music'] as String? ?? '',
        idealWeekend: response['ideal_weekend'] as String? ?? '',
        referralCode: response['referral_code'] as String? ?? '',
        commonInterests: const [],
        weekendAvailability: availability,
        voiceIntroUrl: '',
        compatibilityExplanation: '',
        distanceDisplay: '',
        smoking: response['smoking'] as String?,
        drinking: response['drinking'] as String?,
        exercise: response['exercise'] as String?,
        pets: response['pets'] as String?,
        children: response['children'] as String?,
        heightCm: (response['height_cm'] as num?)?.toInt(),
      );
      state = state.copyWith(currentUser: updatedUser);
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

  /// Fetch AI-generated date ideas from the `date-ideas` Edge Function.
  ///
  /// [partnerInterests] are the interests of the person the user matched with.
  /// [city] is the user's current city. Both may be empty — the function falls
  /// back to defaults in that case.
  ///
  /// The method toggles `isGeneratingDateIdeas` and populates `dateIdeas` on
  /// completion. On any failure, `dateIdeas` is left empty and the loading
  /// flag is cleared — the UI shows its genuine empty state rather than a
  /// fabricated message.
  Future<void> generateDateIdeas({
    required List<String> partnerInterests,
    required String city,
  }) async {
    final userInterests = state.currentUser.interests;

    setIsGeneratingDateIdeas(true);

    try {
      final (ideas, source) = await _dateIdeasRepo.fetchDateIdeas(
        city: city,
        userInterests: userInterests,
        partnerInterests: partnerInterests,
      );

      if (!mounted) return;
      setDateIdeas(ideas);
    } catch (e) {
      if (!mounted) return;
      debugPrint('Failed to generate date ideas: $e');
      setIsGeneratingDateIdeas(false);
    }
  }

  Future<void> loadReferralData() async {
    if (!_hasBackend) return;

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
            badgeTitle: row['badge_title'] as String? ?? '',
            achievementTier: row['achievement_tier'] as String? ?? '',
            linkUrl: row['link_url'] as String? ?? '',
          ),
        );
      }
    } catch (e) {
      // ignore
    }
  }
}
