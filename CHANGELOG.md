# Changelog

All notable changes to **Weekend** are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and
the project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
Releases are published as GitHub Releases with a versioned APK and a SHA-256
checksum.

## [2.1.0] — 2026-09-16

### Fixed — production data integrity

- **Removed every source of fabricated users.** The offline sample deck,
  sample matches, sample chats, sample plans and sample crossed paths
  (`DemoData`) are deleted. Builds without a backend now show genuine empty
  states instead of fictional people, and unconfigured builds show an honest
  "backend not configured" message instead of a simulated login.
- **The placeholder signed-in user no longer carries fabricated identity.**
  The real profile is loaded from Supabase on app start.

### Fixed — matching and discovery

- Matches are now actually loaded (via the `get_matches_for_user` RPC) — the
  Matches tab previously stayed empty in production even after real matches.
- Passes are persisted to the `passes` table so passed profiles stay excluded.
- Like/match logic consolidated through `MatchRepository`: the client only
  records the like; the `check_mutual_like` database trigger transactionally
  creates the match, conversation and referral credit. Client-side writes to
  `matches` (which RLS forbids) are removed.
- Duplicate swipes are guarded against double-submission.

### Fixed — plans, safety, chat

- Weekend Plans create/join/leave now persist to `plans`/`plan_participants`
  with optimistic UI and authoritative re-sync; creator names resolve from
  real profiles.
- Block and Report now persist to `blocks`/`reports` (mapped to the schema's
  `report_type` enum) instead of touching only local state.
- Chat sends no longer double-write (local echo + repository); failures now
  surface a retry-able snackbar and restore the draft.

### Changed — release engineering

- Release builds embed `SUPABASE_URL`/`SUPABASE_ANON_KEY` from repository
  secrets as compile-time defines; the anon key is client-safe and protected
  by RLS. No service-role or privileged credential is ever embedded.
- `profiles` reads use explicit column lists compatible with the
  column-level grants introduced in migration 006.

### Unreleased (previous)


## [Unreleased]

### Security

- Added `009_account_deletion_service_role.sql`: the live `account-deletion`
  path could never succeed — 006 revoked the service role's `EXECUTE` on
  `delete_user_account`, and `assert_self` raises for service-role calls
  (`auth.uid()` is null without a user JWT). The service role now gets an
  explicit grant and bypasses `assert_self`; the Edge Function still
  authenticates the caller's JWT and rejects cross-account deletion, and
  direct authenticated callers remain guarded.
- Added the operator verification plan for TOTP 2FA and account deletion
  (`docs/verification-2fa-deletion.md`).

### Documentation

- Rewrote `README.md` as a complete project landing page: features, screenshots,
  architecture, technology stack, installation, security, privacy, FAQ and
  roadmap.
- Added developer and user documentation: `docs/getting-started.md`,
  `docs/installation.md`, `docs/architecture.md`, `docs/location-discovery.md`,
  `docs/qr-invitations.md`, `docs/security.md`, `docs/privacy.md`,
  `docs/testing.md`, `docs/contributing.md` and a `docs/README.md` index.
- Rewrote `SECURITY.md` (supported versions, private reporting, scope, secret
  handling, APK verification) and `CONTRIBUTING.md`.
- Documented current limitations honestly instead of implying unimplemented
  features ship today (see the *Known limitations* section of the README).

### Fixed

- Added the missing `assets/images/placeholder_avatar.png` artwork referenced by
  the Explore screen. The `assets/images/` directory is now tracked, which also
  fixes the `asset_directory_does_not_exist` warning that made `flutter analyze`
  fail in a fresh clone (and therefore in CI).
- Added `tool/generate_placeholder_assets.dart` so the placeholder artwork can be
  regenerated deterministically, following the existing `tool/` convention.
- Fixed release builds on machines without a debug keystore (including CI and
  fresh clones). When `android/key.properties` is absent, the build now reuses or
  generates the standard Android debug keystore at `$HOME/.android/debug.keystore`
  instead of failing in `:app:validateSigningRelease`. Such APKs are development
  builds signed with a generated key and are logged with an explicit warning;
  production releases still require a real `key.properties`.

## [2.0.1] - 2026-09-13

### Changed

- Updated production APK configuration and Weekend branding for distribution.
- Improved the referral-code experience in the invitation flow.
- Notification taps now route to the relevant destination.
- Weekend Plans UI improvements.

### Build & repository hygiene

- Removed committed build artifacts and Flutter build caches from version
  control; local release artifacts are now git-ignored.

## [2.0.0] - 2026-09-06

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

## [1.0.0] - 2026-09-06

### Added

- First public Weekend release and GitHub landing page.
- Android application distribution through GitHub Releases.

### Notes

- 1.0.0 belongs to the earlier Kotlin/Compose-era codebase. It is superseded by
  the 2.0.x Flutter line and is no longer maintained; see the supported-versions
  table in [SECURITY.md](SECURITY.md).

[Unreleased]: https://github.com/zypherlabs-bit/Weekend/compare/v2.0.1...HEAD
[2.0.1]: https://github.com/zypherlabs-bit/Weekend/compare/v2.0.0...v2.0.1
[2.0.0]: https://github.com/zypherlabs-bit/Weekend/compare/v1.0.0...v2.0.0
[1.0.0]: https://github.com/zypherlabs-bit/Weekend/releases/tag/v1.0.0
