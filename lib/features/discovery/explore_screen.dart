import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import '../../config/supabase_config.dart';
import '../../providers/weekend_provider.dart';
import '../../models/models.dart';
import '../../services/ad_service.dart';
import '../../repositories/ad_repository.dart';
import '../../widgets/location_radius_filter.dart';

class ExploreScreen extends ConsumerStatefulWidget {
  const ExploreScreen({super.key});
  @override
  ConsumerState<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends ConsumerState<ExploreScreen>
    with TickerProviderStateMixin {
  late final AdService _adService;
  @override
  void initState() {
    super.initState();
    _adService = AdService(repository: AdRepository());
    _adService.addListener(_onAdStateChanged);
  }

  void _onAdStateChanged() {
    if (_adService.shouldShowAd && _adService.adId != null) {
      final userId = SupabaseConfig.currentUserId;
      _adService.fetchAd(userId);
    }
  }

  @override
  void dispose() {
    _adService.removeListener(_onAdStateChanged);
    _adService.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF130E20)
          : const Color(0xFFFCF8F7),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _buildHeader(context)),
            SliverToBoxAdapter(child: _buildModeChips(context)),
            SliverToBoxAdapter(child: _buildSections(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Explore',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
            ),
          ),
          Row(
            children: [
              IconButton(
                onPressed: () {
                  _showFilters(context);
                },
                icon: const Icon(Icons.tune_rounded, color: Colors.white70),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: () {
                  _showLocationSettings(context);
                },
                icon: const Icon(Icons.settings_rounded, color: Colors.white70),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildModeChips(BuildContext context) {
    final state = ref.watch(weekendProvider);
    final modes = DiscoveryMode.values;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: modes.map((mode) {
          final isSelected = state.selectedMode == mode;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(mode.title),
              selected: isSelected,
              onSelected: (_) {
                ref.read(weekendProvider.notifier).selectDiscoveryMode(mode);
                _loadProfilesForMode(mode);
              },
              selectedColor: const Color(0xFFFF4B72),
              backgroundColor: Colors.white.withValues(alpha: 0.08),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              side: BorderSide(
                color: isSelected
                    ? const Color(0xFFFF4B72)
                    : Colors.white.withValues(alpha: 0.2),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  void _loadProfilesForMode(DiscoveryMode mode) {
    ref.read(weekendProvider.notifier).loadDiscoveryProfiles();
  }

  Widget _buildSections(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Nearby', 'People closest to you'),
        _buildNearbyPreview(context),
        const SizedBox(height: 24),
        _buildSectionHeader('Weekend Nearby', 'People available this weekend'),
        _buildWeekendNearbyPreview(context),
        const SizedBox(height: 24),
        _buildSectionHeader(
          'Crossed Paths',
          'People you\'ve crossed paths with',
        ),
        _buildCrossedPathsPreview(context),
        const SizedBox(height: 24),
        _buildSectionHeader(
          'Explore Your City',
          'People and plans in your area',
        ),
        _buildCityPreview(context),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildSectionHeader(String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNearbyPreview(BuildContext context) {
    final state = ref.watch(weekendProvider);
    final nearbyProfiles = state.deckProfiles.take(3).toList();
    if (nearbyProfiles.isEmpty) {
      return const _EmptyPreview(
        icon: Icons.place_rounded,
        message: 'Enable location to discover people nearby',
      );
    }
    return _ProfileHorizontalList(profiles: nearbyProfiles);
  }

  Widget _buildWeekendNearbyPreview(BuildContext context) {
    final state = ref.watch(weekendProvider);
    final weekendProfiles = state.deckProfiles
        .where(
          (p) =>
              p.weekendAvailability.isNotEmpty &&
              p.weekendAvailability.values.any((v) => v),
        )
        .take(3)
        .toList();
    if (weekendProfiles.isEmpty) {
      return const _EmptyPreview(
        icon: Icons.calendar_today_rounded,
        message: 'No plans yet. Be the first to set your weekend availability!',
      );
    }
    return _ProfileHorizontalList(profiles: weekendProfiles);
  }

  Widget _buildCrossedPathsPreview(BuildContext context) {
    final state = ref.watch(weekendProvider);
    final crossed = state.crossedPaths.take(3).toList();
    if (crossed.isEmpty) {
      return _EmptyPreview(
        icon: Icons.directions_walk_rounded,
        message: 'Crossed paths will appear here as you explore',
      );
    }
    return SizedBox(
      height: 220,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: crossed.length,
        itemBuilder: (context, index) {
          final cp = crossed[index];
          return Container(
            width: 160,
            margin: const EdgeInsets.only(right: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF2E244A),
              borderRadius: BorderRadius.circular(16),
              image: const DecorationImage(
                image: AssetImage('assets/images/placeholder_avatar.png'),
                fit: BoxFit.cover,
                colorFilter: ColorFilter.mode(Colors.black45, BlendMode.darken),
              ),
            ),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.black.withValues(alpha: 0.7),
                      Colors.transparent,
                    ],
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${cp.crossCount}x',
                      style: const TextStyle(
                        color: Color(0xFFFF9966),
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'crossed',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCityPreview(BuildContext context) {
    final state = ref.watch(weekendProvider);
    final cityProfiles = state.deckProfiles.take(3).toList();
    if (cityProfiles.isEmpty) {
      return const _EmptyPreview(
        icon: Icons.location_city_rounded,
        message: 'No profiles in your city yet',
      );
    }
    return _ProfileHorizontalList(profiles: cityProfiles);
  }

  void _showFilters(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
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
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Discovery Filters',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 24),
            LocationRadiusFilter(
              currentRadiusKm: ref
                  .watch(weekendProvider)
                  .locationPreferences
                  .discoveryRadiusKm,
              onRadiusChanged: (km) {
                ref.read(weekendProvider.notifier).setDiscoveryRadius(km);
                Navigator.pop(context);
              },
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF4B72),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(28),
                  ),
                ),
                child: const Text('Apply Filters'),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showLocationSettings(BuildContext context) {
    context.go('/location-settings');
  }
}

class _ProfileHorizontalList extends StatelessWidget {
  final List<UserProfile> profiles;
  const _ProfileHorizontalList({required this.profiles});
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 220,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: profiles.length,
        itemBuilder: (context, index) {
          final profile = profiles[index];
          return Container(
            width: 150,
            margin: const EdgeInsets.only(right: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              image: profile.photos.isNotEmpty
                  ? DecorationImage(
                      image: CachedNetworkImageProvider(profile.photos.first),
                      fit: BoxFit.cover,
                    )
                  : null,
              color: const Color(0xFF2E244A),
            ),
            child: Stack(
              children: [
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.black.withValues(alpha: 0.8),
                          Colors.black.withValues(alpha: 0.3),
                        ],
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                      ),
                    ),
                    child: Text(
                      profile.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                if (profile.isPhotoVerified)
                  const Positioned(
                    top: 8,
                    right: 8,
                    child: Icon(
                      Icons.verified_rounded,
                      size: 18,
                      color: Color(0xFF4CAF50),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _EmptyPreview extends StatelessWidget {
  final IconData icon;
  final String message;
  const _EmptyPreview({required this.icon, required this.message});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        height: 120,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 32, color: Colors.white54),
              const SizedBox(height: 12),
              Text(
                message,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 13,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

