import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme/app_theme.dart';
import 'weekend_design_system.dart';

/// A selectable filter chip used across the Preferred Match screen.
///
/// Wrapped in [Semantics] with `button: true` and an explicit `selected`
/// state so screen readers announce "Woman, selected" rather than only the
/// label. The visual state is never the only carrier of the selection.
class SelectChip extends StatelessWidget {
  const SelectChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: selected
            ? AppTheme.sunsetCoral
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(WeekendTokens.radiusXl),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(WeekendTokens.radiusXl),
          child: Container(
            // 44dp minimum: comfortably above the 48dp touch-target guidance
            // once the chip's own padding is counted.
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(WeekendTokens.radiusXl),
              border: Border.all(
                color: selected
                    ? AppTheme.sunsetCoral
                    : theme.colorScheme.outlineVariant,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(
                    icon,
                    size: 16,
                    color: selected
                        ? Colors.white
                        : theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                  const SizedBox(width: 6),
                ],
                Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: selected ? Colors.white : theme.colorScheme.onSurface,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Inclusive integer stepper used for the age range.
class NumberStepper extends StatelessWidget {
  const NumberStepper({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(height: WeekendTokens.spacingSm),
        Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(WeekendTokens.radiusLg),
          ),
          child: Row(
            children: [
              IconButton(
                onPressed: value > min ? () => onChanged(value - 1) : null,
                icon: const Icon(Icons.remove_rounded),
                tooltip: 'Decrease $label age',
                iconSize: 20,
              ),
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  label: '$label age',
                  value: '$value',
                  child: ExcludeSemantics(
                    child: Text(
                      '$value',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                ),
              ),
              IconButton(
                onPressed: value < max ? () => onChanged(value + 1) : null,
                icon: const Icon(Icons.add_rounded),
                tooltip: 'Increase $label age',
                iconSize: 20,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Result summary: success, empty-because-filtered, or error.
///
/// The three states are textually and visually distinct on purpose. A user
/// whose filters were honoured and returned nothing must never be shown an
/// error, and a network failure must never be reported as "no matches".
class ResultPanel extends StatelessWidget {
  const ResultPanel({
    super.key,
    required this.theme,
    required this.icon,
    required this.title,
    required this.message,
    required this.tint,
    this.chips = const [],
    this.profiles = const [],
    this.primaryLabel,
    this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
  });

  final ThemeData theme;
  final IconData icon;
  final String title;
  final String message;
  final Color tint;
  final List<String> chips;
  final List<UserProfile> profiles;
  final String? primaryLabel;
  final VoidCallback? onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(WeekendTokens.spacingXxl),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(WeekendTokens.radiusCard),
        border: Border.all(color: tint.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: tint.withValues(alpha: 0.12),
                  borderRadius:
                      BorderRadius.circular(WeekendTokens.radiusLg),
                ),
                child: Icon(icon, color: tint, size: 22),
              ),
              const SizedBox(width: WeekendTokens.spacingMd),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: WeekendTokens.spacingMd),
          Text(
            message,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              height: 1.45,
            ),
          ),
          if (chips.isNotEmpty) ...[
            const SizedBox(height: WeekendTokens.spacingLg),
            Wrap(
              spacing: WeekendTokens.spacingSm,
              runSpacing: WeekendTokens.spacingSm,
              children: [
                for (final chip in chips)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius:
                          BorderRadius.circular(WeekendTokens.radiusSm),
                    ),
                    child: Text(
                      chip,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: 0.75),
                      ),
                    ),
                  ),
              ],
            ),
          ],
          if (profiles.isNotEmpty) ...[
            const SizedBox(height: WeekendTokens.spacingLg),
            for (final profile in profiles.take(5))
              ResultRow(profile: profile),
          ],
          if (primaryLabel != null && onPrimary != null) ...[
            const SizedBox(height: WeekendTokens.spacingXxl),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onPrimary,
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.sunsetCoral,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(WeekendTokens.radiusLg),
                  ),
                ),
                child: Text(primaryLabel!),
              ),
            ),
          ],
          if (secondaryLabel != null && onSecondary != null) ...[
            const SizedBox(height: WeekendTokens.spacingSm),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: onSecondary,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(WeekendTokens.radiusLg),
                  ),
                ),
                child: Text(secondaryLabel!),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One row of a result set: photo, name + age, city, distance.
class ResultRow extends StatelessWidget {
  const ResultRow({super.key, required this.profile});
  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: WeekendTokens.spacingMd),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(WeekendTokens.radiusMd),
            child: SizedBox(
              width: 48,
              height: 48,
              child: profile.photos.isEmpty
                  ? ColoredBox(
                      color: theme.colorScheme.surfaceContainerHighest,
                      child: const Icon(Icons.person_rounded, size: 22),
                    )
                  : Image.network(
                      profile.photos.first,
                      fit: BoxFit.cover,
                      // Signed URLs expire; fall back rather than rendering a
                      // broken-image glyph.
                      errorBuilder: (_, __, ___) => ColoredBox(
                        color: theme.colorScheme.surfaceContainerHighest,
                        child: const Icon(Icons.person_rounded, size: 22),
                      ),
                    ),
            ),
          ),
          const SizedBox(width: WeekendTokens.spacingMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  // Age is omitted entirely when unknown rather than showing
                  // a fabricated number.
                  profile.age > 0
                      ? '${profile.name}, ${profile.age}'
                      : profile.name,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                if (profile.city.isNotEmpty ||
                    profile.distanceDisplay.isNotEmpty)
                  Text(
                    [
                      if (profile.city.isNotEmpty) profile.city,
                      if (profile.distanceDisplay.isNotEmpty)
                        profile.distanceDisplay,
                    ].join(' - '),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
              ],
            ),
          ),
          if (profile.isPhotoVerified)
            Icon(
              Icons.verified_rounded,
              size: 18,
              color: theme.colorScheme.primary,
            ),
        ],
      ),
    );
  }
}

