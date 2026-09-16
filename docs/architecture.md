# Architecture

This document explains how Weekend is put together and where each kind of logic
belongs. It is written against the code in `lib/`, `supabase/` and `android/`.

---

## 1. System overview

```text
┌──────────────────────────────────────────────────────────────┐
│                      Weekend Android app                     │
│                                                              │
│  Flutter UI (Material 3)                                     │
│      screens in lib/features/*                               │
│            │  watch/read                                     │
│            ▼                                                 │
│  Riverpod providers (lib/providers)                          │
│            │                                                 │
│            ▼                                                 │
│  Repositories (lib/repositories)  ──  Services (lib/services)│
│            │                                   │             │
│            ▼                                   ▼             │
│  Supabase client (lib/config)          Kotlin/Android APIs   │
└──────────────────────────────┬───────────────────────────────┘
                               │ HTTPS (TLS only)
                               ▼
┌──────────────────────────────────────────────────────────────┐
│                          Supabase                            │
│                                                              │
│  Auth ── Database (PostgreSQL + PostGIS, RLS) ── Storage     │
│                        │                                     │
│                        ├── Realtime (messages, notifications)│
│                        └── RPCs (security definer)           │
│                                                              │
│  Edge Functions (Deno/TypeScript)                            │
│    photo-verification · account-deletion · icebreaker        │
│    date-ideas · translate-message · serve-ad                 │
└──────────────────────────────────────────────────────────────┘
```

There is exactly one backend: Supabase. The app holds no server code, no
scheduled jobs and no privileged credentials.

---

## 2. Client layers

| Layer | Location | Responsibility | Rules |
|-------|----------|----------------|-------|
| Screens | `lib/features/**` | Presentation, layout, navigation, local widget state | Never call Supabase directly; read state via providers |
| Providers | `lib/providers/` | UI state and orchestration | May call repositories and services |
| Repositories | `lib/repositories/` | All Supabase table/RPC/function access plus row→model mapping | Must handle a `null` client (offline demo mode) |
| Services | `lib/services/` | Platform and cross-cutting concerns: location, ads, QR, biometrics, secure storage, notifications, image optimisation | No UI imports |
| Models | `lib/models/` | Immutable data classes with `copyWith` / `fromJson` | No side effects, no network access |
| Widgets | `lib/widgets/` | Reusable components (`AdCard`, `DiscoveryCard`, safety dialogs, radius filter) | Presentational only |
| Routing | `lib/routing/app_router.dart` | GoRouter configuration and auth-aware redirects | Redirect logic only |
| Theme | `lib/theme/` | Light/dark Material 3 themes and brand palette | — |
| Config | `lib/config/supabase_config.dart` | Compile-time Supabase config + demo-mode detection | Never store secrets |

**Offline demo mode.** `SupabaseConfig.client` returns `null` whenever the app is
built without credentials. Every repository guards on that and returns
`const []`, an empty stream or a local stub instead of throwing. `main.dart` also
wraps `Supabase.initialize` in a try/catch so a bad configuration can never
freeze startup.

---

## 3. Data flow examples

### Discovery (like/pass → match → chat)

```text
DiscoverScreen (features/home)
   → weekendProvider.loadDiscoveryProfiles()
        → DiscoveryRepository.getNearbyProfiles()
             → rpc('get_nearby_profiles', …)      ← PostGIS distance + RLS
   ← List<UserProfile> (never raw coordinates)

Swipe → weekendProvider.likeProfile(id)
   → MatchRepository.likeProfile(id)              ← insert into likes
        → DB trigger check_mutual_like()
             → creates matches row + conversations row
   ← MatchCelebrationDialog (widgets/)
```

### Chat

```text
ChatScreen (features/chat)
   → MessageRepository.subscribeToMessages(matchId)
        → client.from('conversations').stream()
        → client.from('messages').stream()        ← Supabase Realtime
   ← Stream<List<ChatMessage>> rendered live

Send → MessageRepository.sendMessage()
        → insert into messages                    ← enforce_message_rules trigger
```

### Ads

```text
AdService (services/ad_service.dart)
   active discovery timer (120 s, paused on app lifecycle events)
   → AdRepository.fetchAd(userId)
        → functions.invoke('serve-ad')            ← validates caller, returns creative
   → AdCard (widgets/ad_card.dart)
   events → rpc('record_ad_event', …)             ← server-side validation
```

### Location

```text
LocationService
   → PermissionHandler + geolocator (medium accuracy)
   → Geohash.encode(lat, lon, precision: 7)       ← ≈150 m bucket, no raw point
   → user_location_buckets / crossed_paths        ← crossed-paths only
   → rpc('get_nearby_profiles')                   ← distance computed server-side
```

---

## 4. Backend structure

```text
supabase/
├── functions/            # Deno/TypeScript Edge Functions (JWT-authenticated)
│   ├── serve-ad/         # ad selection + event recording
│   ├── photo-verification/
│   ├── account-deletion/
│   ├── icebreaker/
│   ├── date-ideas/
│   └── translate-message/
├── migrations/           # ordered SQL: schema → RLS → functions → hardening
└── test/rls_test.sql     # manual RLS verification script
```

**Security model.** The client is assumed to be fully inspectable. Therefore:

1. Every table has Row Level Security enabled (`002_rls_policies.sql`).
2. Cross-user reads go through `security definer` RPCs that derive the caller
   from `auth.uid()` and verify it with `assert_self(...)`
   (`006_security_fixes.sql`).
3. Privileged columns (verification, moderation, trust) are protected by
   triggers so the client cannot write them.
4. Storage objects are private, scoped per user folder, and readable by others
   only when moderation has approved them.

See [security.md](security.md) for the full model and [supabase.md](supabase.md)
for operational setup.

---

## 5. Android host layer

- `android/app/src/main/kotlin/com/weekend/app/MainActivity.kt` — a
  `FlutterActivity`, i.e. the Kotlin entry point that hosts the Flutter engine.
- `android/app/build.gradle.kts` — Gradle Kotlin DSL, JDK 17, `applicationId`
  `com.weekend.app`, release signing read from an untracked `key.properties`.
- `android/app/src/main/AndroidManifest.xml` — declares only the permissions the
  features need (internet, network state, camera, location, notifications), sets
  `usesCleartextTraffic="false"`, `allowBackup="false"` and a network security
  config.
- Platform capabilities are reached through Flutter plugins: `geolocator`,
  `permission_handler`, `local_auth` (BiometricPrompt), `mobile_scanner`
  (camera), `flutter_secure_storage` (Android Keystore),
  `flutter_local_notifications`.

---

## 6. Design decisions and trade-offs

| Decision | Why | Trade-off |
|----------|-----|-----------|
| Server-side distance instead of client-side | Raw coordinates never leave the database | Requires PostGIS and an RPC per discovery page |
| Geohash buckets for crossed paths | Compare locations without storing precise tracks | Bucket edges can miss near-misses within ~150 m |
| `security definer` RPCs with `assert_self` | Prevents a client from impersonating another user id | More SQL to maintain |
| Demo mode with a `null` client | UI and tests run with no backend; startup cannot crash | Every repository must guard on `null` |
| Ads unlinked from user identity | No behavioural profiling | Less advertiser targeting, by design |
| Local notification channels instead of a push provider | No third-party push dependency yet | No notifications while the app is closed (see roadmap) |

---

## 7. Related documents

- [getting-started.md](getting-started.md)
- [supabase.md](supabase.md)
- [location-discovery.md](location-discovery.md)
- [qr-invitations.md](qr-invitations.md)
- [security.md](security.md)
- [privacy.md](privacy.md)
- [testing.md](testing.md)