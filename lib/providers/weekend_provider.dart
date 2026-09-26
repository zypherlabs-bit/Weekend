import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import '../models/models.dart';

import '../repositories/discovery_repository.dart';
import '../repositories/match_repository.dart';
import '../repositories/message_repository.dart';
import '../repositories/plan_repository.dart';
import '../repositories/profile_repository.dart';
import '../repositories/safety_repository.dart';
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

  WeekendNotifier({
    required DiscoveryRepository discoveryRepository,
    required ProfileRepository profileRepository,
    required MatchRepository matchRepository,
    required MessageRepository messageRepository,
    required PlanRepository planRepository,
    required SafetyRepository safetyRepository,
  }) : _discoveryRepo = discoveryRepository,
       _profileRepo = profileRepository,
       _matchRepo = matchRepository,
       _messageRepo = messageRepository,
       _planRepo = planRepository,
       _safetyRepo = safetyRepository,
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
        })
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
      final matched = await _matchRepo.recordLike(
        userId,
        profile.id,
        isStandOut: isStandOut,
      );
      if (matched) {
        state = state.copyWith(recentMatchCelebration: profile);
        unawaited(loadMatches());
      }
      return matched;
    } catch (e) {
      debugPrint('Failed to record like for ${profile.id}: $e');
      return false;
    }
  }

  /// Pass on a profile. The pass is persisted server-side so the profile
  /// stays excluded from future discovery results.
  Future<void> swipeLeft(String profileId) async {
    if (state.swipedProfileIds.contains(profileId)) return;

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
  /// Every write is addressed to the id from the Supabase **auth session**,
  /// not to `profile.id`. `WeekendState.initial()` seeds a placeholder profile
  /// with `id == 'me'`; writing to that id matches zero rows, and PostgREST
  /// reports a zero-row UPDATE as a success — which is exactly how Edit
  /// Profile could report "Profile updated successfully!" while persisting
  /// nothing and never advancing.
  ///
  /// The `profiles` write is verified (`.select('id')`) before any dependent
  /// writes run, and a failure is rethrown so the UI can show it. Local state
  /// is only updated after the database confirmed the change.
  ///
  /// The secondary writes (interests, weekend availability) are reported
  /// instead of thrown: they used to run inside this same try/catch, so a
  /// single failing auxiliary write rolled back the *reported* outcome of a
  /// profile save that had in fact succeeded, leaving the user stuck on the
  /// screen with a "failed" message. The returned list is empty when every
  /// part persisted.
  Future<List<String>> updateProfile(UserProfile profile) async {
    final client = _client;
    if (client == null) {
      throw StateError(SupabaseConfig.configError);
    }
    final authId = client.auth.currentUser?.id;
    if (authId == null || authId == 'unauthenticated' || authId == 'me') {
      throw StateError(
        'You are not signed in, so the profile could not be saved.',
      );
    }

    // ---- Primary write: the profile itself. Failing here is a real failure. --
    try {
      final updated = await client
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
          .eq('id', authId)
          .select('id')
          .limit(1);

      if (updated.isEmpty) {
        // RLS silently filters unmatched rows, so this is how a blocked or
        // missing profile row surfaces. Never report it as a success.
        throw StateError(
          'The server did not save your profile. Please try again.',
        );
      }
    } on StateError {
      rethrow;
    } catch (e) {
      debugPrint('Failed to update profile: $e');
      // PostgREST failures arrive as opaque "server error" text. The two
      // live causes are a schema/check mismatch (relationship-intent label,
      // social-media bio trigger, column grant) and an RLS rejection — map
      // them to something the user can act on.
      throw StateError(_profileSaveErrorMessage(e));
    }

    // ---- Secondary writes: reported, never silently swallowed. --------------
    final warnings = <String>[];

    if (profile.interests.isNotEmpty) {
      try {
        // The master list is shared, so an interest that does not exist yet is
        // inserted and then linked to this user only.
        await client.from('user_interests').delete().eq('user_id', authId);
        for (final interest in profile.interests) {
          final trimmed = interest.trim();
          if (trimmed.isEmpty) continue;
          final interestResult = await client
              .from('interests')
              .upsert({'name': trimmed})
              .select('id')
              .single();
          await client.from('user_interests').insert({
            'user_id': authId,
            'interest_id': interestResult['id'],
          });
        }
      } catch (e) {
        debugPrint('Failed to update interests: $e');
        warnings.add('Your interests were not saved.');
      }
    }

    try {
      await client.from('user_settings').upsert({
        'user_id': authId,
        'weekend_availability': profile.weekendAvailability,
      });
    } catch (e) {
      debugPrint('Failed to update weekend availability: $e');
      warnings.add('Your weekend availability was not saved.');
    }

    state = state.copyWith(currentUser: profile.copyWith(id: authId));
    return warnings;
  }

  /// Map a `profiles` UPDATE failure to actionable text.
  ///
  /// The save writes exactly the columns migration 006 grants to clients, so
  /// a rejection is one of: an RLS/ownership rejection (stale session), a
  /// CHECK violation (relationship-intent label or the social-media bio
  /// trigger from 014), or a missing-column error when the live database is
  /// behind the app's migrations. The raw PostgREST message would otherwise
  /// surface as "unable to proceed".
  static String _profileSaveErrorMessage(Object e) {
    final msg = e.toString().toLowerCase();
    if (msg.contains('row-level security') ||
        msg.contains('rls') ||
        msg.contains('policy') ||
        msg.contains('42501') ||
        msg.contains('not authorized')) {
      return 'Your profile could not be saved. Please sign out and sign back '
          'in, then try again.';
    }
    if (msg.contains('relationship_intent') ||
        msg.contains('check constraint') ||
        msg.contains('23514')) {
      return 'Your profile could not be saved. Please re-select your dating '
          'preference and try again.';
    }
    if (msg.contains('social media') || msg.contains('validate_profile_bio')) {
      return 'Your bio contains a social media handle or link, which is not '
          'allowed. Please remove it and try again.';
    }
    if (msg.contains('does not exist') || msg.contains('42703')) {
      return 'The app and the database are out of sync. Please update to the '
          'latest version and try again.';
    }
    return 'Your profile could not be saved. Check your connection and try again.';
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
            'last_active_at',
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
        languages: const [],
        prompts: const [],
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
