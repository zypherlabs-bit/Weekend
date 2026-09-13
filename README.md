<div align="center">

<p align="center">
  <img src="docs/assets/weekend-logo.jpg" width="140" alt="Weekend Logo">
</p>

<h1 align="center">Weekend</h1>

<p align="center">
  <strong>Make Every Weekend Brighter.</strong>
</p>

<p align="center">
  A free, open-source dating and social discovery application for meeting real people nearby, finding shared interests, and making plans.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-Android-3DDC84?style=for-the-badge&logo=android&logoColor=white" alt="Android">
  <img src="https://img.shields.io/badge/Flutter-3.24.0-02569B?style=for-the-badge&logo=flutter&logoColor=white" alt="Flutter">
  <img src="https://img.shields.io/badge/Dart-3.5.0-0175C2?style=for-the-badge&logo=dart&logoColor=white" alt="Dart">
  <img src="https://img.shields.io/badge/Supabase-2.x-3FCF8E?style=for-the-badge&logo=supabase&logoColor=white" alt="Supabase">
  <img src="https://img.shields.io/badge/License-MIT-yellow?style=for-the-badge" alt="License">
  <img src="https://img.shields.io/badge/Version-2.0.0-blue?style=for-the-badge" alt="Version">
</p>

</div>

---

## Download Weekend

> **Latest stable Android APK — no subscription, no account required to try.**

### Android APK

**Latest stable version:** `Weekend-v2.0.0-release.apk` (~54 MB)

<p align="center">
  <a href="https://github.com/zypherlabs-bit/Weekend/releases/latest/download/Weekend-v2.0.0-release.apk">
    <img src="https://img.shields.io/badge/Download_Latest_APK-3DDC84?style=for-the-badge&logo=android&logoColor=white" alt="Download Latest APK">
  </a>
</p>

<p align="center">
  <a href="https://github.com/zypherlabs-bit/Weekend/releases/latest/download/Weekend-v2.0.0-release.apk">Download Latest APK</a>
  &bull;
  <a href="https://github.com/zypherlabs-bit/Weekend/releases">View All Releases</a>
  &bull;
  <a href="https://github.com/zypherlabs-bit/Weekend/issues">Report Issue</a>
</p>

| Asset | Description |
|-------|-------------|
| `Weekend-v2.0.0-release.apk` | Versioned production APK |
| `Weekend-v2.0.0-release.apk.sha256` | SHA-256 checksum for verification |

### Verify your download

```bash
# Windows (PowerShell)
Get-FileHash Weekend-v2.0.0-release.apk -Algorithm SHA256

# macOS / Linux
sha256sum Weekend-v2.0.0-release.apk
```

Compare the output against `Weekend-v2.0.0-release.apk.sha256` in the release.

### Install

1. Download `Weekend-v2.0.0-release.apk` from the button above.
2. Open the APK — enable **Install from unknown sources** if prompted.
3. Launch **Weekend** and sign in or explore in demo mode.

**Requirements:** Android 7.0+ (API 24) - ARM64 / ARMv7 / x86_64 - ~5 MB storage

---

## Screenshots

<p align="center">
  <img src="docs/screenshots/welcome.jpg" width="220" alt="Welcome Screen">
  <img src="docs/screenshots/discovery.jpg" width="220" alt="Discovery Screen">
  <img src="docs/screenshots/nearby.jpg" width="220" alt="Nearby Screen">
  <img src="docs/screenshots/match.jpg" width="220" alt="Match Screen">
</p>

<p align="center">
  <img src="docs/screenshots/profile.jpg" width="220" alt="Profile Screen">
  <img src="docs/screenshots/messaging.jpg" width="220" alt="Messaging Screen">
  <img src="docs/screenshots/plans.jpg" width="220" alt="Plans Screen">
  <img src="docs/screenshots/settings.jpg" width="220" alt="Settings Screen">
</p>

---

## In-Feed Advertisements

Weekend includes a privacy-preserving, server-validated in-feed advertisement system:

- **Ad placement** — Advertisements appear contextually in the discovery feed via `AdService` (lib/services/ad_service.dart)
- **Interval timer** — Ads show at a minimum 120-second interval during active discovery; the timer pauses when the app is backgrounded or the user leaves the discovery screen
- **Server-side validation** — All ad impressions, clicks, reports, and hides are recorded via the `serve-ad` Edge Function and the `record_ad_event` RPC, which validates events server-side
- **URL validation** — All ad destination URLs are validated (must be `https`) before any interaction is allowed
- **No tracking** — Ads are served based on discovery context only; no personal data is shared with advertisers
- **User controls** — Users can report or hide advertisements; hidden ads are not shown again to the same user
- **Monetization** — The ad system is the sole monetization mechanism; the app remains free and open source with no paywall

