import 'package:flutter/material.dart';

/// Weekend design tokens: single source of truth for spacing, radius and
/// shared swipe thresholds so screens stop duplicating raw literals.
class WeekendTokens {
  static const double spacingXs = 4;
  static const double spacingSm = 8;
  static const double spacingMd = 12;
  static const double spacingLg = 16;
  static const double spacingXl = 20;
  static const double spacingXxl = 24;

  static const double radiusSm = 8;
  static const double radiusMd = 12;
  static const double radiusLg = 16;
  static const double radiusXl = 20;
  static const double radiusCard = 24;

  static const double swipeThresholdPx = 110;
  static const double swipeVelocityThreshold = 700;
}

/// Shared card surface used by discovery, matches, plans and safety cards.
class WeekendCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;

  const WeekendCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(WeekendTokens.spacingLg),
    this.radius = WeekendTokens.radiusLg,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: const Color(0xFF1C162E),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: child,
    );
    if (onTap == null) return card;
    return GestureDetector(onTap: onTap, child: card);
  }
}

/// Translucent glass surface for banners and overlays. Content painted on top
/// stays opaque for readability; blur is applied by the parent if needed.
class WeekendGlass extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  const WeekendGlass({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(WeekendTokens.spacingLg),
    this.radius = WeekendTokens.radiusLg,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: child,
    );
  }
}
