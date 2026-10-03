# WEEKEND — GOOGLE PLAY FINAL CERTIFICATION

**App:** Weekend — Dating & Matchmaking (`com.weekend.app`)
**Version:** 2.7.0 · `versionCode` 12
**Date:** 2026-10-02
**Base commit:** `8d01432` on `master`
**Supersedes:** `docs/PLAYSTORE_LAUNCH_CERTIFICATION.md` (2026-10-02, NO-GO)

---

# FINAL RESULT: **NO-GO**

The launch gate is not passed. Five of the original seven blockers remain open,
and remediation surfaced two new ones.

Every status below is backed by a command that was run or a file that was read.
Where evidence does not exist, the status is **BLOCKED** or **NOT VERIFIED** —
never PASS.

---

## Final status table

| Item | Status | Basis |
|---|---|---|
| Production signing | **BLOCKED** | No keystore exists; guard verified to refuse |
| Live Supabase | **BLOCKED** | No credential; migrations unapplied |
| Age enforcement | **NOT VERIFIED** | Migration written, not applied, not probed |
| Physical device | **NOT VERIFIED** | `adb devices` empty |
| Passkey | **NOT VERIFIED** | Requires device |
| MFA | **NOT VERIFIED** | Requires device |
| Biometric app lock | **NOT VERIFIED** | Requires device |
| Photo upload | **NOT VERIFIED** | Requires device |
| Location | **NOT VERIFIED** | Requires device |
| Discovery | **NOT VERIFIED** | Requires device + live DB |
| Matching | **NOT VERIFIED** | Requires device + live DB |
| Chat | **NOT VERIFIED** | Requires device + live DB |
| Notifications | **NOT VERIFIED** | Requires device; FCM inert in build |
| Account deletion | **NOT VERIFIED** | Requires device |
| Privacy policy | **FAIL** | Domain parked; all URLs serve a 114-byte stub |
| Terms / guidelines / safety | **FAIL** | Same; 4 of 5 docs untracked |
| In-app policy links | **FAIL** | No policy link exists anywhere in `lib/` |
| Child safety | **NOT VERIFIED** | Enforcement unapplied; contact not named |
| UGC moderation | **NOT VERIFIED** | Implemented in code; process owner not assigned |
| Data Safety | **PASS** (document) | Reconciled with the shipped binary |
| Content rating | **READY** (answers prepared) | Not submitted |
| Target audience | **READY** (answers prepared) | Not submitted |
| App access | **BLOCKED** | Reviewer account not created |
| Closed testing | **BLOCKED** | 0 testers, 0 days |
| AAB | **BLOCKED** | No production key |
| Play App Signing | **BLOCKED** | Cannot enrol without an upload |
| Automated test suite | **PASS** | 343 Python + 295 Flutter, 0 failures |
| Static analysis | **PASS** | `flutter analyze` clean |

---

## Blocker resolution

### Resolved

| # | Was | Now |
|---|---|---|
| 7 | Data Safety predates FCM | **Document rewritten** from `pubspec.lock` and `lib/` |
| — | 8 failing Python checks | **0 failures** — two real harness bugs fixed |
| — | Signing guard unverified | **Proven** by triggering the build failure |
| — | Icon / feature graphic absent | **Generated** at 512×512 and 1024×500 |
| — | Store copy absent | **Written**, every feature verified against source |

### Still open
---

## Evidence

### Toolchain (verified)

```
Flutter 3.41.9 stable · Dart 3.11.5 · JDK 17.0.12
AGP 8.11.1 · Kotlin 2.2.20 · Gradle 8.14
compileSdk 36 · targetSdk 36 · minSdk 24
flutter doctor -v -> No issues found
```

### Test suites (verified)

| Suite | Command | Result |
|---|---|---|
| Static analysis | `flutter analyze` | **No issues found** |
| Flutter unit tests | `flutter test` | **295 passed** |
| Python verification | `pytest tests/python` | **343 passed, 1 skipped** (was 335 passed / 8 failed) |

