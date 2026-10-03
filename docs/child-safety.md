# Child Safety Standards

This document describes Weekend's age-gating, minor detection, and child-safety
reporting mechanisms. These measures comply with Google Play's
**Age-restricted content and families policy** and Google's
**Child safety policy**.

---

## 1. Age gate

> **Corrected 2026-10-02.** This section previously claimed the age gate was
> enforced "server-side" by `ProfileRepository.updateDateOfBirth`. That was
> wrong: `updateDateOfBirth` runs in the **Flutter client** and throws a Dart
> exception. It is a UX guard, not a security control. Because the Supabase
> anon key is public by design and migration `006` grants the `authenticated`
> role `UPDATE` on `date_of_birth`, the gate was bypassable without the app —
> by calling the REST API directly, or by setting `date_of_birth` in
> `/auth/v1/signup` metadata, which `handle_new_user` copied into the profile
> row without validation. The true server-side enforcement is migration
> **`028_adult_only_enforcement.sql`** (written during the launch audit;
> **not yet applied to the live database**).

Enforcement now exists in four layers, the last three of which are database-side:

- **UI picker.** The sign-up flow requires a **date of birth**, and the picker
  `lastDate` is `DateTime(now.year - 18, now.month, now.day)`
  (`lib/features/profile/edit_profile_screen.dart`).
- **Client validation.** `ProfileRepository.updateDateOfBirth` rejects an
  under-18 date and reports `profiles.dob.underage`. Convenience only.
- **Database write trigger (migration 028).** `on_adult_date_of_birth` rejects
  any INSERT or UPDATE of `date_of_birth` that computes to an age under 18,
  on every write path, for every role. A `NULL` date of birth is tolerated
  during onboarding but fails closed downstream.
- **Database freeze (migration 028).** `on_freeze_date_of_birth` locks the
  date of birth once the profile is activated, so age cannot be changed to
  re-enter the dating surface with a different apparent age.
- **Database read/match guards (migrations 027 + 028).** `search_profiles` and
  `get_nearby_profiles` apply an unconditional 18+ floor that a caller cannot
  widen, and `record_like` / `check_mutual_like` require both parties to be
  *proven* adults before a match — and therefore a conversation — can exist.

**Result: an under-18 date of birth cannot be stored, cannot be discovered,
and cannot match or message.** This holds for the Flutter app, the REST API,
direct RPC calls and hand-written requests alike.

**Verification status: the SQL is written and statically guarded by 32 tests in
`tests/python/test_adult_only_enforcement.py`, but it has NOT been applied to
or probed against the live database. Treat this as NOT VERIFIED until it has
been.**

## 2. No minor data collection

Weekend collects nothing from users under 18 because an under-18 date of birth
cannot be stored, and a profile with no date of birth is not discoverable and
cannot match. There is no age-gate bypass or "under-18 mode."

- No COPPA-covered data processing (no knowledge of a minor's identity,
  no geolocation from a minor, no persistent identifier from a minor).
- The minimum age is enforced in three layers: UI picker, client-side
  validation, and database CHECK constraints.

## 3. Minor detection and reporting

If a user believes someone on the platform is a minor, they can report that
profile. The `SafetyRepository.mapReportType` method maps any reason containing
"underage", "minor", "child", or "too young" to the `underage` report category
(`lib/repositories/safety_repository.dart:126`).

The `reports` table CHECK constraint in migration 026 accepts `underage` as a
distinct category, so it is not lost in a generic bucket
(`supabase/migrations/026_dating_platform_completion.sql:1126`).

### Report flow

1. **Report a User** in the Safety Centre (`lib/features/safety/safety_center_screen.dart`)
   or the profile/chat action sheet.
2. Select "Underage / minor" as the reason.
3. The report is submitted through the `submit_report` RPC, which:
   - Validates the category server-side (CHECK constraint).
   - Rate-limits to 20 reports per day per reporter.
   - De-duplicates against an existing open report on the same user.
   - Requires authentication (RLS: `reporter_id = auth.uid()`).
4. Reports are immutable once created.

### Underage response

All `underage` reports are escalated for **immediate human review**. The
moderation queue treats `underage` as the highest-priority category. Upon
confirmation:

- The profile is suspended pending verification.
- If the user cannot verify age, the account is permanently deleted.
- The deletion is performed through the `account-deletion` Edge Function
  (`supabase/functions/account-deletion/index.ts`), which removes the auth user,
  profile rows, storage objects, and sessions.

## 4. Safety centre

The in-app **Safety Centre** (`lib/features/safety/safety_center_screen.dart`)
provides:

- **Blocked Users** — list and remove blocks.
- **Report a User** — guided report submission with category selection.
- **Photo Verification** — verify identity to increase trust score.
- **Dating Safety Guide** — tips for safe online dating.
- **Report Scams & Fraud** — instructions for identifying romance scams.
- **Safety Tips** — seven safety cards covering first meetings, privacy, and
  suspicious behavior.

## 5. Photo verification

Photo verification requires a live camera selfie matched against an ID document.
The `photo-verification` Edge Function (`supabase/functions/photo-verification/index.ts`)
analyzes the submission and writes the result to
`verification_requests.verification_status`. Only `approved` photos are visible
to other users; `pending` and `rejected` are hidden from the discovery deck.

## 6. Related policies

- [safety-policy.md](safety-policy.md) — full safety and content policy
- [terms.md](terms.md) — Terms of Service (includes age requirement)
- [community-guidelines.md](community-guidelines.md) — acceptable use
- [google-play-data-safety.md](google-play-data-safety.md) — Data Safety form

---

**Age gate enforcement**: `lib/features/profile/edit_profile_screen.dart:1247`
(lastDate = DateTime(now.year - 18))
**Server validation**: `lib/repositories/profile_repository.dart:668`
**Underage report category**: `lib/repositories/safety_repository.dart:126`
**Report submission RPC**: `submit_report` (migration 026)
