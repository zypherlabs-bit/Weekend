# Changelog

## [1.0.0] - 2026-09-06

### Initial Release

Weekend is a free, open-source dating and social discovery app focused on helping people nearby make real weekend plans and connect through shared interests.

### Features

- **Nearby-first discovery** — PostGIS-powered location-based profile discovery
- **Unlimited likes, matches, and messaging** — Completely free, no subscriptions
- **Real-human photo verification** — Multi-signal AI verification
- **Weekend Plans** — Create and join local plans and activities
- **Smart icebreakers** — AI-generated conversation starters
- **Date ideas** — Personalized suggestions based on shared interests
- **Message translation** — Break language barriers
- **Referral system** — Invite friends safely
- **Safety tools** — Block, report, and account deletion

### Security

- JWT authentication on all Supabase Edge Functions
- Row Level Security (RLS) enabled on all database tables
- Server-side authorization for all security-critical operations
- Location privacy — exact GPS coordinates never exposed
- Rate limiting and abuse detection
- Complete server-side account deletion
- R8 code shrinking and obfuscation for release builds

### Technical

- Native Android with Kotlin and Jetpack Compose
- Supabase backend (Auth, PostgreSQL, Storage, Realtime, Edge Functions)
- PostGIS for location queries
- Coil for image loading
- Ktor for networking
- MVVM architecture with repository pattern

### Build

- Debug APK: ~26 MB
- Release APK: ~1.3 MB (with R8 minification)
- Min SDK: 24 (Android 7.0)
- Target SDK: 35
