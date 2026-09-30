# Feature Parity Matrix

**Project:** Weekend (Flutter + Supabase dating app)
**Audit Date:** 2026-09-30
**Baseline:** Tinder-style swipe-based dating platform (functional reference only — no proprietary code/assets copied)

## Legend

| Status | Meaning |
|--------|---------|
| COMPLETE | Fully implemented server-side + client-side + UI + tests |
| PARTIAL | Partially implemented — backend or model exists but missing UI/integration |
| MISSING | Not present anywhere in the codebase |
| BROKEN | Implemented but non-functional (dead code, never invoked, unreachable) |
| NEEDS_REFACTOR | Implemented but with known defects to address during refactoring |
| BLOCKED | Depends on an external factor or prior phase |

---

## Matrix

| # | Feature Area | Status | Notes |
|---|-------------|--------|-------|
| 1 | **Authentication** | COMPLETE | Email/password signup/signin (`AuthRepository`), email verification, social (Google, Apple, passkey via Supabase native WebAuthn). `passkey-authenticate`/`passkey-register` Edge Functions are retired/hard-disabled (410) — auth flows through `client.auth.passkey.*`. |
| 2 | **Password Reset** | COMPLETE | Supabase native reset flow in `auth_repository.dart`. |
| 3 | **MFA (TOTP 2FA)** | COMPLETE | Enrollment, challenge, and verification via Supabase native MFA. `mfa_attempt_limiter_test.dart` guards brute-force. Recovery codes in migration 025. |
| 4 | **Biometric / App Lock** | COMPLETE | `BiometricAuthService` + `AppLockService` + `BiometricLockGate` widget. `app_lock_lifecycle_test.dart` and `biometric_error_mapping_test.dart` cover lifecycle/error mapping. |
| 5 | **Discovery / Swipe Deck** | COMPLETE | Profiles via `get_nearby_profiles` RPC. Swipe right (like) via `record_like` RPC with `LikeOutcome` enum. Swipe left (pass) via `record_pass` RPC. Ad cards inserted every ~3rd card. |
| 6 | **Discovery Modes** | COMPLETE | For You, Nearby, Global, Crossed Paths modes via `DiscoveryMode` enum + `_modeToString`. Location radius filter in `LocationRadiusFilter` widget. |
| 7 | **Like Recording** | COMPLETE | `record_like` RPC (migration 026) replaces raw INSERT+read. Returns matched/recorded/failed. Checks blocks. Idempotent via upsert + unique constraint. |
| 7b | **Stand Out (Super Like)** | COMPLETE | `isStandOut` parameter on `recordLike` routes to `p_is_stand_out` RPC param. Star button in `home_screen.dart:579` calls `swipeRight(..., isStandOut: true)`. Read back via `is_stand_out` column in `get_received_likes`. Badge shown in `likes_screen.dart:232`. |
| 8 | **Pass Recording** | COMPLETE | `record_pass` RPC (migration 026) upserts and withdraws outstanding like. |
| 9 | **Mutual Matches** | COMPLETE | `check_mutual_like` trigger creates match + conversation transactionally. `get_matches_for_user` RPC (migration 026) is privacy-safe. `MatchItem` model. |
| 10 | **Match Celebration** | COMPLETE | `recentMatchCelebration` field + `MatchCelebrationDialog` widget. |
| 11 | **Unmatch** | COMPLETE | `unmatch_match` RPC (migration 026) deletes match + conversation + members + messages + clears like/pass rows. |
| 12 | **Liked Profiles Tracking** | COMPLETE | `likedProfiles` list in state. Optimistic removal + card restore on failure. |
| 13 | **Received Likes ("Likes You")** | COMPLETE | `get_received_likes` RPC (migration 026) + `LikesScreen` + `ReceivedLikesNotifier`. Like-back routes through `swipeRight`. Non-mutual exclusion enforced server-side. |
| 14 | **Chat / Messaging** | COMPLETE | `ChatScreen` with realtime subscription via Supabase Realtime. `sendMessage` persists to `messages` table. Message translation via `translate-message` Edge Function. Read receipts via `last_read_at` on `conversation_members`. |
| 15 | **Match Conversation Routing** | COMPLETE | `MatchConversationScreen` resolves match id → MatchItem → ChatScreen. |
| 16 | **Push Notifications** | COMPLETE | System toasts via `NotificationService`. Notification centre via `NotificationRepository` + `NotificationCentreScreen` + `NotificationCentreNotifier`. RPCs: `get_notifications`, `notification_unread_count`, `mark_all_notifications_read` (migration 026). Realtime subscription with proper handle lifecycle. |
| 17 | **Notification Deep Links** | COMPLETE | `new_message` → `/chat/:matchId`, `new_like` → `/likes`, `new_match` → `/home`. |
| 18 | **Advanced Search** | COMPLETE | `search_profiles` RPC (migration 022/023). `SearchFilters` model with 13 filter fields. `SearchNotifier` + `search_screen.dart`. All hard filters enforced server-side. Server error ≠ empty result. |
| 19 | **Search Filters Persistence** | COMPLETE | `saveLocationPreferences` writes to `user_settings` with `onConflict: 'user_id'` (fixed from PK-target bug). |
| 20 | **Profile Editing** | COMPLETE | `buildProfilePayload` enforces CHECK constraints. `saveProfileWithRecovery` handles zero-row UPDATE → INSERT recovery. DOB picker with 18–120 age validation. Prompts encoding/decoding. Lifestyle fields validated. |
| 21 | **Photo Upload** | COMPLETE | `uploadProfilePhoto` with JPEG/PNG/WebP magic-byte validation. Storage-first → DB-row. Storage-bucket RLS verified. Orphan cleanup on DB failure. |
| 22 | **Photo Moderation** | COMPLETE | `moderation_status = 'approved'` filter on all photo fetches. `photo-verification` Edge Function exists + dialog in safety centre. |
| 23 | **Photo Reorder / Primary / Delete** | COMPLETE | `set_profile_photo_order` RPC, `set_primary_profile_photo` RPC, delete with min-photo enforcement. |
| 24 | **Profile Fields** | COMPLETE | Display name, bio, city, occupation, education, favorite music, ideal weekend, relationship intent, gender, height, smoking/drinking/exercise/pets/children, languages, prompts (up to 5 with template). `ProfileSchema` centralizes validation. |
| 25 | **Referral System** | COMPLETE | `get_referral_stats` RPC. `ReferralData` model. Referral codes via migration 017. QR invite screen. |
| 26 | **Weekend Plans** | COMPLETE | `PlanRepository` + `PlansScreen`. Create with category/venue/time/description. Join/leave via `plan_participants`. Privacy levels (public/private). Participant list. |
| 27 | **Date Ideas** | COMPLETE | `DateIdeasRepository` calls `date-ideas` Edge Function (Gemini + fallback). `generateDateIdeas()` method on `WeekendNotifier` wires state + repository + edge function. `DateIdeasWidget` renders ideas in a bottom sheet with loading/empty/refresh states. Button wired into `ChatScreen` app bar. Test in `test/date_ideas_test.dart`. |
| 28 | **Voice Intro** | **MISSING** | `UserProfile.voiceIntroUrl` field exists but is hardcoded to `''` everywhere. No recording UI, no audio playback, no storage integration, no API. Pure schema placeholder. |
| 29 | **Ads** | COMPLETE | `AdService` with 120s default timer (configurable via `AdConfig`), `AdRepository` + `serve-ad` Edge Function. `AdCard` widget. Event recording (impression/click/dismiss). `ad_service_timer_test.dart` + `ad_card_test.dart`. Free-user ad eligibility. |
| 30 | **Blocking** | COMPLETE | `SafetyRepository.blockUser` + `blocks` table. `blockUser` in `WeekendNotifier`. Block list UI in safety centre. |
| 31 | **Reporting** | COMPLETE | `SafetyRepository.reportUser` + `reports` table. Report dialog with 7 reason options in safety centre. Auto-blocks after report. |
| 32 | **Privacy Controls** | COMPLETE | Show in search, show distance, crossed paths, read receipts — all persisted to `user_settings`. Loads from live row, writes only toggled columns. |
| 33 | **Safety Center** | COMPLETE | Emergency banner (Call 112), safety tools, safety tips, resources, Weekend safety features. Links to RAINN, FTC, findahelpline.com. |
| 34 | **Crossed Paths** | COMPLETE | Geohash bucket storage (`user_location_buckets`). `compute_crossed_paths` RPC. 2km location fuzzing via `toApproximateCoordinates`. Geohash encoding at precision 7. |
| 35 | **Location Services** | COMPLETE | `LocationService` with geocoding, distance formatting, approximate coordinates. |
| 36 | **Theme** | COMPLETE | Light/Dark/System modes. Persisted via SharedPreferences. Mirrored to `user_settings.theme_preference`. `theme_provider.dart` loaded before first frame. |
| 37 | **Premium / Subscriptions** | COMPLETE | `PlansRepository` + `SubscriptionPlan` model. Free-user restrictions enforced (ad eligibility, discovery limits). |
| 38 | **Free-User Limits** | COMPLETE | Free users see ads; premium users don't. Discovery card limits via `AdConfig`. |
| 39 | **Account Deletion** | COMPLETE | `account-deletion` Edge Function with service role + cascade to all tables. `deleteUserAccount` RPC (migration 006, fixed in 009). |
| 40 | **Onboarding** | COMPLETE | `OnboardingScreen` + wizard. Interest selection, preferences setup. |
| 41 | **QR Invite / Scanner** | COMPLETE | `qr_invite_screen.dart` (QR code generation + share), `qr_scanner_screen.dart`. `QrInvitationService` + `SecureStorageService`. |
| 42 | **Settings** | COMPLETE | `SettingsDialog` with theme toggle, app lock, safety center link, about/open source. |
| 43 | **About / Open Source** | COMPLETE | `AboutOpenSourceScreen`. |

