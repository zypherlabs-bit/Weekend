import 'package:flutter/material.dart';

/// Weekend's brand and semantic colour system.
///
/// Every screen should read from `Theme.of(context)` or [WeekendPalette] rather
/// than hardcoding a hex value, so Day / Night / Auto cannot leave an
/// unreadable surface behind.  The coral→violet ribbon "W" is the brand mark;
/// the palette is deliberately restrained around it.
class AppTheme {
  // ---------------------------------------------------------------- brand
  static const Color sunsetCoral = Color(0xFFFF4B72);
  static const Color sunsetCoralDark = Color(0xFFE0385D);
  static const Color coralDeep = Color(0xFFD92F58);
  static const Color goldenPeach = Color(0xFFFF9966);
  static const Color goldenPeachLight = Color(0xFFFFB38A);
  static const Color violet = Color(0xFF8B5CF6);
  static const Color violetDeep = Color(0xFF6D3FD1);

  // ---------------------------------------------------------------- night
  static const Color midnightViolet = Color(0xFF1A1429);
  static const Color midnightVioletSurface = Color(0xFF231B38);
  static const Color midnightVioletCard = Color(0xFF2E244A);
  static const Color darkBackground = Color(0xFF0B0714);
  static const Color darkBackgroundAlt = Color(0xFF130B20);
  static const Color darkSurface = Color(0xFF171024);
  static const Color darkSurfaceVariant = Color(0xFF241A34);
  static const Color darkOnBackground = Color(0xFFF7F1FB);
  static const Color darkOnSurface = Color(0xFFF7F1FB);
  static const Color darkOnSurfaceVariant = Color(0xFFC9BBD5);

  // ----------------------------------------------------------------- day
  static const Color lightBackground = Color(0xFFF8F4F1);
  static const Color lightBackgroundAlt = Color(0xFFFFF9F5);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceVariant = Color(0xFFF3E9E4);
  static const Color lightOnBackground = Color(0xFF211A20);
  static const Color lightOnSurface = Color(0xFF211A20);
  static const Color lightOnSurfaceVariant = Color(0xFF6E5E68);

  // --------------------------------------------------------------- status
  /// Error / destructive accent. Used for destructive confirmations and
  /// failure states so they never rely on the primary coral, which is the
  /// app's action colour and must not read as "delete".
  static const Color errorRed = Color(0xFFE5484D);
  static const Color successGreen = Color(0xFF2E9E6B);
  static const Color warningAmber = Color(0xFFD98324);

  /// Presence / verification accent.  Bright enough to sit on a photo scrim in
  /// both themes, which is why it is not the darker [successGreen].
  static const Color onlineGreen = Color(0xFF6FD08C);

  static ThemeData get lightTheme => _build(
    brightness: Brightness.light,
    scheme: const ColorScheme.light(
      primary: coralDeep,
      onPrimary: Colors.white,
      primaryContainer: Color(0xFFFFDCE2),
      onPrimaryContainer: Color(0xFF3F0013),
      secondary: violetDeep,
      onSecondary: Colors.white,
      secondaryContainer: Color(0xFFEDE2FF),
      onSecondaryContainer: Color(0xFF24103F),
      tertiary: Color(0xFFB55416),
      onTertiary: Colors.white,
      error: errorRed,
      onError: Colors.white,
      errorContainer: Color(0xFFFFDAD8),
      onErrorContainer: Color(0xFF410001),
      surface: lightSurface,
      onSurface: lightOnSurface,
      onSurfaceVariant: lightOnSurfaceVariant,
      surfaceContainerLowest: Color(0xFFFFFDFB),
      surfaceContainerLow: Color(0xCCFBF6F3),
      surfaceContainer: Color(0xCCF3E9E4),
      // Translucent tints: every Material surface now sits over the shared
      // `WeekendAtmosphere` backdrop, which is what gives the app its frosted
      // depth without paying for a blur behind each card.
      surfaceContainerHigh: Color(0xD9EFE3DD),
      surfaceContainerHighest: Color(0xE6F3E9E4),
      outline: Color(0xFFB9A7A0),
      outlineVariant: Color(0xFFE4D5CE),
      shadow: Color(0x33201A22),
      scrim: Color(0x99201A22),
      inverseSurface: darkSurface,
      onInverseSurface: darkOnSurface,
      inversePrimary: goldenPeachLight,
    ),
    background: lightBackground,
    surfaceTint: lightSurface,
    variant: lightSurfaceVariant,
  );

