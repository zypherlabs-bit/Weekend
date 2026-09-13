import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../providers/weekend_provider.dart';
import '../../providers/auth_provider.dart';
import '../../models/models.dart';
import '../../services/ad_service.dart';
import '../../repositories/ad_repository.dart';
import '../../widgets/discovery_card.dart';
import '../../widgets/ad_card.dart';
import '../../widgets/match_celebration_dialog.dart';
import '../../widgets/safety_dialogs.dart';
import '../../services/location_service.dart';
import '../chat/chat_screen.dart';
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
  bool _isCheckingLocation = true;

  final List<Widget> _screens = [
    const DiscoverScreen(),
    const ExploreScreen(),
    const MatchesScreen(),
    const ProfileTabScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadInitialData();
    });
  }

  Future<void> _loadInitialData() async {
    final userId =
        Supabase.instance.client.auth.currentUser?.id ?? 'user_me';
    ref.read(weekendProvider.notifier).loadDiscoveryProfiles();
    ref.read(weekendProvider.notifier).loadReferralData();
    ref.read(weekendProvider.notifier).loadCrossedPaths();

    final hasPerms = await LocationService.hasPermission();
    if (mounted) {
      setState(() {
        _showLocationBanner = !hasPerms;
        _isCheckingLocation = false;
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
      backgroundColor: const Color(0xFF130E20),
      body: Stack(
        children: [
          IndexedStack(
            index: _currentIndex,
            children: _screens,
          ),
          if (_showLocationBanner) _buildLocationBanner(),
        ],
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
            border:
                Border.all(color: const Color(0xFFFF4B72).withOpacity(0.5)),
          ),
          child: Row(
            children: [
              const Icon(Icons.location_on_rounded,
                  color: Color(0xFFFF9966), size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Enable location to discover people nearby',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.85),
                    fontSize: 13,
                  ),
                ),
              ),
              TextButton(
                onPressed: () async {
                  final granted = await LocationService.requestPermission();
                  if (granted) {
                    setState(() => _showLocationBanner = false);
                    ref
                        .read(weekendProvider.notifier)
                        .updateLocationIfNeeded();
                  }
                },
                style: TextButton.styleFrom(
                  backgroundColor: const Color(0xFFFF4B72),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                ),
                child: const Text(
                  'Allow',
                  style: TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: () => Navigator.pushNamed(context, '/location-settings'),
                child: const Icon(Icons.chevron_right_rounded,
                    color: Colors.white54, size: 20),
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
      unselectedItemColor: Colors.white.withOpacity(0.55),
      items: [
        BottomNavigationBarItem(
          icon: Icon(_currentIndex == 0
              ? Icons.weekend_rounded
              : Icons.weekend_outlined),
          label: 'Discover',
        ),
        BottomNavigationBarItem(
          icon: Icon(_currentIndex == 1
              ? Icons.explore_rounded
              : Icons.explore_outlined),
          label: 'Explore',
        ),
        BottomNavigationBarItem(
          icon: Stack(
            children: [
              Icon(_currentIndex == 2
                  ? Icons.chat_bubble_rounded
                  : Icons.chat_bubble_outline_rounded),
              if (state.matches.any((m) => m.unreadCount > 0))
                Positioned(
                  right: 0,
                  top: 0,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                      color: Color(0xFFFF4B72),
                      shape: BoxShape.circle,
                    ),
                    constraints:
                        const BoxConstraints(minWidth: 16, minHeight: 16),
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
            ],
          ),
          label: 'Chat',
        ),
        BottomNavigationBarItem(
          icon: Icon(_currentIndex == 3
              ? Icons.person_rounded
              : Icons.person_outline_rounded),
          label: 'Profile',
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
  List<Advertisement> _availableAds = [];
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

  void _onAdStateChanged() {
    if (_adService.shouldShowAd && !_isFetchingAd && !_adInjected) {
      _fetchAdAndInsert();
    }
  }

  Future<void> _fetchAdAndInsert() async {
    setState(() => _isFetchingAd = true);

    final userId =
        Supabase.instance.client.auth.currentUser?.id ?? 'user_me';
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

    return Scaffold(
      backgroundColor: const Color(0xFF130E20),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
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
                                state.selectedMode == DiscoveryMode.FOR_YOU,
                            onTap: () => ref
                                .read(weekendProvider.notifier)
                                .selectDiscoveryMode(DiscoveryMode.FOR_YOU),
                          ),
                          const SizedBox(width: 8),
                          _FilterChip(
                            label: 'Nearby',
                            isSelected:
                                state.selectedMode == DiscoveryMode.NEARBY,
                            onTap: _onNearbyTap,
                          ),
                          const SizedBox(width: 8),
                          _FilterChip(
                            label: 'Crossed Paths',
                            isSelected: state.selectedMode ==
                                DiscoveryMode.CROSSED_PATHS,
                            onTap: () => ref
                                .read(weekendProvider.notifier)
                                .selectDiscoveryMode(
                                    DiscoveryMode.CROSSED_PATHS),
                          ),
                          const SizedBox(width: 8),
                          _FilterChip(
                            label: 'Global',
                            isSelected:
                                state.selectedMode == DiscoveryMode.GLOBAL,
                            onTap: () => ref
                                .read(weekendProvider.notifier)
                                .selectDiscoveryMode(DiscoveryMode.GLOBAL),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_availableAds.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF4B72).withOpacity(0.2),
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
                      icon: const Icon(Icons.tune_rounded, color: Colors.white),
                    ),
                ],
              ),
            ),
            Expanded(
              child: state.deckProfiles.isEmpty
                  ? _EmptyState(
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
                                  .swipeRight(state.deckProfiles[i],
                                      isStandOut: true),
                              showDistance: state
                                  .locationPreferences.showDistanceEnabled,
                            ),
                      ],
                    ),
            ),
            if (state.deckProfiles.isNotEmpty) ...[
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _ActionButton(
                      icon: Icons.close_rounded,
                      color: const Color(0xFF22202A),
                      iconColor: Colors.white,
                      onPressed: () => ref
                          .read(weekendProvider.notifier)
                          .swipeLeft(state.deckProfiles.last.id),
                    ),
                    _ActionButton(
                      icon: Icons.star_rounded,
                      color: const Color(0xFF22202A),
                      iconColor: const Color(0xFFFF9966),
                      onPressed: () => ref
                          .read(weekendProvider.notifier)
                          .swipeRight(state.deckProfiles.last, isStandOut: true),
                    ),
                    _ActionButton(
                      icon: Icons.favorite_rounded,
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
      Navigator.pushNamed(context, '/location-permission').then((_) {
        _adService.startActiveDiscoveryTimer();
        ref
            .read(weekendProvider.notifier)
            .selectDiscoveryMode(DiscoveryMode.NEARBY);
        ref
            .read(weekendProvider.notifier)
            .updateLocationIfNeeded();
      });
    } else {
      ref
          .read(weekendProvider.notifier)
          .selectDiscoveryMode(DiscoveryMode.NEARBY);
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
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
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
              color: Colors.white.withOpacity(0.7),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 12),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                thumbColor: const Color(0xFFFF4B72),
                overlayColor: const Color(0xFFFF4B72).withOpacity(0.2),
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 12),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 24),
                trackHeight: 4,
              ),
              child: Slider(
                value: currentRadius.toDouble(),
                min: 1,
                max: 100,
                divisions: 20,
                activeColor: const Color(0xFFFF4B72),
                inactiveColor: Colors.white.withOpacity(0.2),
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
              onPressed: () {
                ref
                    .read(weekendProvider.notifier)
                    .saveLocationPreferences();
                Navigator.pop(context);
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
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportOption extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _ReportOption({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.report_rounded,
          color: Color(0xFFFF4B72), size: 20),
      title: Text(
        label,
        style: const TextStyle(color: Colors.white, fontSize: 14),
      ),
      onTap: onTap,
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
  });

  @override
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
                : Colors.white.withOpacity(0.2),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.black : Colors.white.withOpacity(0.7),
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color iconColor;
  final double size;
  final VoidCallback onPressed;

  const _ActionButton({
    required this.icon,
    required this.color,
    this.iconColor = Colors.white,
    this.size = 54,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, color: iconColor, size: size * 0.4),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onAction;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: const Color(0xFFFF4B72).withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 40, color: const Color(0xFFFF4B72)),
            ),
            const SizedBox(height: 24),
            Text(
              title,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 14,
                color: Colors.white.withOpacity(0.7),
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: onAction,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF4B72),
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
              child: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}

class MatchesScreen extends ConsumerWidget {
  const MatchesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(weekendProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF130E20),
      body: SafeArea(
        child: state.matches.isEmpty
            ? _EmptyState(
                icon: Icons.chat_bubble_outline_rounded,
                title: 'No Matches Yet',
                subtitle:
                    'Start discovering profiles to find your matches!',
                actionLabel: 'Discover',
                onAction: () {},
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

class MatchCard extends StatelessWidget {
  final MatchItem match;

  const MatchCard({super.key, required this.match});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChatScreen(match: match),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF1C162E),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundImage:
                  NetworkImage(match.user.photos.firstOrNull ?? ''),
            ),
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
                      color: Colors.white.withOpacity(0.6),
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
              ),
          ],
        ),
      ),
    );
  }
}
