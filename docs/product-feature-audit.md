# Product Feature Audit

**Audit date:** 2026-09-30
**Scope:** Every user-facing and developer-facing feature in the Weekend app and Supabase backend.
**Status legend:** `IMPLEMENTED` · `PARTIAL` · `BROKEN` · `NOT IMPLEMENTED` · `NOT VERIFIED`

---

## Authentication

| Feature | Status | Evidence |
|---------|--------|----------|
| Email / password signup | IMPLEMENTED | `lib/features/auth/signup_wizard_screen.dart`, `lib/repositories/auth_repository.dart` |
| Email confirmation flow | IMPLEMENTED | `confirm_email_screen.dart`, `auth.resend(type: signup)` |
| Email / password signin | IMPLEMENTED | `auth_screen.dart` |
| Session restore on relaunch | IMPLEMENTED | `AuthNotifier` subscribes to `onAuthStateChange` |
| Password reset | IMPLEMENTED | `auth.sendResetPassword` |
| Passkey (WebAuthn / Credential Manager) | PARTIAL | Client implementation complete (`passkey_service.dart`); live project reports `passkey_disabled`. See README known limitations. |
| TOTP two-factor (MFA) | IMPLEMENTED | `mfa_enrollment_screen.dart`, `mfa_challenge_screen.dart` |
| MFA recovery codes | IMPLEMENTED | `mfa_recovery_codes` table, Settings → Security |
| Biometric app lock | IMPLEMENTED | `biometric_lock_gate.dart`, `app_lock_service.dart` |
| Logout | IMPLEMENTED | Auth state management |

## Profile

| Feature | Status | Evidence |
|---------|--------|----------|
| Personal details (name, age, city, bio) | IMPLEMENTED | `profile_schema.dart`, `profile_repository.dart` |
| Photos (add, replace, reorder, set-primary, delete) | IMPLEMENTED | `profile_photos` table, `ImageOptimizer` |
| Prompts (15 question prompts) | IMPLEMENTED | `profile_schema.dart` |
| Interests | IMPLEMENTED | `interests` table, `ensure_interest` RPC |
| Lifestyle attributes | IMPLEMENTED | Smoking, drinking, exercise, children, pets, height |
| Relationship intent | IMPLEMENTED | `relationship_intent` column |
| Languages | IMPLEMENTED | `languages` column |
| Weekend availability | IMPLEMENTED | `user_settings.weekend_availability` JSONB |
| Profile editing / save recovery | IMPLEMENTED | `ProfileRepository.updateProfile` with INSERT-recovery, migration 020 |
| Profile completeness | IMPLEMENTED | `get_my_profile_completion` RPC |
| Verified photos | PARTIAL | Photo verification Edge Function exists; moderation state gates visibility |
| Trust score | IMPLEMENTED | Rendered on profile cards |

## Discovery

| Feature | Status | Evidence |
|---------|--------|----------|
| Nearby discovery | IMPLEMENTED | `get_nearby_profiles` RPC, PostGIS distance |
| Discovery radius (0.5–100 km) | IMPLEMENTED | `DiscoveryMode.nearby`, slider control |
| Discovery modes (Near, City, Global, Travel, Crossed Paths) | IMPLEMENTED | `DiscoveryMode` enum |
| Explore mode chips | IMPLEMENTED | For You, Nearby, Around Me, City, Global, etc. |
| Crossed paths | PARTIAL | Geohash buckets + `compute_crossed_paths` function; not surfaced as explicit crossed-path UI |
| Advanced search (hard filters) | IMPLEMENTED | `search_profiles` RPC, migration 022/023 |
| Age filtering | IMPLEMENTED | Server-side |
| Gender / interested-in filtering | IMPLEMENTED | Server-side |
| Distance filtering | IMPLEMENTED | PostGIS `ST_DWithin` |
| Interests filtering | IMPLEMENTED | Server-side |
| Lifestyle filtering | IMPLEMENTED | Server-side |
| City filtering | IMPLEMENTED | Server-side |

## Matching

| Feature | Status | Evidence |
|---------|--------|----------|
| Likes | IMPLEMENTED | `record_like` RPC |
| Passes | IMPLEMENTED | `record_pass` RPC |
| Mutual match (database trigger) | IMPLEMENTED | `check_mutual_like` trigger |
| Match celebration | IMPLEMENTED | `match_celebration_dialog.dart` |
| Matches list | IMPLEMENTED | `get_matches_for_user` RPC |
| Unmatch | IMPLEMENTED | `unmatch_match` RPC |
| Received likes | IMPLEMENTED | `get_received_likes` RPC, `/likes` screen |

## Messaging

