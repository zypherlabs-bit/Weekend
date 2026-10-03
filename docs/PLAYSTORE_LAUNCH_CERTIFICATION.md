# WEEKEND — GOOGLE PLAY LAUNCH CERTIFICATION

**App:** Weekend — Dating & Matchmaking (`com.weekend.app`)
**Version:** 2.7.0 (`versionCode` 12)
**Date:** 2026-10-02
**Base commit:** `8d01432` on `master`
**Auditor:** automated audit (code, migrations, build artifacts)

---

# FINAL RESULT: **NO-GO**

This is not a formality. An earlier revision of this document stated
"GO with human-blocked items" while simultaneously recording that release
signing was blocked. Under the launch gate those are contradictory: GO requires
signing to be verified. That document has been replaced by this one.

**Why NO-GO, in one paragraph:** the AAB builds and targets API 36, but it is
signed with the **Android debug key**, no production keystore exists, the age
gate was client-side only until this audit (now fixed in code, but not yet
applied to or verified against the live database), and the mandatory closed
test — 12 testers for 14 continuous days — has not happened and cannot be
manufactured. Publishing now would be a policy breach.

---

## 1. Blockers, in priority order

| # | Blocker | Severity | Status |
|---|---------|----------|--------|
| 1 | Release AAB signed with the **debug key** (`CN=Android Debug`). A debug-signed upload permanently consumes the package's first signing key and cannot be updated via Play App Signing. | **BLOCKER** | Needs a real keystore (human) |
| 2 | Closed testing not performed: **0 of 12 testers, 0 of 14 days**. Required before production access. | **BLOCKER** | Human + time-bound |
| 3 | Age-gate fixes (migrations `027`/`028`) are **written but never applied to or probed against the live database**. No Docker/psql available here. | **BLOCKER** | Needs DB apply + probe |
| 4 | No physical-device testing: no Android device attached (`flutter doctor` lists only Windows, Chrome, Edge). Passkeys, MFA, biometric lock, notifications, photo upload and account deletion are therefore **NOT VERIFIED**. | **BLOCKER** | Needs hardware |
| 5 | Play Console declarations (Data Safety, content rating, target audience, app access, ads) cannot be submitted without account access. | **BLOCKER** | Human, Play Console |
| 6 | Privacy policy URL is not confirmed publicly reachable. | **BLOCKER** | Human |
| 7 | `docs/PLAYSTORE_LAUNCH_CERTIFICATION.md` previously asserted a "server-side CHECK rejects under-18". No such constraint existed. Corrected below. | Fixed in code | Migration `028` |

### Defects found and fixed during this audit

| Defect | Where | Impact |
|---|---|---|
| **Age gate was client-side only.** `updateDateOfBirth` threw a Dart exception, but migration `006` grants `authenticated` UPDATE on `date_of_birth`, and the anon key is public by design. A minor could `PATCH /rest/v1/profiles` or set `date_of_birth` in `/auth/v1/signup` metadata (`handle_new_user` copied it unvalidated). | `lib/repositories/profile_repository.dart`, `supabase/migrations/006_security_fixes.sql:551` | Child-safety bypass |
| **Minors could match and message.** Neither `record_like` nor `check_mutual_like` checked age. | migration `026`, `003` | Child-safety bypass |
| **`search_profiles` returned every profile when no age range was sent** (`not v_age_set or ...` short-circuits TRUE), and a caller could pass `p_age_min = 13`. | migration `023` | Child-safety bypass |
| **Migration `027`'s `get_nearby_profiles` could never work.** It selected `prof.user_id`, `prof.age`, `prof.location`, `prof.primary_photo_path`, `prof.interests` — none exist on `profiles` — and filtered `passes` on `passer_id`/`passed_id` instead of `user_id`/`target_id`. It also declared a signature the client never calls. Postgres does not validate a plpgsql body at CREATE time, so it compiled and **every discovery call would raise at runtime** (silently returning `[]`, because the repository catches). | `supabase/migrations/027` | Total discovery outage |
| **Gradle daemon crash.** `org.gradle.jvmargs=-Xmx8G -XX:MaxMetaspaceSize=4G` requests ~12 GB on a 7.9 GB host; the JVM died mid-build with a misleading crash inside `mobile_scanner`'s Kotlin compile. | `android/gradle.properties` | Release build impossible |
| **Release builds silently fell back to the debug key.** | `android/app/build.gradle.kts` | Undeliverable artifact |

