import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../models/models.dart';
import '../../providers/feature_providers.dart';
import '../../providers/weekend_provider.dart'
    show weekendProvider, surgeProvider, DiscoveryMode, WeekendState;
import '../../repositories/discovery_repository.dart';
import '../../services/ad_service.dart';
import '../../repositories/ad_repository.dart';
import '../../theme/app_theme.dart';
import '../../widgets/match_celebration_dialog.dart';
import '../../widgets/weekend_design_system.dart';

/// Horizontal distance (logical pixels) a drag must travel before it counts
/// as a pass or like swipe.
const double _kSwipeThresholdPx = 100;

/// Drag velocity (logical pixels per second) that counts as a swipe even if
/// the card has not travelled the full threshold.
const double _kSwipeVelocityThreshold = 700;

class DiscoverScreen extends ConsumerStatefulWidget {
  const DiscoverScreen({super.key});
  @override
  ConsumerState<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends ConsumerState<DiscoverScreen>
    with WidgetsBindingObserver, AutomaticKeepAliveClientMixin {
  final AdService _adService = AdService(repository: AdRepository());
  Offset _dragOffset = Offset.zero;
  int _photoIndex = 0;
  final Set<String> _impressionSubmitted = {};
  bool _isActing = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _adService.startActiveDiscoveryTimer();
    });
    ref.listen<WeekendState>(weekendProvider, (previous, next) {
      if (previous?.recentMatchCelebration == null &&
          next.recentMatchCelebration != null &&
          mounted) {
        _showMatchCelebration(next.recentMatchCelebration!);
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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

  void _recordSeenImpression(UserProfile topCard) {
    final photoId = topCard.primaryPhotoId;
    if (photoId.isEmpty || _impressionSubmitted.contains(photoId)) return;
    _impressionSubmitted.add(photoId);
    unawaited(DiscoveryRepository().recordPhotoImpressions([photoId]));
  }

  void _showMatchCelebration(UserProfile matchedUser) {
    showDialog<UserProfile>(
      context: context,
      barrierDismissible: false,
      builder: (context) => MatchCelebrationDialog(
        currentUser: ref.read(weekendProvider).currentUser,
        matchedUser: matchedUser,
        onStartChat: () {
          Navigator.pop(context);
          ref.read(weekendProvider.notifier).clearCelebration();
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                "It's a match! Open the Chat tab to start messaging.",
              ),
            ),
          );
        },
        onDismiss: () {
          Navigator.pop(context);
          ref.read(weekendProvider.notifier).clearCelebration();
        },
      ),
    );
  }

  void _pass(UserProfile profile) => _actOnProfile(profile, like: false);
  void _like(UserProfile profile) => _actOnProfile(profile, like: true);

  Future<void> _actOnProfile(UserProfile profile, {required bool like}) async {
    if (_isActing) return;
    _isActing = true;
    try {
      if (like) {
        await ref.read(weekendProvider.notifier).swipeRight(profile);
      } else {
        await ref.read(weekendProvider.notifier).swipeLeft(profile.id);
      }
    } finally {
      if (mounted) {
        _isActing = false;
        setState(() => _dragOffset = Offset.zero);
      }
    }
  }

  void _openProfile(UserProfile profile) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _ProfileDetailSheet(profile: profile),
    );
  }

  void _showFilterSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const _DiscoveryFilterSheet(),
    );
  }

  void _selectPhoto(int index, int count) {
    if (count < 2) return;
    setState(() {
      _photoIndex = ((index % count) + count) % count;
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final state = ref.watch(weekendProvider);
    final theme = Theme.of(context);
    final topProfile = state.deckProfiles.isEmpty
        ? null
        : state.deckProfiles.last;

    if (topProfile != null) {
      _recordSeenImpression(topProfile);
    }

    // Use a Stack to layer: full-screen photo, gradients, top tabs, profile details, action buttons
    return topProfile == null
        ? _EmptyDiscovery(
            onAdjustFilters: _showFilterSheet,
            onRediscover: () => ref
                .read(weekendProvider.notifier)
                .loadDiscoveryProfiles(),
          )
        : AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            child: _buildFullScreenDiscovery(topProfile),
          );
  }

  Widget _buildFullScreenDiscovery(UserProfile profile) {
    final photos = profile.photos;
    final showDistance = ref
        .read(weekendProvider)
        .locationPreferences
        .showDistanceEnabled;
    final mediaQuery = MediaQuery.of(context);
    final statusBarHeight = mediaQuery.padding.top;
    final bottomInset = mediaQuery.padding.bottom;

    return GestureDetector(
      onHorizontalDragStart: (_) => setState(() => _dragOffset = Offset.zero),
      onHorizontalDragUpdate: (d) => setState(() => _dragOffset += d.delta),
      onHorizontalDragEnd: (d) => _onDragEnd(d, profile),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        transform: Matrix4.translationValues(_dragOffset.dx, 0, 0)
          ..rotateZ(_dragOffset.dx * 0.0008),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 1. Full-screen background profile image
            Positioned.fill(child: _buildPhoto(profile)),
            // 2. Subtle gradient overlay for text readability (top for tabs, bottom for details/buttons)
            Positioned.fill(child: _buildFullScreenScrim()),
            // 3. Top photo indicators (dots)
            if (photos.length >= 2)
              Positioned(
                top: statusBarHeight + 14,
                left: 0,
                right: 0,
                child: _photoIndicators(photos.length),
              ),
            // 4. Top verification badge and online dot
            if (photos.isNotEmpty) ...[
              Positioned(
                top: statusBarHeight + 16,
                left: 16,
                child: _verificationBadge(profile),
              ),
              Positioned(
                top: statusBarHeight + 16,
                right: 16,
                child: _onlineDot(profile),
              ),
            ],
            // 5. Fixed top discovery tabs (anchored below status bar)
            Positioned(
              top: statusBarHeight,
              left: 0,
              right: 0,
              child: _DiscoveryHeader(state: ref.watch(weekendProvider), onFilterTap: _showFilterSheet),
            ),
            // 6. Profile details near bottom of photo
            Positioned(
              left: 0,
              right: 0,
              bottom: 100 + bottomInset, // Space for action buttons + bottom inset
              child: _buildDetails(profile, showDistance),
            ),
            // 7. Action buttons above bottom navigation
            Positioned(
              left: 0,
              right: 0,
              bottom: bottomInset,
              child: _buildActionRow(profile),
            ),
          ],
        ),
      ),
    );
  }

  void _onDragEnd(DragEndDetails details, UserProfile profile) {
    final v = details.primaryVelocity ?? 0;
    final dx = _dragOffset.dx;
    final pass = dx > _kSwipeThresholdPx || v > _kSwipeVelocityThreshold;
    final like = dx < -_kSwipeThresholdPx || v < -_kSwipeVelocityThreshold;
    if (!pass && !like) {
      setState(() => _dragOffset = Offset.zero);
      return;
    }
    pass ? _pass(profile) : _like(profile);
  }

  Widget _buildPhoto(UserProfile profile) {
    final photos = profile.photos;
    if (photos.isEmpty) {
      return Container(
        color: const Color(0xFF2E244A),
        alignment: Alignment.center,
        child: const Icon(
          Icons.person_rounded,
          size: 88,
          color: Colors.white24,
        ),
      );
    }
    return CachedNetworkImage(
      imageUrl: photos[_photoIndex.clamp(0, photos.length - 1)],
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      placeholder: (_, __) => Container(
        color: const Color(0xFF2E244A),
        alignment: Alignment.center,
        child: const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            color: AppTheme.sunsetCoral,
          ),
        ),
      ),
      errorWidget: (_, __, ___) => Container(
        color: const Color(0xFF2E244A),
        alignment: Alignment.center,
        child: const Icon(
          Icons.broken_image_rounded,
          size: 60,
          color: Colors.white24,
        ),
      ),
    );
  }

  Widget _buildFullScreenScrim() => DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          // Top gradient for tab readability
          Colors.black.withValues(alpha: 0.45),
          Colors.black.withValues(alpha: 0.3),
          Colors.transparent,
          Colors.transparent,
          // Bottom gradient for profile details and action buttons
          Colors.black.withValues(alpha: 0.25),
          Colors.black.withValues(alpha: 0.55),
          Colors.black.withValues(alpha: 0.85),
        ],
        stops: const [0.0, 0.08, 0.35, 0.55, 0.7, 0.88, 1.0],
      ),
    ),
  );

  Widget _photoIndicators(int count) {
    if (count < 2) return const SizedBox.shrink();
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: GestureDetector(
              onTap: () => _selectPhoto(i, count),
              child: Container(
                width: i == _photoIndex ? 22 : 7,
                height: 7,
                decoration: BoxDecoration(
                  color: i == _photoIndex
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _verificationBadge(UserProfile profile) {
    if (!profile.isPhotoVerified) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF1C162E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.verified_rounded, color: Color(0xFF6FD08C), size: 14),
          SizedBox(width: 4),
          Text(
            'Verified',
            style: TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _onlineDot(UserProfile profile) {
    if (!profile.isOnline) return const SizedBox.shrink();
    return Container(
      width: 10,
      height: 10,
      decoration: const BoxDecoration(
        color: Color(0xFF6FD08C),
        shape: BoxShape.circle,
      ),
    );
  }

  Widget _buildDetails(UserProfile profile, bool showDistance) {
    final age = profile.age > 0 ? profile.age : null;
    final meta = <String>[];
    if (showDistance &&
        (profile.distanceDisplay.trim().isNotEmpty || profile.distanceKm > 0)) {
      meta.add(
        profile.distanceDisplay.trim().isNotEmpty
            ? profile.distanceDisplay
            : '${profile.distanceKm} km away',
      );
    }
    if (profile.heightCm != null) meta.add('${profile.heightCm} cm');
    if (profile.relationshipIntent.trim().isNotEmpty) {
      meta.add(profile.relationshipIntent);
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  profile.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    height: 1.1,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (age != null)
                Text(
                  '$age',
                  style: const TextStyle(color: Colors.white70, fontSize: 24),
                ),
              if (profile.isPhotoVerified) ...[
                const SizedBox(width: 6),
                const Icon(
                  Icons.verified_rounded,
                  color: Color(0xFF6FD08C),
                  size: 18,
                ),
              ],
            ],
          ),
          if (meta.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < meta.length; i++) ...[
                  if (i > 0) ...[
                    Container(
                      width: 1,
                      height: 10,
                      color: Colors.white.withValues(alpha: 0.35),
                    ),
                    const SizedBox(width: 8),
                  ],
                  _MetaLine(icon: _metaIcon(meta[i]), text: meta[i]),
                ],
              ],
            ),
          ],
          if (profile.occupation.trim().isNotEmpty ||
              profile.education.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              profile.occupation.trim().isNotEmpty
                  ? profile.occupation
                  : profile.education,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 14,
              ),
            ),
          ],
        ],
      ),
    );
  }

  IconData _metaIcon(String text) {
    if (text == 'Nearby' || text.endsWith('km away')) {
      return Icons.near_me_rounded;
    }
    if (text.endsWith('cm')) return Icons.height_rounded;
    return Icons.location_on_rounded;
  }

  Widget _buildActionRow(UserProfile profile) {
    final mediaQuery = MediaQuery.of(context);
    final bottomInset = mediaQuery.padding.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(32, 10, 32, 10 + bottomInset),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _ActionButton(
            icon: Icons.close_rounded,
            label: 'Pass',
            color: const Color(0xFF22202A),
            onPressed: () => _pass(profile),
          ),
          _ActionButton(
            icon: Icons.favorite_rounded,
            label: 'Like',
            color: AppTheme.sunsetCoral,
            size: 64,
            onPressed: () => _like(profile),
          ),
          _ActionButton(
            icon: Icons.info_outline_rounded,
            label: 'View profile',
            color: const Color(0xFF22202A),
            onPressed: () => _openProfile(profile),
          ),
        ],
      ),
    );
  }
}

