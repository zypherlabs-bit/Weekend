import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Weekend design tokens: single source of truth for spacing, radius, blur and
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

  // ---------------------------------------------------------------- glass
  /// Blur radius for glass surfaces. Kept modest: enough to read as frosted
  /// glass without turning every frame into a full-screen blur (perf).
  static const double blurSigma = 18;

  /// Backdrop alphas. In light mode glass sits on a bright background and
  /// needs MORE fill to stay readable; in dark mode a light veil reads
  /// better. Text is never placed on a fully transparent surface.
  static const double glassAlphaDark = 0.10;
  static const double glassAlphaLight = 0.55;

  static const double glassBorderAlphaDark = 0.16;
  static const double glassBorderAlphaLight = 0.70;
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
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: Theme.of(context).brightness == Brightness.dark
              ? Colors.white.withValues(alpha: 0.06)
              : Colors.black.withValues(alpha: 0.05),
        ),
      ),
      child: child,
    );
    if (onTap == null) return card;
    return GestureDetector(onTap: onTap, child: card);
  }
}

/// True frosted-glass surface: translucent fill + backdrop blur + hairline
/// border + soft outer shadow. Theme aware, so the same widget is readable in
/// light and dark mode.
class WeekendGlass extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  /// Blur strength. Lower it on large scrolling surfaces.
  final double blurSigma;

  /// Tint blended over the blur. Defaults to a neutral surface tint.
  final Color? tint;

  /// When false the surface is a flat translucent panel (cheaper: use it on
  /// dense lists where many blurred layers would cost too much).
  final bool blur;

  const WeekendGlass({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(WeekendTokens.spacingLg),
    this.radius = WeekendTokens.radiusLg,
    this.blurSigma = WeekendTokens.blurSigma,
    this.tint,
    this.blur = true,
  });

  /// Lighter treatment for secondary information panels.
  const WeekendGlass.subtle({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(WeekendTokens.spacingMd),
    this.radius = WeekendTokens.radiusMd,
    this.tint,
  })  : blurSigma = 10,
        blur = true;

  /// Heavier treatment for dialogs, sheets and the swipe action bar.
  const WeekendGlass.strong({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(WeekendTokens.spacingXl),
    this.radius = WeekendTokens.radiusCard,
    this.tint,
  })  : blurSigma = 26,
        blur = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final fillAlpha = isDark
        ? WeekendTokens.glassAlphaDark
        : WeekendTokens.glassAlphaLight;
    final base = tint ?? (isDark ? Colors.white : AppTheme.lightSurface);

    final surface = Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            base.withValues(alpha: (fillAlpha + (isDark ? 0.05 : 0.0)).clamp(0.0, 1.0)),
            base.withValues(alpha: fillAlpha),
          ],
        ),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(
                  alpha: WeekendTokens.glassBorderAlphaDark)
              : Colors.black.withValues(alpha: 0.06),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.30 : 0.08),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );

    if (!blur) return surface;

    // Clip so the blur follows the rounded corners.
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: surface,
      ),
    );
  }
}

/// Atmospheric backdrop: a soft vertical gradient with two blurred colour
/// glows. Painted behind content so glass surfaces have something to refract,
/// which is what makes the frosted look read as depth instead of flat grey.
class WeekendAtmosphere extends StatelessWidget {
  final Widget child;

  const WeekendAtmosphere({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isDark
              ? const [
                  Color(0xFF160F26),
                  AppTheme.darkBackground,
                  Color(0xFF1B1030),
                ]
              : const [
                  Color(0xFFFFF7F4),
                  AppTheme.lightBackground,
                  Color(0xFFFFF1EC),
                ],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -110,
            right: -80,
            child: _Glow(
              color:
                  AppTheme.sunsetCoral.withValues(alpha: isDark ? 0.30 : 0.22),
              size: 300,
            ),
          ),
          Positioned(
            bottom: -130,
            left: -90,
            child: _Glow(
              color: (isDark ? AppTheme.goldenPeach : AppTheme.goldenPeachLight)
                  .withValues(alpha: isDark ? 0.22 : 0.28),
              size: 340,
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  final Color color;
  final double size;

  const _Glow({required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color, color.withValues(alpha: 0)],
          ),
        ),
      ),
    );
  }
}
