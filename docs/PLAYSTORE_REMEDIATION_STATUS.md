# WEEKEND — PLAY STORE REMEDIATION STATUS

**App:** Weekend — Dating & Matchmaking (`com.weekend.app`)
**Version:** 2.7.0 (`versionCode` 12)
**Date:** 2026-10-02
**Base commit:** `8d01432` on `master`
**Trigger:** `docs/PLAYSTORE_LAUNCH_CERTIFICATION.md` (2026-10-02), result **NO-GO**
**Auditor:** automated remediation pass

---

## Verdict: still **NO-GO**

This document records what was actually executed during remediation and what
still blocks publication. Each row cites the command run or the file inspected.

Three blockers moved. Four did not, because each requires something only the
account holder can supply (a keystore, database credentials, hardware, Play
Console access).

---

## Phase 1 — Repository re-audit

```
git branch --show-current   -> master
git rev-parse HEAD          -> 8d01432
git log --oneline -3        -> 8d01432 (Merge branch 'master' of ...)
git remote -v               -> origin https://github.com/zypherlabs-bit/Weekend.git
```

The repository has **not** changed since the audit's base commit. HEAD is
exactly `8d01432`.

However, the working tree was **not clean**. It carries substantial uncommitted
work — including the very files the audit reasons about:

```
 M android/app/build.gradle.kts          <- the release-signing guard
 M android/app/src/main/AndroidManifest.xml
 M android/gradle.properties
 M lib/services/notification_service.dart <- FCM wiring
 M pubspec.yaml / pubspec.lock           <- firebase_core, firebase_messaging
 M lib/features/chat/chat_screen.dart
 M lib/features/settings/settings_dialog.dart
 M supabase/functions/translate-message/index.ts
 D android/hs_err_pid13844.log
?? lib/firebase_options.dart
?? supabase/migrations/027_device_tokens_and_mode_queries.sql
?? supabase/migrations/028_adult_only_enforcement.sql
?? docs/{PLAYSTORE_LAUNCH_CERTIFICATION,terms,child-safety,
        community-guidelines,safety-policy,google-play-data-safety,
        store-listing,app-access}.md
```

**Consequence:** the age-enforcement migrations, the FCM dependency and the
signing guard are all **untracked or uncommitted** — they are not in `8d01432`.
Any CI run from `master` today does **not** contain migration 028, the adult age
gate, or the debug-signing refusal. This must be committed before anything else
is meaningful.

### Toolchain

| Component | Version | Source |
|---|---|---|
| Flutter | 3.41.9 (stable) | `flutter --version` |
| Dart | 3.11.5 | `flutter --version` |
| Android SDK | 36.1.0, platform android-36.1, build-tools 36.1.0 | `flutter doctor -v` |
| JDK | 17.0.12 (Oracle) | `flutter doctor -v` |
| AGP | 8.11.1 | `android/settings.gradle.kts` |
| Kotlin | 2.2.20 | `android/settings.gradle.kts` |
| Gradle | 8.14 | `gradle-wrapper.properties` |

`flutter doctor -v`: **No issues found.** All licenses accepted.

### Tests

| Suite | Command | Before | After |
|---|---|---|---|
| Dart / Flutter | `flutter test` | 295 passed | 295 passed |
| Static analysis | `flutter analyze` | No issues found | No issues found |
| Python verification | `pytest tests/python` | 335 passed, **8 failed** | **343 passed**, 1 skipped |

The previous audit recorded "8 pre-existing failures" as acceptable. They were
not acceptable — see below.


## Blockers: status after this pass

| # | Blocker | Audit status | Now | Evidence |
|---|---|---|---|---|
| 1 | Release AAB signed with Android debug key | BLOCKER | **BLOCKED — HUMAN ACTION REQUIRED** | Guard verified below |
| 2 | Closed testing 0/12 testers, 0/14 days | BLOCKER | **BLOCKED — HUMAN ACTION REQUIRED** | Cannot be manufactured |
| 3 | Migrations 027/028 not applied to live DB | BLOCKER | **BLOCKED — HUMAN ACTION REQUIRED** | No credentials available |
| 4 | No physical Android device | BLOCKER | **BLOCKED — HUMAN ACTION REQUIRED** | `adb devices` empty |
| 5 | Play Console declarations incomplete | BLOCKER | Prepared, **not submitted** | `docs/store-listing.md` |
| 6 | Privacy policy URL not confirmed reachable | BLOCKER | **CONFIRMED BLOCKER (worse)** | Parked domain |
| 7 | Data Safety must be reconciled with FCM | BLOCKER | **DONE — rewritten** | `docs/google-play-data-safety.md` |