### Ad Data Flow

```
User browses Discover → AdService timer counts active seconds → 
At 120s threshold, ad becomes eligible → 
AdService.fetchAd() calls serve-ad Edge Function → 
get_ad_for_user RPC returns next eligible campaign → 
AdCard renders with ADVERTISEMENT badge → 
Impressions/clicks recorded via record_ad_event RPC
```

---

## Location Discovery & Privacy

Weekend's location discovery is designed with privacy as a core principle:

- **Privacy-safe geohash buckets** — Raw GPS coordinates are converted to geohash buckets at precision 7 (~150m resolution) using the bundled `Geohash` class. This allows crossed-paths detection without exposing exact location
- **Approximate coordinates** — The `LocationService.toApproximateCoordinates()` method rounds coordinates to a configurable grid, adding noise for additional privacy
- **Server-side distance computation** — The `get_nearby_profiles` RPC uses PostGIS to compute distances server-side. No raw coordinates are returned to the client
- **No exact location sharing** — Other users only see your city/locality and approximate distance ("5 km away")
- **Crossed Paths** — When you and another user are in the same geohash bucket within a time window, a crossed path is recorded. The `compute_crossed_paths` RPC handles this server-side
- **Location settings** — Users can toggle location discovery, crossed paths, distance display, nearby discovery, and travel mode (for discovering in another city)
- **Permission-first UX** — A dedicated `LocationPermissionScreen` explains the privacy benefits before requesting permission
- **App lifecycle awareness** — The `AdService` timer pauses on `AppLifecycleState.paused`/`inactive` and resumes on `resumed`

Weekend is a **free and open-source dating and social discovery application** built for people who want to meet others nearby, make real plans, and connect through shared interests.

### Nearby First

Discover people relevant to your location using PostGIS-powered proximity search. Weekend ranks profiles by distance, compatibility, activity, shared interests, and profile quality.

### Real Connections

Go beyond endless swiping. Weekend helps you find people who share your interests and are ready to make real-world plans.

### Make Plans

Turn conversations into real activities. Create and join local plans, date ideas, and weekend activities.

### Free

Core dating and social features are available **without subscriptions, premium memberships, paid likes, or paid matches**. Weekend is completely free to use.

### Open Source

The community can inspect, improve, and contribute to the project. Anyone can review the source code, report vulnerabilities, propose improvements, and contribute to making Weekend better.

### Privacy First

Exact location and sensitive information are protected. Raw GPS coordinates are never exposed to other users and never selected through public queries — only city/locality and computed distances are shared.

---

## Features

### Discovery
- **Swipe-based discovery** — Browse profiles with an intuitive swipe interface
- **Personalized discovery** — Profiles ranked by compatibility and shared interests
- **Nearby-first profiles** — GPS-based discovery powered by PostGIS
- **Crossed Paths** — Matches based on your historical location overlap using privacy-safe geohash buckets
- **Mingle-style location discovery** — See who's nearby, available this weekend, or in your city
- **Filters** — Narrow down discovery by age, distance, interests, and more
- **Interests** — Connect through shared hobbies and activities
- **In-feed advertisements** — Contextually placed ads with 120-second interval timer

### Matching
- **Unlimited likes** — Like as many profiles as you want, completely free
- **Unlimited matches** — No restrictions on matching
- **Mutual matching** — Connect when both people express interest
- **Shared-interest suggestions** — Discover common ground with matches

### Nearby
- **GPS-based discovery** — Find people near your current location
- **City/locality detection** — Automatically detect your area
- **Approximate distance** — See how far away someone is
- **Privacy-preserving location** — Exact coordinates never shared

### Messaging
- **Realtime chat** — Instant messaging with matches
- **Unread messages** — Track which conversations have new messages
- **Conversation controls** — Manage your conversations
- **Smart icebreakers** — AI-generated conversation starters

### Weekend Plans
- **Create plans** — Organize activities and events
- **Discover plans** — Find local plans and activities
- **Activity-based connections** — Meet people through shared activities
- **Date ideas** — Personalized suggestions based on shared interests

### Safety
- **Photo verification** — Multi-signal detection for real-human photos
- **Suspicious-profile detection** — Automated abuse detection
- **Report** — Report inappropriate behavior
- **Block** — Block unwanted users
- **Unmatch** — Remove matches
- **Account deletion** — Complete server-side data removal

### Image Optimization
- **Automatic resizing** — Images resized for optimal display
- **Image compression** — Reduced file sizes with high visual quality
- **Thumbnail generation** — Fast-loading previews
- **Reduced storage/network usage** — Efficient data usage

