import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../config/supabase_config.dart';
import '../../providers/weekend_provider.dart';
import '../../models/models.dart';
import '../../services/ad_service.dart';
import '../../repositories/ad_repository.dart';
import '../../repositories/discovery_repository.dart';
import '../../widgets/discovery_card.dart';
import '../../widgets/weekend_design_system.dart';
import '../../widgets/weekend_empty_state.dart';
import '../../services/location_service.dart';
import '../../providers/interactions_provider.dart';
import '../../providers/feature_providers.dart';
import '../likes/likes_screen.dart';
import '../notifications/notifications_screen.dart';
import '../profile/profile_screen.dart';
import '../discovery/explore_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _currentIndex = 0;
  bool _showLocationBanner = false;
  /// Reads the notification badge.
  int get _unreadNotifications => ref.watch(unreadCountProvider);

/// The tab stack.
///
/// Both new surfaces are embedded rather than pushed so switching tabs
/// preserves their scroll position and loaded pages, which is the point of an
/// IndexedStack. `onNavigate` routes notification taps back through the tab
/// index instead of trying to push onto a navigation stack that does not exist
/// at this depth.
List<Widget> get _screens => [
    const DiscoverScreen(),
    const ExploreScreen(),
    MatchesScreen(
      onDiscoverTap: () => setState(() => _currentIndex = 0),
    ),
    const ProfileTabScreen(),
    // Embedded rather than pushed so switching tabs preserves their scroll
    // position and loaded pages.
    LikesScreen(
      onOpenDiscover: () => setState(() => _currentIndex = 0),
    ),
    NotificationCentreScreen(
      onNavigate: (type) => setState(() {
        _currentIndex = switch (type) {
          'new_like' => 4,
          'new_match' || 'new_message' => 2,
          _ => _currentIndex,
        };
      }),
    ),
  ];
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadInitialData();
      // Ask the server whether a Swipe Surge is live in the user's own
      // city. The banner below only ever shows what the server reports -
      // never a simulated surge.
      ref.read(surgeProvider.notifier).refresh();
    });
  }

  Future<void> _loadInitialData() async {
    final notifier = ref.read(weekendProvider.notifier);
    notifier.loadCurrentUser();
    notifier.loadDiscoveryProfiles();
    notifier.loadReferralData();
    notifier.loadCrossedPaths();
    notifier.loadMatches();
    notifier.loadPlans();
    // Drives the Alerts tab badge. The count is a single indexed COUNT, not a
    // table read, so it is cheap enough to run at every home mount.
    ref.read(unreadCountProvider.notifier).refresh();
    final hasPerms = await LocationService.hasPermission();
    if (mounted) {
      setState(() {
        _showLocationBanner = !hasPerms;
      });
    }
    if (hasPerms) {
      ref.read(weekendProvider.notifier).updateLocationIfNeeded();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(weekendProvider);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: WeekendAtmosphere(
        child: Stack(
          children: [
            IndexedStack(index: _currentIndex, children: _screens),
            if (_showLocationBanner) _buildLocationBanner(),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomNav(state),
    );
  }

  Widget _buildLocationBanner() {
    return Align(
      alignment: Alignment.topCenter,
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF2E244A),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color(0xFFFF4B72).withValues(alpha: 0.5),
            ),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.location_on_rounded,
                color: Color(0xFFFF9966),
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Enable location to discover people nearby',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 13,
                  ),
                ),
              ),
              TextButton(
                onPressed: () async {
                  final granted = await LocationService.requestPermission();
                  if (granted) {
                    setState(() => _showLocationBanner = false);
                    ref.read(weekendProvider.notifier).updateLocationIfNeeded();
                  }
                },
                style: TextButton.styleFrom(
                  backgroundColor: const Color(0xFFFF4B72),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                ),
                child: const Text(
                  'Allow',
                  style: TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: () => context.go('/location-settings'),
                child: const Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.white54,
                  size: 20,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomNav(WeekendState state) {
    return BottomNavigationBar(
      currentIndex: _currentIndex,
      onTap: (index) {
        setState(() => _currentIndex = index);
      },
      backgroundColor: const Color(0xFF2E244A),
      type: BottomNavigationBarType.fixed,
      selectedItemColor: const Color(0xFFFF4B72),
      unselectedItemColor: Colors.white.withValues(alpha: 0.55),
      selectedLabelStyle: const TextStyle(fontSize: 12),
      unselectedLabelStyle: const TextStyle(fontSize: 12),
      items: [
        BottomNavigationBarItem(
          icon: Semantics(
            label: 'Discover tab',
            child: Icon(
              _currentIndex == 0
                  ? Icons.weekend_rounded
                  : Icons.weekend_outlined,
            ),
          ),
          label: 'Discover',
          tooltip: 'Discover',
        ),
        BottomNavigationBarItem(
          icon: Semantics(
            label: 'Explore tab',
            child: Icon(
              _currentIndex == 1
                  ? Icons.explore_rounded
                  : Icons.explore_outlined,
            ),
          ),
          label: 'Explore',
          tooltip: 'Explore',
        ),
        BottomNavigationBarItem(
          icon: Semantics(
            label: 'Chat tab',
            child: Stack(
              children: [
                Icon(
                  _currentIndex == 2
                      ? Icons.chat_bubble_rounded
                      : Icons.chat_bubble_outline_rounded,
                ),
                if (state.matches.any((m) => m.unreadCount > 0))
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Semantics(
                      label:
                          '${state.matches.fold(0, (sum, m) => sum + m.unreadCount)} unread messages',
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(
                          color: Color(0xFFFF4B72),
                          shape: BoxShape.circle,
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 16,
                          minHeight: 16,
                        ),
                        child: Text(
                          '${state.matches.fold(0, (sum, m) => sum + m.unreadCount)}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          label: 'Chat',
          tooltip: 'Chat',
        ),
        BottomNavigationBarItem(
          icon: Semantics(
            label: 'Profile tab',
            child: Icon(
              _currentIndex == 3
                  ? Icons.person_rounded
                  : Icons.person_outline_rounded,
            ),
          ),
          label: 'Profile',
          tooltip: 'Profile',
        ),
        // Reached by tap-through from the Chat tab rather than by a tab of
        // its own: six bottom tabs is past what a phone tab bar carries well,
        // and matches + conversations are the same surface, so the two entry
        // points belong together. Both are real routes (/likes, /notifications)
        // so they are also deep-linkable.
        BottomNavigationBarItem(
          icon: Semantics(
            label: 'Likes you tab',
            child: Icon(
              _currentIndex == 4
                  ? Icons.star_rounded
                  : Icons.star_outline_rounded,
            ),
          ),
          label: 'Likes',
          tooltip: 'People who liked you',
        ),
        BottomNavigationBarItem(
          icon: Semantics(
            label: 'Notifications tab',
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  _currentIndex == 5
                      ? Icons.notifications_rounded
                      : Icons.notifications_none_rounded,
                ),
                if (_unreadNotifications > 0)
                  Positioned(
                    right: -6,
                    top: -4,
                    child: Semantics(
                      label: '$_unreadNotifications unread notifications',
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF4B72),
                          shape: BoxShape.circle,
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 16,
                          minHeight: 16,
                        ),
                        child: Text(
                          '$_unreadNotifications',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          label: 'Alerts',
          tooltip: 'Notifications',
        ),
      ],
    );
  }
}

class DiscoverScreen extends ConsumerStatefulWidget {
  const DiscoverScreen({super.key});
  @override
  ConsumerState<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends ConsumerState<DiscoverScreen>
    with WidgetsBindingObserver, AutomaticKeepAliveClientMixin {
  final AdService _adService = AdService(repository: AdRepository());
  final List<Advertisement> _availableAds = [];
  bool _isFetchingAd = false;
  bool _adInjected = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _adService.startActiveDiscoveryTimer();
    });
    _adService.addListener(_onAdStateChanged);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _adService.removeListener(_onAdStateChanged);
    _adService.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        _adService.pauseTimer();
        break;
      case AppLifecycleState.resumed:
        _adService.resumeTimer();
        break;
      default:
        break;
    }
  }

  /// Stand-out like with an optional attached note (the compliment
  /// feature, migration 032). The note is validated server-side; the
  /// sheet only offers 140 characters and a plain text field.
  void _showStandOutNoteSheet(UserProfile profile) {
    final controller = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF22202A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          24,
          20,
          MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: StatefulBuilder(
          builder: (context, setSheetState) {
            final note = controller.text.trim();
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.star_rounded, color: Color(0xFFFF9966), size: 22),
                    SizedBox(width: 8),
                    Text(
                      'Stand-out like',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 17,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Add an optional note to ${_firstName(profile.name)} - it is delivered with your like before you match.',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: controller,
                  autofocus: true,
                  maxLines: 3,
                  maxLength: 140,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    counterStyle: TextStyle(color: Colors.white54),
                    hintText: 'Say something they will remember...',
                    hintStyle: TextStyle(color: Colors.white38),
                    filled: true,
                    fillColor: Color(0xFF2E2B3A),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: (_) => setSheetState(() {}),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(color: Colors.white54),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFFF9966),
                      ),
                      onPressed: () {
                        Navigator.of(context).pop();
                        ref.read(weekendProvider.notifier).swipeRight(
                              profile,
                              isStandOut: true,
                              note: note.isEmpty ? null : note,
                            );
                      },
                      child: Text(
                        note.isEmpty ? 'Stand-out like' : 'Send with note',
                        style: const TextStyle(color: Color(0xFF22202A)),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  String _firstName(String full) {
    final trimmed = full.trim().isEmpty ? '' : full.trim();
    if (trimmed.isEmpty || trimmed == 'Weekend member') return 'them';
    return trimmed.split(' ').first;
  }

  /// Photo ids already submitted for impression recording this session.
  final Set<String> _impressionSubmitted = {};

  void _recordSeenImpression(UserProfile topCard) {
    final photoId = topCard.primaryPhotoId;
    if (photoId.isEmpty || _impressionSubmitted.contains(photoId)) return;
    _impressionSubmitted.add(photoId);
    unawaited(
      DiscoveryRepository().recordPhotoImpressions([photoId]),
    );
    // Result is advisory (server dedupes and rate-limits); failures are
    // deliberately silent — an impression is an analytics signal, not user
    // state, so no snackbar may claim or fault it.
  }

  void _onAdStateChanged() {
    if (_adService.shouldShowAd && !_isFetchingAd && !_adInjected) {
      _fetchAdAndInsert();
    }
  }

  Future<void> _fetchAdAndInsert() async {
    setState(() => _isFetchingAd = true);
    final userId = SupabaseConfig.currentUserId;
    final ad = await _adService.fetchAd(userId);
    if (ad != null && mounted) {
      setState(() {
        _availableAds.add(ad);
        _adInjected = true;
        _isFetchingAd = false;
      });
      _adService.markAdDisplayed(ad);
    } else {
      setState(() => _isFetchingAd = false);
    }
  }

  @override
  bool wantKeepAlive = true;
  @override
  Widget build(BuildContext context) {
    super.build(context);
    final state = ref.watch(weekendProvider);
    // Photo impressions: the card the user actually SAW gets one impression
    // recorded per person per day, server-side. Recording happens for the
    // deck's top card whenever the deck puts a new profile on top, with a
    // local dedupe so a rebuild does not fire the RPC repeatedly — the
    // unique (photo, viewer, day) server constraint is the real guarantee.
    if (state.deckProfiles.isNotEmpty) {
      _recordSeenImpression(state.deckProfiles.last);
    }
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _FilterChip(
                            label: 'For You',
                            isSelected:
                                state.selectedMode == DiscoveryMode.forYou,
                            onTap: () => ref
                                .read(weekendProvider.notifier)
                                .selectDiscoveryMode(DiscoveryMode.forYou),
                          ),
                          const SizedBox(width: 8),
                          _FilterChip(
                            label: 'Nearby',
                            isSelected:
                                state.selectedMode == DiscoveryMode.nearby,
                            onTap: _onNearbyTap,
                          ),
                          const SizedBox(width: 8),
                          _FilterChip(
                            label: 'Crossed Paths',
                            isSelected:
                                state.selectedMode ==
                                DiscoveryMode.crossedPaths,
                            onTap: () => ref
                                .read(weekendProvider.notifier)
                                .selectDiscoveryMode(
                                  DiscoveryMode.crossedPaths,
                                ),
                          ),
                          const SizedBox(width: 8),
                          _FilterChip(
                            label: 'Global',
                            isSelected:
                                state.selectedMode == DiscoveryMode.global,
                            onTap: () => ref
                                .read(weekendProvider.notifier)
                                .selectDiscoveryMode(DiscoveryMode.global),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_availableAds.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF4B72).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'AD',
                        style: TextStyle(
                          color: Color(0xFFFF4B72),
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  if (state.deckProfiles.isNotEmpty)
                    IconButton(
                      tooltip: 'Advanced search and filters',
                      onPressed: () => context.push('/search'),
                      icon: const Icon(Icons.tune_rounded, color: Colors.white),
                    ),
                  if (state.deckProfiles.isNotEmpty)
                    IconButton(
                      tooltip: 'Discovery radius',
                      onPressed: () {
                        showModalBottomSheet(
                          context: context,
                          backgroundColor: Colors.transparent,
                          builder: (context) => _FilterSheet(
                            currentRadius:
                                state.locationPreferences.discoveryRadiusKm,
                          ),
                        );
                      },
                      icon: const Icon(
                        Icons.social_distance_rounded,
                        color: Colors.white,
                      ),
                    ),
                ],
              ),
            ),
            const _SurgeBanner(),
            Expanded(
              child: state.deckProfiles.isEmpty
                  ? WeekendEmptyState(
                      icon: Icons.search_off_rounded,
                      title: "You're All Caught Up!",
                      subtitle:
                          'No more profiles nearby. Try adjusting your filters or check back later.',
                      actionLabel: 'Rediscover',
                      onAction: () {
                        ref
                            .read(weekendProvider.notifier)
                            .loadDiscoveryProfiles();
                        _adService.resetAdInterval();
                        setState(() {
                          _adInjected = false;
                          _availableAds.clear();
                        });
                      },
                    )
                  : Stack(
                      children: [
                        for (int i = state.deckProfiles.length - 1; i >= 0; i--)
                          if (i < 2)
                            DiscoveryCard(
                              key: ValueKey(state.deckProfiles[i].id),
                              profile: state.deckProfiles[i],
                              isTop: i == state.deckProfiles.length - 1,
                              onSwipeLeft: () => ref
                                  .read(weekendProvider.notifier)
                                  .swipeLeft(state.deckProfiles[i].id),
                              onSwipeRight: () => ref
                                  .read(weekendProvider.notifier)
                                  .swipeRight(state.deckProfiles[i]),
                              onStandOut: () => ref
                                  .read(weekendProvider.notifier)
                                  .swipeRight(
                                    state.deckProfiles[i],
                                    isStandOut: true,
                                  ),
                              showDistance:
                                  state.locationPreferences.showDistanceEnabled,
                            ),
                      ],
                    ),
            ),
            if (state.deckProfiles.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 40,
                  vertical: 16,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _ActionButton(
                      icon: Icons.close_rounded,
                      semanticLabel: 'Pass on this profile',
                      color: const Color(0xFF22202A),
                      iconColor: Colors.white,
                      onPressed: () => ref
                          .read(weekendProvider.notifier)
                          .swipeLeft(state.deckProfiles.last.id),
                    ),
                    _ActionButton(
                      icon: Icons.star_rounded,
                      semanticLabel: 'Send a stand-out like',
                      color: const Color(0xFF22202A),
                      iconColor: const Color(0xFFFF9966),
                      onPressed: () => _showStandOutNoteSheet(
                        state.deckProfiles.last,
                      ),
                    ),
                    _ActionButton(
                      icon: Icons.favorite_rounded,
                      semanticLabel: 'Like this profile',
                      color: const Color(0xFFFF4B72),
                      size: 64,
                      onPressed: () => ref
                          .read(weekendProvider.notifier)
                          .swipeRight(state.deckProfiles.last),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _onNearbyTap() async {
    final hasPerms = await LocationService.hasPermission();
    if (!hasPerms) {
      _adService.pauseTimer();
      if (!context.mounted) return;
      // Restore discovery state when the user returns from the permission
      // screen. The ad timer stays paused while the permission UI is shown.
      // ignore: use_build_context_synchronously - guarded by context.mounted above
      unawaited(context.push('/location-permission').then((_) {
        if (!mounted) return;
        _adService.startActiveDiscoveryTimer();
        ref
            .read(weekendProvider.notifier)
            .selectDiscoveryMode(DiscoveryMode.nearby);
        ref.read(weekendProvider.notifier).updateLocationIfNeeded();
      }));
    } else {
      ref
          .read(weekendProvider.notifier)
          .selectDiscoveryMode(DiscoveryMode.nearby);
    }
  }
}

class _FilterSheet extends ConsumerWidget {
  final int currentRadius;
  const _FilterSheet({required this.currentRadius});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      height: 300,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Discovery Filters',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Discovery radius: $currentRadius km',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 12),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              thumbColor: const Color(0xFFFF4B72),
              overlayColor: const Color(0xFFFF4B72).withValues(alpha: 0.2),
              activeTrackColor: const Color(0xFFFF4B72),
              inactiveTrackColor: Colors.white.withValues(alpha: 0.2),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 12),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 24),
              trackHeight: 4,
            ),
            child: Slider(
              value: currentRadius.toDouble(),
              min: 1,
              max: 100,
              divisions: 20,
              label: '$currentRadius km',
              onChanged: (value) {
                ref
                    .read(weekendProvider.notifier)
                    .setDiscoveryRadius(value.round());
              },
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: () async {
                // Awaited and reported: closing the sheet used to happen even
                // when the write to user_settings was dropped, so the slider
                // silently reset on the next launch.
                try {
                  await ref
                      .read(weekendProvider.notifier)
                      .saveLocationPreferences();
                  if (context.mounted) Navigator.pop(context);
                } catch (e) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Filters could not be saved. Check your connection.',
                      ),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF4B72),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28),
                ),
              ),
              child: const Text(
                'Apply Filters',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? Colors.transparent
                : Colors.white.withValues(alpha: 0.2),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected
                ? Colors.black
                : Colors.white.withValues(alpha: 0.7),
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}

/// Server-truth Swipe Surge banner. Hidden entirely when the server
/// reports no active surge: no simulated urgency is ever shown.
class _SurgeBanner extends ConsumerWidget {
  const _SurgeBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final surge = ref.watch(surgeProvider);
    if (!surge.active) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Semantics(
        label: 'Swipe surge is active in ${surge.city}',
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFFF4B72).withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: const Color(0xFFFF4B72).withValues(alpha: 0.5),
            ),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.bolt_rounded,
                color: Color(0xFFFF4B72),
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Swipe Surge is live in ${surge.city.isEmpty ? 'your area' : surge.city} - right now activity is higher than usual.',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String semanticLabel;
  final Color color;
  final Color iconColor;
  final double size;
  final VoidCallback onPressed;
  const _ActionButton({
    required this.icon,
    required this.semanticLabel,
    required this.color,
    this.iconColor = Colors.white,
    this.size = 54,
    required this.onPressed,
  });
  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: IconButton(
          tooltip: semanticLabel,
          onPressed: onPressed,
          icon: Icon(icon, color: iconColor, size: size * 0.4),
        ),
      ),
    );
  }
}