---

## 2. Phase-by-phase status

| Phase | Status | Evidence |
|---|---|---|
| 0. Baseline | PASS | `master`, origin `zypherlabs-bit/Weekend`, HEAD `8d01432`; Flutter 3.41.9 / Dart 3.11.5 |
| 1. Policy baseline | PASS | Requirements enumerated in §4 below |
| 2. Android 16 / API 36 | PASS | `aapt2 dump badging` on the built APK: `compileSdkVersion='36'`, `targetSdkVersion='36'` |
| 3. Production environment | PASS | No loopback backend endpoints. `localhost` occurs in the APK only inside Flutter engine / Dart VM service strings. |
| 4. Supabase audit | NOT VERIFIED | SQL reviewed statically; no live DB available to execute RLS probes |
| 5. Authentication | NOT VERIFIED | Code reviewed; no device run |
| 6. Passkey | NOT VERIFIED | Requires physical device. AssetLinks not served on the RP ID |
| 7. MFA / 2FA | NOT VERIFIED | Server-backed TOTP exists; no device run of enroll → verify → challenge → disable |
| 8. Age restriction | **FIXED, NOT VERIFIED in DB** | `028_adult_only_enforcement.sql`; 32 static guards pass; never applied to a live DB |
| 9. Child safety | NOT VERIFIED | Policy docs exist; in-app reporting present; no Play Console self-certification |
| 10. UGC moderation | NOT VERIFIED | Report/block implemented; not exercised |
| 11. Sexual content safety | NOT VERIFIED | Prohibited in policy; no live moderation evidence |
| 12. Profile system | NOT VERIFIED | No device run of the 4-photo flow |
| 13. Photo/video permissions | PASS (static) | Manifest has no `READ_MEDIA_*` / storage permissions; Photo Picker used |
| 14. Location privacy | PASS (static) | Raw coordinates never returned by RPCs; only distance + city |
| 15. Discovery | **FIXED** | Migration `027` rewritten; signature restored to what the client calls |
| 16. Matching | **FIXED** | `unique (liker_id, liked_id)`; self-like `check (liker_id <> liked_id)`; adult guard added |
| 17. Chat | NOT VERIFIED | RLS reviewed statically; no live test |
| 18. Notifications | NOT VERIFIED | FCM optional; Firebase options come from `--dart-define` (no committed secrets) |
| 19. Biometric lock | NOT VERIFIED | Lifecycle state machine unit-tested; device run required |
| 20. Account deletion | NOT VERIFIED | Edge Function + RPC exist; no live deletion run |
| 21. Privacy policy | NOT VERIFIED | `docs/privacy.md` exists; public URL reachability unconfirmed |
| 22. Terms & guidelines | PASS (docs exist) | terms, community guidelines, safety policy, child safety |
| 23. Data safety | NOT VERIFIED | `docs/google-play-data-safety.md` written from source audit; not submitted |
| 24. Content rating | NOT VERIFIED | Not completed in Play Console |
| 25. Target audience | NOT VERIFIED | Not configured in Play Console |
| 26–28. Store listing / assets / SEO | NOT VERIFIED | Copy drafted in `docs/store-listing.md`; assets not generated |
| 29. App access | NOT VERIFIED | Instructions in `docs/app-access.md`; reviewer account not created |
| 30. Release signing | **FAIL** | `apksigner verify` → `CN=Android Debug` |
| 31. Versioning | PASS | `2.7.0` / code `12`; `pubspec.yaml` is the single source of truth |
| 32. Build AAB | PASS | Built, 107,647,629 bytes |
| 33. Release APK on device | BLOCKED | No device attached |
| 34. Physical device matrix | BLOCKED | No device attached |
| 35. Automated tests | PASS | `flutter analyze` clean; 295 Flutter tests pass; 335 Python tests pass (8 pre-existing failures) |
| 36. Performance | NOT VERIFIED | No profiling performed |
| 37. Security scan | PASS | No committed secrets; `.gitignore` covers `key.properties`, `*.jks`, `*.keystore`, `.env` |
| 38. AAB validation | PASS | SHA-256 recorded; `targetSdk=36`; package correct |
| 39. Closed test | **FAIL** | 0 testers, 0 days |
| 40. Play Console setup | BLOCKED | No account access |
| 41. Production access | BLOCKED | Blocked by #39 |
| 42. This report | — | — |
| 43. Launch gate | **NO-GO** | 7 blockers open |
| 44. Publish | NOT ATTEMPTED | Gate not passed |
| 45–46. Post-launch | NOT APPLICABLE | Not published |

