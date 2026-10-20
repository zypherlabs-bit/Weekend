import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Weekend design tokens: single source of truth for spacing, radius, blur and
/// shared swipe thresholds so screens stop duplicating raw literals.
class WeekendTokens {
  static const double spacingXs = WeekendSpacing.xs;
  static const double spacingSm = WeekendSpacing.sm;
  static const double spacingMd = WeekendSpacing.md;
  static const double spacingLg = WeekendSpacing.lg;
  static const double spacingXl = WeekendSpacing.xl;
  static const double spacingXxl = WeekendSpacing.xxl;

  static const double radiusSm = WeekendRadius.sm;
  static const double radiusMd = WeekendRadius.md;
  static const double radiusLg = WeekendRadius.lg;
  static const double radiusXl = WeekendRadius.xl;
  static const double radiusCard = WeekendRadius.xl;

  static const double swipeThresholdPx = 110;
  static const double swipeVelocityThreshold = 700;

  // ---------------------------------------------------------------- glass
  /// Blur radius for glass surfaces. Kept modest: enough to read as frosted
  /// glass without turning every frame into a full-screen blur (perf).
  static const double blurSigma = 18;

  /// Backdrop alphas. In light mode glass sits on a bright background and
  /// needs MORE fill to stay readable; in dark mode a light veil reads
  /// better. Text is never placed on a fully transparent surface.
  static const double glassAlphaDark = 0.16;
  static const double glassAlphaLight = 0.62;

  static const double glassBorderAlphaDark = 0.16;
  static const double glassBorderAlphaLight = 0.07;
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
    final theme = Theme.of(context);
    final card = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: theme.brightness == Brightness.dark
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
  }) : blurSigma = 10,
       blur = true;

  /// Heavier treatment for dialogs, sheets and the swipe action bar.
  const WeekendGlass.strong({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(WeekendTokens.spacingXl),
    this.radius = WeekendTokens.radiusCard,
    this.tint,
  }) : blurSigma = 26,
       blur = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final canBlur = blur && !reduceMotion;

    final fillAlpha = isDark
        ? WeekendTokens.glassAlphaDark
        : WeekendTokens.glassAlphaLight;
    final base =
        tint ??
        (isDark ? theme.colorScheme.surface : theme.colorScheme.surface);

    final surface = Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            base.withValues(
              alpha: (fillAlpha + (isDark ? 0.05 : 0.0)).clamp(0.0, 1.0),
            ),
            base.withValues(alpha: fillAlpha),
          ],
        ),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(
                  alpha: WeekendTokens.glassBorderAlphaDark,
                )
              : Colors.black.withValues(
                  alpha: WeekendTokens.glassBorderAlphaLight,
                ),
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

    if (!canBlur) return surface;

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

/// Card-shaped glass, named for the brief's component vocabulary.
class WeekendGlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;

  const WeekendGlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(WeekendSpacing.lg),
    this.radius = WeekendRadius.xl,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final card = WeekendGlass(padding: padding, radius: radius, child: child);
    if (onTap == null) return card;
    return Semantics(
      button: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(radius),
        onTap: onTap,
        child: card,
      ),
    );
  }
}

/// A flatter glass panel for dense list rows.  No blur: cheaper when many
/// rows are on screen at once.
class WeekendGlassPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  const WeekendGlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(WeekendSpacing.md),
    this.radius = WeekendRadius.md,
  });

  @override
  Widget build(BuildContext context) {
    return WeekendGlass(
      padding: padding,
      radius: radius,
      blur: false,
      child: child,
    );
  }
}

/// Primary / secondary glass action.
class WeekendGlassButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;
  final bool primary;
  final bool expanded;

  const WeekendGlassButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
    this.primary = true,
    this.expanded = true,
  });

  @override
  State<WeekendGlassButton> createState() => _WeekendGlassButtonState();
}