---

## What was actually fixed

### 1. Eight failing Python checks (real defect, now green)

The audit filed these as "pre-existing failures". They were genuine bugs in the
verification harness, introduced when migrations 027/028 were added.

**Root cause A — `weekend_checks.latest_migration_text()` returned only the
highest-numbered file.** Six checks assert on schema introduced by *earlier*
migrations (`025_profile_experience_and_mfa_recovery.sql` defines
`mfa_recovery_codes`, `set_profile_photo_order`, `minimum_profile_photos`). The
moment `028` became the highest-numbered file, those checks read only 028 and
failed. `conftest.latest_migration_text()` has always concatenated all
migrations; the two helpers had silently diverged. Fixed by making the helper
delegate to `migration_text()`.

**Root cause B — `conftest.function_body()` grabbed the wrong function body.**
It probed for the first `$$...$$` pair anywhere after the signature. Several
functions use a *tagged* delimiter (`as $fn$ ... $fn$`), which contains no `$$`
at all, so the search ran past the real body and returned a completely unrelated
function — migration 024's `pin_search_path` loop was being returned for
`minimum_profile_photos`. Fixed by matching the delimiter that actually follows
`as`, then returning everything up to its twin.

Both fixes restore the checks' original intent. Neither weakens an assertion.

### 2. Release-signing guard verified as working

The guard added in `android/app/build.gradle.kts` was proven to fire, not merely
inspected:

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

This is a **safety** control, not the fix for blocker 1 — the fix is a real
keystore, which requires a human decision.

### 3. Data Safety document reconciled with FCM (blocker 7)

Rewritten from `pubspec.lock` and `lib/` rather than from assumption. The
decisive finding: **the FCM dependency does not function in the shipped build.**

- `android/app/google-services.json` — **absent**
- `com.google.gms.google-services` Gradle plugin — **not applied** in
  `settings.gradle.kts` or `app/build.gradle.kts`
- `lib/firebase_options.dart` — a **hand-written placeholder** whose every value
  is `String.fromEnvironment('WEEKEND_FIREBASE_*')`, i.e. empty strings unless
  someone defines them

So `Firebase.initializeApp` receives empty credentials, throws, and is swallowed
by the `catch` in `notification_service.dart::_initFirebase`, which logs
"FCM not configured". **No FCM token is ever generated or transmitted in the
current release build.** The declaration must reflect the build that ships, not
the code that was written.

### 4. `.gitignore` protection confirmed

Keystore material is already excluded at both levels, verified by reading:

- root `.gitignore`: `*.jks` (25), `*.keystore` (26), `key.properties` (29), `debug.keystore` (30)
---

## What remains blocked, and why it cannot be automated

### Blocker 1 — production signing

No keystore exists anywhere on this machine and none may be fabricated.
Generating one requires choosing and protecting a key that permanently governs
the app's identity; it must not be created casually by an agent.

`android/key.properties` is absent. Instructions are in
`docs/HUMAN_ACTIONS_REQUIRED.md` §1.

**Status: BLOCKED — HUMAN ACTION REQUIRED. Not a PASS, and not a faked PASS.**

### Blocker 2 — closed testing

12 testers over 14 continuous days. Time-bound and human. Fabricating tester
counts, dates or feedback is explicitly out of scope and was not done.

### Blocker 3 — live database migration

`supabase` CLI 2.117.0 is installed and the project **is** linked
(`supabase/.temp/project-ref` -> `ocypgybqfushqfzisnvs`, name `weekend`), but
every authenticated command fails:

```
$ supabase migration list
Access token not provided. Supply an access token by running `supabase login`
or setting the SUPABASE_ACCESS_TOKEN environment variable.
```