---

## 3. Build evidence

```
Flutter                3.41.9 (stable)
Dart                   3.11.5
Android Gradle Plugin  8.11.1
Kotlin                 2.2.20
Gradle                 8.14
JDK                    17
compileSdk             36   (aapt2 badging)
targetSdk              36   (aapt2 badging)
minSdk                 24
versionName            2.7.0
versionCode            12
package ID             com.weekend.app
```

Artifacts produced 2026-10-02:

```
AAB  build/app/outputs/bundle/release/app-release.aab
     107,647,629 bytes
     SHA-256 4821f57ec14884ebdc5319a9e571f43d39b045c0328105de207770a9830cc32e

APK  build/app/outputs/flutter-apk/app-release.apk
     128,027,975 bytes
     SHA-256 32368c3e2bfeb2036dbff7af395607ee88b0f0590e938163a8c33afd7e95197c
```

**Both artifacts are debug-signed and therefore NOT distributable.**

---

## 4. Applicable Play requirements

- Target API 36 for the 2026 submission window — satisfied.
- Data Safety form must reflect actual collection — inventory produced in
  `docs/google-play-data-safety.md`; must be reconciled with the new Firebase
  Cloud Messaging dependency (device token, app instance id), which that
  document predates.
- Account deletion must work in-app and be documented — implemented, unverified
  live.
- UGC apps need in-app report + block and a moderation process — implemented,
  unverified live.
- Dating apps are age-restricted; minors must be prevented — now enforced in
  the database layer, but **not yet applied or probed**.
- Privacy policy must be publicly reachable — unconfirmed.
- Closed test of 12 testers / 14 continuous days before production access — not
  started.

---

## 5. What must happen next

1. Generate a production keystore, put it in a secret manager, create
   `android/key.properties`, enroll in Play App Signing, back up the keystore.
2. Apply `supabase/migrations/027` and `028` to the live project, then run
   `supabase/test/rls_test.sql` plus negative probes (minor DOB rejected,
   minor cannot match, `p_age_min = 13` returns nothing).
3. Attach a physical Android device and run the Phase 33/34 matrix — especially
   passkeys, MFA, biometric lock, photo upload and account deletion.
4. Create the Play Console developer account, complete developer verification,
   and submit all App content declarations using `docs/google-play-data-safety.md`
   (updated for FCM).
5. Run closed testing with 12+ real testers for 14 continuous days, tracking
   opt-in dates, crashes and feedback honestly.
6. Produce the 512×512 icon, feature graphic and real device screenshots.
7. Re-run this gate. Only then upload the AAB and submit for review.

**Until items 1–7 are done, the correct action is to not publish.**
