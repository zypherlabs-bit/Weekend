# Location & Discovery

Weekend is a **location-based dating app**, and this document explains how
discovery works and how the location handling stays privacy-preserving.

Key files: `lib/services/location_service.dart`,
`lib/features/discovery/`, `lib/widgets/location_radius_filter.dart`,
`supabase/migrations/003_database_functions.sql`,
`supabase/migrations/006_security_fixes.sql`,
`supabase/migrations/007_advertisements_and_location.sql`.

---

## 1. Discovery modes

The Explore screen renders one chip per `DiscoveryMode` value
(`lib/models/models.dart`):

| Mode | Chip label |
|------|-----------|
| `forYou` | For You |
| `nearby` | Nearby |
| `aroundMe` | Around Me |
| `city` | City |
| `global` | Global |
| `travelMode` | Travel Mode |
| `crossedPaths` | Crossed Paths |
| `interests` | Interests |
| `weekendPlans` | Plans |

**How the modes behave today.** Selecting a chip re-runs discovery, and the mode
is passed to the `get_nearby_profiles` RPC as `p_discovery_mode`. The current
implementation of the RPC applies the caller's distance/age/gender filters,
excludes anyone they have already liked, passed, matched, blocked or reported,
and ranks results by distance, compatibility and recent activity. Per-mode result
sets (for example a dedicated "Plans" query) are **not** implemented yet — a chip
currently changes the presentation context rather than the SQL filter. Improving
this is tracked on the [roadmap](../README.md#roadmap).

---

## 2. The discovery query

```text
client → rpc('get_nearby_profiles', {
            p_user_id, p_limit, p_offset,
            p_max_distance_km, p_preferred_genders,
            p_age_min, p_age_max, p_discovery_mode })

returns table (
  profile_id, display_name, age, gender, bio, city,
  distance_km, is_photo_verified, trust_score,
  primary_photo_url, interests, relationship_intent,
  last_active_at, compatibility_score
)
```

Properties worth noting:

- The function is `security definer` and begins with
  `perform public.assert_self(p_user_id)`, so a caller can only compute discovery
  results **for themselves**. This blocks enumerating the database with arbitrary
  filters.
- Page size is clamped (`least(p_limit, 50)`).
- **Distance is computed inside PostgreSQL** with PostGIS (`ST_Distance` on
  `geography`), rounded to one decimal, and **no latitude/longitude is returned**.
- `compatibility_score` is a simple, transparent blend of distance, verification
  and activity — the SQL itself notes it is *not* a scientific compatibility
  prediction, and the UI presents it as a suggestion signal.
- Blocks, passes, existing likes and existing matches are excluded in SQL, so a
  client cannot re-surface someone the user has already acted on.

---

## 3. Radius

- `LocationService.supportedRadii` = **0.5, 1, 5, 10, 25, 50, 100 km**.
- The radius is selectable from the discovery filter sheet and the location
  settings screen (`LocationRadiusFilter`).
- Changing the radius updates `LocationPreferences.discoveryRadiusKm` in app
  state and is persisted to `user_settings.max_distance_km`.

---

## 4. Location acquisition

`LocationService` wraps `geolocator` (imported as `geolocator` to avoid clashing
with the project's own `LocationPreferences` model):

- `hasPermission`, `requestPermission`, `isLocationServiceEnabled`
- `getCurrentPosition()` — medium accuracy, 10 s timeout, returns `null` on any
  failure instead of throwing
- `getLastKnownPosition()` — cheap fallback
- `getCityName(lat, lon)` / `getPlacemark(...)` — reverse geocoding via
  `geocoding` to derive the city/locality shown on a profile
- `formatDistance` / `formatDistanceWithAway` — presentation helpers ("800 m",
  "4.2 km", "4.2 km away")
- `isWithinRadius`, `distanceInKm` — client-side helpers for filters and previews

Permission UX: `location_permission_screen.dart` explains what location is used
for before the Android permission dialog appears, and the app keeps working
(albeit without nearby results) if permission is denied.

---

## 5. Privacy-safe geohashing

Instead of storing a movement history, Weekend converts a position into a
**geohash bucket**:

```dart
Geohash.encode(lat, lon, precision: 7)   // ≈150 m × 150 m cell
```

- `Geohash` implements standard base-32 geohash encode/decode plus
  `encodeFromPosition`; correctness is covered by `test/geohash_test.dart`.
- `LocationService.getGeohashBucket(position)` uses precision 7.
- `LocationService.toApproximateCoordinates(lat, lon, gridSizeKm)` rounds a
  position to a configurable grid (default 1 km) for additional noise.
- Buckets are stored in `user_location_buckets` (`geohash_7`, `city`, `locality`,
  `country`), and co-location is aggregated in `crossed_paths`
  (`geohash_bucket`, `first_crossed_at`, `last_crossed_at`, `cross_count`) and
  `crossed_paths_log`. `compute_crossed_paths(...)` performs the aggregation
  server-side.

In practice this means crossed paths compare **cells**, not tracks. Two people in
the same ≈150 m cell can be recorded as having crossed paths without either
person's exact position being revealed to the other. Because a bucket is an area,
proximity inside a cell cannot be distinguished below that resolution — a
deliberate trade-off in favour of privacy.

---

## 6. Location controls

| Setting | Where | Notes |
|---------|-------|-------|
| Location discovery on/off | Location settings | Master switch for using location |
| Nearby discovery on/off | Location settings | Whether nearby people appear in discovery |
| Show distance on/off | Location settings | Whether others see an approximate distance |
| Crossed paths on/off | Location settings | Opt out of crossed-path detection |
| Travel mode | Location settings | Discover in another city; carries `travel_mode_city` / `travel_mode_lat` / `travel_mode_lon` in the preference model |
| Discovery radius | Discovery filter sheet / location settings | Persisted to `user_settings.max_distance_km` |

`LocationPreferences` (`lib/models/models.dart`) serialises these fields with
`toJson` / `fromJson`, using database-style keys
(`location_discovery_enabled`, `crossed_paths_enabled`,
`show_distance_enabled`, `nearby_discovery_enabled`, `travel_mode_enabled`,
`discovery_radius_km`, `travel_mode_city`, `travel_mode_lat`,
`travel_mode_lon`).

**Current persistence status:** the discovery radius is persisted to
`user_settings.max_distance_km`. The remaining toggles currently live in app
session state, and the corresponding database columns are reserved for the planned
persistence work. The privacy-controls dialog in the safety centre is
informational today — its switches are not yet bound to storage. See
[privacy.md](privacy.md) and the project
[roadmap](../README.md#roadmap).

---

## 7. Testing location logic

```bash
flutter test test/geohash_test.dart
flutter test test/location_service_test.dart
```

`geohash_test.dart` checks encode/decode round-tripping and known reference
values; `location_service_test.dart` covers distance/formatting helpers and radius
math. When you change location logic, extend those suites rather than adding
ad-hoc assertions elsewhere.

---

## 8. Related documents

- [architecture.md](architecture.md) — where location code sits in the layers
- [privacy.md](privacy.md) — the full data-handling picture
- [supabase.md](supabase.md) — applying the migrations that create these tables
- [qr-invitations.md](qr-invitations.md) — the invitation and referral flow