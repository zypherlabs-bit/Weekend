package com.weekend.app.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

val DarkColorScheme =
  darkColorScheme(
    primary = SunsetCoral,
    onPrimary = Color.White,
    primaryContainer = MidnightVioletCard,
    onPrimaryContainer = GoldenPeachLight,
    secondary = GoldenPeach,
    onSecondary = MidnightViolet,
    secondaryContainer = MidnightVioletSurface,
    onSecondaryContainer = GoldenPeachLight,
    tertiary = GoldenPeachLight,
    onTertiary = MidnightViolet,
    background = DarkBackground,
    onBackground = DarkOnBackground,
    surface = DarkSurface,
    onSurface = DarkOnSurface,
    surfaceVariant = DarkSurfaceVariant,
    onSurfaceVariant = DarkOnSurface,
    outline = Color(0x33FFFFFF),
    outlineVariant = Color(0x1AFFFFFF)
  )

val LightColorScheme =
  lightColorScheme(
    primary = SunsetCoral,
    onPrimary = Color.White,
    primaryContainer = CoralPrimaryContainerLight,
    onPrimaryContainer = CoralOnPrimaryContainerLight,
    secondary = GoldenPeach,
    onSecondary = Color.White,
    secondaryContainer = Color(0xFFFFE5DB),
    onSecondaryContainer = Color(0xFF421E05),
    tertiary = PeachTertiaryLight,
    onTertiary = Color.White,
    background = LightBackground,
    onBackground = LightOnBackground,
    surface = LightSurface,
    onSurface = LightOnSurface,
    surfaceVariant = LightSurfaceVariant,
    onSurfaceVariant = Color(0xFF4A3B43),
    outline = Color(0xFFD3C5C2),
    outlineVariant = Color(0xFFEBE0DD)
  )

@Composable
fun WeekendTheme(
  themeMode: ThemeMode,
  content: @Composable () -> Unit,
) {
  val darkTheme = when (themeMode) {
    ThemeMode.SYSTEM -> isSystemInDarkTheme()
    ThemeMode.LIGHT -> false
    ThemeMode.DARK -> true
  }
  WeekendTheme(darkTheme = darkTheme, content = content)
}

@Composable
fun WeekendTheme(
  darkTheme: Boolean = isSystemInDarkTheme(),
  content: @Composable () -> Unit,
) {
  val colorScheme = if (darkTheme) DarkColorScheme else LightColorScheme

  MaterialTheme(colorScheme = colorScheme, typography = Typography, content = content)
}

