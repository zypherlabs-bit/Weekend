import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/models.dart';
import '../../providers/weekend_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/weekend_design_system.dart';

/// Immersive profile photo viewer.
///
/// • Horizontal swipe between [UserProfile.photos] via a [PageView].
/// • Vertical reveal scroll: a [CustomScrollView] per page scrolls to expose
///   profile details beneath the full-width photo.
/// • Photo indicator overlay (dot row + "i/n" text).
/// • Shared [Hero] transition back to the [ProfileScreen] avatar, tagged with
///   [UserProfile.primaryPhotoId] (falls back to [UserProfile.id] when empty).
///
/// Zoom is intentionally omitted: `photo_view` 0.15 exposes no `panEnabled`
/// API, so a pan-active PhotoView would fight the vertical reveal scroll.
/// Conflict-free pinch-to-zoom can be added later with
/// `InteractiveViewer(panEnabled: false)` wrapping the [CachedNetworkImage].
class ProfileViewerScreen extends ConsumerStatefulWidget {
  const ProfileViewerScreen({this.initialIndex = 0, super.key});

  /// Zero-based starting photo. Pushed from [ProfileScreen] as 0 (the primary).
  final int initialIndex;

  @override
  ConsumerState<ProfileViewerScreen> createState() =>
      _ProfileViewerScreenState();
}

const _kPlaceholderColor = Color(0xFF2E244A);

class _ProfileViewerScreenState extends ConsumerState<ProfileViewerScreen> {
  late final PageController _pageController;
  late int _currentPage;

  @override
  void initState() {
    super.initState();
    _currentPage = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  String _heroTag(UserProfile user) =>
      'profileAvatar_${user.primaryPhotoId.isNotEmpty ? user.primaryPhotoId : user.id}';

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(weekendProvider).currentUser;
    final photos = user.photos;
    final heroTag = _heroTag(user);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            if (photos.isNotEmpty)
              PageView.builder(
                controller: _pageController,
                physics: const BouncingScrollPhysics(),
                itemCount: photos.length,
                onPageChanged: (i) => setState(() => _currentPage = i),
                itemBuilder: (context, index) {
                  final photoUrl = photos[index];
                  // index == 0 == the primary photo shown by ProfileScreen.
                  // Only that page carries the Hero so it pairs with the
                  // avatar source during the push transition.
                  final tag = index == 0 ? heroTag : null;
                  return CustomScrollView(
                    // Vertical axis here; PageView handles horizontal paging.
                    // Flutter's gesture arena disambiguates perpendicular
                    // axes, so there is no pan conflict on the reveal scroll.
                    slivers: [
                      SliverToBoxAdapter(
                        child: _PhotoTile(photoUrl: photoUrl, heroTag: tag),
                      ),
                      SliverToBoxAdapter(child: _DetailsSection(user: user)),
                      const SliverToBoxAdapter(child: SizedBox(height: 40)),
                    ],
                  );
                },
              )
            else
              const Center(
                child: Icon(
                  Icons.person_rounded,
                  size: 88,
                  color: Colors.white24,
                ),
              ),
            Padding(
              padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _CloseButton(onTap: () => Navigator.of(context).pop()),
                  _PhotoIndicator(
                    currentPage: _currentPage,
                    total: photos.length,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({required this.photoUrl, this.heroTag});

  final String photoUrl;
  final String? heroTag;

  @override
  Widget build(BuildContext context) {
    final photoHeight = MediaQuery.of(context).size.height * 0.55;
    final image = CachedNetworkImage(
      imageUrl: photoUrl,
      fit: BoxFit.cover,
      width: double.infinity,
      height: photoHeight,
      placeholder: (_, __) => Container(
        color: _kPlaceholderColor,
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
        color: _kPlaceholderColor,
        alignment: Alignment.center,
        child: const Icon(
          Icons.broken_image_rounded,
          size: 60,
          color: Colors.white24,
        ),
      ),
    );

    final picture = SizedBox(height: photoHeight, child: image);
    final wrapped = switch (heroTag) {
      final String tag => Hero(tag: tag, child: picture),
      null => picture,
    };
    return wrapped;
  }
}

/// Top-left safe close affordance.
class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.onTap});

  final void Function() onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 16),
      child: Material(
        color: Colors.transparent,
        child: Ink(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.35),
            shape: BoxShape.circle,
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(20),
            child: const Icon(
              Icons.close_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
        ),
      ),
    );
  }
}

/// Dot indicator + "current/total" text, mirroring Discovery's
/// `_photoIndicators` aesthetic (no external dependency).
class _PhotoIndicator extends StatelessWidget {
  const _PhotoIndicator({required this.currentPage, required this.total});

  final int currentPage;
  final int total;

  @override
  Widget build(BuildContext context) {
    if (total <= 1) {
      return const SizedBox.shrink();
    }
    final dots = List<Widget>.generate(total, (i) {
      final active = i == currentPage;
      return AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.symmetric(horizontal: 3.5),
        width: active ? 22 : 7,
        height: 7,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(5),
          color: active
              ? AppTheme.sunsetCoral
              : Colors.white.withValues(alpha: 0.55),
        ),
      );
    });
    return Padding(
      padding: const EdgeInsets.only(right: 16),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ...dots,
          const SizedBox(width: 8),
          Text(
            '${currentPage + 1}/$total',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Colors.white70,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Profile details revealed on the vertical reveal scroll.
class _DetailsSection extends StatelessWidget {
  const _DetailsSection({required this.user});

  final UserProfile user;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '${user.name}, ${user.age}',
                style: theme.textTheme.titleLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (user.isPhotoVerified) ...[
                const SizedBox(width: 6),
                const Icon(
                  Icons.verified_rounded,
                  size: 18,
                  color: AppTheme.onlineGreen,
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(
                Icons.location_on_rounded,
                size: 14,
                color: Colors.white70,
              ),
              const SizedBox(width: 2),
              Text(
                user.city,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.white70,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (user.bio.isNotEmpty)
            _ProfileSection(
              title: 'About',
              child: Text(
                user.bio,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.92),
                  height: 1.35,
                ),
              ),
            ),
          if (user.interests.isNotEmpty) ...[
            const SizedBox(height: 20),
            _ProfileSection(
              title: 'Interests',
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final interest in user.interests)
                    _InterestChip(interest: interest),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _InterestChip extends StatelessWidget {
  const _InterestChip({required this.interest});

  final String interest;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Chip(
      label: Text(interest, style: const TextStyle(color: Colors.white)),
      backgroundColor: scheme.surface.withValues(alpha: 0.25),
      shape: StadiumBorder(
        side: BorderSide(color: Colors.white.withValues(alpha: 0.2), width: 1),
      ),
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: -3),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}

/// Mirrors `profile_screen.dart`'s `_ProfileSection` (glass card + label).
class _ProfileSection extends StatelessWidget {
  const _ProfileSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8),
        WeekendGlassCard(
          padding: const EdgeInsets.all(16),
          radius: 16,
          child: SizedBox(width: double.infinity, child: child),
        ),
      ],
    );
  }
}
