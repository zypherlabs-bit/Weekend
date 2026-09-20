# Privacy

This page describes **what the Weekend app actually handles**, based on the code
and database schema in this repository. It is a technical description, not legal
advice, and it is not a claim of compliance with any particular regulation.

Operators who self-host Weekend are responsible for their own privacy notices and
legal obligations.

---

## 1. Summary

| | |
|---|---|
| Exact GPS shared with other users? | **No.** Distance is computed server-side and returned as a number. |
| Location stored for discovery | Raw coordinates on your own profile row (server-side) plus a geohash bucket in `user_location_buckets` |
| Photos visible to strangers? | Only after moderation marks them `approved`, and only through a private bucket |
| Ads profiled against you? | **No.** Ad selection is contextual; no advertiser receives your profile or location |
| Third-party analytics SDK in the app? | None |
| Account data removal | Server-side deletion functions; see the current limitation below |

---

## 2. What the app collects and stores

| Data | Stored in | Why |
|------|-----------|-----|
| Email address, password (hashed by Supabase Auth), session tokens | Supabase `auth.users` | Sign-in and account recovery |
| Display name, date of birth, gender, bio, occupation, education, relationship intent | `profiles` | Your profile |
| Interests, prompts, languages, favourite places | `user_interests`, `interests`, profile fields | Matching and shared-interest discovery |
| Photos and thumbnails | `profile_photos` (+ private Storage objects) | Your profile; moderation state tracked per photo |
| Visibility preferences and discovery radius | `user_settings`, `preferences` | Discovery behaviour |
| Likes and passes | `likes`, `passes` | Matchmaking |
| Matches and conversations | `matches`, `conversations`, `conversation_members` | Chat eligibility and unread state |
| Messages | `messages` | Chat (plus optional translated text) |
| Blocks and reports | `blocks`, `reports` | Safety enforcement |
| Plans you create or join | `plans`, `plan_participants` | Weekend Plans |
| Referral code and invitation events | `referrals`, `referral_events` | Invitation attribution |
| Verification submissions and results | `verification_requests`, `moderation_events` | Photo verification and moderation |
| Notifications | `notifications` | In-app notifications |
| Ad interactions | `ad_impressions`, `ad_clicks`, `ad_events` | Frequency capping and fraud prevention (records the acting user id; not shared with advertisers) |

The app contains **no analytics, advertising-SDK, crash-reporting or social-login
tracking packages**. See `pubspec.yaml` for the complete dependency list.

---

## 3. Location handling in detail

1. The app requests location permission with a screen that explains the benefit
   first (`location_permission_screen.dart`), using medium accuracy.
2. Your own profile row holds `latitude` / `longitude`. These are used by
   PostgreSQL/PostGIS to compute distance **server-side**.
3. The `get_nearby_profiles` RPC returns `distance_km` (rounded), display name,
   age, city and other profile fields — **it does not return coordinates**, and it
   only computes results for the authenticated caller (`assert_self`).
4. For crossed paths the app encodes a **geohash bucket** (precision 7, roughly
   150 m) and stores it in `user_location_buckets`; co-location is recorded in
   `crossed_paths` with counts and timestamps rather than a movement trail.
5. What another user sees is limited to your city/locality and an approximate
   distance such as "5 km away".

Additional location toggles (location discovery, nearby discovery, distance
display, crossed paths, travel mode) are held in the app's session state, and the
chosen radius is persisted to `user_settings.max_distance_km`. Database defaults
such as `user_settings.show_me_in_search`, `discovery_emails_enabled`,
`push_notifications_enabled` and `preferences.show_me_to` are part of the schema
and can be set at the database level; dedicated UI for every one of them is still
on the roadmap (`show_me_to` and read receipts are not yet wired to the app).

---

## 4. Photos and moderation

- Photos upload into a **private** Storage bucket (`profile-photos`), scoped to
  your own folder; there is no public bucket URL.
- Each photo row carries a `moderation_status` of `pending`, `approved` or
  `rejected`. Other users can read a photo only when it is `approved`.
- Clients cannot set the moderation or verification columns themselves —
  `protect_photo_moderation` and `protect_profile_columns` block it.
- Verification submissions are handled by the `photo-verification` Edge Function
  and the result is written server-side.

---

## 5. Advertisements

- Ads are selected for the discovery context, not from a behavioural profile.
- The app asks the `serve-ad` Edge Function; the server decides which creative is
  eligible.
- Impression, click, hide and report events are recorded server-side with the
  acting user id for frequency capping and abuse prevention. **Advertisers are not
  given your identity, profile or location.**
- You can hide or report an ad; a hidden ad is not shown to you again.
- Destination URLs must be HTTPS before the app will open them.

---

## 6. User controls

| Want to… | Where |
|----------|-------|
| Stop using location for discovery | Location settings → Location discovery / Nearby discovery off |
| Stop sharing approximate distance | Location settings → Show distance off |
| Disable crossed paths | Location settings → Crossed paths off |
| Change how far discovery searches | Location settings → Discovery radius |
| Report or block someone | Safety centre (or the profile/chat action sheet) |
| Review blocked users | Safety centre → Blocked users |
| Lock the app behind biometrics | Biometric app lock on resume |
| Check verification state | Safety centre → Photo verification, plus the badge on profiles |

---

## 7. Retention and deletion

- Profile data is removed by the server-side deletion path (`delete_user_account`
  RPC and the `account-deletion` Edge Function), including related rows and the
  auth user.
- In-app deletion is wired: **Settings → Delete Account** invokes the
  `account-deletion` Edge Function with the caller's own access token; the
  function verifies identity server-side before performing the privileged
  cleanup (profile rows, auth user, storage objects, sessions). Operators
  should verify the end-to-end flow with
  [verification-2fa-deletion.md](verification-2fa-deletion.md) before opening
  a deployment to users.
- The schema does not define automatic expiry jobs (for example, timed deletion
  of `crossed_paths_log` or old messages). Self-hosting operators should define a
  retention policy appropriate to their users.
- Uninstalling the app removes local app data.

---

## 8. Data sharing

- **Supabase** hosts the database, auth, storage, realtime and serverless
  functions of a Weekend deployment. Data therefore lives in the Supabase project
  the app was built against.
- **AI provider calls** happen only inside Edge Functions (for example photo
  verification, translation, icebreakers). The provider key stays server-side, so
  the client never contacts the provider directly with a secret.
- No advertising network, analytics provider or data broker receives user data
  from the app.

---

## 9. Related documents

- [security.md](security.md) — how access is enforced
- [location-discovery.md](location-discovery.md) — discovery and geohashing design
- [qr-invitations.md](qr-invitations.md) — what an invitation payload contains
- [../README.md](../README.md) — feature overview and FAQ