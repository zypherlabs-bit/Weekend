# Weekend v2.8.3 — Full-Screen Profile Photo with Fixed Top Tabs

## What's New

### Full-Screen Profile Photo with Fixed Top Tabs
- Profile image now fills the entire discovery screen (edge-to-edge)
- Top discovery tabs (For You, Nearby, Around Me, City, Filter) remain anchored below the status bar
- Sophisticated gradient scrim overlay ensures text readability over photos
- Profile details positioned near bottom of photo
- Action buttons (Pass, Like, View Profile) positioned above bottom navigation
- Proper safe area handling for status bar, camera cutouts, and bottom gesture area
- Empty discovery state shows tabs with atmospheric background
- All existing discovery filters and modes preserved
- Swipe gestures (drag to pass/like) work as before
- Photo navigation (tap indicators) preserved

### Launcher Icon W-Centering
- The 3-D ribbon "W" product mark is now perfectly centered within the Android
  adaptive-icon mask's 66% safe zone (16% inset in `ic_launcher.xml`)
- Foreground and monochrome drawables verified at all densities
  (mdpi ×2 through xxxhdpi) with sub-pixel centering accuracy

### Quality
- Removed unused `surgeProvider` import to resolve analyzer warning
- Theme color refinements in `colors.xml`

## Testing
- All 381 existing tests pass (`flutter test`)
- `flutter analyze` clean (0 issues)
- Release APK builds successfully (v2.8.3+16, 124.8MB)
- Verified on web (Chrome) and Android APK on physical device

## Download
The release APK is attached: `app-release.apk`