### Referrals
- **Referral code** — Share your unique code
- **Referral link** — Direct link for easy sharing
- **QR code** — Scan-to-refer functionality
- **Referral tracking** — Monitor your referrals
- **Anti-abuse protection** — Prevention of referral fraud

---

## Privacy

Weekend is designed with privacy as a core principle:

- **GPS is used for nearby discovery** — Your location helps find relevant profiles
- **Exact location is not publicly displayed** — Only approximate distance and city/locality are shown
- **Users control profile visibility** — Choose who can see your profile
- **Private information is protected** — Sensitive data is never exposed
- **Users can block/report others** — Full control over your experience
- **Users can delete their account** — Complete server-side data removal via the `account-deletion` Edge Function

---

## Safety

Weekend implements multiple layers of safety:

- **Profile/photo moderation** — Multi-signal AI verification for profile photos
- **Suspicious account detection** — Automated detection of potentially harmful accounts
- **Reporting** — Report inappropriate behavior for review
- **Blocking** — Block any user at any time
- **Unmatching** — Remove matches you no longer want to talk to
- **Privacy controls** — Manage your visibility and data
- **Rate limiting** — API request throttling to prevent abuse

> **Note:** Automated moderation can make mistakes. Weekend includes appropriate review mechanisms for moderation decisions.

---

## Architecture

```
                   Weekend (Flutter)
                         |
         +---------------+---------------+
         |               |               |
         v               v               v
   Flutter UI    Riverpod State     Supabase Client
         |               |               |
         |       Geolocation    Edge Functions
         |               |               |
         +-------+-------+-------+-------+
                 |               |
                 v               v
            PostgreSQL      Storage
               |   (PostGIS) |
               +-------+-------+
                       |
                       v
                   Realtime
                       |
                       v
              Ad System (serve-ad)
```

### Tech Stack

| Layer | Technology |
|-------|------------|
| Language | Dart 3.11.5 |
| UI Framework | Flutter 3.41.9 |
| State Management | Riverpod 2.6.1 |
| Navigation | GoRouter 14.8.1 |
| Backend | Supabase 2.x |
| Database | PostgreSQL + PostGIS |
| Location | geolocator 13.0.4, geocoding 3.0.0 |
| Image Loading | cached_network_image 3.4.1 |
| Ads | In-feed advertisements via Supabase Edge Functions |

---

## Backend

Weekend uses **Supabase** as its complete backend platform:

| Capability | Supabase Service |
|------------|------------------|
| Authentication (email/password, email verification, password reset, Google sign-in) | **Supabase Auth** |
| PostgreSQL database with Row Level Security on every table | **Supabase Database (PostgreSQL + PostGIS)** |
| Private `profile-photos` storage bucket with per-user folder policies | **Supabase Storage** |
| Realtime chat and notification streams | **Supabase Realtime** |
| Photo verification, icebreakers, date ideas, translation, account deletion | **Supabase Edge Functions** |

---

## Getting Started

### Prerequisites