### The two harness bugs (real defects, fixed)

1. **`weekend_checks.latest_migration_text()` returned only the highest-numbered
   migration.** Six checks assert on schema introduced by migration 025
   (`mfa_recovery_codes`, `set_profile_photo_order`, `minimum_profile_photos`).
   Adding 028 silently broke them. `conftest.latest_migration_text()` had always
   concatenated all migrations; the two helpers had diverged. Fixed by
   delegating to `migration_text()`.

2. **`conftest.function_body()` returned the wrong function body.** It searched
   for the first `$$...$$` pair after the signature. Functions using a *tagged*
   delimiter (`as $fn$ ... $fn$`) contain no `$$`, so the search ran past the
   real body and returned migration 024's `pin_search_path` loop for
   `minimum_profile_photos`. Fixed by matching the delimiter that follows `as`.

Neither fix weakens an assertion; both restore the checks' original intent.

### Signing guard (proven, not assumed)

```
$ ./gradlew :app:bundleRelease -PallowDebugSigning=false
BUILD FAILED
* Where: Build file 'android/app/build.gradle.kts' line: 221
* What went wrong:
REFUSING TO BUILD a release artifact: android/key.properties is missing or
incomplete, so the build would fall back to the Android DEBUG key. A debug-signed
release cannot be updated through Play App Signing and permanently consumes the
package's first signing key.
```

```
Production signing:   BLOCKED — HUMAN ACTION REQUIRED
Certificate subject:  (none — no keystore exists)
SHA-256 fingerprint:  (none — no keystore exists)
AAB signature:        BLOCKED
APK signature:        BLOCKED
```

No keystore exists on this machine: a recursive search for `*.jks` and
`*.keystore` returned zero results. `.gitignore` correctly excludes
`key.properties`, `*.jks`, `*.keystore` and `debug.keystore` at both root and
`android/` level. No secret is committed.

### FCM — the dependency that does not work

| Requirement | State |
|---|---|
| `android/app/google-services.json` | **absent** |
| `com.google.gms.google-services` plugin applied | **no** |
| `lib/firebase_options.dart` | hand-written placeholder, all values `String.fromEnvironment` → empty |
| Backend sender for FCM | **does not exist** |

`Firebase.initializeApp` throws on empty credentials; `notification_service.dart`
catches it and logs `FCM not configured`. **No token is generated or
transmitted.** The Data Safety form therefore declares **Device identifiers =
No**. Also note there is no push sender in `supabase/functions/`, so remote
delivery does not exist even if the client were configured.

### Privacy policy URLs (FAIL)

```
GET https://weekend.app/privacy   -> 200, 114 bytes
GET https://weekend.app/terms     -> 200, 114 bytes  (byte-identical)
GET https://weekend.app/safety    -> 200, 114 bytes  (byte-identical)
GET https://weekend.app/lander    -> 403 Forbidden

body: <!DOCTYPE html><html><head><script>window.onload=function(){
      window.location.href="/lander"}</script></head></html>
```

Every path returns the same 114-byte parking stub. An HTTP status check alone
would have produced a **false PASS** — this is why the body was inspected.

`https://zypherlabs-bit.github.io/Weekend/` → **404** (Pages not enabled).
On `raw.githubusercontent.com`, only `docs/privacy.md` resolves; `terms.md`,
---

## The gate, restated

Per the launch gate, the app is **NO-GO** while any of these stand:

```
Debug signing                     -> OPEN (no keystore)
Missing production keystore       -> OPEN
Unverified live age enforcement   -> OPEN
No physical device test           -> OPEN
Missing privacy URL               -> OPEN (domain parked)
Missing Play declarations         -> OPEN (not submitted)
Incomplete closed testing         -> OPEN (0 testers, 0 days)
```

Plus, found during this pass:

```
No in-app privacy policy link     -> OPEN
FCM declared but non-functional   -> OPEN (declaration corrected, build not)
```

**Do not publish. Do not upload the current debug-signed artifacts.**

---

