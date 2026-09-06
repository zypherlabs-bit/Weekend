import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';

final weekendProvider = StateNotifierProvider<WeekendNotifier, WeekendState>((ref) {
  return WeekendNotifier();
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
    );
  }
}

class WeekendNotifier extends StateNotifier<WeekendState> {
  WeekendNotifier() : super(WeekendState.initial());

  void selectDiscoveryMode(DiscoveryMode mode) {
    state = state.copyWith(selectedMode: mode);
  }

  void setMaxDistance(int km) {
    state = state.copyWith(maxDistanceKm: km);
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
    }
    
    state = state.copyWith(
      deckProfiles: state.deckProfiles.where((p) => p.id != profile.id).toList(),
      likedProfiles: [...state.likedProfiles, profile.id],
    );
  }

  void swipeLeft(String profileId) {
    state = state.copyWith(
      deckProfiles: state.deckProfiles.where((p) => p.id != profileId).toList(),
    );
  }

  void clearCelebration() {
    state = state.copyWith(recentMatchCelebration: null);
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
}
