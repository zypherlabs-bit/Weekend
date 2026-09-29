import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/models.dart';
import '../models/profile_schema.dart';

/// Weekend's profile card.
///
/// Information hierarchy (media-first, progressive disclosure)
/// ---------------------------------------------------------
///   1. Photos            dominant, swipeable, full-bleed
///   2. Name              bottom-left, largest type
///   3. Age               next to the name
///   4. City              under the name
///   5. Distance          privacy-safe label, top-right
///   6. Bio               in the expanded panel
///   7. Interests         in the expanded panel
///   8. Relationship intent  in the expanded panel
///   9. Prompts           in the expanded panel
///  10. Lifestyle         in the expanded panel
///
/// The first five are always visible so the card can be judged at a glance in a
/// deck; the rest live behind an explicit "info" affordance, which keeps the
/// photo dominant instead of burying it under a wall of text.
///
/// Location privacy: the card renders only the server-produced label
/// ("Nearby", "5 km away", a city name). `latitude`/`longitude` are never read
/// here and never rendered.
class DiscoveryCard extends StatefulWidget {
  final UserProfile profile;
  final bool isTop;
  final VoidCallback onSwipeLeft;
  final VoidCallback onSwipeRight;
  final VoidCallback onStandOut;
  final bool showDistance;

  const DiscoveryCard({
    super.key,
    required this.profile,
    required this.isTop,
    required this.onSwipeLeft,
    required this.onSwipeRight,
    required this.onStandOut,
    this.showDistance = true,
  });

  @override
  State<DiscoveryCard> createState() => _DiscoveryCardState();
}

