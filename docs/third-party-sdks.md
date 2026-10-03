# Third-Party SDK Inventory — Weekend 2.7.0

**Date:** 2026-10-02
**Source of truth:** `pubspec.lock` (resolved versions), `pubspec.yaml`,
`android/app/build.gradle.kts`, `android/app/src/main/AndroidManifest.xml`
**Purpose:** the factual input to `docs/google-play-data-safety.md`.

Every version below is the **resolved** version from `pubspec.lock`, not the
constraint in `pubspec.yaml`. Where a package ships Android native code, its
Android-specific implementation package is listed too.

---

## 1. Backend / infrastructure

| SDK | Version | Data collected | Purpose | Shared? | Required? | Documentation |
|---|---|---|---|---|---|---|
| `supabase_flutter` | 2.17.2 | — (client SDK) | Auth, PostgREST, Realtime, Storage client | — | Yes | Supabase docs |
| `supabase` | 2.16.1 | — (client SDK) | Underlying Dart client | — | Yes | Supabase docs |
| `http` | 1.6.0 | Network metadata | REST calls | — | Yes | dart.dev |

> The Supabase **project** is the backend, not a bundled SDK. It receives email,
> profile data, photos, messages and location as a processor. See the
> "Data shared with third parties" section of the Data Safety form.

---

## 2. Notifications — **present in source, inert in the shipped build**

| SDK | Version | Data collected | Purpose | Shared? | Required? | Documentation |
|---|---|---|---|---|---|---|
| `firebase_core` | 3.15.2 | App instance ID, device ID | Firebase bootstrap | Would be Google | **No** | Firebase docs |
| `firebase_messaging` | 15.2.10 | FCM registration token, notification payloads | Remote push | Would be Google | **No** | Firebase docs |
| `flutter_local_notifications` | 18.0.1 | None (local only) | In-app notification display | No | Yes | pub.dev |

### Why this is declared "No" in the Data Safety form

Three independent facts were verified in the repository:

1. **`android/app/google-services.json` does not exist.** FCM on Android cannot
   initialise without it.
2. **The `com.google.gms.google-services` Gradle plugin is not applied.** It is
   absent from both `android/settings.gradle.kts` and
   `android/app/build.gradle.kts`.
3. **`lib/firebase_options.dart` is a hand-written placeholder**, not generated
   by `flutterfire configure`. Every field is
   `String.fromEnvironment('WEEKEND_FIREBASE_*')`, which resolves to an empty
   string in any build that does not pass those `--dart-define` flags — and
   `.github/workflows/release.yml` passes only `SUPABASE_URL` and
   `SUPABASE_ANON_KEY`.

Consequently `Firebase.initializeApp` throws, `notification_service.dart`
catches it and logs `FCM not configured`, and **no token is generated,
transmitted or stored**.

**Additional finding:** even if the SDKs were correctly configured, there is
**no push sender**. No Edge Function or scheduled job in `supabase/functions/`
dispatches to FCM. Remote push delivery therefore does not exist today; the app
delivers foreground notifications via Supabase Realtime
(`notification_service.dart::subscribeToNotifications`) and local notifications.

**Decision required before launch:** either (a) complete the Firebase setup and
add a sender, then declare device identifiers in the Data Safety form; or
(b) remove the dead FCM dependency and keep declaring none. Option (b) is the
smaller change and matches what the binary does today. **Do not declare FCM
tokens while the code path is inert** — that is a false statement in a
Google-owned form.

---

## 3. Location

| SDK | Version | Data collected | Purpose | Shared? | Required? | Documentation |
|---|---|---|---|---|---|---|
| `geolocator` (+ `_android` 4.6.2) | 13.0.4 | Coarse/approximate coordinates | Nearby discovery | No | Yes | pub.dev |
| `geocoding` (+ `_android` 3.3.1) | 3.0.0 | Coordinates → city/locality | City detection | No | Yes | pub.dev |
| `permission_handler` (+ `_android` 12.1.0) | 11.4.0 | Permission state | Consent flow | No | Yes | pub.dev |

> Coordinates are stored only on the user's own profile row, consumed
> server-side by PostGIS, and **fuzzed** (`toApproximateCoordinates`) before
> being exposed. Other users receive a rounded `distance_km` and a locality
> string, never coordinates.

---

## 4. Biometrics, passkeys and authentication

| SDK | Version | Data collected | Purpose | Shared? | Required? | Documentation |
|---|---|---|---|---|---|---|
| `local_auth` (+ `_android` 2.0.8) | 3.0.2 | Biometric result (no biometric data) | Biometric app lock | No | Yes | pub.dev |
| `credential_manager` (+ `_android` 4.1.0) | 5.1.0 | Public key credential handle | Passkey sign-in | No | Yes | pub.dev |
---

