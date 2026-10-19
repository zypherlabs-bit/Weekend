import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../providers/weekend_provider.dart';
import '../../models/models.dart';
import '../../widgets/weekend_design_system.dart';
import '../../widgets/weekend_empty_state.dart';
import '../../services/location_service.dart';
import '../../providers/interactions_provider.dart';
import '../../providers/feature_providers.dart';
import '../likes/likes_screen.dart';
import '../notifications/notifications_screen.dart';
import '../profile/profile_screen.dart';
import '../discovery/explore_screen.dart';
import '../discovery/discover_screen.dart';

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
