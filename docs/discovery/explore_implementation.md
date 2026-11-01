# Explore Implementation

## Modes
Explore exposes five independent modes:
1. For You (`for_you`) - ranked by compatibility signals.
2. Nearby (`nearby`) - location-based via PostGIS.
3. City (`city`) - profiles in the user's city.
4. Global (`global`) - no geographic restriction.
5. Travel Mode (`travel`) - uses stored travel destination; never overwrites real GPS.

## UI
- `ExploreScreen` mode chips limited to the five spec modes.
- Switching a chip calls `selectDiscoveryMode` then `loadDiscoveryProfiles`.
- Independent pagination/refresh via repository.

## State separation
- Shared `deckProfiles` populated per mode; mode tracked in `selectedMode`.
- Switching modes reloads from backend; stale results replaced.

## Live verification
- Each mode maps to a distinct `p_discovery_mode` value handled by `get_nearby_profiles`.