- [Android Studio](https://developer.android.com/studio) (latest stable version)
- [JDK 17](https://adoptium.net/) or later
- [Git](https://git-scm.com/)
- [Supabase](https://supabase.com/) account and project

### Clone the Repository

```bash
git clone https://github.com/zypherlabs-bit/Weekend.git
cd Weekend
```

### Install Dependencies

Open the project in Android Studio and let it sync. Or use the command line:

```bash
./gradlew build
```

### Configure Supabase

1. Create a Supabase project at [supabase.com](https://supabase.com/)
2. Copy `.env.example` to `.env`:
   ```bash
   cp .env.example .env
   ```
3. Edit `.env` with your Supabase credentials:
   ```properties
   SUPABASE_URL=https://your-project-ref.supabase.co
   SUPABASE_ANON_KEY=your-public-anon-key
   ```

   These values come from **Supabase Dashboard -> Project Settings -> API**. The anon key is a public key — it is safe to embed in a mobile app **because Row Level Security protects all data**. Never put the service-role key or database password in `.env`.

4. Run the database migrations in `supabase/migrations/` through the Supabase Dashboard or CLI.

### Run the Application

```bash
# On a connected device or emulator
./gradlew installDebug

# Or run directly
./gradlew :app:run
```

Without a configured `.env`, the app runs in **offline demo mode** with sample data instead of crashing.

---

## Database Setup

The SQL migrations in `supabase/migrations/` define the full schema:

| Migration | Description |
|-----------|-------------|
| `001_initial_schema.sql` | Core tables, RLS, and constraints |
| `002_rls_policies.sql` | Row Level Security policies |
| `003_database_functions.sql` | Database functions and triggers |
| `004_storage_policies.sql` | Storage bucket policies |
| `005_security_hardening.sql` | Security hardening |
| `006_security_fixes.sql` | Additional security fixes |
| `007_advertisements_and_location.sql` | Advertisement tables, crossed-paths, user location buckets |
| `008_advertisements_rls_and_functions.sql` | RLS policies and RPCs for ads (`get_ad_for_user`, `record_ad_event`, `compute_crossed_paths`) |

### Key Tables

- `profiles` — User profiles with location data
- `profile_photos` — Profile photos with moderation
- `interests` / `user_interests` — Interest system
- `likes` / `passes` — Swipe actions
- `matches` — Mutual matches
- `conversations` / `messages` — Messaging
- `plans` / `plan_participants` — Weekend Plans
- `referrals` / `referral_events` — Referral system
- `verification_requests` — Photo verification
- `blocks` / `reports` — Safety features
- `ad_campaigns` — Advertiser campaigns
- `advertisements` — Individual ad creatives
- `ad_impressions` / `ad_clicks` / `ad_events` — Ad event tracking
- `crossed_paths` — Geohash-based crossed-path matches
- `user_location_buckets` — Privacy-safe location buckets for crossed-paths

Row Level Security is enabled on every table. See [docs/supabase.md](docs/supabase.md) for complete setup instructions.

---

## Testing

```bash
# Run lint analysis
flutter analyze

# Run tests
flutter test

# Build release APK
flutter build apk --release
```

---

## Releases

Production APK builds are distributed through **GitHub Releases**.

- Each release contains a **versioned APK** (e.g. `Weekend-v2.0.0-release.apk`) and its **SHA-256 checksum**.
- **SHA-256 checksums** are provided for verification.
- Download the latest APK from the [Download Latest APK](#android-apk) button above, or browse **[all releases](https://github.com/zypherlabs-bit/Weekend/releases)**.

---

## Project Structure

```
Weekend/
+-- app/                          # Main application module (Flutter/Dart)
|   +-- src/
|   |   +-- main.dart             # Entry point
|   +-- features/                 # Screen-level feature modules
|   +-- lib/                      # Shared libraries
|   +-- pubspec.yaml              # Dependencies
+-- supabase/
|   +-- migrations/              # Database migrations
|   +-- functions/               # Edge Functions
+-- docs/
|   +-- assets/                  # Logo and preview images
|   +-- screenshots/             # App screenshots
+-- .github/
    +-- workflows/               # CI/CD
    +-- ISSUE_TEMPLATE/          # Issue templates
```

---

## Roadmap

### Completed

- [x] Authentication (email/password, Google sign-in)
- [x] Profile creation and editing
- [x] Nearby-first discovery with PostGIS
- [x] Swipe-based discovery
- [x] Unlimited likes and matches
- [x] Realtime messaging
- [x] Weekend Plans
- [x] Photo verification
- [x] Smart icebreakers
- [x] Date ideas
- [x] Message translation
- [x] Referral system
- [x] Safety tools (block, report, unmatch)
- [x] Account deletion
- [x] Image optimization
- [x] Row Level Security on all tables

### Planned

- [ ] iOS release
- [ ] Video profiles
- [ ] Voice messages
- [ ] Advanced matching algorithms
- [ ] Additional language support
- [ ] Web version
- [ ] Community improvements

---

## Contributing

We welcome contributions from the community! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

---

## Security

See [SECURITY.md](SECURITY.md) for our security policy and vulnerability reporting process.

**Key security principles:**

- All authorization is enforced server-side via Supabase RLS
- No secrets are embedded in the client (only public anon key)
- Client-side validation is for UX only, not security
- Defense-in-depth with rate limiting, abuse detection, and monitoring

---

## License

Weekend is open source and available under the MIT License. See [LICENSE](LICENSE) for details.

---

## Important Notices

### Free and Open Source

> **Weekend is currently completely free to use.** The current release does not require subscriptions, premium memberships, paid likes, or paid matches. All core features are available to everyone.

### Future Monetization

> The project is currently free and open source. Future versions may introduce optional subscription-based or other monetization features as the project evolves. Any future changes will be communicated transparently.

### Open Source Transparency

> Because Weekend is open source, anyone can inspect the source code, report vulnerabilities, propose improvements, and contribute to the project. Backend authorization remains server-side through Supabase Row Level Security.

---

## Contact & Support

- **Issues:** [GitHub Issues](https://github.com/zypherlabs-bit/Weekend/issues)
- **Discussions:** [GitHub Discussions](https://github.com/zypherlabs-bit/Weekend/discussions)
- **Security:** See [SECURITY.md](SECURITY.md) for vulnerability reporting

---

<div align="center">

**Weekend** — Meet people. Make plans.

Made with love by the Weekend team and contributors.

</div>