class MatchesScreen extends ConsumerWidget {
  final VoidCallback? onDiscoverTap;
  const MatchesScreen({super.key, this.onDiscoverTap});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(weekendProvider);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: state.matches.isEmpty
            ? WeekendEmptyState(
                icon: Icons.chat_bubble_outline_rounded,
                title: 'No Matches Yet',
                subtitle: 'Start discovering profiles to find your matches!',
                actionLabel: 'Discover',
                onAction: onDiscoverTap,
              )
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: state.matches.length,
                itemBuilder: (context, index) {
                  final match = state.matches[index];
                  return MatchCard(match: match);
                },
              ),
      ),
    );
  }
}

class ProfileTabScreen extends StatelessWidget {
  const ProfileTabScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return const ProfileScreen();
  }
}

/// Avatar that gracefully handles profiles with no photos yet â€” it renders a
/// placeholder icon instead of attempting to load an empty image URL.
class _MatchAvatar extends StatelessWidget {
  final List<String> photos;
  const _MatchAvatar({required this.photos});

  @override
  Widget build(BuildContext context) {
    final photo = photos.isNotEmpty ? photos.first : null;
    if (photo == null || photo.isEmpty) {
      return CircleAvatar(
        radius: 28,
        backgroundColor: const Color(0xFF2E244A),
        child: Icon(
          Icons.person_rounded,
          color: Colors.white.withValues(alpha: 0.6),
          size: 28,
        ),
      );
    }
    return CircleAvatar(
      radius: 28,
      backgroundImage: CachedNetworkImageProvider(photo),
    );
  }
}