class _DiscoveryCardState extends State<DiscoveryCard> {
  final PageController _pageController = PageController();
  int _photoIndex = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // A horizontal drag on the photo pager is owned by the PageView, so the
      // swipe gesture only claims drags that start on the chrome, not the media.
      onHorizontalDragEnd: (details) {
        if (!widget.isTop) return;
        final v = details.primaryVelocity;
        if (v != null && v > 250) {
          widget.onSwipeLeft();
        } else if (v != null && v < -250) {
          widget.onSwipeRight();
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        margin: EdgeInsets.only(bottom: widget.isTop ? 0 : 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 20,
              spreadRadius: 2,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Stack(
            children: [
              Positioned.fill(child: _buildMedia(context)),
              // Legibility scrim: strongest at the bottom, where the text sits.
              const Positioned.fill(child: _Scrim()),
              _photoIndicator(),
              if (widget.profile.isPhotoVerified)
                const Positioned(top: 16, left: 16, child: _VerifiedBadge()),
              if (widget.showDistance) _buildDistanceBadge(),
              _buildIdentity(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMedia(BuildContext context) {
    if (widget.profile.photos.isEmpty) {
      return Container(
        color: const Color(0xFF2E244A),
        child: const Center(
          child: Icon(Icons.person_rounded, size: 80, color: Colors.white24),
        ),
      );
    }
    return PageView.builder(
      controller: _pageController,
      physics: const ClampingScrollPhysics(),
      itemCount: widget.profile.photos.length,
      onPageChanged: (i) => setState(() => _photoIndex = i),
      itemBuilder: (context, i) => CachedNetworkImage(
        imageUrl: widget.profile.photos[i],
        fit: BoxFit.cover,
        placeholder: (_, __) => Container(
          color: const Color(0xFF2E244A),
          child: const Center(
            child: CircularProgressIndicator(
              color: Color(0xFFFF4B72),
              strokeWidth: 2,
            ),
          ),
        ),
        errorWidget: (_, __, ___) => Container(
          color: const Color(0xFF2E244A),
          child: const Icon(
            Icons.broken_image_rounded,
            size: 60,
            color: Colors.white24,
          ),
        ),
      ),
    );
  }

  /// "N of M" indicator, only when there is more than one photo.
  Widget _photoIndicator() {
    final count = widget.profile.photos.length;
    if (count < 2) return const SizedBox.shrink();
    return Positioned(
      top: 16,
      left: 0,
      right: 0,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < count; i++)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: i == _photoIndex ? 18 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: i == _photoIndex
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
        ],
      ),
    );
  }

  /// Privacy-safe distance label. Never a coordinate, never a street address.
  Widget _buildDistanceBadge() {
    final label = widget.profile.distanceDisplay.trim().isNotEmpty
        ? widget.profile.distanceDisplay
        : (widget.profile.distanceKm > 0
              ? '${widget.profile.distanceKm} km away'
              : 'Nearby');
    return Positioned(
      top: 16,
      right: 16,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.near_me_rounded, size: 14, color: Colors.white),
            const SizedBox(width: 5),
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  /// Name, age, city and the "show more" affordance.
  Widget _buildIdentity() {
    final profile = widget.profile;
    final city = profile.city.trim();
    // Age 0 means "not stated" - never render a fabricated number.
    final age = profile.age > 0 ? profile.age : null;

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 12, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Flexible(
                  child: Text(
                    profile.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                      height: 1.1,
                    ),
                  ),
                ),
                if (age != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    '$age',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 24,
                      fontWeight: FontWeight.w300,
                    ),
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
            if (city.isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(
                    Icons.location_on_rounded,
                    size: 14,
                    color: Colors.white70,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      city,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (profile.relationshipIntent.trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              _IntentChip(label: profile.relationshipIntent),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                _InfoButton(onTap: _openDetailSheet),
                const SizedBox(width: 10),
                if (profile.photos.length > 1)
                  _MiniChip(
                    icon: Icons.photo_library_rounded,
                    label: '${_photoIndex + 1}/${profile.photos.length}',
                  ),
                if (profile.trustScore > 0) ...[
                  const SizedBox(width: 8),
                  _MiniChip(
                    icon: Icons.shield_rounded,
                    label: '${profile.trustScore}%',
                    tint: const Color(0xFFFF9966),
                  ),
                ],
                if (profile.crossedPathsCount > 0) ...[
                  const SizedBox(width: 8),
                  _MiniChip(
                    icon: Icons.route_rounded,
                    label: 'Met ${profile.crossedPathsCount}x',
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _openDetailSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _ProfileDetailSheet(profile: widget.profile),
    );
  }
}

/// Full profile, revealed progressively.
class _ProfileDetailSheet extends StatelessWidget {
  final UserProfile profile;
  const _ProfileDetailSheet({required this.profile});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.62,
      minChildSize: 0.4,
      maxChildSize: 0.94,
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
                    // 2-5: identity, repeated at full size for reading comfort.
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
                    if (profile.interests.isNotEmpty)
                      _SheetSection(
                        title: 'Interests',
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final interest in profile.interests)
                              _Tag(
                                label: interest,
                                highlighted: profile.commonInterests.contains(
                                  interest,
                                ),
                              ),
                          ],
                        ),
                      ),
                    if (profile.prompts.isNotEmpty)
                      _SheetSection(
                        title: 'Prompts',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final prompt in profile.prompts)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      prompt.questionText,
                                      style: const TextStyle(
                                        color: Color(0xFFFF9966),
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      prompt.answer,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 15,
                                        height: 1.45,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    if (_lifestyleRows.isNotEmpty)
                      _SheetSection(
                        title: 'Lifestyle',
                        child: Column(
                          children: [
                            for (final row in _lifestyleRows)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 5,
                                ),
                                child: Row(
                                  children: [
                                    Text(
                                      row.$1,
                                      style: const TextStyle(
                                        color: Colors.white54,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const Spacer(),
                                    Text(
                                      row.$2,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    if (profile.occupation.trim().isNotEmpty ||
                        profile.education.trim().isNotEmpty ||
                        profile.favoriteMusic.trim().isNotEmpty ||
                        profile.idealWeekend.trim().isNotEmpty ||
                        profile.languages.isNotEmpty)
                      _SheetSection(
                        title: 'More',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (profile.occupation.trim().isNotEmpty)
                              _Fact(
                                icon: Icons.work_outline_rounded,
                                value: profile.occupation.trim(),
                              ),
                            if (profile.education.trim().isNotEmpty)
                              _Fact(
                                icon: Icons.school_outlined,
                                value: profile.education.trim(),
                              ),
                            if (profile.favoriteMusic.trim().isNotEmpty)
                              _Fact(
                                icon: Icons.music_note_rounded,
                                value: profile.favoriteMusic.trim(),
                              ),
                            if (profile.idealWeekend.trim().isNotEmpty)
                              _Fact(
                                icon: Icons.weekend_rounded,
                                value: profile.idealWeekend.trim(),
                              ),
                            if (profile.languages.isNotEmpty)
                              _Fact(
                                icon: Icons.translate_rounded,
                                value: profile.languages.join(', '),
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

  /// Lifestyle values present on this profile, in the catalogue's order.
  ///
  /// Null values are skipped so the sheet never renders "Smoking: " with an
  /// empty answer.
  List<(String, String)> get _lifestyleRows {
    final rows = <(String, String)>[];
    void add(String column, String? value) {
      if (value == null || value.trim().isEmpty) return;
      for (final field in ProfileSchema.lifestyleFields) {
        if (field.column == column) rows.add((field.label, value));
      }
    }

    add('smoking', profile.smoking);
    add('drinking', profile.drinking);
    add('exercise', profile.exercise);
    add('pets', profile.pets);
    add('children', profile.children);
    return rows;
  }
}

/// Bottom-to-top scrim so the identity text stays legible on any photo.
class _Scrim extends StatelessWidget {
  const _Scrim();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.transparent,
              Colors.black.withValues(alpha: 0.15),
              Colors.black.withValues(alpha: 0.75),
              Colors.black.withValues(alpha: 0.92),
            ],
            stops: const [0.35, 0.55, 0.8, 1.0],
          ),
        ),
      ),
    );
  }
}

class _VerifiedBadge extends StatelessWidget {
  const _VerifiedBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF6FD08C).withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.verified_rounded, size: 13, color: Colors.white),
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
}

class _IntentChip extends StatelessWidget {
  final String label;
  const _IntentChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFFF4B72).withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _InfoButton extends StatelessWidget {
  final VoidCallback onTap;
  const _InfoButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Show full profile',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.info_outline_rounded, size: 15, color: Colors.white),
              SizedBox(width: 6),
              Text(
                'Show more',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color tint;
  const _MiniChip({
    required this.icon,
    required this.label,
    this.tint = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: tint),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 11),
          ),
        ],
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
    final city = profile.city.trim();
    final distance = profile.distanceDisplay.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
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
            ],
          ),
          const SizedBox(height: 6),
          // Privacy-safe location: a city and an approximate distance, never a
          // coordinate and never a street address.
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              if (city.isNotEmpty)
                _MetaLine(icon: Icons.location_on_rounded, text: city),
              if (distance.isNotEmpty || profile.distanceKm > 0)
                _MetaLine(
                  icon: Icons.near_me_rounded,
                  text: distance.isNotEmpty
                      ? distance
                      : '${profile.distanceKm} km away',
                ),
            ],
          ),
          if (profile.relationshipIntent.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            _IntentChip(label: profile.relationshipIntent),
          ],
        ],
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

class _SheetSection extends StatelessWidget {
  final String title;
  final Widget child;
  const _SheetSection({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String label;
  final bool highlighted;
  const _Tag({required this.label, this.highlighted = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: highlighted
            ? const Color(0xFFFF4B72).withValues(alpha: 0.9)
            : Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: highlighted
            ? null
            : Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: highlighted ? Colors.white : Colors.white70,
          fontSize: 12,
          fontWeight: highlighted ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  final IconData icon;
  final String value;
  const _Fact({required this.icon, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: Colors.white38),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}
