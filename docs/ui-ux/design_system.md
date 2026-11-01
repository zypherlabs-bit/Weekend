# Weekend Design System

## 1. Visual Direction

Sleek, minimal, premium, elegant, clean, smooth, visually balanced, consistent across
all screens. Avoid clutter, excessive gradients, unnecessary borders, excessive shadows,
and oversized decorative elements.

## 2. Colour Palette (AppTheme)

Brand: sunsetCoral #FF4B72, sunsetCoralDark #E0385D, coralDeep #D92F58 (primary),
goldenPeach #FF9966, violet #8B5CF6, violetDeep #6D3FD1 (secondary).

Night: midnightViolet #1A1429, surface #231B38, card #2E244A, background #0B0714.

Day: background #F8F4F1, surface #FFFFFF, surfaceVariant #F3E9E4.

Status: errorRed #E5484D, successGreen #2E9E6B, warningAmber #D98324,
onlineGreen #6FD08C.

Both light and dark ColorSchemes are built in AppTheme.lightTheme / darkTheme. Theme
persistence via ThemeProvider (shared_preferences).

## 3. Spacing Tokens (WeekendSpacing)

xxs 2, xs 4, sm 8, md 12, lg 16, xl 20, xxl 24, xxxl 32, huge 48.

## 4. Radius Tokens (WeekendRadius)

xs 8, sm 12, md 16, lg 20, xl 26, pill 999.

Buttons: primary 16-20, secondary 14-18, small 12-16, icon circular/softly rounded.
Inputs 14-18, cards 18-24, bottom sheets rounded upper corners, dialogs rounded.

## 5. Typography

Material 3 text theme tuned in AppTheme: displayLarge 54/700, headlineLarge 30/700,
titleLarge 20/700, bodyLarge 16/400, bodyMedium 14/400, bodySmall 12/400, labelLarge 15/600.
Font: system default (Roboto on Android). Line heights 1.05-1.50.

## 6. Motion Tokens (WeekendMotion)

quick 140ms, standard 240ms, gentle 380ms, curve easeOutCubic. Reduced-motion respected
via MediaQuery.disableAnimations.

## 7. Reusable Components

- WeekendCard / WeekendGlassCard — rounded card surfaces.
- WeekendGlass — frosted glass surface.
- WeekendGlassButton (primary action, loading, icon, expanded).
- WeekendGlassIconButton — 44dp circular icon button.
- WeekendGlassTextField — rounded input.
- WeekendGlassChip — pill filter chip.
- WeekendGlassDialog / showWeekendGlassDialog — rounded dialog.
- WeekendGlassBottomSheet — rounded upper corners.
- WeekendEmptyState / WeekendErrorState — empty/error states.
- WeekendAtmosphere — gradient backdrop with glows.
- WeekendGlassNavigationBar — frosted bottom nav plate.
- WeekendLogo, MatchCelebrationDialog, AdCard, DiscoveryCard, etc.

## 8. Dark / Light Mode

ThemeMode persisted; all surfaces read from Theme.of(context). No hardcoded palettes
in screens (migrated via tool/theme_sweep.py).