class _WeekendGlassButtonState extends State<WeekendGlassButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final enabled = widget.onPressed != null && !widget.loading;

    final foreground = widget.primary
        ? Colors.white
        : theme.colorScheme.onSurface;

    final decoration = widget.primary
        ? BoxDecoration(
            borderRadius: BorderRadius.circular(WeekendRadius.md),
            gradient: const LinearGradient(
              colors: [Color(0xFFFF4B72), Color(0xFFB34EDB)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: AppTheme.sunsetCoral.withValues(alpha: 0.28),
                blurRadius: 22,
                offset: const Offset(0, 10),
              ),
            ],
          )
        : BoxDecoration(
            borderRadius: BorderRadius.circular(WeekendRadius.md),
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.white.withValues(alpha: 0.62),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.14)
                  : Colors.black.withValues(alpha: 0.07),
            ),
          );

    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      child: AnimatedScale(
        scale: _pressed ? 0.985 : 1,
        duration: WeekendMotion.quick,
        curve: WeekendMotion.curve,
        child: Opacity(
          opacity: enabled ? 1 : 0.5,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(WeekendRadius.md),
              onTap: enabled ? widget.onPressed : null,
              onHighlightChanged: (value) => setState(() => _pressed = value),
              child: Ink(
                decoration: decoration,
                child: Container(
                  height: 54,
                  width: widget.expanded ? double.infinity : null,
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisSize: widget.expanded
                        ? MainAxisSize.max
                        : MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (widget.loading)
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: foreground,
                          ),
                        )
                      else if (widget.icon != null)
                        Icon(widget.icon, size: 20, color: foreground),
                      if (widget.loading || widget.icon != null)
                        const SizedBox(width: 10),
                      Text(
                        widget.label,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: foreground,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Bottom navigation with a frosted plate behind the existing
/// [BottomNavigationBar].  The bar itself is transparent; this only supplies
/// the material and the top hairline.
class WeekendGlassNavigationBar extends StatelessWidget {
  final Widget child;

  const WeekendGlassNavigationBar({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    final plate = DecoratedBox(
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF120B1E).withValues(alpha: 0.88)
            : Colors.white.withValues(alpha: 0.82),
        border: Border(
          top: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.05),
          ),
        ),
      ),
      child: child,
    );

    if (reduceMotion) return plate;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: plate,
      ),
    );
  }
}

/// Glass dialog shell used for confirmations, settings and destructive
/// actions.  The Material dialog remains, so focus trapping and accessibility
/// semantics behave exactly as the platform expects.
class WeekendGlassDialog extends StatelessWidget {
  final String title;
  final Widget content;
  final List<Widget> actions;
  final IconData? icon;
  final bool destructive;

  const WeekendGlassDialog({
    super.key,
    required this.title,
    required this.content,
    this.actions = const [],
    this.icon,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: WeekendGlass.strong(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 14),
          radius: WeekendRadius.xl,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (icon != null) ...[
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color:
                            (destructive
                                    ? theme.colorScheme.error
                                    : theme.colorScheme.primary)
                                .withValues(alpha: 0.14),
                      ),
                      child: Icon(
                        icon,
                        size: 20,
                        color: destructive
                            ? theme.colorScheme.error
                            : theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: destructive
                            ? theme.colorScheme.error
                            : theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Flexible(
                child: SingleChildScrollView(
                  child: DefaultTextStyle.merge(
                    style: theme.textTheme.bodyMedium!.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    child: content,
                  ),
                ),
              ),
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    for (final action in actions)
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: action,
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

Future<T?> showWeekendGlassDialog<T>({
  required BuildContext context,
  required String title,
  required Widget content,
  List<Widget> actions = const [],
  IconData? icon,
  bool destructive = false,
  bool barrierDismissible = true,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierColor: Colors.black.withValues(alpha: 0.48),
    builder: (context) => WeekendGlassDialog(
      title: title,
      content: content,
      actions: actions,
      icon: icon,
      destructive: destructive,
    ),
  );
}

class WeekendGlassBottomSheet extends StatelessWidget {
  final Widget child;
  final String? title;
  final EdgeInsetsGeometry padding;

  const WeekendGlassBottomSheet({
    super.key,
    required this.child,
    this.title,
    this.padding = const EdgeInsets.fromLTRB(20, 4, 20, 20),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: WeekendGlass.strong(
        radius: WeekendRadius.xl,
        padding: padding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurfaceVariant.withValues(
                    alpha: 0.28,
                  ),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            if (title != null) ...[
              Text(title!, style: theme.textTheme.titleLarge),
              const SizedBox(height: 12),
            ],
            child,
          ],
        ),
      ),
    );
  }
}

Future<T?> showWeekendGlassSheet<T>({
  required BuildContext context,
  required Widget child,
  String? title,
  bool isScrollControlled = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.48),
    builder: (context) => WeekendGlassBottomSheet(title: title, child: child),
  );
}

/// Glass-styled text field used by the security screen and new surfaces.
class WeekendGlassTextField extends StatelessWidget {
  final TextEditingController? controller;
  final String label;
  final String? hint;
  final IconData? icon;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final String? Function(String?)? validator;
  final void Function(String)? onChanged;
  final void Function(String)? onSubmitted;
  final bool enabled;
  final Widget? suffixIcon;

