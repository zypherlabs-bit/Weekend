# Test Results

## Flutter
- `flutter analyze`: No issues found.
- `flutter test`: All tests passed (386+).

## Python
- `pytest tests/python`: 344 passed, 1 skipped.

## Live backend
- Supabase project reachable (probe account sign-in succeeded).
- Discovery RPC `get_nearby_profiles` present and callable.
- Mode values handled: nearby, city, global, travel, for_you, crossed_paths.

## Known limitations
- Explore screen historically displayed static sections; mode chips now limited to five spec modes.
- Live profile volume may be limited; empty states shown when no eligible profiles.
- Travel destination persistence requires user_settings travel columns (migration 031).