class _DiscoveryHeader extends ConsumerWidget {
  final WeekendState state;
  final VoidCallback onFilterTap;
  const _DiscoveryHeader({required this.state, required this.onFilterTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final surge = ref.watch(surgeProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Tab row - transparent background so photo shows through
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 12, 6),
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final mode in DiscoveryMode.values)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: _ModeTab(
                            label: mode.title,
                            selected: state.selectedMode == mode,
                            onTap: () {
                              ref
                                  .read(weekendProvider.notifier)
                                  .selectDiscoveryMode(mode);
                              ref
                                  .read(weekendProvider.notifier)
                                  .loadDiscoveryProfiles();
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _FilterButton(onTap: onFilterTap),
            ],
          ),
        ),
        // Surge banner - use glass effect for readability over photo
        if (surge.active) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: Semantics(
              label: 'Swipe surge is active in ${surge.city}',
              child: WeekendGlass(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                radius: 14,
                blurSigma: 12,
                child: const Text(
                  'Swipe surge active',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _ModeTab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _ModeTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: WeekendMotion.quick,
          curve: WeekendMotion.curve,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? theme.colorScheme.primary
                : (theme.brightness == Brightness.dark
                    ? Colors.white.withValues(alpha: 0.12)
                    : Colors.black.withValues(alpha: 0.08)),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected
                  ? theme.colorScheme.primary
                  : Colors.white.withValues(alpha: 0.3),
            ),
          ),
          child: Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: selected
                  ? theme.colorScheme.onPrimary
                  : Colors.white,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _FilterButton extends StatelessWidget {
  final VoidCallback onTap;
  const _FilterButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return WeekendGlass(
      padding: const EdgeInsets.all(10),
      radius: 22,
      blurSigma: 12,
      child: IconButton(
        icon: const Icon(Icons.tune_rounded, color: Colors.white),
        onPressed: onTap,
        tooltip: 'Discovery filters',
      ),
    );
  }
}

class _EmptyDiscovery extends StatelessWidget {
  final VoidCallback onAdjustFilters;
  final VoidCallback onRediscover;
  const _EmptyDiscovery({
    required this.onAdjustFilters,
    required this.onRediscover,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mediaQuery = MediaQuery.of(context);
    final bottomInset = mediaQuery.padding.bottom;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Background atmosphere
        const WeekendAtmosphere(child: SizedBox.expand()),
        // Content
        SafeArea(
          top: true,
          bottom: false,
          child: Column(
            children: [
              // Top tabs header (empty state still shows tabs)
              _DiscoveryHeader(
                state: WeekendState.initial(),
                onFilterTap: onAdjustFilters,
              ),
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.people_outline_rounded,
                          size: 64,
                          color: Colors.white38,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'No profiles right now',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Try another discovery mode or adjust your filters.',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 14,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        WeekendGlassButton(
                          label: 'Adjust filters',
                          onPressed: onAdjustFilters,
                          primary: true,
                        ),
                        const SizedBox(height: 12),
                        WeekendGlassButton(
                          label: 'Rediscover',
                          onPressed: onRediscover,
                          primary: false,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // Bottom spacing for nav bar
              SizedBox(height: 80 + bottomInset),
            ],
          ),
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final double size;
  final VoidCallback onPressed;
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    this.size = 52,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(size / 2),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.45),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
              BoxShadow(
                color: color.withValues(alpha: 0.3),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Icon(icon, color: Colors.white, size: size * 0.54),
        ),
      ),
    );
  }
}

