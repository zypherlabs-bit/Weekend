package com.example.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable

private val DarkColorScheme =
  darkColorScheme(
    primary = SunsetCoral,
    onPrimary = CoralOnPrimaryLight,
    primaryContainer = MidnightVioletCard,
    onPrimaryContainer = GoldenPeachLight,
    secondary = GoldenPeach,
    onSecondary = MidnightViolet,
    secondaryContainer = MidnightVioletSurface,
    onSecondaryContainer = GoldenPeachLight,
    tertiary = GoldenPeachLight,
    background = DarkBackground,
    onBackground = DarkOnBackground,
    surface = DarkSurface,
    onSurface = DarkOnSurface,
    surfaceVariant = DarkSurfaceVariant,
    onSurfaceVariant = DarkOnSurface
  )

private val LightColorScheme =
  lightColorScheme(
    primary = CoralPrimaryLight,
    onPrimary = CoralOnPrimaryLight,
    primaryContainer = CoralPrimaryContainerLight,
    onPrimaryContainer = CoralOnPrimaryContainerLight,
    secondary = VioletSecondaryLight,
    onSecondary = VioletOnSecondaryLight,
    secondaryContainer = VioletSecondaryContainerLight,
    tertiary = PeachTertiaryLight,
    background = LightBackground,
    onBackground = LightOnBackground,
    surface = LightSurface,
    onSurface = LightOnSurface,
    surfaceVariant = LightSurfaceVariant,
    onSurfaceVariant = LightOnSurface
  )

@Composable
fun WeekendTheme(
  darkTheme: Boolean = isSystemInDarkTheme(),
  content: @Composable () -> Unit,
) {
  val colorScheme = if (darkTheme) DarkColorScheme else LightColorScheme

  MaterialTheme(colorScheme = colorScheme, typography = Typography, content = content)
}
