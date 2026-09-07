package com.example.ui.theme

/**
 * Supported Theme Configuration Modes for the Weekend application.
 */
enum class ThemeMode(
    val title: String,
    val description: String
) {
    SYSTEM(
        title = "System Default",
        description = "Matches your device's system theme setting"
    ),
    LIGHT(
        title = "Light Mode",
        description = "Warm Sand and crisp vibrant daylight aesthetic"
    ),
    DARK(
        title = "Dark Mode",
        description = "Signature Midnight Violet & Sunset Coral evening aesthetic"
    )
}