`SUPABASE_ACCESS_TOKEN` and `SUPABASE_DB_PASSWORD` are unset. `psql` is not
installed and Docker is not installed. There is therefore **no path** from this
environment to the production database.

Migrations 027/028 were reviewed statically (see the final certification) and
are sound, but *written* is not *applied*. Until they are applied and probed,
live age enforcement is **NOT VERIFIED**.

### Blocker 4 — physical device

```
$ adb devices
List of devices attached
      (empty)

$ flutter devices
Windows (desktop), Chrome (web), Edge (web)
```

No Android hardware. Every device-gated item — passkeys, MFA, biometric app
lock, photo upload, notifications, account deletion — is **NOT VERIFIED**.
Static reading of the code is not a substitute and was not treated as one.

### Blocker 6 — privacy policy URL (newly confirmed, and worse than recorded)

The audit asked for confirmation. Confirmation is now obtained, and it is a
failure:

```
$ GET https://weekend.app/privacy     -> 200, 114 bytes
$ GET https://weekend.app/terms       -> 200, 114 bytes
$ GET https://weekend.app/safety      -> 200, 114 bytes   (identical body)
$ GET https://weekend.app/lander      -> 403 Forbidden

body (every path, byte-identical):
<!DOCTYPE html><html><head><script>window.onload=function(){
window.location.href="/lander"}</script></head></html>
```

`weekend.app` is a **parked domain**. Every path returns the same 114-byte
JavaScript stub that redirects to `/lander`, which is forbidden. There is no
privacy policy, no terms page, no community guidelines and no safety policy
served at any of these addresses. An HTTP 200 here does **not** mean the page
exists; it means the parking service answered.

Cross-checked: `https://zypherlabs-bit.github.io/Weekend/` returns **404**
(no Pages site), and of the five policy documents in `docs/`, only `privacy.md`
is reachable on `raw.githubusercontent.com` — `terms.md`, `community-guidelines.md`,
`safety-policy.md` and `child-safety.md` are untracked and return **404**.

**Consequence:** there is currently no publicly reachable privacy policy for
this app. Play Console will reject the submission, and it would be rejected
correctly. This alone is disqualifying.

### In-app policy links — also absent

Phase 23 requires in-app links to the policies. A scan of every Dart file under
`lib/` found **no** privacy-policy, terms, community-guidelines or child-safety
link. The only outbound URLs in the app are the GitHub repository
(`about_open_source_screen.dart`) and an external safety article (Rainn).
The in-app "Privacy" tile in `settings_dialog.dart` navigates to
**/location-settings** — it is a settings sub-page, not a policy.

Play requires an in-app privacy policy link and, for a dating/UGC app, in-app
access to the safety and community-guidelines content. Both are missing.

---

## Live-enforcement probes (Phase 6/7) — NOT RUN

Not attempted. Without database access the probes cannot execute, and reporting
them as passed would be fabrication. The exact probe SQL and expected results
are supplied in `docs/HUMAN_ACTIONS_REQUIRED.md` §3 for the operator to run.

---

## Device matrix (Phase 10–21) — NOT RUN

No device attached. Not run, not simulated, not inferred from unit tests.

---

## Honest summary

| | Count |
|---|---|
| Blockers resolved | 2 of 7 (Data Safety reconciliation; verification-harness defects) |
| Blockers requiring a human | 5 |
| New blockers found during remediation | 2 (parked policy domain; no in-app policy links) |
| Device claims made | 0 |
| Live-DB claims made | 0 |
| Closed-testing claims made | 0 |
| Placeholder PASS values written | 0 |

The repository is in a stronger, more honest state than it was: the release
guard is proven, the Data Safety declaration now matches the shipped binary, the
verification suite is green, and the true state of the public web surface has
been established rather than assumed.

It is **not** ready to publish, and this document does not claim it is.
- `android/.gitignore`: `key.properties` (13), `**/*.keystore` (14), `**/*.jks` (15)

A repo-wide search for `*.jks` / `*.keystore` returns nothing — no keystore is
committed or present on disk.