  static ThemeData get darkTheme => _build(
    brightness: Brightness.dark,
    scheme: const ColorScheme.dark(
      primary: sunsetCoral,
      onPrimary: Colors.white,
      primaryContainer: Color(0xFF5B1230),
      onPrimaryContainer: Color(0xFFFFD9E1),
      secondary: Color(0xFFC5A7FF),
      onSecondary: Color(0xFF24103F),
      secondaryContainer: Color(0xFF35234F),
      onSecondaryContainer: Color(0xFFEADDFF),
      tertiary: goldenPeach,
      onTertiary: Color(0xFF2E1507),
      error: Color(0xFFFF6B6E),
      onError: Color(0xFF3A0004),
      errorContainer: Color(0xFF5C1216),
      onErrorContainer: Color(0xFFFFDAD8),
      surface: darkSurface,
      onSurface: darkOnSurface,
      onSurfaceVariant: darkOnSurfaceVariant,
      surfaceContainerLowest: Color(0xFF08040F),
      surfaceContainerLow: Color(0xB3110A1B),
      surfaceContainer: Color(0xCC171024),
      // See the light scheme: translucent so the atmosphere shows through.
      surfaceContainerHigh: Color(0xCC241A34),
      surfaceContainerHighest: Color(0xD92E2240),
      outline: Color(0xFF7E7088),
      outlineVariant: Color(0xFF3A2D48),
      shadow: Color(0xCC000000),
      scrim: Color(0xCC000000),
      inverseSurface: lightSurface,
      onInverseSurface: lightOnSurface,
      inversePrimary: coralDeep,
    ),
    background: darkBackground,
    surfaceTint: darkSurface,
    variant: darkSurfaceVariant,
  );

  static ThemeData _build({
    required Brightness brightness,
    required ColorScheme scheme,
    required Color background,
    required Color surfaceTint,
    required Color variant,
  }) {
    final isDark = brightness == Brightness.dark;
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      fontFamily: 'Roboto',
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
    );

    final textTheme = _textTheme(base.textTheme, scheme);

