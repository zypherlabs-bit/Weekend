# Changelog

All notable changes to **Weekend** are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and
the project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
Releases are published as GitHub Releases with a versioned APK and a SHA-256
checksum.

## [2.3.1] - 2026-09-26

### Fixed - Edit Profile photo upload + save

- Photo upload maps Storage + `profile_photos` rejections to actionable
  messages instead of opaque "server error"; `moderation_status` is no longer
  sent from the client (server decides per 006/011).
- Edit Profile save maps `profiles` UPDATE rejections (RLS/stale session,
  relationship-intent CHECK, social-media bio trigger 014, missing-column
  42703) to actionable messages; raw SDK prefixes stripped before display.
- New migration `018_edit_profile_live_fixes.sql`: grants on
  `profile_photos`/`interests`/`user_interests`, RLS for shared `interests`
  list (links stay owner-only), idempotent re-assert of the private
  `profile-photos` bucket + owner-folder storage policies. Apply with
  `supabase db push` before testing the release APK.
- New migration `019_weekend_availability_shape_fix.sql`: 016 guarded
  `user_settings.weekend_availability` with JSONB *containment*
  (`<@ '{"Saturday":true,"Sunday":true}'`), but containment compares values —
  so the `false` the client writes for an unselected day raised
  `23514 ... violates check constraint "user_settings_weekend_availability_shape"`
  and the save failed. 019 replaces it with a key-set + value-type check
  (`weekend_availability_is_valid`) that still refuses unknown keys and
  non-boolean values.
- Migrations **015–019 are now applied to the LIVE Supabase project**
  (001–013 were already applied out-of-band and have been baselined in
  `supabase_migrations.schema_migrations`, which did not exist before).

## [Unreleased]

### Fixed - LIVE-only auth

- Auth repository auth calls now throw a clear "not connected to a backend"
  error instead of silently returning. The silent return made signup look
  accepted ("check your email") on builds with no backend while nothing was
  ever sent.
- Release CI refuses to build when `SUPABASE_URL` / `SUPABASE_ANON_KEY`
  secrets are missing or still placeholders, so a release APK can never be an
  offline demo build.

### Added - passkey plumbing

- Credential-manager based passkey save/get in `auth_repository.dart`
  (`credential_manager` 5.1.0).

### Fixed - Android release build

- `credential_manager_android` 4.1.0 configures `kotlin { ... }` in its own
  `build.gradle` without ever applying the Kotlin plugin — it assumes AGP 9's
  built-in Kotlin (its buildscript pins AGP 9.0.1). This project resolves the
  Android Gradle plugin to 8.11.1, so `assembleRelease` died with
  "Could not find method kotlin() ... on project ':credential_manager_android'".
  The root `android/build.gradle.kts` now puts `kotlin-gradle-plugin:2.2.20`
  (matching `settings.gradle.kts`) on the buildscript classpath inherited by
  subprojects and applies `org.jetbrains.kotlin.android` to that module the
  moment its Android library plugin is attached — before its script reaches the
  `kotlin { ... }` block.

## [2.3.0] - 2026-09-22

### Fixed - signup, email confirmation and navigation

- **Duplicate screens after signup are gone.** `appRouterProvider` no longer
  `ref.watch`es the auth state. Watching rebuilt the provider on every
  auth-state emission and constructed a brand-new `GoRouter`, which restarts at
  `/` and replayed splash -> entry screens instead of continuing forward. The
  state now reaches the router through `refreshListenable`, so exactly one
  router instance survives the whole flow.
- **"Check your email" is no longer a dead end.** When Supabase returns a user
  with no session (`mailer_autoconfirm = false`) the app records an explicit
  `awaitingEmailConfirmation` state instead of a red error banner and continues
  to a dedicated confirmation step.
- **New `/confirm-email` step** with a genuine Supabase re-send
  (`auth.resend(type: signup)`), an "I've confirmed - Sign in" action and a
  "Use a different email" escape. No local verification flag is ever set.
- **Real session synchronisation.** `AuthNotifier` subscribes to
  `onAuthStateChange`, so a session created outside the widget tree (the
  confirmation link opened in a browser) is adopted without restarting the app.
  The listener never satisfies a pending 2FA step-up.
- **Stale errors no longer persist.** `WeekendAuthState.copyWith` gained
  `clearError` / `clearPendingEmail`. Previously `error: null` was silently
  ignored, so an old error banner followed the user between forms.
- **Readable auth error mapping** for unconfirmed emails, invalid credentials,
  existing accounts, send rate limits and rejected addresses instead of raw SDK
  text.
- **Signing in with an unconfirmed account** (`email_not_confirmed`) now routes
  to the confirmation step instead of reporting a credential failure.
- **"Get Started" opens the sign-up form** (`/auth?mode=signup`) instead of
  showing the sign-in form first.
- `emailRedirectTo` plumbing (`--dart-define=AUTH_EMAIL_REDIRECT_URL=...`) for
  signup and password-reset emails. When unset, Supabase keeps using the
  project's Site URL, which is GoTrue's documented behaviour.

### Added - tests

- `test/app_router_stability_test.dart` fails if an auth-state change ever
  reconstructs the router again.
- `test/widget_test.dart` now asserts onboarding -> sign-up directly, including
  that the sign-in form is not shown first.

### Verified against the live project

- Live project ref `ocypgybqfushqfzisnvs` is the only backend in the release
  path (confirmed by scanning the packaged Dart snapshot).
- Signup, confirmation-email delivery and password sign-in were exercised end
  to end against the live project.

### Requires Supabase dashboard action (operator)

The live project still uses Supabase defaults for two mailer settings. Neither
can be changed from the repository, and both must be changed before
confirmation can complete on a phone:

1. **Authentication -> URL Configuration -> Site URL** is still
   `http://localhost:3000`, so the emailed confirmation link redirects to
   localhost. Set it (and add the app URL to *Redirect URLs*) to the real
   production origin.
2. **Project Settings -> Auth -> SMTP** still uses Supabase's built-in shared
   mailer (`noreply@mail.app.supabase.io`), which is rate limited and frequently
   spam-filtered. Configure a custom SMTP provider.


## [2.2.0] — 2026-09-20

### Added — release and distribution

- **Production release APK built with real Supabase credentials** (v2.2.0+4).
- **Verified installation on Android emulator** — app launches successfully,
  connects to Supabase backend.
- **GitHub release published** with versioned APK and SHA-256 checksum.
- **README updated** to point to v2.2.0 download links.

### Fixed — build and verification

- All 94 automated tests pass.
- Flutter analyze reports no issues.
- APK signed and verified: package `com.weekend.app`, version 2.2.0 (code 4),
  minSdk 24, targetSdk 36.
- SHA-256: `592BFAD4772B37E5C01144C11854D84AD14774734DDF31F65FC80701B602F4FB`

### Updated — documentation

- README download section points to v2.2.0 APK.
- SHA-256 checksum file included in release assets.

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

[Unreleased]: https://github.com/zypherlabs-bit/Weekend/compare/v2.3.0...HEAD
[2.3.0]: https://github.com/zypherlabs-bit/Weekend/compare/v2.2.0...v2.3.0
[2.2.0]: https://github.com/zypherlabs-bit/Weekend/compare/v2.1.0...v2.2.0
[2.0.1]: https://github.com/zypherlabs-bit/Weekend/compare/v2.0.0...v2.0.1
[2.0.0]: https://github.com/zypherlabs-bit/Weekend/compare/v1.0.0...v2.0.0
[1.0.0]: https://github.com/zypherlabs-bit/Weekend/releases/tag/v1.0.0
