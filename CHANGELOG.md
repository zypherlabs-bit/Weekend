# Changelog

## [2.0.0] - 2026-09-14

### Major Changes

- **Flutter migration** — Migrated from Kotlin/Compose to Flutter/Dart for cross-platform capability
- **In-feed advertisements** — Added privacy-preserving, server-validated ad system with 120-second active discovery interval
- **Ad management** — Ad cards with ADVERTISEMENT/Sponsored labels, report/hide functionality, server-side event validation via `serve-ad` Edge Function
- **Crossed Paths** — Geohash-based privacy-safe crossed-path detection
- **User location buckets** — Privacy-preserving location storage for discovery features
- **Location radius filter** — Distance-based discovery filtering in the discovery feed
- **Ad config** — Configurable ad intervals and display settings

### Features

- **Authentication** — Email/password
- **Profile creation and editing** — Full profile management with photos, prompts, interests
- **Profile display** — Detailed profile view with compatibility explanation
- **Discovery** — Swipe-based discovery with nearby, crossed-paths, and global modes
- **Location-aware discovery** — PostGIS-powered proximity search, privacy-safe location handling
- **Distance/radius filtering** — Configurable discovery radius
- **Nearby profiles** — GPS-based discovery with approximate distance
- **Crossed Paths** — Historical location overlap detection using geohash buckets
- **Global discovery** — Browse profiles worldwide or by city
- **Likes and passes** — Unlimited likes and passes
- **Mutual matches** — Match when both users express interest
- **Unlimited messaging** — No message limits
- **Realtime chat** — Instant messaging with matches via Supabase Realtime
- **Notifications** — Relevant notifications for matches and messages
- **Blocking and reporting** — Full user safety controls
- **Unmatching** — Remove matches
- **Verification** — Photo verification with multi-signal detection
- **Privacy controls** — Location discovery toggles, profile visibility settings
- **Weekend Plans** — Create and join local plans and activities
- **In-feed advertisements** — Clearly labeled ads after 120 seconds of active discovery
- **Image optimization** — Automatic resizing, compression, and thumbnail generation
- **Referral system** — Invite friends with referral codes and tracking
- **Row Level Security** — RLS enabled on all database tables
- **Storage policies** — Privacy-safe photo storage with per-user folder policies
- **Realtime** — Chat and notification streams via Supabase Realtime
- **Edge Functions** — AI features, account deletion, ad serving

### Security

- JWT authentication on all Supabase Edge Functions
- Row Level Security (RLS) enabled on all database tables
- Server-side authorization for all security-critical operations
- Location privacy — exact GPS coordinates never exposed
- Rate limiting and abuse detection
- Complete server-side account deletion
- Ad event validation server-side via `serve-ad` Edge Function
- Ad destination URL validation (HTTPS only)
- Privacy-preserving geohash-based location handling

### Technical

- **Flutter** 3.41.9 / **Dart** 3.11.5
- **Supabase** 2.x (Auth, PostgreSQL + PostGIS, Storage, Realtime, Edge Functions)
- **Riverpod** 2.6.1 for state management
- **GoRouter** 14.8.1 for navigation
- **geolocator** for location services
- **cached_network_image** for image loading

### Build

- Release APK: ~54 MB
- Min SDK: 24 (Android 7.0)
- Target SDK: 35