## 5. Media

| SDK | Version | Data collected | Purpose | Shared? | Required? | Documentation |
|---|---|---|---|---|---|---|
| `image_picker` (+ `_android` 0.8.13+17) | 1.2.3 | Selected photo | Profile photo | No | Yes | pub.dev |
| `image` | 4.9.2 | None (local processing) | Compression, EXIF strip | No | Yes | pub.dev |
| `image_editor` | 1.4.0 | Selected photo | Crop/rotate | No | Yes | pub.dev |
| `photo_view` | 0.15.0 | None | Full-screen photo display | No | Yes | pub.dev |
| `cached_network_image` | 3.4.1 | None (caching) | Photo loading | No | Yes | pub.dev |
| `record` | 6.2.1 | Audio (voice intro) | Voice intros | No | Optional | pub.dev |
| `audioplayers` | 6.7.1 | None (playback) | Voice intro playback | No | Optional | pub.dev |
| `mobile_scanner` | 7.4.1 | Camera frames (on-device) | QR invitations | No | Optional | pub.dev |
| `video_player` | 2.9.2 | Bundled assets only | Onboarding clips | No | Yes | pub.dev |
| `lottie` | 3.3.1 | Bundled assets only | Animations | No | Yes | pub.dev |

---

## 6. Networking and device

| SDK | Version | Data collected | Purpose | Shared? | Required? | Documentation |
|---|---|---|---|---|---|---|
| `connectivity_plus` | 6.1.5 | Network state (not an identifier) | Offline handling | No | Yes | pub.dev |
| `share_plus` | 10.1.4 | Content the user shares | Share sheet | Only if user acts | Optional | pub.dev |
| `url_launcher` | 6.3.1 | None | Open external links | No | Yes | pub.dev |

---

## 7. UI / state (no data collection)

`flutter_riverpod` 2.6.1 · `go_router` 14.8.1 · `flutter_svg` 2.0.17 ·
`shimmer` 3.0.0 · `flutter_staggered_animations` 1.1.1 · `qr_flutter` 4.1.0 ·
`intl` 0.19.0 · `timeago` 3.7.0 · `uuid` 4.5.1 · `cupertino_icons` 1.0.8 ·
`image_editor` 1.4.0

---

## 8. Explicitly absent

Verified absent from `pubspec.lock` — these are the SDKs Play reviewers most
often find undeclared:

| Category | SDKs checked | Present? |
|---|---|---|
| Analytics | Firebase Analytics, Mixpanel, Amplitude, Segment, Google Analytics | **No** |
| Crash reporting | Crashlytics, Sentry, Bugsnag, ACRA | **No** |
| Advertising | AdMob, Google Mobile Ads, Unity Ads, Meta Audience Network, AppLovin, IronSource | **No** |
| Attribution | AppsFlyer, Adjust, Branch | **No** |
| Remote config | Firebase Remote Config | **No** |
| Maps | Google Maps SDK, Mapbox | **No** |
| A/B testing | Firebase Experiments, Optimizely | **No** |
| Chat transport | SendGrid, Twilio | **No** |

The one advertising surface in the app is the **first-party** `serve-ad` Edge
Function, which returns contextual creative from Weekend's own backend. It is
not an ad-network SDK and does not transmit profile or location data to an
advertiser.

---

## 9. Android permissions declared

From `android/app/src/main/AndroidManifest.xml`:

| Permission | Why | Data sent off-device? |
|---|---|---|
| `INTERNET` | Backend calls | Yes — necessary |
| `ACCESS_NETWORK_STATE` | Connectivity | No |
| `CAMERA` | QR scanner | Frames processed on device |
| `ACCESS_COARSE_LOCATION` | Nearby discovery | Approximate only |
| `ACCESS_FINE_LOCATION` | Nearby discovery | Approximate only, fuzzed |
| `POST_NOTIFICATIONS` | Local notifications | No |
| `RECORD_AUDIO` | Voice intros | Only on explicit action |
| `USE_BIOMETRIC` / `USE_FINGERPRINT` | App lock, passkeys | No |

`android:allowBackup="false"` and `usesCleartextTraffic="false"` are both set.
| `flutter_secure_storage` | 9.2.4 | Session tokens | Token storage | No | Yes | pub.dev |
| `crypto` | 3.0.7 | None (local computation) | PKCE / hashing | No | Yes | pub.dev |

> No biometric template or fingerprint image ever leaves the secure hardware.
> Only a passkey public-key handle is stored, by Supabase Auth.