---

## Summary

- **COMPLETE:** 44 areas
- **MISSING:** 1 area (Voice Intro)

### Remaining Gap: Voice Intro (MISSING — candidate for next phase)

`UserProfile.voiceIntroUrl` exists as a field but is hardcoded to `''` everywhere. No recording UI, no audio playback, no storage integration, no API. Pure schema placeholder.

### Recently Resolved: Date Ideas (COMPLETE)

The `date-ideas` Edge Function was implemented server-side but never invoked from the client. This was fixed by:

- `lib/repositories/date_ideas_repository.dart` — calls the `date-ideas` Edge Function via `client.functions.invoke()`
- `lib/widgets/date_ideas_widget.dart` — `DateIdeasButton` + `DateIdeasSheet` (bottom sheet with loading/empty/refresh states)
- `generateDateIdeas()` method on `WeekendNotifier` in `lib/providers/weekend_provider.dart`
- Wired `DateIdeasButton` into `ChatScreen` app bar
- `test/date_ideas_test.dart` (3 tests for no-backend fallback behavior)

`UserProfile.voiceIntroUrl` exists as a field but is always `''`. No recording UI, no audio playback, no storage integration, no API. Pure schema placeholder.

---

> **Note:** This matrix tracks application feature completeness only. It does not include the marketing/SEO work defined in the Master Prompt phases (Phase 0–15). Those phases are documented in `docs/github-page-baseline.md`, `docs/product-feature-audit.md`, `docs/github-user-journey.md`, `docs/github-discovery.md`, and `docs/SEO.md`.
