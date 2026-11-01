# Backend Queries

## Discovery RPC
`public.get_nearby_profiles(...)` is the single server-side discovery function. It branches
on `p_discovery_mode`:
- `nearby`: within `p_max_distance_km` of viewer.
- `city`: same city as viewer (case-insensitive trim).
- `global`: no geographic filter.
- `travel`: uses `user_settings.travel_*` destination (7-day validity), falls back to home.
- `crossed_paths`: within radius.
- `for_you` (default): within radius, ranked by compatibility.

## Supporting tables
- `profiles` (id, display_name, gender, city, latitude, longitude, date_of_birth, ...)
- `user_settings` (travel_mode_enabled, travel_city, travel_lat, travel_lon, travel_started_at, max_distance_km, preferred genders via location prefs)
- `blocks`, `passes`, `likes`, `matches`, `reports`
- `profile_photos` (moderation_status, storage_path)

## Indexes
- GiST index on profile location (PostGIS).
- Standard indexes on user_id foreign keys.

## Security
- `assert_self(p_user_id)` enforces caller identity.
- SECURITY DEFINER with search_path pinned.
- Revoked from anon/public; granted to authenticated.