| Feature | Status | Evidence |
|---------|--------|----------|
| Real-time chat | IMPLEMENTED | Supabase Realtime, `message_repository.dart` |
| Conversation on match | IMPLEMENTED | Created with match by `check_mutual_like` |
| Message rules (block enforcement) | IMPLEMENTED | `enforce_message_rules` trigger (both directions) |
| Read state | IMPLEMENTED | `read_state` per conversation member |
| Server-side translation | PARTIAL | `translate-message` Edge Function + columns exist; no UI button |
| Media messages | NOT IMPLEMENTED | No image/video sending in chat |
| Reactions | NOT IMPLEMENTED | Not present in codebase |

## Safety

| Feature | Status | Evidence |
|---------|--------|----------|
| Report | IMPLEMENTED | `submit_report` RPC, structured reasons |
| Block | IMPLEMENTED | `enforce_message_rules` trigger (both directions) |
| Blocked users excluded | IMPLEMENTED | From discovery and messaging |
| Unmatch | IMPLEMENTED | `unmatch_match` RPC |
| Block unwind | IMPLEMENTED | `enforce_block_unwind` trigger |
| Account deletion (server-side) | IMPLEMENTED | `account-deletion` Edge Function |
| Biometric app lock | IMPLEMENTED | Device-credential fallback |

## Plans

| Feature | Status | Evidence |
|---------|--------|----------|
| Create a plan | IMPLEMENTED | `plans_screen.dart`, `plan_repository.dart` |
| Discover plans | IMPLEMENTED | Plan browsing |
| Join / leave | IMPLEMENTED | Optimistic UI + re-sync |

## QR & Referrals

| Feature | Status | Evidence |
|---------|--------|----------|
| QR invitation generation | IMPLEMENTED | Signed payload, 30-day expiry |
| QR scanner | IMPLEMENTED | `mobile_scanner` |
| Referral recording | IMPLEMENTED | `record_referral` RPC |
| Referral credit on match | IMPLEMENTED | `check_mutual_like` trigger |
| Open Source screen (with QR) | IMPLEMENTED | `about_open_source_screen.dart` |

## Notifications

| Feature | Status | Evidence |
|---------|--------|----------|
| Notification centre | IMPLEMENTED | `notifications` table, `notification_repository.dart` |
| Realtime streaming | IMPLEMENTED | Supabase Realtime |
| Local notifications | IMPLEMENTED | `flutter_local_notifications` |
| In-app badge | IMPLEMENTED | `notification_unread_count` RPC |
| Deep links | IMPLEMENTED | `_onNotificationTap` routes to destination |
| **Remote push (FCM)** | NOT IMPLEMENTED | No FCM/APNs integration |

## Verification & Trust

| Feature | Status | Evidence |
|---------|--------|----------|
| Photo verification | PARTIAL | Edge Function exists; moderation auto-approves |
| Trust score | IMPLEMENTED | Rendered on cards |
| TDZ crash fix | IMPLEMENTED | Migration 024 `pg_temp` sweep |

## Monetization

| Feature | Status | Evidence |
|---------|--------|----------|
| In-feed ads | IMPLEMENTED | `serve-ad` Edge Function, 120s interval |
| Ad labels | IMPLEMENTED | ADVERTISEMENT / Sponsored labels |
| Report / hide ads | IMPLEMENTED | Server-side event validation |
| **Subscription / Premium** | NOT IMPLEMENTED | Explicitly not built (see feature-parity-matrix.md) |

## Additional Features

| Feature | Status | Evidence |
|---------|--------|----------|
| Theme (light/dark/system) | IMPLEMENTED | `theme_provider.dart`, persisted |
| Voice intros | NOT IMPLEMENTED | Field exists; recording/upload/playback not implemented |
| Voice messages | PARTIAL | Tooltip exists; "not available in this release" |
| Date ideas | IMPLEMENTED | `date-ideas` Edge Function + UI (chat screen button) |
| Icebreakers | NOT IMPLEMENTED | Edge Function exists; not surfaced in UI |

## Analytics

| Feature | Status | Evidence |
|---------|--------|----------|
| Analytics SDK | NOT IMPLEMENTED | Explicitly not built by design |

## Infrastructure

| Feature | Status | Evidence |
|---------|--------|----------|
| Row Level Security | IMPLEMENTED | All tables |
| SECURITY DEFINER functions | IMPLEMENTED | `search_path` pinned (migration 024) |
| CI/CD | IMPLEMENTED | `ci.yml`, `release.yml` |
| Tag-driven releases | IMPLEMENTED | GitHub Actions |
| SHA-256 checksums | IMPLEMENTED | Per release |

## Verification Status

| Check | Evidence type | Status |
|-------|---------------|--------|
| Passkey registration on device | DEVICE | NOT VERIFIED |
| Physical Android device pass | DEVICE | NOT VERIFIED |
| Sign-up / email confirmation live | RUNTIME | NOT VERIFIED (429 rate limit) |
| Two-account matching / chat live | RUNTIME | NOT VERIFIED (no test accounts) |
| Photo upload / moderation live | RUNTIME | NOT VERIFIED |
| FCM push | RUNTIME | NOT VERIFIED (not implemented) |