import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../models/models.dart';
import '../../providers/feature_providers.dart';
import 'widgets/swipe_deck.dart';
import '../../providers/weekend_provider.dart'
    show weekendProvider, WeekendState;
import '../../repositories/discovery_repository.dart';
import '../../services/ad_service.dart';
import '../../repositories/ad_repository.dart';
import '../../theme/app_theme.dart';
import '../../widgets/match_celebration_dialog.dart';
import '../../widgets/weekend_design_system.dart';

class DiscoverScreen extends ConsumerStatefulWidget {
  const DiscoverScreen({super.key});
  @override
  ConsumerState<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends ConsumerState<DiscoverScreen>
    with WidgetsBindingObserver, AutomaticKeepAliveClientMixin {
  final AdService _adService = AdService(repository: AdRepository());
  final Set<String> _impressionSubmitted = {};

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


  @override
  Widget build(BuildContext context) {
    super.build(context);
    final state = ref.watch(weekendProvider);
    final profiles = state.deckProfiles;
    final topProfile = profiles.isEmpty ? null : profiles.last;

    if (topProfile != null) {
      _recordSeenImpression(topProfile);
    }

    // The discovery tabs stay anchored above the swipe deck.
    final header = _DiscoveryHeader(state: state, onFilterTap: _showFilterSheet);

    if (topProfile == null) {
      return _EmptyDiscovery(
        onAdjustFilters: _showFilterSheet,
        onRediscover: () =>
            ref.read(weekendProvider.notifier).loadDiscoveryProfiles(),
      );
    }

    return Column(
      children: [
        header,
        Expanded(
          child: SwipeDeck(
            profiles: profiles.reversed.map((profile) {
              return SwipeProfile(
                id: profile.id,
                name: profile.name,
                age: profile.age,
                photoUrls: profile.photos,
                subtitle: profile.bio.isEmpty ? null : profile.bio,
              );
            }).toList(),
            onAction: (SwipeProfile profile, SwipeDirection direction) async {
              final notifier = ref.read(weekendProvider.notifier);
              try {
                if (direction == SwipeDirection.pass) {
                  await notifier.swipeLeft(profile.id);
                } else {
                  final current = ref.read(weekendProvider);
                  final userProfile = current.deckProfiles.firstWhere(
                    (candidate) => candidate.id == profile.id,
                    orElse: () => throw StateError('profile not in deck'),
                  );
                  await notifier.swipeRight(userProfile);
                }

                // Weekend's notifier removes the card optimistically and
                // restores it internally only when the server write genuinely
                // fails. If the profile is still in the deck, restoration
                // happened, so SwipeDeck restores its copy too: no profile is
                // silently lost and no false match is created.
                final stillPresent = ref.read(weekendProvider).deckProfiles.any(
                  (candidate) => candidate.id == profile.id,
                );
                return !stillPresent;
              } catch (_) {
                return false;
              }
            },
            onProfileTap: (SwipeProfile profile) {
              final current = ref.read(weekendProvider);
              final userProfile = current.deckProfiles.firstWhere(
                (candidate) => candidate.id == profile.id,
                orElse: () => throw StateError('profile not in deck'),
              );
              if (mounted) {
                _openProfile(userProfile);
              }
            },
            onEmpty: () =>
                ref.read(weekendProvider.notifier).loadDiscoveryProfiles(),
          ),
        ),
      ],
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
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
              color: selected ? theme.colorScheme.onPrimary : Colors.white,
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