class _MetaLine extends StatelessWidget {
  final IconData icon;
  final String text;
  const _MetaLine({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Colors.white54),
        const SizedBox(width: 4),
        Text(text, style: const TextStyle(color: Colors.white70, fontSize: 13)),
      ],
    );
  }
}

class _Tag extends StatelessWidget {
  final String label;
  const _Tag({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Text(
        label,
        style: const TextStyle(color: Colors.white70, fontSize: 12),
      ),
    );
  }
}

class _SheetHeader extends StatelessWidget {
  final UserProfile profile;
  const _SheetHeader({required this.profile});

  @override
  Widget build(BuildContext context) {
    final age = profile.age > 0 ? profile.age : null;
    final photo = profile.photos.isNotEmpty ? profile.photos.first : null;
    return Column(
      children: [
        if (photo != null) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: CachedNetworkImage(
              imageUrl: photo,
              height: 140,
              width: double.infinity,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(height: 16),
        ],
        Row(
          children: [
            Expanded(
              child: Text(
                profile.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (age != null) ...[
              const SizedBox(width: 8),
              Text(
                '$age',
                style: const TextStyle(color: Colors.white70, fontSize: 20),
              ),
            ],
            if (profile.isPhotoVerified) ...[
              const SizedBox(width: 8),
              const Icon(
                Icons.verified_rounded,
                color: Color(0xFF6FD08C),
                size: 20,
              ),
            ],
          ],
        ),
        if (profile.city.trim().isNotEmpty ||
            profile.distanceDisplay.trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            [
              if (profile.city.trim().isNotEmpty) profile.city.trim(),
              if (profile.distanceDisplay.trim().isNotEmpty)
                profile.distanceDisplay,
            ].join('  ·  '),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 14,
            ),
          ),
        ],
      ],
    );
  }
}

