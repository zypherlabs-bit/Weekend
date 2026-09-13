# Weekend Development Guide

## Stack

- **Flutter** 3.41.9 / **Dart** 3.11.5
- **Supabase** 2.x (PostgreSQL + PostGIS + Edge Functions)
- **Riverpod** 2.6.1 for state management
- **GoRouter** 14.8.1 for navigation

## Development Commands

```bash
flutter analyze          # Lint and static analysis
flutter test             # Run all tests
flutter test --coverage  # Run tests with coverage
flutter run -d chrome    # Run in browser for debugging
flutter build apk --release  # Build production APK
```

## Architecture

- `lib/features/` — Screen-level feature modules (auth, chat, discovery, profile, plans, settings)
- `lib/services/` — Business logic services (LocationService, AdService)
- `lib/repositories/` — Data layer (DiscoveryRepository, AdRepository)
- `lib/models/` — Data models (UserProfile, Advertisement, AdConfig, CrossedPath, LocationPreferences)
- `lib/widgets/` — Reusable UI components
- `lib/providers/` — Riverpod state notifiers
- `lib/theme/` — App theming
- `supabase/migrations/` — Database migrations
- `supabase/functions/` — Supabase Edge Functions (TypeScript)

## Testing

Tests are in `test/`. Run with `flutter test`.

- `geohash_test.dart` — Geohash encode/decode correctness
- `location_service_test.dart` — Location utility methods
- `ad_service_timer_test.dart` — Ad timer logic and event recording
- `ad_card_test.dart` — AdCard widget rendering and interactions
- `discovery_repository_test.dart` — Repository data mapping logic

## Database

Migrations live in `supabase/migrations/`. The RLS test script is at `supabase/test/rls_test.sql`.

## Edge Functions

Deploy from `supabase/functions/`. The `serve-ad` function handles ad fetching and event recording.

## Important Coding Conventions

- Import geolocator as `geolocator` alias to avoid conflicts with custom LocationPreferences
- AdService timer: 120s default production interval, configurable via AdConfig
- Never embed secrets in Dart code — use `String.fromEnvironment` for Supabase URL/anon key
- All ad events are validated server-side; client records are advisory only
