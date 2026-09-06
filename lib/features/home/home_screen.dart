import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/weekend_provider.dart';
import '../../providers/auth_provider.dart';
import '../../models/models.dart';
import '../../widgets/discovery_card.dart';
import '../../widgets/match_celebration_dialog.dart';
import '../../widgets/safety_dialogs.dart';
import '../chat/chat_screen.dart';
import '../profile/profile_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _currentIndex = 0;

  final List<Widget> _screens = [
    const DiscoverScreen(),
    const NearbyScreen(),
    const LikesAndPlansScreen(),
    const MatchesScreen(),
    const ProfileTabScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(weekendProvider);
    
    return Scaffold(
      backgroundColor: const Color(0xFF130E20),
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        backgroundColor: const Color(0xFF2E244A),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: const Color(0xFFFF4B72),
        unselectedItemColor: Colors.white.withOpacity(0.55),
        items: [
          BottomNavigationBarItem(
            icon: Icon(_currentIndex == 0 ? Icons.weekend_rounded : Icons.weekend_outlined),
            label: 'Discover',
          ),
          BottomNavigationBarItem(
            icon: Icon(_currentIndex == 1 ? Icons.place_rounded : Icons.place_outlined),
            label: 'Nearby',
          ),
          BottomNavigationBarItem(
            icon: Icon(_currentIndex == 2 ? Icons.favorite_rounded : Icons.favorite_outlined),
            label: 'Likes',
          ),
          BottomNavigationBarItem(
            icon: Stack(
              children: [
                Icon(_currentIndex == 3 ? Icons.chat_bubble_rounded : Icons.chat_bubble_outline_rounded),
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
                      constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
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
            icon: Icon(_currentIndex == 4 ? Icons.person_rounded : Icons.person_outline_rounded),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

class DiscoverScreen extends ConsumerWidget {
  const DiscoverScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(weekendProvider);
    
    return Scaffold(
      backgroundColor: const Color(0xFF130E20),
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
                            isSelected: state.selectedMode == DiscoveryMode.FOR_YOU,
                            onTap: () => ref.read(weekendProvider.notifier).selectDiscoveryMode(DiscoveryMode.FOR_YOU),
                          ),
                          const SizedBox(width: 8),
                          _FilterChip(
                            label: 'Nearby',
                            isSelected: state.selectedMode == DiscoveryMode.NEARBY,
                            onTap: () => ref.read(weekendProvider.notifier).selectDiscoveryMode(DiscoveryMode.NEARBY),
                          ),
                          const SizedBox(width: 8),
                          _FilterChip(
                            label: 'Vibes',
                            isSelected: state.selectedMode == DiscoveryMode.INTERESTS,
                            onTap: () => ref.read(weekendProvider.notifier).selectDiscoveryMode(DiscoveryMode.INTERESTS),
                          ),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => _showSafetyCenter(context),
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
                      subtitle: 'No more profiles nearby. Try adjusting your filters or check back later.',
                      actionLabel: 'Rediscover',
                      onAction: () => ref.read(weekendProvider.notifier).resetDeck(),
                    )
                  : Stack(
                      children: [
                        for (int i = state.deckProfiles.length - 1; i >= 0; i--)
                          if (i < 2)
                            DiscoveryCard(
                              profile: state.deckProfiles[i],
                              isTop: i == state.deckProfiles.length - 1,
                              onSwipeLeft: () => ref.read(weekendProvider.notifier).swipeLeft(state.deckProfiles[i].id),
                              onSwipeRight: () => ref.read(weekendProvider.notifier).swipeRight(state.deckProfiles[i]),
                              onStandOut: () => ref.read(weekendProvider.notifier).swipeRight(state.deckProfiles[i], isStandOut: true),
                            ),
                      ],
                    ),
            ),
            if (state.deckProfiles.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _ActionButton(
                      icon: Icons.close_rounded,
                      color: const Color(0xFF22202A),
                      iconColor: Colors.white,
                      onPressed: () => ref.read(weekendProvider.notifier).swipeLeft(state.deckProfiles.last.id),
                    ),
                    _ActionButton(
                      icon: Icons.star_rounded,
                      color: const Color(0xFF22202A),
                      iconColor: const Color(0xFFFF9966),
                      onPressed: () => ref.read(weekendProvider.notifier).swipeRight(state.deckProfiles.last, isStandOut: true),
                    ),
                    _ActionButton(
                      icon: Icons.favorite_rounded,
                      color: const Color(0xFFFF4B72),
                      size: 64,
                      onPressed: () => ref.read(weekendProvider.notifier).swipeRight(state.deckProfiles.last),
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

  void _showSafetyCenter(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => const SafetyCenterDialog(),
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
            color: isSelected ? Colors.transparent : Colors.white.withOpacity(0.2),
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
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
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

class NearbyScreen extends StatelessWidget {
  const NearbyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF130E20),
      body: Center(
        child: Text(
          'Nearby',
          style: TextStyle(color: Colors.white, fontSize: 24),
        ),
      ),
    );
  }
}

class LikesAndPlansScreen extends StatelessWidget {
  const LikesAndPlansScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF130E20),
      body: Center(
        child: Text(
          'Likes & Plans',
          style: TextStyle(color: Colors.white, fontSize: 24),
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
                subtitle: 'Start discovering profiles to find your matches!',
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
              backgroundImage: NetworkImage(match.user.photos.firstOrNull ?? ''),
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
                    match.lastMessage.isEmpty ? 'Start chatting!' : match.lastMessage,
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
              ),
          ],
        ),
      ),
    );
  }
}
