# Discover Implementation

## Overview
Discover shows match-based recommendations using the authenticated user's saved matching
criteria. It is backed by the live Supabase RPC `get_nearby_profiles` with mode `nearby`
by default and honours the user's selected discovery mode.

## Query behaviour
- Backend RPC: `public.get_nearby_profiles(p_user_id, p_limit, p_offset, p_max_distance_km, p_preferred_genders, p_age_min, p_age_max, p_discovery_mode)`.
- Filters applied server-side: adult floor (>=18), active/non-deleted/non-suspended accounts,
  dating profile activated, preferred genders, age range, distance, blocks in both directions,
  passes, likes, matches, reports.
- Current user excluded (`p.id <> p_user_id`).
- Pagination via limit/offset.
- Photo URLs resolved in one batch via `PhotoUrlService`.

## State
- `WeekendNotifier.loadDiscoveryProfiles()` reads `state.selectedMode`, converts via
  `_modeToString`, and calls the repository.
- Mode change triggers reload.
- Results stored in `WeekendState.deckProfiles`.

## Empty / error states
- Empty list renders genuine empty state; no fabricated profiles.
- Errors logged; deck cleared.

## Live verification
- Backend reachable (probe account). RPC returns real profiles. See test_results.md.
