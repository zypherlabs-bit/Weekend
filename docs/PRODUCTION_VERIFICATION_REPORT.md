# Production Verification Report — Weekend

**Date:** 28 Sep 2026
**Branch:** `fix/edit-profile-save-recovery` (base `master`)
**Build:** `app-release.apk` 75.6 MB · SHA-256 `f9ff4f8a…265606`
**Backend:** live Supabase project `ocypgybqfushqfzisnvs`
**Test device:** Android emulator `emulator-5554` (API 35, 1080x2400)
**Host:** Windows 11 25H2

---

## Verdict

# NOT READY FOR PRODUCTION RELEASE

**Status: NOT VERIFIED — PHYSICAL ANDROID DEVICE TEST REQUIRED**

The reported defect is **fixed and verified against the live backend**. The
remaining blockers are release-process and coverage issues, not known code
defects in the save path.

### Blocking

| # | Blocker | Detail |
|---|---|---|
| **B1** | **No physical-device test** | Every result is emulator-only. OEM permission dialogs, real GPS accuracy, background networking and push delivery are unreproducible on an emulator. |
| **B2** | **APK is debug-signed** | Certificate is `CN=Android Debug`. Not publishable to Google Play, and not updatable in place once a real key is introduced. |
| **B3** | **No iOS build exists** | `ios/` is the default scaffold; no `Podfile`, no signing team, no `build/ios/`. Requires macOS + Xcode. |
| **B4** | **Sign-up unverifiable** | Live project returns HTTP 429 `over_email_send_rate_limit`, so signup, email confirmation and password reset cannot be end-to-end tested. |

### Non-blocking issues found

| # | Issue | Severity |
|---|---|---|
| N1 | **Edit Profile button is below the fold** on Profile (`profile_screen.dart:250`) — the screen does not advertise that it is editable. | Medium (UX) |
| N2 | **~30 foreign keys cascade from `profiles`.** Account deletion removes settings, preferences, likes, matches and messages. | Medium (data loss) |
| N3 | **Bare `sn:` social handles are not detected** by the social-handle obfuscation filter. | Low |

### Bug found and fixed during this audit

The Edit Profile recovery path — the fix this branch introduces — silently
**destroyed the user's referral code**. Migration 017 guarantees every profile
owns a stable, unique code, but that is enforced only by a trigger on
`auth.users`; a direct `INSERT INTO public.profiles` bypasses it, and the
payload carries no `referral_code`.

Reproduced on the live project (1 of 9 rows affected — precisely the recovered
one), fixed by migration **`021_referral_code_on_insert.sql`** (a
`BEFORE INSERT` trigger that fills a missing code), and verified end-to-end:
after a delete-and-save cycle the profile came back with its **original**
code, `WKND-8C352EC95D`.

The existing 128 tests did not catch this — they cover the save path but not
the referral invariant across a recovery. Full write-up in
[`LIVE_SCREEN_AUDIT.md`](LIVE_SCREEN_AUDIT.md) §2a.

---

## What was verified

### Automated

| Check | Result |
|---|---|
| `flutter analyze` | **No issues found!** |
| `flutter test` | **All 128 passed** |
| Live migrations 001–021 | Applied |
| `scripts/audit_weekend_live.py` | **6/6 checks passed** |
| REST + RLS end-to-end checks | Pass |
| `apksigner verify` | Valid signature (debug key — see B2) |

### On-device, against the live backend

The Edit Profile save/recovery lifecycle — the reason this branch exists —
was exercised through the real Flutter UI, with every result confirmed by
querying `public.profiles` directly.

1. Save with three changed fields → all three written.
2. Force-stop and cold relaunch → data persisted, session intact.
3. Re-open Edit Profile → form repopulated from the database.
4. Empty Full Name → save blocked, row untouched.
5. Unchanged save → row rewritten, `updated_at` advanced.
6. **Row deleted server-side while signed in → Save re-created it** under the
   auth session id. This is the original bug; it is fixed.
7. Save with no network → classified `[PROFILE_UPDATE_NETWORK]` error, no
   false success, no data corruption, input preserved.
8. Retry after connectivity restored → committed successfully.

Screens confirmed rendering without crash: Onboarding, Sign in, Discover,
Explore, Chat, Profile, Edit Profile, Location Settings.

Full detail, including raw evidence: [`LIVE_SCREEN_AUDIT.md`](LIVE_SCREEN_AUDIT.md).

---

## What is NOT verified

Stated plainly, because none of it should be assumed working:

* **Physical Android device** — not tested at all.
* **iOS** — not built, not tested; cannot be built on Windows.
* **Sign-up, email confirmation, password reset** — rate-limited (429).
* **Two-account matching, chat, and Realtime delivery** — needs two live
  accounts with nearby locations; the audit account had no candidates.
* **Photo upload and moderation** — Storage write and `profile_photos` row
  unverified in the running app.
* **Cascade delete behaviour** — untested *by choice*: it is destructive and
  needs a product decision, not a test run.

---

## Required before release

1. **Generate a real release keystore** and commit `android/key.properties`
   (never the keystore). Rebuild and re-verify the signature. → clears **B2**
2. **Run a physical Android device pass** over the nine screens in
   `LIVE_SCREEN_AUDIT.md` §1, including photo upload and location. → clears **B1**
3. **Test sign-up once email rate limits reset**, and confirm confirmation +
   password-reset emails arrive. → clears **B4**
4. **Decide cascade-delete policy** for the ~30 dependent tables, and
   implement it deliberately. → addresses **N2**
5. **Move the Edit Profile / Settings row above the fold.** → addresses **N1**
6. **For iOS:** provision a macOS + Xcode machine, add CocoaPods, set
   `DEVELOPMENT_TEAM`, and produce a signed IPA. → clears **B3**

Until steps 1–3 are done, any APK produced by `tool/build_release.ps1` is an
internal test build and must not be distributed.
