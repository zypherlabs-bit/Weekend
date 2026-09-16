<div align="center">

<img src="docs/assets/weekend-logo.jpg" width="132" alt="Weekend app logo">

# Weekend — Free Open Source Dating &amp; Social Discovery App

**Make Every Weekend Brighter.**

Free • Open Source • Android • Flutter • Supabase

[![Android](https://img.shields.io/badge/platform-Android-3DDC84?style=for-the-badge&logo=android&logoColor=white)](https://developer.android.com/)
[![Flutter](https://img.shields.io/badge/Flutter-3.41.9-02569B?style=for-the-badge&logo=flutter&logoColor=white)](https://flutter.dev/)
[![Dart](https://img.shields.io/badge/Dart-3.11.5-0175C2?style=for-the-badge&logo=dart&logoColor=white)](https://dart.dev/)
[![Supabase](https://img.shields.io/badge/Supabase-PostgreSQL%20%2B%20PostGIS-3FCF8E?style=for-the-badge&logo=supabase&logoColor=white)](https://supabase.com/)
[![CI](https://github.com/zypherlabs-bit/Weekend/actions/workflows/ci.yml/badge.svg?branch=master)](https://github.com/zypherlabs-bit/Weekend/actions/workflows/ci.yml)
[![Latest release](https://img.shields.io/github/v/release/zypherlabs-bit/Weekend?style=for-the-badge&color=blue)](https://github.com/zypherlabs-bit/Weekend/releases/latest)
[![License: MIT](https://img.shields.io/github/license/zypherlabs-bit/Weekend?style=for-the-badge&color=yellow)](LICENSE)

</div>

---

**Weekend** is a free, open-source dating and social discovery app for Android. It is
built with **Flutter (Dart)** and a **Kotlin/Android** host layer on top of a
**Supabase** backend (PostgreSQL + PostGIS, Auth, Storage, Realtime and Edge
Functions). Weekend helps people find others nearby, match on shared interests,
chat in real time, and turn conversations into real weekend plans — while keeping
location and personal data deliberately private.

- 📱 **Android app, free to download and use** — no subscription, no paywall on
  core features
- 🔓 **Open source (MIT)** — inspect it, self-host the backend, or contribute
- 📍 **Location-aware, privacy-first discovery** — nearby, crossed-paths and
  global modes without ever exposing exact GPS coordinates
- 💬 **Real-time messaging** with mutual matches
- 📅 **Weekend Plans**, QR invitations, biometric app lock and a full safety centre

---

## Table of contents

- [Download Weekend](#download-weekend)
- [What is Weekend?](#what-is-weekend)
- [Why Weekend?](#why-weekend)
- [Features](#features)
  - [Location-based discovery](#location-based-discovery)
  - [Matchmaking](#matchmaking)
  - [Real-time messaging](#real-time-messaging)
  - [Weekend Plans](#weekend-plans)
  - [QR invitations](#qr-invitations)
  - [Biometric app lock](#biometric-app-lock)
  - [Safety, reporting and blocking](#safety-reporting-and-blocking)
  - [Profile verification and photo moderation](#profile-verification-and-photo-moderation)
  - [Advertisement-supported free experience](#advertisement-supported-free-experience)
- [Screenshots](#screenshots)
- [Technology stack](#technology-stack)
- [Architecture](#architecture)
- [Supabase backend](#supabase-backend)
- [Developer setup](#developer-setup)
- [Configuration](#configuration)
- [Building the Android APK](#building-the-android-apk)
- [Testing](#testing)
- [Project structure](#project-structure)
- [Security](#security)
- [Privacy](#privacy)
- [Known limitations](#known-limitations)
- [Roadmap](#roadmap)
- [FAQ](#faq)
- [Contributing](#contributing)
- [Documentation](#documentation)
- [License](#license)

---

## Download Weekend

Download the latest Weekend Android APK from **GitHub Releases**.

<p align="center">
  <a href="https://github.com/zypherlabs-bit/Weekend/releases/latest">
    <img src="https://img.shields.io/badge/Download_Latest_APK-3DDC84?style=for-the-badge&logo=android&logoColor=white" alt="Download the latest Weekend Android APK">
  </a>
</p>

| Link | Purpose |
|------|---------|
| [**Latest release page**](https://github.com/zypherlabs-bit/Weekend/releases/latest) | Always points at the newest stable Weekend release |
| [`Weekend-v2.0.1-release.apk`](https://github.com/zypherlabs-bit/Weekend/releases/latest/download/Weekend-v2.0.1-release.apk) | Current production APK (~74 MB) |
| [`Weekend-v2.0.1-release.apk.sha256`](https://github.com/zypherlabs-bit/Weekend/releases/latest/download/Weekend-v2.0.1-release.apk.sha256) | SHA-256 checksum for the current APK |
| [All releases](https://github.com/zypherlabs-bit/Weekend/releases) | Full release history and notes |

**Requirements:** Android 7.0 (API 24) or newer · `arm64-v8a` / `armeabi-v7a` / `x86_64`

### Install the APK

1. Download `Weekend-v2.0.1-release.apk` from the link above.
2. Verify the download (recommended):

   ```bash
   # Windows (PowerShell)
   Get-FileHash Weekend-v2.0.1-release.apk -Algorithm SHA256

   # macOS / Linux
   sha256sum Weekend-v2.0.1-release.apk
   ```

   Compare the output with the contents of
   `Weekend-v2.0.1-release.apk.sha256` in the same release.

3. Open the APK on your device. Because Weekend is distributed directly through
   GitHub (not through an app store), Android will show its standard security
   prompt asking you to allow installing apps from this source — confirm it to
   continue. Weekend does not attempt to bypass or disable this protection.
4. Launch **Weekend** and create an account or sign in.

Step-by-step instructions for every platform are in
[docs/installation.md](docs/installation.md).

---

## What is Weekend?

Weekend is a **modern dating and social discovery application** for Android that
focuses on the weekend: meeting people near you, discovering shared interests,
and making actual plans instead of endless swiping.

It is built as a genuinely **open-source project**. The complete Android
application, the database schema, the row-level-security policies and the Edge
Functions are all in this repository under the MIT licence, so anyone can read
how the app works, run it against their own Supabase project, or contribute
improvements.

**Who it is for:**

- People who want an **alternative to closed, ad-heavy or paywalled dating
  apps** and who value being able to see the code and the data model
- Android users looking for **nearby, location-based discovery** rather than a
  purely global swipe feed
- Developers who want a realistic **Flutter + Supabase + PostGIS reference
  application** they can learn from or self-host
- Anyone who wants to meet people through **shared activities and real plans**

**Why it exists:** most free dating apps are either closed source, riddled with
paywalls on basic interactions, or careless with location data. Weekend was
written to show that a free, privacy-conscious, open-source dating app with
real-time chat, matchmaking and location discovery is achievable with a modern
Flutter and Supabase stack — and to make that implementation available for
anyone to inspect.

---

## Why Weekend?

| | |
|---|---|
| **Free and open source** | MIT-licensed; no paid likes, paid matches or subscription required for the core dating and social experience. |
| **Privacy-focused location** | Exact GPS coordinates are never shared with other users. Distance is computed server-side; other people only ever see a city and an approximate distance. |
| **Nearby-first discovery** | PostGIS-backed proximity search ranks profiles by distance, compatibility, activity and shared interests. |
| **Real conversations** | Unlimited likes and matches for everyone, with real-time messaging between mutual matches. |
| **Plans, not just chats** | Weekend Plans let people create and join local activities. |
| **Safety built in** | Blocking, reporting, unmatching, photo verification, moderation and a biometric app lock. |
| **Server-side security** | Row Level Security on every table; the client is treated as fully inspectable. |
| **Hackable and self-hostable** | Point the app at your own Supabase project in minutes, or read the schema and build something new. |

---

## Features

### Location-based discovery

Weekend is a **location-based dating app** at its core: discovery is anchored to
where you are, while the location data itself stays private.

- **Nearby discovery** — `DiscoveryMode.nearby` returns profiles around your
  current position using the `get_nearby_profiles` RPC and PostGIS distance
  computation performed on the server.
- **Discovery radius** — choose a radius of 0.5, 1, 5, 10, 25, 50 or 100 km.
  The radius is applied server-side.
- **Discovery modes** — the Explore screen exposes chips for For You, Nearby,
  Around Me, City, Global, Travel Mode, Crossed Paths, Interests and Plans. The
  mode is passed to the RPC as a hint; today the query itself applies the
  distance/age/gender filters, excludes people you have already liked, passed,
  matched, blocked or reported, and ranks by distance, compatibility and activity.
- **Crossed Paths** — Weekend records privacy-safe location *buckets* (geohash
  precision 7, ≈150 m) instead of raw coordinates. When you and another person
  occupy the same bucket inside a time window, `compute_crossed_paths` can
  surface that as a crossed path.
- **Explore sections** — the Explore tab groups Nearby, Weekend Nearby,
  Crossed Paths and Explore Your City previews.
- **Travel mode** — a toggle for discovering people in another city, stored with
  your location preferences.
- **City and approximate distance** — other users see a locality and an
  approximate distance such as "5 km away", never a coordinate pair.
- **Granular location controls** — independent switches for location discovery,
  nearby discovery, distance display and crossed paths, plus a
  permission-explaining screen before Android's location prompt is shown.
- **Geohash utilities** — the bundled `Geohash` class (encode/decode) is covered
  by unit tests in `test/geohash_test.dart`.

Implementation: `lib/services/location_service.dart`,
`lib/features/discovery/`, `lib/widgets/location_radius_filter.dart`,
`supabase/migrations/003_database_functions.sql`,
`supabase/migrations/008_advertisements_rls_and_functions.sql`.
Details: [docs/location-discovery.md](docs/location-discovery.md).

### Matchmaking

Weekend is an **open-source matchmaking app** with a deliberately simple, honest
matching model:

- **Likes and passes** — unlimited for every user; there is no paid-like or
  pay-to-match mechanic in the current release.
- **Mutual matches** — a database trigger (`check_mutual_like`) creates a match
  when two people like each other, and creates the conversation record at the
  same time.
- **Shared interests** — profiles carry interests, prompts, languages,
  favourite places and weekend availability; common interests are highlighted
  when you view a profile.
- **Compatibility explanation** — profile cards include a short, human-readable
  explanation of why a profile is being suggested (distance, shared interests,
  activity).
- **Genuine profiles** — trust score and photo-verification state are surfaced
  on profile cards.
- **Match celebration** — a dedicated match dialog, and matches are the only
  way to start a conversation.

Implementation: `lib/providers/weekend_provider.dart`,
`lib/repositories/match_repository.dart`,
`lib/widgets/match_celebration_dialog.dart`,
`supabase/migrations/003_database_functions.sql`.

### Real-time messaging

Weekend includes a **real-time dating chat** between mutual matches:

- **Realtime delivery** — the app subscribes to Supabase Realtime streams for the
  conversation, so new messages appear without a manual refresh
  (`MessageRepository.subscribeToMessages`).
- **Conversations per match** — a conversation and its membership rows are
  created with the match; messages are stored in PostgreSQL and protected by RLS
  so only participants can read them.
- **Message rules enforced in the database** — a trigger validates message
  inserts (conversation membership, blocked users), so the API cannot be abused
  to post into someone else's conversation.
- **Read state** — unread tracking per conversation member.
- **Message translation (server-side)** — the `translate-message` Edge Function
  and the `messages.translated_text` / `is_translated` columns let a message be
  translated without the provider key ever reaching the client. The translated
  text is rendered underneath the original in the chat UI.
- **Safety by construction** — conversations only exist for mutual matches, and
  blocked users are excluded from messaging.

> Voice messages and message reactions are **not** part of the current release —
> see [Known limitations](#known-limitations) and the [Roadmap](#roadmap).

Implementation: `lib/features/chat/chat_screen.dart`,
`lib/repositories/message_repository.dart`,
`supabase/functions/translate-message/`.

### Weekend Plans

Dating apps usually end at the chat. Weekend continues into the weekend itself:

- **Create a plan** — title, category (coffee, dinner, and more), venue, time and
  description.
- **Join or leave a plan** — one tap, with participant counts.
- **Discover plans** — browse local plans from the Weekend Plans screen.
- **Activity-based connections** — meet people around something you actually
  want to do.

Implementation: `lib/features/plans/plans_screen.dart`,
`lib/repositories/plan_repository.dart`,
`supabase/migrations/001_initial_schema.sql` (`plans`,
`plan_participants`).

### QR invitations

Weekend has its own **app-to-app invitation system** built around QR codes, so
people can be onboarded without a public marketing website:

```text
Create a Weekend invitation (in app)
        ↓
Generate a signed QR code
        ↓
Another person scans it with the Weekend in-app scanner
        ↓
Weekend validates the invitation (format → signature → expiry → server lookup)
        ↓
Sign up or sign in
        ↓
Referral attribution
```

- Invitations are **versioned** and **expire after 30 days**.
- The payload is **signed** (HMAC-SHA256) and validated locally, then checked
  against the `referrals` table server-side.
- The scanner uses the device camera through `mobile_scanner`; camera permission
  is declared in the Android manifest and requested at the moment of use.
- Self-referrals are detected and rejected.
- Invitations are created and scanned from inside the app rather than from a web
  landing page.

Implementation: `lib/services/qr_invitation_service.dart`,
`lib/features/qr/qr_invite_screen.dart`, `lib/features/qr/qr_scanner_screen.dart`.
Details: [docs/qr-invitations.md](docs/qr-invitations.md).

### Biometric app lock

Weekend can lock itself behind Android's secure biometric framework when the app
is backgrounded:

- **Fingerprint** and **face / device biometrics** wherever Android supports them
  (via `local_auth`).
- **Device-credential fallback** — the prompt allows the device PIN / pattern /
  password (`biometricOnly: false`), so the lock still works where biometrics are
  not enrolled.
- **Automatic re-lock** — the lock is applied on `paused` / `inactive` / `hidden`
  / `detached` lifecycle events and re-authentication is requested on resume.
- **Handled lockout states** — `LockedOut` and `PermanentlyLockedOut` surface as
  explicit results instead of silent failures.

Weekend never receives or stores biometric templates: matching happens entirely
inside Android's biometric stack. Weekend only stores the *preference* (lock
on/off) and the enrolled biometric type, in platform secure storage.

Implementation: `lib/services/biometric_auth_service.dart`,
`lib/services/secure_storage_service.dart`,
`lib/features/auth/biometric_lock_screen.dart`, `lib/main.dart`.

### Safety, reporting and blocking

- **Safety centre** — one place for blocked users, reporting, sharing your plans
  with a trusted contact, photo verification, account security and privacy
  controls, plus practical dating-safety guidance.
- **Report a user** — structured reasons (inappropriate photos, harassment or
  bullying, fake profile, inappropriate messages, and more); reports are written
  to the `reports` table.
- **Block a user** — blocked users are excluded from discovery and messaging;
  blocks live in the `blocks` table and are enforced in the discovery RPC and the
  message trigger.
- **Unmatch** — remove a match and its conversation.
- **Suspicious-content handling** — uploaded photos carry a moderation state, and
  message/photo rules are enforced by database triggers plus the
  photo-verification function.
- **Account deletion (server-side)** — the `account-deletion` Edge Function and
  the `delete_user_account` RPC delete profile data, related rows and the auth
  user on the server, so removal does not depend on client behaviour.

See [docs/security.md](docs/security.md) for enforcement details.

### Profile verification and photo moderation

- **Photo verification** — the `photo-verification` Edge Function performs
  multi-signal analysis (human face, AI/synthetic image, illustration,
  screenshot and similar signals) and writes the result server-side.
- **Moderation state** — `profile_photos.moderation_status` gates whether other
  users can read a photo; `protect_photo_moderation` stops clients from setting
  that column themselves.
- **Verification badge** — verification state is shown on profile cards
  (`is_photo_verified`, kept in sync by the `sync_photo_verified` trigger).
- **Trust score** — a per-profile signal rendered alongside verification state.

### Advertisement-supported free experience

The current release is free and is supported by a deliberately
privacy-preserving in-feed ad system:

- Ads appear **in the discovery feed only**, after at least 120 seconds of
  *active* discovery (`AdService` timer; it pauses when the app is backgrounded
  or you leave the screen).
- Every ad is clearly labelled and can be **reported or hidden**; hidden ads are
  not shown to that user again.
- Ad selection is contextual, not behavioural — no personal data is shared with
  advertisers.
- Impression, click, report and hide events are validated **server-side** by the
  `serve-ad` Edge Function and the `record_ad_event` RPC.
- Destination URLs must be `https://` before any interaction is allowed.
- **No paywall:** likes, matches, messaging and plans are not gated behind ads or
  a subscription.

Implementation: `lib/services/ad_service.dart`,
`lib/repositories/ad_repository.dart`, `lib/widgets/ad_card.dart`,
`supabase/functions/serve-ad/`, `test/ad_service_timer_test.dart`.

---

## Screenshots

<p align="center">
  <img src="docs/screenshots/welcome.jpg" width="200" alt="Weekend welcome and sign-in screen">
  <img src="docs/screenshots/discovery.jpg" width="200" alt="Weekend Discover feed with location-based profile discovery">
  <img src="docs/screenshots/nearby.jpg" width="200" alt="Weekend Nearby view with approximate distance and discovery radius">
</p>

<p align="center"><em>Welcome &amp; sign-in &nbsp;•&nbsp; Discover — location-based profile discovery &nbsp;•&nbsp; Nearby — approximate distance and radius</em></p>

<p align="center">
  <img src="docs/screenshots/match.jpg" width="200" alt="Weekend mutual match screen">
  <img src="docs/screenshots/messaging.jpg" width="200" alt="Weekend real-time chat screen">
  <img src="docs/screenshots/plans.jpg" width="200" alt="Weekend Plans screen for creating and joining local plans">
</p>

<p align="center"><em>Match — mutual match celebration &nbsp;•&nbsp; Chat — real-time messaging &nbsp;•&nbsp; Weekend Plans — create and join local plans</em></p>

<p align="center">
  <img src="docs/screenshots/profile.jpg" width="200" alt="Weekend profile with interests, prompts and compatibility">
  <img src="docs/screenshots/photo-verification.jpg" width="200" alt="Weekend photo verification screen">
  <img src="docs/screenshots/settings.jpg" width="200" alt="Weekend privacy and safety settings">
</p>

<p align="center"><em>Profile — interests, prompts and compatibility &nbsp;•&nbsp; Photo verification &nbsp;•&nbsp; Privacy &amp; safety settings</em></p>

<p align="center">
  <img src="docs/screenshots/referral.jpg" width="200" alt="Weekend QR invitation and referral screen">
</p>

<p align="center"><em>QR invitation — invite someone to Weekend and attribute the referral</em></p>

All screenshots show the current Weekend UI and contain no personal data or
credentials. To refresh them, run the app and replace the files in
`docs/screenshots/`.

---

## Technology stack

Every entry below is actually used by this project.

| Layer | Technology |
|-------|------------|
| Application language | **Dart 3.11.5** |
| UI framework | **Flutter 3.41.9** (Material 3) |
| Android host layer | **Kotlin** (`FlutterActivity`), Gradle **Kotlin DSL**, JDK 17 |
| Platform | **Android 7.0+ (API 24)** · `targetSdk` 36 · `applicationId` `com.weekend.app` |
| State management | **Riverpod 2.6.1** (`flutter_riverpod`) |
| Navigation | **GoRouter 14.8.1** |
| Backend platform | **Supabase** (Auth, PostgreSQL, PostGIS, Storage, Realtime, Edge Functions) |
| Database | **PostgreSQL + PostGIS** (geospatial columns and server-side distance queries) |
| Location | `geolocator` 13.x, `geocoding` 3.x, `permission_handler` |
| Realtime | Supabase Realtime Postgres change streams |
| Storage | Supabase Storage (private `profile-photos` bucket) |
| Notifications | `flutter_local_notifications` |
| Secure storage | `flutter_secure_storage` (Android Keystore) |
| Biometrics | `local_auth` 3.x |
| QR | `qr_flutter` (generate) + `mobile_scanner` (scan) |
| Media | `image_picker`, `image_editor`, `image`, `cached_network_image`, `photo_view` |
| Animations | `lottie`, `shimmer`, `flutter_staggered_animations` |
| Edge Functions runtime | **Deno / TypeScript** (Supabase Edge Functions) |
| CI/CD | **GitHub Actions** (`ci.yml`, `release.yml`) |
| Tests | `flutter_test`, `mocktail` |

---

## Architecture

```text
                    Weekend Android App
                            │
                            ▼
                Flutter UI (Material 3, Riverpod, GoRouter)
                            │
                            ▼
                    Dart application layer
        ┌───────────────────┼────────────────────┐
        ▼                   ▼                    ▼
   Repositories         Services            Providers
 (discovery, match,   (location, ads,    (auth state, app
  message, plan,       QR invitations,    state, discovery
  profile, ad …)       biometrics,        mode, filters,
                       notifications,     matches, plans)
                       image optimizer)
                            │
                            ▼
              Kotlin / Android platform APIs
     (MainActivity host, permissions, camera, Keystore,
      BiometricPrompt via local_auth, notifications)
                            │
                            ▼
                         Supabase
        ┌───────────┬─────┴──────┬────────────┐
        ▼           ▼            ▼            ▼
       Auth      Database      Storage      Realtime
    (sessions) (PostgreSQL     (private   (messages,
                + PostGIS,    profile-     notifications)
                 RLS on       photos)
                 all tables)
                    │
                    ▼
              Edge Functions (Deno)
   photo-verification · account-deletion · icebreaker
   · date-ideas · translate-message · serve-ad
```

**Layering rules used in this codebase**

- `lib/features/` — screen-level modules (auth, chat, discovery, home, matching,
  onboarding, plans, profile, qr, safety, settings).
- `lib/repositories/` — the only layer that talks to Supabase tables and RPCs.
- `lib/services/` — platform and cross-cutting logic (location, ads, QR
  invitations, biometrics, secure storage, notifications, image optimisation).
- `lib/providers/` — Riverpod notifiers holding UI state.
- `lib/models/` — plain data models.
- `lib/widgets/` — reusable UI components.

Nothing security-critical relies on the client: the app is treated as fully
inspectable, and every authorization decision is enforced by Row Level Security
or a database function. More detail:
[docs/architecture.md](docs/architecture.md).

---

## Supabase backend

Weekend runs entirely on Supabase — there is no second backend.

| Capability | Supabase service |
|------------|------------------|
| Email/password auth, session handling | **Supabase Auth** |
| Profiles, likes, matches, messages, plans, ads — RLS on every table | **PostgreSQL + PostGIS** |
| Private profile photos with per-user folder policies | **Storage** |
| Chat and notification streams | **Realtime** |
| Photo verification, account deletion, icebreakers, date ideas, translation, ad serving | **Edge Functions** |

**Migrations** (`supabase/migrations/`, applied in order):

| Migration | Contents |
|-----------|----------|
| `001_initial_schema.sql` | Core tables, constraints, PostGIS, indexes |
| `002_rls_policies.sql` | Row Level Security on every table |
| `003_database_functions.sql` | Triggers (profile creation, mutual like, deletion) and RPCs (`get_nearby_profiles`, `get_matches_for_user`, `get_referral_stats`, `delete_user_account`) |
| `004_storage_policies.sql` | Private `profile-photos` bucket and storage policies |
| `005_security_hardening.sql` | Protected columns, verification sync, interest helpers |
| `006_security_fixes.sql` | Least-privilege rewrites of the RPCs, `assert_self`, message/photo protection |
| `007_advertisements_and_location.sql` | Ad campaigns, crossed paths, user location buckets |
| `008_advertisements_rls_and_functions.sql` | Ad RLS plus `get_ad_for_user`, `record_ad_event`, `compute_crossed_paths` |

Full setup, local development and production checklist:
[docs/supabase.md](docs/supabase.md).

---

## Developer setup

### Prerequisites

- [Flutter](https://docs.flutter.dev/get-started/install) **3.41.9** (stable
  channel, which bundles **Dart 3.11.5**)
- **JDK 17** for the Android build
- Android SDK + an emulator or physical device (Android 7.0+)
- A [Supabase](https://supabase.com/) project (free tier is enough)
- [Git](https://git-scm.com/)

### Clone and install

```bash
git clone https://github.com/zypherlabs-bit/Weekend.git
cd Weekend
flutter pub get
```

### Run without a backend (offline demo mode)

Weekend starts in **offline demo mode** when no Supabase credentials are
supplied: the whole UI is navigable against on-device sample data, so you can
review the interface without provisioning anything.

```bash
flutter run -d chrome      # or: flutter run  (device/emulator)
```

### Run against your own Supabase project

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://your-project-ref.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=your-public-anon-key
```

Then apply the migrations and deploy the Edge Functions — see
[docs/supabase.md](docs/supabase.md) and
[docs/getting-started.md](docs/getting-started.md).

---

## Configuration

| Value | Where it comes from | How it reaches the app |
|-------|---------------------|------------------------|
| `SUPABASE_URL` | Supabase Dashboard → Project Settings → API | `--dart-define` (read by `lib/config/supabase_config.dart` via `String.fromEnvironment`) |
| `SUPABASE_ANON_KEY` | Same page — the **anon/public** key | `--dart-define` |
| `GEMINI_API_KEY` | Your AI provider account | **Supabase Edge Function secret only** — never in the app |
| Release signing keys | Your keystore | Untracked `android/key.properties` (see `android/key.properties.example`) |

`SUPABASE_URL` and `SUPABASE_ANON_KEY` also appear in **`.env.example`** as a
documented template. `.env` files are git-ignored and are **not** read at
runtime — the app reads compile-time `--dart-define` values only.

> **Never** commit or ship the `service_role` key, the database password, or any
> provider API key. The anon key is designed to be public *because* Row Level
> Security protects every table; a service-role key bypasses RLS entirely.

---

## Building the Android APK

```bash
# Debug build for a connected device
flutter build apk --debug

# Release APK (with your Supabase project baked in)
flutter build apk --release \
  --dart-define=SUPABASE_URL=https://your-project-ref.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=your-public-anon-key

# Output: build/app/outputs/flutter-apk/app-release.apk
```

Release signing is picked up from an untracked `android/key.properties`
(`storeFile`, `storePassword`, `keyAlias`, `keyKeyPassword`). Without it, the
build reuses — or generates — the standard Android **debug keystore** so CI and
fresh clones stay friction-free. Such builds print an explicit warning: an APK
signed this way is a **development build and must not be distributed as a
production release**. Production releases must provide a real `key.properties`
with your own keystore.

**Versioning** lives in `pubspec.yaml` (`version: 2.0.1+2`). Pushing a `v*` tag
triggers `.github/workflows/release.yml`, which builds the APK, generates
`Weekend-v<version>-release.apk` plus a `.sha256` checksum, and publishes both
to a GitHub Release.

---

## Testing

```bash
flutter analyze                  # static analysis / lints
flutter test                     # unit + widget tests
flutter test --coverage          # with coverage
flutter test test/geohash_test.dart   # a single suite
```

| Test file | Covers |
|-----------|--------|
| `test/geohash_test.dart` | Geohash encode/decode correctness and round-tripping |
| `test/location_service_test.dart` | Location utilities, radius math, distance formatting |
| `test/ad_service_timer_test.dart` | Ad timer behaviour, lifecycle pausing, event recording |
| `test/ad_card_test.dart` | Ad card rendering, labels, report/hide interactions |
| `test/discovery_repository_test.dart` | Repository mapping of RPC rows into models |
| `test/widget_test.dart` | App-level widget smoke test |

CI (`.github/workflows/ci.yml`) runs `flutter pub get`, `flutter analyze`,
`flutter test` and a release APK build on every push and pull request. Details:
[docs/testing.md](docs/testing.md).

---

## Project structure

```text
Weekend/
├── android/                  # Android host (Kotlin MainActivity, Gradle KTS, manifest)
│   ├── app/src/main/kotlin/com/weekend/app/MainActivity.kt
│   └── app/src/main/AndroidManifest.xml
├── assets/
│   ├── icons/                # Weekend logo (app icon sources)
│   └── images/               # In-app artwork (placeholder avatar)
├── docs/
│   ├── assets/               # Logo and social-preview artwork
│   ├── screenshots/          # Current UI screenshots
│   └── *.md                  # Documentation (see below)
├── integration_test/         # Integration test entrypoints
├── lib/
│   ├── config/               # Supabase configuration (String.fromEnvironment)
│   ├── features/             # Screen-level modules (auth, chat, discovery, home,
│   │                         #   matching, onboarding, plans, profile, qr,
│   │                         #   safety, settings)
│   ├── models/               # Data models (profile, match, message, ad, …)
│   ├── providers/            # Riverpod state notifiers
│   ├── repositories/         # Supabase data access (tables, RPCs, functions)
│   ├── routing/              # GoRouter configuration
│   ├── services/             # Location, ads, QR, biometrics, storage, media
│   ├── theme/                # App theming
│   ├── utils/                # Shared helpers
│   ├── widgets/              # Reusable UI components
│   └── main.dart             # Entry point
├── supabase/
│   ├── functions/            # Edge Functions (Deno/TypeScript)
│   ├── migrations/           # Numbered SQL migrations (schema + RLS)
│   └── test/                 # RLS verification SQL script
├── test/                     # Unit and widget tests
├── tool/                     # Codegen/diagnostic scripts (icons, placeholder art)
├── .github/
│   ├── ISSUE_TEMPLATE/
│   ├── workflows/            # ci.yml, release.yml
│   └── pull_request_template.md
├── .env.example              # Documented configuration template
├── pubspec.yaml              # App metadata, version and dependencies
└── README.md
```

---

## Security

Weekend assumes the client is fully inspectable — anyone can read the source and
the APK — so **all authorization is enforced server-side**.

- **Row Level Security on every table.** Policies are defined in
  `supabase/migrations/002_rls_policies.sql` and hardened in `006_security_fixes.sql`.
- **Least-privilege RPCs.** Discovery, matches, referral stats and ad serving run
  through `security definer` functions that derive the caller from
  `auth.uid()` and call `assert_self(...)` instead of trusting a user id passed
  from the app.
- **Protected columns.** `protect_profile_columns` and
  `protect_photo_moderation` stop clients from writing verification,
  moderation, or trust fields directly.
- **Private storage.** The `profile-photos` bucket is private; users write only
  into their own folder, and other users can read only photos whose moderation
  status is `approved`.
- **No secrets in the client.** Only the anon key is embedded, and it is supplied
  at build time via `--dart-define`. Provider keys (`GEMINI_API_KEY`) live as
  Edge Function secrets.
- **Authenticated Edge Functions.** Functions authenticate the caller's JWT
  before doing work.
- **Transport security.** HTTPS only; the Android manifest sets
  `usesCleartextTraffic="false"` and ships a network security config.
- **Backups disabled at the OS level.** `allowBackup="false"` prevents Android
  cloud backups from copying app data; sensitive preferences use
  `flutter_secure_storage` (Android Keystore).
- **Release integrity.** Every release ships a SHA-256 checksum next to the APK.

Found a vulnerability? Please follow [SECURITY.md](SECURITY.md) — report privately
rather than in a public issue. Details:
[docs/security.md](docs/security.md).

---

## Privacy

Privacy is a product decision in Weekend, not an afterthought.

- **No public exact GPS.** Weekend stores privacy-safe location buckets (geohash
  precision 7, ≈150 m) and approximate coordinates; the raw position is not
  exposed to other users and is not returned by public queries.
- **Server-side distance only.** `get_nearby_profiles` computes distance inside
  PostgreSQL/PostGIS and returns a distance value — not coordinates.
- **What other people see:** a city/locality and an approximate distance such as
  "5 km away".
- **User-controlled visibility.** Independent switches for location discovery,
  nearby discovery, distance display and crossed paths; profile visibility
  controls in the safety centre.
- **Data minimisation.** Ads are contextual and are not used to build a
  behavioural profile; no personal data is shared with advertisers.
- **Protected media.** Photos live in a private bucket and are readable by others
  only once approved.
- **Account data.** Server-side deletion functions remove profile data and the
  auth user.

Full description of the data the app handles and the controls available:
[docs/privacy.md](docs/privacy.md).

> Weekend does not claim compliance with any specific privacy regulation. These
> documents describe actual data handling in the current source code, and
> operators self-hosting Weekend are responsible for their own legal compliance.

---

## Known limitations

Weekend is an actively evolving open-source project. These are the gaps in the
current release, documented honestly so nothing here overstates what the code
does today:

| Area | Current state |
|------|---------------|
| **In-app account deletion** | The backend deletion path exists (`account-deletion` Edge Function and the `delete_user_account` RPC), and the safety/settings UI presents the confirmation dialog. The confirmation button is not yet wired to invoke that function, so deletion currently requires a maintainer or a direct server call. |
| **Referral completion write** | QR invitations can be generated, scanned and validated (format, signature, expiry and a server-side lookup against `referrals`). The credit-on-match step exists in the `check_mutual_like` trigger, but creating the pending referral row from a scanned invite expects a `record_referral` RPC that is not yet defined in `supabase/migrations`. |
| **Message translation trigger** | The `translate-message` Edge Function and the `translated_text` / `is_translated` columns and rendering are in place, but the chat UI has no "translate" action yet. |
| **Icebreakers & date ideas** | `icebreaker` and `date-ideas` Edge Functions are implemented server-side; they are not yet surfaced in the UI. |
| **Voice intros / voice messages** | `UserProfile.voiceIntroUrl` and a voice-intro indicator on discovery cards exist; recording and upload are not implemented. |
| **Notifications** | Android notification channels, local notifications and a `notifications` table with Realtime streaming exist. There is no remote push (FCM) integration yet, so notifications are seen while the app is running. |
| **Email confirmation** | Behaviour depends on your own Supabase Auth settings (email confirmation on/off). |
| **iOS** | An `ios/` host project is present, but only Android is built, released and tested. |
| **Sign-in methods** | Email + password only. Google/other OAuth providers are not implemented. |

What Weekend does **not** do: it does not collect exact GPS coordinates for other
users, does not sell or share personal data with advertisers, and does not gate
likes, matches or messaging behind a payment.

---

## Roadmap

### Shipped in 2.0.x

- [x] Flutter (Dart) app for Android with a Kotlin host layer
- [x] Supabase backend: Auth, PostgreSQL + PostGIS, Storage, Realtime, Edge Functions
- [x] Email/password authentication with session restore and password reset
- [x] Profile creation, editing, photos, prompts and interests
- [x] Nearby-first discovery with PostGIS (`get_nearby_profiles`)
- [x] Discovery modes (For You, Nearby, Around Me, City, Global, Travel Mode, Crossed Paths, Interests, Plans) with a shared proximity query
- [x] Discovery radius filter and travel mode
- [x] Privacy-safe geohash location buckets and crossed paths
- [x] Unlimited likes, passes and mutual matches
- [x] Real-time messaging between matches
- [x] Weekend Plans (create, discover, join, leave)
- [x] Photo verification and photo moderation
- [x] Safety centre: report, block, unmatch, privacy controls, safety guidance
- [x] QR invitations with signed, expiring payloads and an in-app scanner
- [x] Biometric app lock with device-credential fallback
- [x] Privacy-preserving in-feed ads with server-validated events
- [x] Image optimisation (resize, compress, thumbnails)
- [x] Row Level Security hardened on every table
- [x] CI (analyze, tests, release APK build) and tag-driven releases with checksums

### Planned

- [ ] Mode-specific queries (per-mode result sets beyond today's shared proximity query)
- [ ] Wire in-app account deletion to the `account-deletion` Edge Function
- [ ] Add the `record_referral` database function and complete referral attribution
- [ ] Translate-on-tap in chat using the existing `translate-message` function
- [ ] Surface icebreakers and date ideas in the UI
- [ ] Voice intros and voice messages
- [ ] Remote push notifications (FCM)
- [ ] Video profiles
- [ ] Additional sign-in providers and languages
- [ ] iOS release
- [ ] Web build

Roadmap items are intentions, not commitments. Anything not merged into `master`
should be treated as unshipped.

---

## FAQ

### What is Weekend?

Weekend is a free, open-source dating and social discovery app for Android. It
helps you find people nearby, match on shared interests, chat in real time and
make actual weekend plans. It is built with Flutter/Dart and a Kotlin Android
host on top of a Supabase backend.

### Is Weekend free?

Yes. The current release is completely free: there are no subscriptions, no paid
likes, no paid matches and no paywall on messaging or plans. Development is
supported by privacy-preserving in-feed advertisements rather than by charging
users. Future versions may add optional paid features, and any such change will
be documented in the [CHANGELOG](CHANGELOG.md).

### Is Weekend open source?

Yes — Weekend is released under the [MIT licence](LICENSE), and the whole project
(app, database migrations, RLS policies and Edge Functions) is in this
repository. You can read it, fork it, self-host the backend, or contribute.

### Is Weekend available for Android?

Yes. Weekend ships as an Android APK (Android 7.0 / API 24 and newer) published
in [GitHub Releases](https://github.com/zypherlabs-bit/Weekend/releases/latest).
An `ios/` project folder exists in the repository, but there is no iOS release
yet.

### What technology does Weekend use?

Flutter 3.41.9 and Dart 3.11.5 for the app, Kotlin for the Android host layer
with Gradle Kotlin DSL, Riverpod for state management, GoRouter for navigation,
and Supabase for the backend — PostgreSQL with PostGIS, Auth, Storage, Realtime
and Deno/TypeScript Edge Functions. See the
[technology stack](#technology-stack).

### Does Weekend support location-based discovery?

Yes. Weekend is a location-based dating app: it offers Nearby discovery, a
discovery radius from 0.5 km to 100 km, city detection, approximate distance,
crossed-path detection and a set of discovery mode chips (For You, Nearby, Around
Me, City, Global, Travel Mode, Crossed Paths, Interests, Plans). Distance is
computed server-side, and exact GPS coordinates are never shown to other users.

### Does Weekend support real-time chat?

Yes. Mutual matches get a conversation backed by Supabase Realtime, so messages
arrive live. Message inserts are validated by a database trigger, and the
`translate-message` Edge Function plus translation columns exist for
server-side message translation.

### Does Weekend support QR invitations?

Yes. Weekend can generate a signed QR invitation (valid for 30 days) that another
person scans inside the app; Weekend then validates it and links the sign-up to
the referral. See [QR invitations](#qr-invitations).

### Does Weekend support fingerprint or face/device biometrics?

Yes. Weekend can lock the app behind Android biometrics (fingerprint, and face or
other device biometrics where supported), with the device PIN/pattern/password as
a fallback. Weekend does not store biometric templates.

### Does Weekend use Supabase?

Yes — Supabase is the entire backend. Postgres with PostGIS stores the data with
Row Level Security on every table, Supabase Auth handles sessions, Storage holds
private profile photos, Realtime streams chat and notifications, and Edge
Functions handle photo verification, account deletion, AI helpers, translation
and ad serving.

### How can I download Weekend?

Download the latest APK from the
[Weekend releases page](https://github.com/zypherlabs-bit/Weekend/releases/latest),
verify its SHA-256 checksum, then open it on your Android device and confirm
Android's "install from this source" prompt. Full instructions:
[docs/installation.md](docs/installation.md).

### Does Weekend work without a backend?

Yes for evaluation: with no Supabase credentials the app runs in **offline demo
mode** against bundled sample data, which is useful for reviewing the UI.
Real accounts, matching, messaging and plans require a Supabase project (either
the maintainers' or your own).

### How can I contribute to Weekend?

Read [CONTRIBUTING.md](CONTRIBUTING.md) and [docs/contributing.md](docs/contributing.md),
then open an issue or a pull request. Bug reports, documentation fixes,
translations and code contributions are all welcome.

### Is Weekend a replacement for mainstream dating apps?

Weekend is a genuine, working dating and social discovery application, but it is
an independent open-source project with a smaller user base than commercial
platforms. Its advantages are that it is free, open source, inspectable and
privacy-oriented. It makes no claim to be the biggest or "best" dating app —
it aims to be a trustworthy one.

### Where do I report a security issue?

Privately, per [SECURITY.md](SECURITY.md). Please do not open a public issue for
a vulnerability.

---

## Contributing

Contributions are welcome — code, documentation, tests, design and translations
alike.

1. Read [CONTRIBUTING.md](CONTRIBUTING.md) and the
   [Code of Conduct](CODE_OF_CONDUCT.md).
2. Fork the repository and create a branch from `master`.
3. Make your change, run `flutter analyze` and `flutter test`, and keep the
   change focused.
4. Open a pull request using the repository template.

Never include secrets, real `.env` files, keystores or personal data in a commit.
Security-sensitive reports go through [SECURITY.md](SECURITY.md) instead of the
public issue tracker.

---

## Documentation

| Document | What it covers |
|----------|----------------|
| [docs/getting-started.md](docs/getting-started.md) | First-run walkthrough, from clone to a working build |
| [docs/installation.md](docs/installation.md) | Installing the APK and verifying it, for end users |
| [docs/architecture.md](docs/architecture.md) | Layers, data flow, folders and design decisions |
| [docs/supabase.md](docs/supabase.md) | Supabase project setup, migrations, RLS, storage, realtime, Edge Functions |
| [docs/location-discovery.md](docs/location-discovery.md) | Nearby discovery, radius, travel mode and privacy-safe geohashing |
| [docs/qr-invitations.md](docs/qr-invitations.md) | The QR invitation and referral flow |
| [docs/security.md](docs/security.md) | Threat model, server-side enforcement, secrets and release integrity |
| [docs/privacy.md](docs/privacy.md) | What data Weekend handles and the controls available to users |
| [docs/testing.md](docs/testing.md) | Test suites, how to run them and what to add |
| [docs/contributing.md](docs/contributing.md) | Contributor workflow in depth |
| [SECURITY.md](SECURITY.md) | Vulnerability disclosure policy |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Contribution guide |
| [CHANGELOG.md](CHANGELOG.md) | Release history |

---

## License

Weekend is open source under the **MIT License**. See [LICENSE](LICENSE).

You are free to use, modify and redistribute the code, including commercially,
provided the copyright notice and permission notice are retained.

"Weekend" and the Weekend logo are the project's own branding; the MIT licence
covers the source code, not the marks.

---

## About this repository

- **Project:** Weekend — Make Every Weekend Brighter.
- **Repository:** <https://github.com/zypherlabs-bit/Weekend>
- **Releases:** <https://github.com/zypherlabs-bit/Weekend/releases>
- **Issues:** <https://github.com/zypherlabs-bit/Weekend/issues>
- **License:** MIT
- **Platforms:** Android (Flutter + Kotlin host)
- **Backend:** Supabase (PostgreSQL + PostGIS, Auth, Storage, Realtime, Edge Functions)

Download counts shown anywhere for this project refer to **GitHub release asset
downloads**, unless explicitly stated otherwise. They are not a count of unique
users, installs or active users.

---

<div align="center">

**Weekend** — Make Every Weekend Brighter.

Free • Open Source • Android • Flutter • Supabase

Built by the Weekend maintainers and contributors.

</div>