    return base.copyWith(
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      canvasColor: background,
      splashColor: scheme.primary.withValues(alpha: 0.12),
      highlightColor: scheme.primary.withValues(alpha: 0.06),
      dividerColor: scheme.outlineVariant.withValues(alpha: 0.6),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.6),
        thickness: 1,
        space: 24,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: scheme.onSurface, size: 22),
        titleTextStyle: textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
        systemOverlayStyle: null,
      ),
      iconTheme: IconThemeData(color: scheme.onSurface, size: 24),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
          side: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.10)
                : Colors.black.withValues(alpha: 0.06),
          ),
        ),
        titleTextStyle: textTheme.headlineSmall?.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w700,
        ),
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: scheme.surface,
        modalBarrierColor: Colors.black.withValues(alpha: isDark ? 0.62 : 0.40),
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        dragHandleColor: scheme.onSurfaceVariant.withValues(alpha: 0.35),
        showDragHandle: true,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark
            ? Colors.white.withValues(alpha: 0.055)
            : Colors.white.withValues(alpha: 0.74),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 17,
        ),
        labelStyle: TextStyle(color: scheme.onSurfaceVariant),
        hintStyle: TextStyle(
          color: scheme.onSurfaceVariant.withValues(alpha: 0.72),
        ),
        helperStyle: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
        prefixIconColor: scheme.onSurfaceVariant,
        suffixIconColor: scheme.onSurfaceVariant,
        border: _inputBorder(scheme.outlineVariant.withValues(alpha: 0.55)),
        enabledBorder: _inputBorder(
          scheme.outlineVariant.withValues(alpha: 0.55),
        ),
        focusedBorder: _inputBorder(scheme.primary, width: 1.6),
        errorBorder: _inputBorder(scheme.error),
        focusedErrorBorder: _inputBorder(scheme.error, width: 1.6),
        disabledBorder: _inputBorder(
          scheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 52),
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          disabledBackgroundColor: scheme.onSurface.withValues(alpha: 0.12),
          disabledForegroundColor: scheme.onSurface.withValues(alpha: 0.38),
          textStyle: textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: 0.1,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          elevation: 0,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(0, 52),
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          textStyle: textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: 0.1,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 52),
          foregroundColor: scheme.onSurface,
          side: BorderSide(color: scheme.outline.withValues(alpha: 0.55)),
          textStyle: textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          textStyle: textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark
            ? scheme.surfaceContainerHigh
            : scheme.inverseSurface,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: isDark ? scheme.onSurface : scheme.onInverseSurface,
        ),
        actionTextColor: isDark ? scheme.primary : scheme.inversePrimary,
        elevation: 0,
        insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: Colors.transparent,
        elevation: 0,
        selectedItemColor: scheme.primary,
        unselectedItemColor: scheme.onSurfaceVariant.withValues(alpha: 0.72),
        selectedLabelStyle: textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelStyle: textTheme.labelSmall,
        type: BottomNavigationBarType.fixed,
        showUnselectedLabels: true,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.transparent,
        elevation: 0,
        indicatorColor: scheme.primary.withValues(alpha: 0.14),
        labelTextStyle: WidgetStatePropertyAll(textTheme.labelSmall),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? scheme.primary : scheme.onSurfaceVariant,
            size: 24,
          );
        }),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return Colors.white;
          return isDark ? scheme.onSurfaceVariant : scheme.outline;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return scheme.primary;
          return isDark
              ? Colors.white.withValues(alpha: 0.12)
              : Colors.black.withValues(alpha: 0.08);
        }),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return scheme.primary;
          return Colors.transparent;
        }),
        side: BorderSide(color: scheme.outline.withValues(alpha: 0.7)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: isDark
            ? Colors.white.withValues(alpha: 0.07)
            : Colors.white.withValues(alpha: 0.72),
        selectedColor: scheme.primary.withValues(alpha: 0.16),
        labelStyle: textTheme.labelMedium?.copyWith(color: scheme.onSurface),
        secondaryLabelStyle: textTheme.labelMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
        side: BorderSide(
          color: isDark
              ? Colors.white.withValues(alpha: 0.10)
              : Colors.black.withValues(alpha: 0.06),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.primary.withValues(alpha: 0.14),
        circularTrackColor: scheme.primary.withValues(alpha: 0.14),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: scheme.inverseSurface,
          borderRadius: BorderRadius.circular(10),
        ),
        textStyle: textTheme.bodySmall?.copyWith(
          color: scheme.onInverseSurface,
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.onSurfaceVariant,
        textColor: scheme.onSurface,
        subtitleTextStyle: textTheme.bodySmall?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }

  static OutlineInputBorder _inputBorder(Color color, {double width = 1}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: color, width: width),
    );
  }

  static TextTheme _textTheme(TextTheme base, ColorScheme scheme) {
    TextStyle? tuned(
      TextStyle? style, {
      required double size,
      required FontWeight weight,
      double? height,
      double? letterSpacing,
    }) {
      return style?.copyWith(
        fontSize: size,
        fontWeight: weight,
        height: height,
        letterSpacing: letterSpacing,
        color: scheme.onSurface,
      );
    }

    return base.copyWith(
      displayLarge: tuned(
        base.displayLarge,
        size: 54,
        weight: FontWeight.w700,
        height: 1.05,
        letterSpacing: -1.4,
      ),
      displayMedium: tuned(
        base.displayMedium,
        size: 42,
        weight: FontWeight.w700,
        height: 1.08,
        letterSpacing: -1.0,
      ),
      displaySmall: tuned(
        base.displaySmall,
        size: 34,
        weight: FontWeight.w700,
        height: 1.12,
        letterSpacing: -0.7,
      ),
      headlineLarge: tuned(
        base.headlineLarge,
        size: 30,
        weight: FontWeight.w700,
        height: 1.16,
        letterSpacing: -0.6,
      ),
      headlineMedium: tuned(
        base.headlineMedium,
        size: 25,
        weight: FontWeight.w700,
        height: 1.20,
        letterSpacing: -0.4,
      ),
      headlineSmall: tuned(
        base.headlineSmall,
        size: 21,
        weight: FontWeight.w700,
        height: 1.24,
        letterSpacing: -0.2,
      ),
      titleLarge: tuned(
        base.titleLarge,
        size: 20,
        weight: FontWeight.w700,
        height: 1.25,
      ),
      titleMedium: tuned(
        base.titleMedium,
        size: 16,
        weight: FontWeight.w600,
        height: 1.30,
      ),
      titleSmall: tuned(
        base.titleSmall,
        size: 14,
        weight: FontWeight.w600,
        height: 1.30,
      ),
      bodyLarge: tuned(
        base.bodyLarge,
        size: 16,
        weight: FontWeight.w400,
        height: 1.50,
      ),
      bodyMedium: tuned(
        base.bodyMedium,
        size: 14,
        weight: FontWeight.w400,
        height: 1.48,
      ),
      bodySmall: tuned(
        base.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        size: 12,
        weight: FontWeight.w400,
        height: 1.42,
      ),
      labelLarge: tuned(
        base.labelLarge,
        size: 15,
        weight: FontWeight.w600,
        height: 1.20,
      ),
      labelMedium: tuned(
        base.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
        size: 12,
        weight: FontWeight.w600,
        height: 1.20,
      ),
      labelSmall: tuned(
        base.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
        size: 11,
        weight: FontWeight.w500,
        height: 1.18,
      ),
    );
  }
}

/// Spacing / radius / motion tokens.  Kept alongside the theme so a screen
/// never invents a one-off radius.
class WeekendSpacing {
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
  static const double huge = 48;
}

class WeekendRadius {
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 26;
  static const double pill = 999;
}

class WeekendMotion {
  static const Duration quick = Duration(milliseconds: 140);
  static const Duration standard = Duration(milliseconds: 240);
  static const Duration gentle = Duration(milliseconds: 380);
  static const Curve curve = Curves.easeOutCubic;
}