## What was delivered

| Artifact | Path |
|---|---|
| Remediation status | `docs/PLAYSTORE_REMEDIATION_STATUS.md` |
| This certification | `docs/PLAYSTORE_FINAL_CERTIFICATION.md` |
| Human action guide | `docs/HUMAN_ACTIONS_REQUIRED.md` |
| Data Safety (reconciled) | `docs/google-play-data-safety.md` |
| SDK inventory | `docs/third-party-sdks.md` |
| Store listing copy | `docs/store-listing.md` |
| Play icon (512×512) | `docs/store-assets/play-icon-512.png` |
| Feature graphic (1024×500) | `docs/store-assets/play-feature-graphic-1024x500.png` |
| Asset generator | `tool/make_store_assets.py` |

Test-harness fixes: `tests/python/weekend_checks.py`,
`tests/python/conftest.py`.

---

## Integrity statement

| | |
|---|---|
| Physical-device verifications claimed | **0** |
| Live-database verifications claimed | **0** |
| Closed-testing figures claimed | **0** |
| Placeholder PASS values written | **0** |
| Blocker statuses overridden | **0** |
| Secrets created or exposed | **0** |

The audit's NO-GO stands. This pass resolved what could be resolved honestly
and documented the rest precisely enough that it can be finished.
`community-guidelines.md`, `safety-policy.md` and `child-safety.md` return
**404** because they are untracked.

### Live database (BLOCKED)

Project `ocypgybqfushqfzisnvs` (name `weekend`) **is** linked, but:

```
$ supabase migration list
Access token not provided. Supply an access token by running `supabase login`
or setting the SUPABASE_ACCESS_TOKEN environment variable.
```

`SUPABASE_ACCESS_TOKEN` unset · `SUPABASE_DB_PASSWORD` unset · `psql` not
installed · Docker not installed. No path to production from this environment.

**Migration 028 static review (sound, unapplied):** the DOB guard is a
`BEFORE INSERT OR UPDATE` trigger rather than a CHECK constraint, correctly —
`now()`/`age()` are not IMMUTABLE and Postgres rejects them in CHECK. It is
deliberately *not* exempted for `service_role`, unlike `protect_profile_columns`,
which would reopen the hole. Both `search_profiles` and `get_nearby_profiles`
clamp `p_age_min` to 18 internally. Function definitions are followed by
`revoke all ... from public, anon` and `grant execute ... to authenticated`.
An audit block emits a NOTICE counting under-18 and null-DOB rows before
anything is changed, so a partially-migrated database is avoided.

**Reviewing the SQL is not the same as proving it works.** Until it is applied
and probed against live data, age enforcement is **NOT VERIFIED**.

### Physical device (NOT VERIFIED)

```
$ adb devices
List of devices attached
      (empty)
$ flutter devices
Windows (desktop) • Chrome (web) • Edge (web)
```

No Android hardware. Phases 10–21 were not run, were not simulated, and were
not inferred from unit tests. An emulator was deliberately not substituted:
its software fingerprint is not evidence for biometric or passkey behaviour.

| # | Blocker | Status |
|---|---|---|
| 1 | Debug-signed release | BLOCKED — no keystore |
| 2 | Closed testing 0/12, 0/14 | BLOCKED — human + time |
| 3 | Migrations unapplied | BLOCKED — no credential |
| 4 | No physical device | BLOCKED — no hardware |
| 5 | Play declarations | Prepared, not submitted |
| 6 | Privacy policy unreachable | **FAIL** — worse than recorded |

### New blockers found

| # | Blocker | Evidence |
|---|---|---|
| 8 | **Domain parked.** `weekend.app` serves an identical 114-byte JS stub on every path, redirecting to `/lander` (403). There is no policy content at any address. | Live HTTP check, 2026-10-02 |
| 9 | **No in-app policy links.** Play requires an in-app privacy policy link. A scan of `lib/` found none; the Settings "Privacy" tile opens `/location-settings`. | Scan of all `lib/**/*.dart` |