class _SheetSection extends StatelessWidget {
  final String title;
  final Widget child;
  const _SheetSection({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: Colors.white38),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileDetailSheet extends StatelessWidget {
  final UserProfile profile;
  const _ProfileDetailSheet({required this.profile});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.66,
      minChildSize: 0.5,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF1C162E),
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
                  children: [
                    _SheetHeader(profile: profile),
                    if (profile.bio.trim().isNotEmpty) ...[
                      _SheetSection(
                        title: 'About',
                        child: Text(
                          profile.bio.trim(),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 15,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                    if (profile.interests.isNotEmpty) ...[
                      _SheetSection(
                        title: 'Interests',
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final interest in profile.interests)
                              _Tag(label: interest),
                          ],
                        ),
                      ),
                    ],
                    if (profile.prompts.isNotEmpty) ...[
                      _SheetSection(
                        title: 'Prompts',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final prompt in profile.prompts)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: _DetailRow(
                                  icon: Icons.chat_bubble_outline_rounded,
                                  label: prompt.questionText,
                                  value: prompt.answer,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                    _SheetSection(
                      title: 'About them',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (profile.occupation.trim().isNotEmpty)
                            _DetailRow(
                              icon: Icons.work_rounded,
                              label: 'Occupation',
                              value: profile.occupation,
                            ),
                          if (profile.education.trim().isNotEmpty)
                            _DetailRow(
                              icon: Icons.school_rounded,
                              label: 'Education',
                              value: profile.education,
                            ),
                          if (profile.heightCm != null)
                            _DetailRow(
                              icon: Icons.height_rounded,
                              label: 'Height',
                              value: '${profile.heightCm} cm',
                            ),
                          if (profile.languages.isNotEmpty)
                            _DetailRow(
                              icon: Icons.translate_rounded,
                              label: 'Languages',
                              value: profile.languages.join(', '),
                            ),
                          if (profile.smoking != null)
                            _DetailRow(
                              icon: Icons.smoke_free_rounded,
                              label: 'Smoking',
                              value: profile.smoking!,
                            ),
                          if (profile.drinking != null)
                            _DetailRow(
                              icon: Icons.wine_bar_rounded,
                              label: 'Drinking',
                              value: profile.drinking!,
                            ),
                        ],
                      ),
                    ),
                    _SheetSection(
                      title: 'Trust',
                      child: Row(
                        children: [
                          _DetailRow(
                            icon: Icons.shield_rounded,
                            label: 'Verification',
                            value: profile.isPhotoVerified
                                ? 'Photo verified'
                                : 'Not photo verified',
                          ),
                          const SizedBox(width: 16),
                          _DetailRow(
                            icon: Icons.trending_up_rounded,
                            label: 'Trust score',
                            value: '${profile.trustScore}%',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DiscoveryFilterSheet extends ConsumerStatefulWidget {
  const _DiscoveryFilterSheet();

  @override
  ConsumerState<_DiscoveryFilterSheet> createState() =>
      _DiscoveryFilterSheetState();
}

class _DiscoveryFilterSheetState extends ConsumerState<_DiscoveryFilterSheet> {
  late int _radius;

  @override
  void initState() {
    super.initState();
    _radius = ref.read(weekendProvider).locationPreferences.discoveryRadiusKm;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Discovery Filters',
            style: theme.textTheme.titleLarge?.copyWith(
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Discovery radius: $_radius km',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              thumbColor: theme.colorScheme.primary,
              activeTrackColor: theme.colorScheme.primary,
              inactiveTrackColor: theme.colorScheme.surfaceContainerHighest,
              trackHeight: 4,
            ),
            child: Slider(
              value: _radius.toDouble(),
              min: 1,
              max: 100,
              divisions: 20,
              label: '$_radius km',
              onChanged: (value) {
                setState(() => _radius = value.round());
                ref.read(weekendProvider.notifier).setDiscoveryRadius(_radius);
              },
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: () async {
                try {
                  await ref
                      .read(weekendProvider.notifier)
                      .saveLocationPreferences();
                  if (context.mounted) Navigator.pop(context);
                } catch (e) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text(
                        'Filters could not be saved. Check your connection.',
                      ),
                      backgroundColor: theme.colorScheme.error,
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
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