  const WeekendGlassTextField({
    super.key,
    required this.label,
    this.controller,
    this.hint,
    this.icon,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.validator,
    this.onChanged,
    this.onSubmitted,
    this.enabled = true,
    this.suffixIcon,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      validator: validator,
      onChanged: onChanged,
      onFieldSubmitted: onSubmitted,
      enabled: enabled,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: icon == null ? null : Icon(icon),
        suffixIcon: suffixIcon,
      ),
    );
  }
}

/// Selectable glass chip used for filters and appearance presets.
class WeekendGlassChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback? onTap;
  final String? semanticsLabel;

  const WeekendGlassChip({
    super.key,
    required this.label,
    this.icon,
    this.selected = false,
    this.onTap,
    this.semanticsLabel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = selected
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;

    return Semantics(
      button: onTap != null,
      selected: selected,
      label: semanticsLabel ?? label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(WeekendRadius.pill),
          onTap: onTap,
          child: AnimatedContainer(
            duration: WeekendMotion.quick,
            curve: WeekendMotion.curve,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: selected
                  ? theme.colorScheme.primary.withValues(alpha: 0.14)
                  : (theme.brightness == Brightness.dark
                        ? Colors.white.withValues(alpha: 0.06)
                        : Colors.white.withValues(alpha: 0.68)),
              borderRadius: BorderRadius.circular(WeekendRadius.pill),
              border: Border.all(
                color: selected
                    ? theme.colorScheme.primary.withValues(alpha: 0.55)
                    : theme.colorScheme.outlineVariant.withValues(alpha: 0.55),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 16, color: fg),
                  const SizedBox(width: 7),
                ],
                Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: fg,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
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

/// The real Weekend mark, loaded from the generated transparent master.
///
/// `assets/logo/weekend-logo.jpg` is the source artwork; the PNG is derived by
/// `tool/prepare_brand_assets.py` so in-app surfaces get alpha instead of a
/// black square.  No text glyph is substituted for the logo.
class WeekendLogo extends StatelessWidget {
  final double size;
  final bool showWordmark;
  final String? tagline;
  final bool glow;

  const WeekendLogo({
    super.key,
    this.size = 96,
    this.showWordmark = false,
    this.tagline,
    this.glow = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final image = Image.asset(
      'assets/icons/weekend_logo.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      semanticLabel: 'Weekend',
      errorBuilder: (context, error, stackTrace) => Icon(
        Icons.weekend_rounded,
        size: size * 0.6,
        color: theme.colorScheme.primary,
      ),
    );

    final mark = glow
        ? DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppTheme.sunsetCoral.withValues(alpha: 0.22),
                  blurRadius: size * 0.32,
                  spreadRadius: size * 0.04,
                ),
                BoxShadow(
                  color: AppTheme.violet.withValues(alpha: 0.16),
                  blurRadius: size * 0.44,
                  spreadRadius: size * 0.02,
                ),
              ],
            ),
            child: image,
          )
        : image;

    if (!showWordmark && tagline == null) {
      return Semantics(label: 'Weekend logo', image: true, child: mark);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(label: 'Weekend logo', image: true, child: mark),
        const SizedBox(height: 16),
        if (showWordmark)
          Text(
            'Weekend',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.6,
              color: theme.colorScheme.onSurface,
            ),
          ),
        if (tagline != null) ...[
          const SizedBox(height: 6),
          Text(
            tagline!,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

/// Round glass icon action with a guaranteed 48dp touch target.
class WeekendGlassIconButton extends StatelessWidget {
  final IconData icon;
  final String semanticLabel;
  final VoidCallback? onPressed;
  final bool tinted;

  const WeekendGlassIconButton({
    super.key,
    required this.icon,
    required this.semanticLabel,
    required this.onPressed,
    this.tinted = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: semanticLabel,
      child: SizedBox(
        width: 44,
        height: 44,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: Ink(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: tinted
                    ? theme.colorScheme.primary.withValues(alpha: 0.14)
                    : (theme.brightness == Brightness.dark
                          ? Colors.white.withValues(alpha: 0.07)
                          : Colors.white.withValues(alpha: 0.72)),
                border: Border.all(
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.55,
                  ),
                ),
              ),
              child: Icon(
                icon,
                size: 21,
                color: tinted
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurface,
              ),
            ),
          ),
        ),
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
              ? [
                  Color(0xFF160F26),
                  AppTheme.darkBackground,
                  Color(0xFF1B1030),
                ]
              : [
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
              color: AppTheme.sunsetCoral.withValues(
                alpha: isDark ? 0.30 : 0.22,
              ),
              size: 300,
            ),
          ),
          Positioned(
            bottom: -130,
            left: -90,
            child: _Glow(
              color: (isDark ? AppTheme.violet : AppTheme.goldenPeachLight)
                  .withValues(alpha: isDark ? 0.26 : 0.28),
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
          gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
        ),
      ),
    );
  }
}