class MatchCard extends StatelessWidget {
  final MatchItem match;
  const MatchCard({super.key, required this.match});

  /// One honest status chip while a match has never been opened: whose turn
  /// it is, or that the window passed. Derived only from `get_matches_for_user`
  /// data; nothing is shown for started conversations or legacy matches.
  Widget? _windowChip() {
    if (match.lastMessage.isNotEmpty &&
        match.lastMessage != 'No messages yet') {
      return null;
    }
    final (String label, Color color) chipInfo;
    switch (match.initiationStatus) {
      case 'awaiting_you':
        chipInfo = ('Your turn to open', const Color(0xFFFF9966));
        break;
      case 'awaiting_them':
        chipInfo = ('Their opening message', Colors.white38);
        break;
      case 'expired':
        chipInfo = ('Window expired — rematch?', Colors.redAccent);
        break;
      default:
        return null;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: chipInfo.$2.withValues(alpha: 0.18),
        borderRadius: const BorderRadius.all(Radius.circular(12)),
      ),
      child: Text(
        chipInfo.$1,
        style: TextStyle(
          color: chipInfo.$2,
          fontSize: 11,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chip = _windowChip();
    return Semantics(
      button: true,
      label: 'Conversation with ${match.user.name}'
          '${match.unreadCount > 0 ? ', ${match.unreadCount} unread' : ''}',
      child: GestureDetector(
        // Routed through GoRouter rather than a bare `Navigator.push` so a
        // conversation is addressable at /chat/:matchId and a notification
        // deep link lands on exactly the same screen.
        onTap: () => context.push('/chat/${match.id}'),
        child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF1C162E),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            _MatchAvatar(photos: match.user.photos),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    match.user.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    match.lastMessage.isEmpty
                        ? 'Start chatting!'
                        : match.lastMessage,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (match.unreadCount > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: const BoxDecoration(
                  color: Color(0xFFFF4B72),
                  borderRadius: BorderRadius.all(Radius.circular(12)),
                ),
                child: Text(
                  '${match.unreadCount}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              )
            else
              chip ?? const SizedBox.shrink(),
          ],
        ),
        ),
      ),
    );
  }
}

