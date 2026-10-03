# HUMAN ACTIONS REQUIRED — Weekend Play Store Launch

**Date:** 2026-10-02
**Audit baseline:** `8d01432`
**Current HEAD:** `d5e49e5`
**Companion documents:** `docs/PLAYSTORE_REMEDIATION_STATUS.md`,
`docs/PLAYSTORE_FINAL_CERTIFICATION.md`

---

## Why this document exists

Several launch blockers cannot be resolved by an automated agent, because they
require your Google account, your production database credentials, a physical
Android handset, or real people. This file does not say "you need to do this".
It gives the exact steps, what you must supply back, and how to confirm the
result is genuinely correct.

**§1 is now complete** (committed as `d5e49e5`). **§2–§8 remain genuinely
outstanding** and require your accounts, credentials, hardware or people.

| § | Action | Blocks | Status |
|---|---|---|---|
| 1 | Commit the uncommitted work | everything | **DONE — `d5e49e5`** |
| 2 | Publish the policy pages | the submission | outstanding |
| 3 | Create the production keystore | the build, the upload | outstanding |
| 4 | Apply migrations 027/028 + run probes | launch | outstanding |
| 5 | Physical-device testing | launch | outstanding |
| 6 | Play Console account + declarations | the submission | outstanding |
| 7 | Reviewer account | review | outstanding |
| 8 | Closed testing | production access | outstanding |

---

## §1 — Commit the uncommitted work ✅ DONE

### STATUS: COMPLETE — commit `d5e49e5`

The work has been committed to `master`. The working tree is clean.

### WHAT WAS DONE

```
$ git log --oneline -1
d5e49e5 fix(safety): enforce adults-only in the database, refuse debug-signed releases

$ git status --porcelain
(clean)

$ git ls-tree -r --name-only HEAD -- supabase/migrations | grep -E '027|028'
supabase/migrations/027_device_tokens_and_mode_queries.sql
supabase/migrations/028_adult_only_enforcement.sql
```

40 files changed, 5413 insertions, 2133 deletions.

### SAFETY CHECKS PERFORMED BEFORE COMMITTING

| Check | Result |
|---|---|
| Real secret values in the staged diff (Supabase JWT/anon keys, `sbp_` PATs, PEM private keys, AWS keys, GitHub tokens) | **none found** |
| Credential assignments (`KEY=<value>`) | **none found** |
| `.env`, `*.jks`, `*.keystore`, `android/key.properties` in the index | **none staged** |
| `.env` (holds live credentials) | present on disk, **git-ignored** (`.gitignore:20`) |
| Keystore files anywhere in the repo | **none exist** |

Textual matches for `service_role` / `SUPABASE_SERVICE_ROLE_KEY` appear in
source, tests and docs, but they are **variable names and prose**, never
values. No secret was committed.

### ALSO INCLUDED

- `android/hs_err_pid13844.log` deleted — a 2 MB JVM OOM crash dump committed
  by accident, produced by the old `-Xmx8G` setting that
  `android/gradle.properties` no longer uses. `hs_err_pid*.log` and
  `replay_pid*.log` are now git-ignored so it cannot recur.

### REMAINING FOR YOU

**Push to the remote.** The commit is local only:

```bash
git push origin master
```

Then confirm CI is green and that a build from `master` now contains the age
gate:

```bash
git log --oneline -1 origin/master
git --no-pager ls-tree -r --name-only origin/master -- supabase/migrations | grep 028
```

### IMPORTANT

Committing the migration does **not** apply it. Migration 028 is in git but is
still **not applied to the live database** — that is §4, and age enforcement
remains **NOT VERIFIED** until it is.

---

## §2 — Publish the policy pages

### ACTION
Serve the five policy documents at stable public HTTPS URLs.

### WHY REQUIRED
`https://weekend.app` is a **parked domain**. Verified on 2026-10-02:

```
GET https://weekend.app/privacy   -> 200, 114 bytes
GET https://weekend.app/terms     -> 200, 114 bytes   (byte-identical body)
GET https://weekend.app/lander    -> 403 Forbidden
```

Every path returns:

```html
<!DOCTYPE html><html><head><script>window.onload=function(){
window.location.href="/lander"}</script></head></html>
```

There is **no privacy policy, terms page or safety policy at any of these
addresses.** A naive "does it return 200?" check would pass, which is exactly
the trap this documents.

Play will reject the submission without a reachable privacy policy, and it
would be right to.

### EXACT STEPS

**Option A — GitHub Pages (cheapest, workable today)**

1. **Settings → Pages → Source: `master`, branch `/docs`**. Every policy already
   lives in `docs/` as Markdown.
2. Play requires an HTML page, so render Markdown to HTML at deploy time
   (a build step) or commit rendered `.html` alongside each `.md`.
3. Verify the five URLs return real HTML with the Weekend brand in `<title>`.

`https://zypherlabs-bit.github.io/Weekend/` currently returns **404** — Pages
is not enabled yet.

**Option B — the domain you already own**

Point the domain at a real host serving the same five documents, keeping the
paths stable: `/privacy`, `/terms`, `/community-guidelines`, `/safety`,
`/child-safety`.

**Do not** point Play at a raw Markdown URL on `raw.githubusercontent.com`.
It is publicly reachable but renders as plain text.

### ALSO REQUIRED: IN-APP LINKS

The app currently has **no** privacy-policy, terms, community-guidelines or
child-safety link anywhere in `lib/`. The Settings "Privacy" tile navigates to
`/location-settings` — a settings page, not a policy. Play requires an in-app
privacy policy link for apps that collect personal data.

---

## §3 — Create the production upload keystore

### ACTION
Generate a production keystore, back it up securely, and configure Gradle.

### WHY REQUIRED
Blocker 1. **No keystore exists anywhere on this machine** — verified by a
recursive search for `*.jks` / `*.keystore` (zero results). Without one, any
release build either fails or falls back to the debug key.

A debug-signed upload **permanently consumes the package's first signing key**
and cannot be replaced through Play App Signing. Getting this wrong is
expensive and effectively irreversible.

The Gradle guard is in place and verified working:

```
BUILD FAILED
* Where: Build file 'android/app/build.gradle.kts' line: 221
REFUSING TO BUILD a release artifact: android/key.properties is missing or
incomplete, so the build would fall back to the Android DEBUG key.
```

### EXACT STEPS

> I deliberately did **not** generate this key. Choosing and protecting a key
> that permanently governs your app's identity is your decision, and the
> passphrase must never be typed into a chat log.

**1. Generate the keystore** (run locally, outside the repo):

```bash
keytool -genkeypair -v \
  -keystore ~/keys/weekend-upload.jks \
  -alias weekend-upload \
  -keyalg RSA -keysize 4096 -validity 10000 \
  -storetype PKCS12
```

Use a **distinct, memorable alias** — do not reuse `androiddebugkey`. Record
the passphrase in a password manager as you type it.

**2. Back it up immediately, in two places, offline.** If this file is lost you
cannot ship updates to an app already on Play.

**3. Write `android/key.properties`** (git-ignored):

```properties
storePassword=<store passphrase>
keyPassword=<key passphrase>
keyAlias=weekend-upload
storeFile=../keys/weekend-upload.jks
```

Use a path that resolves correctly from `android/`.

**4. Confirm it is ignored, never committed:**

```bash
git check-ignore -v android/key.properties
git status --porcelain android/
```

**5. Build and verify:**

```bash
flutter clean
flutter pub get
flutter build appbundle --release
flutter build apk --release
```

```bash
# APK
"$ANDROID_HOME/build-tools/36.1.0/apksigner" verify --verbose \
  --print-certs build/app/outputs/flutter-apk/app-release.apk

# AAB (signed as a JAR)
keytool -printcert -jarfile build/app/outputs/bundle/release/app-release.aab
```

The subject **must not** be `CN=Android Debug`.

### WHAT TO PROVIDE BACK
The certificate subject and SHA-256 fingerprint. **Never send the keystore,
passphrase or alias.**
---

## §4 — Apply migrations 027/028 and run the age-safety probes

### ACTION
Apply the two pending migrations to the live Supabase project, then run the
negative probes that prove the adults-only rule holds server-side.

### WHY REQUIRED
Blocker 3. The migrations are written and reviewed but **not applied**. Until
they run, a minor can still:

- set an under-18 date of birth directly via `PATCH /rest/v1/profiles`
- set an under-18 DOB at signup through `/auth/v1/signup` metadata
  (`handle_new_user` copied it unvalidated)
- bypass the client-side check entirely, because the Supabase anon key ships
  inside the APK and is public by design
- match and message another user, because neither `record_like` nor
  `check_mutual_like` checked age

This is the highest-severity item after signing.

### WHY AN AGENT CANNOT DO IT

```
$ supabase migration list
Access token not provided. Supply an access token by running `supabase login`
or setting the SUPABASE_ACCESS_TOKEN environment variable.
```

`SUPABASE_ACCESS_TOKEN` and `SUPABASE_DB_PASSWORD` are unset. `psql` and Docker
are not installed. The project **is** linked
(`supabase/.temp/project-ref` → `ocypgybqfushqfzisnvs`, name `weekend`), so
this is the correct project — but there is no credential to reach it. Applying
SQL to production with no credentials is impossible; guessing is unacceptable.

### EXACT STEPS

**0. Back up first.** Take a Supabase backup (Dashboard → Database → Backups, or
`supabase db dump`) before running anything.

**1. Authenticate.**

```bash
supabase login
# or, non-interactive:
export SUPABASE_ACCESS_TOKEN="sbp_..."
```

**2. Confirm you are pointed at the right project — this matters.**

```bash
supabase projects list
supabase link --project-ref ocypgybqfushqfzisnvs
```
### §4b — THE PROBES (all five must behave as stated)

Use two real adult test accounts (`adultA`, `adultB`) plus one test account
attempting a minor DOB. Test accounts only — never real users.

```sql
-- PROBE 1: minor DOB must be REJECTED
update public.profiles
   set date_of_birth = date '2010-01-01'
 where id = '<adultA uuid>';
-- EXPECT: ERROR: Weekend is for adults 18+ only ...
-- The BEFORE INSERT/UPDATE trigger on_adult_date_of_birth must fire.

-- PROBE 2: a minor profile must not be able to become discoverable
update public.profiles
   set dating_profile_activated = true,
       date_of_birth = date '2012-05-05'
 where id = '<adultA uuid>';
-- EXPECT: REJECTED (same trigger).

-- PROBE 4: the age filter must have a hard floor of 18
--   select count(*) from public.search_profiles(
--       '<adultA uuid>'::uuid, null, 13, 100, null, null, null, null,
--       null, null, null, 50, 0);
-- EXPECT: 0 minor profiles. The function must clamp p_age_min to 18
-- internally regardless of what the client sends.

-- PROBE 5: minor -> like must not create a match
--   select * from public.record_like('<minor uuid>', '<adultB uuid>', false);
-- EXPECT: ERROR — the function must reject a caller under 18.
```

```bash
# PROBE 3: the direct REST bypass (the decisive test)
# The anon key is public by design — it ships inside the APK.
curl -X PATCH "$SUPABASE_URL/rest/v1/profiles?id=eq.<adultA uuid>" \
     -H "apikey: $SUPABASE_ANON_KEY" \
     -H "Authorization: Bearer <adultA access token>" \
     -H "Content-Type: application/json" \
     -d '{"date_of_birth":"2010-01-01"}'
# EXPECT: HTTP 4xx with the adult-only error.
# This proves enforcement is in the DATABASE, not in Flutter.
# A success here is a child-safety breach: do not ship.
```

**Every probe must fail in the stated way.** Probe 3 alone closes blocker 3.

### §4c — RLS SUITE

```bash
psql "$DATABASE_URL" -f supabase/test/rls_test.sql
```

Every negative case must fail:

```
User A -> User B private data          -> denied
User A -> User B private photos        -> denied
User A -> User B profile modification  -> denied
User A -> User B messages              -> denied
Blocked user -> protected resources    -> denied
Deleted user  -> protected resources   -> denied
Minor        -> dating functions       -> denied
```

Record the actual output — pass and fail alike.

### WHAT TO PROVIDE BACK
1. `supabase migration list --linked` showing 027 and 028 applied.
2. Output of all five probes.
3. Output of `rls_test.sql`.
4. The under-18 row count from the migration 028 NOTICE.

### HOW TO VERIFY
Re-run probe 3. If it now returns 4xx, enforcement is genuinely database-side.

---

## §5 — Physical Android device testing

### ACTION
Attach a real Android handset and run the device-gated matrix.

### WHY REQUIRED
Blocker 4. No device is attached:

```
$ adb devices
List of devices attached
      (empty)
**7. Photo upload (Phase 15).** Full production path, all four required photos:

```
Edit Profile -> Add photo -> Photo Picker -> Validation -> Compression
  -> Metadata handling -> Supabase Storage -> Database update -> Profile refresh
```

Test: large photo, invalid format, duplicate, portrait, landscape, poor
network, cancelled upload, retry, delete, replacement.

**8. Location (Phase 16).** Granted, denied, approximate, precise, GPS off,
network off, city detection, nearby discovery, distance filter. Confirm exact
coordinates are never exposed to another user.

**9. Discovery / Matching / Chat (Phases 17–19).** Every filter and every
transition: gender, age, distance, intent, interests, blocked, passed, matched,
deleted, inactive; like, pass, mutual like, match, duplicate, self like, block,
unmatch; send, receive, realtime, reconnect, read status, typing, media,
report.

**10. Notifications (Phase 20).** Foreground, background, terminated, tap, deep
link, permission denied. Confirm sensitive message text is not on the lock
screen.

> Expect FCM-dependent cases to fail: FCM cannot initialise in this build (no
> `google-services.json`). Foreground delivery via Supabase Realtime works;
> background/terminated push does not. Either configure FCM or accept and
> document the limitation before submission.

**11. Account deletion (Phase 21).** Delete a real test account. Verify the
account is gone, the session invalidated, the profile removed, photos deleted,
and authenticated access impossible afterwards.

### WHAT TO PROVIDE BACK
A results table: item, PASS / FAIL / NOT VERIFIED, device model, Android
version, date, evidence (screenshot or log excerpt).

### HOW TO VERIFY
Any FAIL blocks launch. Record them honestly — a real FAIL found now is far
cheaper than a rejection or a 1-star review after launch.

---

## §6 — Play Console account and App content declarations

### ACTION
Create/complete the Play Console listing and every App content declaration.

### WHY REQUIRED
Blocker 5. Play Console declarations require your Google account and cannot be
submitted programmatically. All the text is prepared; entering and submitting
it is yours.

### EXACT STEPS

**1. Create the app.**

- Play Console → **Create app**
- Language: English · Name: `Weekend — Dating & Matchmaking` · Category:
  **Dating**
- Declarations: contains **ads**, **not** a kids app, target audience **18+**

**2. Complete developer verification** (identity, address, contact email,
phone). New personal accounts must also pass **device verification**.

**3. App content:**

| Section | Source of truth |
|---|---|
| Privacy policy | §2 URL — **must be live first** |
| Ads | `docs/store-listing.md` §9 |
| App access | §7 below |
| Content rating | `docs/store-listing.md` §5 — expect **Mature 17+** |
| Target audience | `docs/store-listing.md` §6 — **18+ only** |
| News / COVID / Government / Financial / Health | No |
| Data safety | `docs/google-play-data-safety.md` — **device IDs = No** |
| Data deletion | In-app **and** a web request URL — must be live |
| Account deletion | Reachable in-app — verify on device (§5) |
| Child Safety Standards | Complete — needs a named contact |
| Families policy | Not a families app |

**4. Upload the signed AAB** — only after §3 produces a production-signed
artifact. Never a debug-signed AAB.

### THE FCM DECISION (before submitting Data safety)

`docs/google-play-data-safety.md` says **Device identifiers = No**, because FCM
cannot initialise in the shipped build. That is honest and matches the binary.
Choose one:

- **(a) Keep it inert** — ship without remote push, declare no device IDs.
  Smallest change. Document that notifications are foreground-only.
- **(b) Make FCM work** — create a Firebase project, run `flutterfire
  configure`, add `android/app/google-services.json`, apply the
  `com.google.gms.google-services` plugin, and **write a backend sender** (none
  exists today). Then declare the FCM token as collected and shared with Google
  for push delivery.

Declaring an FCM token that is never generated would be a false statement in a
Google-owned form. Do not do it.

### CHILD SAFETY

Play requires, for a dating app with user-generated content:

- a **named child-safety contact** with a monitored email address
- a published **child-safety policy** URL (§2)
- confirmation that the app **excludes minors** — true, via migration 028

Complete the **Child Safety Standards** questionnaire only after §4 proves the
---

## §7 — Reviewer (App access) account

### ACTION
Create a dedicated account for Google's review team.

### WHY REQUIRED
Weekend requires sign-in, so Play requires working credentials. Using a real
user's private account would expose their data to a Google review and to anyone
who later finds the listing.

### EXACT STEPS

**1. Create** `play-reviewer@weekend.app` (or similar) in the **live**
environment — not a local database.

**2. Seed it so the app does not look broken:**

- adult date of birth (18+)
- gender and interests completed
- **at least 4 approved photos** (the profile cannot become discoverable below
  the 4-photo minimum, so discovery will look empty without them)
- ensure a few other active profiles exist nearby so discovery has content
- leave MFA **off** so the reviewer is not locked out
- leave passkey enrolment empty

**3. Paste the navigation instructions** from `docs/store-listing.md` §7 into
the App access form.

### WHAT TO PROVIDE BACK
The reviewer username and password — to be entered **directly into Play
Console only**, never into a document, a commit or a chat message.

### HOW TO VERIFY
Sign out, sign in as the reviewer on a device, and walk every section listed in
the navigation instructions. Confirm each one opens.

---

## §8 — Closed testing

### ACTION
Run a closed test with at least 12 real testers for the required continuous
period (typically 14 days) before applying for production access.

### WHY REQUIRED
Blocker 2. Current state: **0 testers, 0 days**. For a new personal developer
account, Google requires 12 testers opted in continuously for 14 days before
production access is granted.

**This cannot be manufactured and was not.** Tester counts, opt-in dates and
feedback must be real. Claiming otherwise would be a false statement to Google
and a policy breach.

### EXACT STEPS

**1. Set up the track.** Play Console → **Testing → Internal testing** to
validate, then **Closed testing → Create track**.

**2. Recruit 12+ real people.** Track them honestly:

| Tester | Email | Opt-in date | Device | Android version | Issues | Feedback | Fixed |
|---|---|---|---|---|---|---|---|
| | | | | | | | |

**3. Upload a real signed build** to the closed track (§3 first).

**4. Run the full 14 days continuously.** Any tester opting out resets the
clock. Do not remove inactive testers to keep the count up.

**5. Triage feedback and ship fixes.** Crashes, ANRs, signup/login failures,
profile, discovery, chat, notifications, permissions, performance.

**6. Only after the period genuinely elapses** apply for production access:
**Testing → Closed testing → Apply for production**.

### WHAT TO PROVIDE BACK
The tester table with **real** dates, and the production-access approval.

### HOW TO VERIFY
Play Console shows the closed test as completed and production access granted.

---

## Closing note

The app is **NO-GO** until §1–§8 are genuinely complete. The repository is in
the strongest verified state available without your accounts, your hardware
and your keystore:

- the release-signing guard is proven to refuse a debug-signed build
- the Data Safety declaration now matches the shipped binary
- the verification suite is green (343 Python checks, 295 Flutter tests)
- the icon and feature graphic are generated at Play's exact dimensions
- the true state of the public web surface is documented rather than assumed

No claim in any of these documents was produced by inference, and no blocker
was marked PASS on the basis of code inspection alone.
age enforcement actually works on the live database. Answering it before then
would be certifying something unverified.

### WHAT TO PROVIDE BACK
Confirmation that each App content section is submitted, plus the chosen FCM
option (a) or (b).

### HOW TO VERIFY
Play Console shows every section green before **Save and publish**.
$ flutter devices
Windows (desktop) • Chrome (web) • Edge (web)
```

Passkeys, MFA, the biometric app lock, photo upload, notifications and account
deletion **cannot** be verified without hardware. Android Credential Manager,
the fingerprint prompt and the Photo Picker all behave differently on an
emulator, and an emulator's software fingerprint is not evidence.

**No PASS may be recorded for these from code inspection.** Nothing below was
run.

### EXACT STEPS

**1. Connect the device.** USB debugging on, then:

```bash
adb devices
flutter devices
```

**2. Install the release build** (§3 must be done first — a debug build cannot
test Play App Signing or release passkeys):

```bash
flutter build apk --release
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

**3. Authentication (Phase 11).** Record PASS / FAIL / NOT VERIFIED for:

```
Signup
Signin
Logout
Session restoration (kill and relaunch)
Email verification (if enabled)
Password recovery (if enabled)
Passkey sign-in
MFA enrolment + challenge
Account recovery
```

**4. Passkeys (Phase 12).** The full ceremony must work:

```
Continue with Passkey
  -> Android Credential Manager
  -> biometric / device credential
  -> challenge -> server verification
  -> Supabase session -> authenticated app
```

Then sign in again after **logout**, after **app restart**, and after **process
death** (`adb shell am kill com.weekend.app`).

> Passkeys on a **release** build require `assetlinks.json` to list the release
> certificate SHA-256. If this fails while the debug build works, the cause is
> the asset-links fingerprint, not a code bug — see §3.

**5. MFA (Phase 13).** Enrol, verify by OTP, log out, log back in, pass the 2FA
challenge. Then the negative cases — all four **must fail**:

```
Incorrect OTP                          -> FAIL
Expired OTP                            -> FAIL
Replay OTP                             -> FAIL
Disable without required verification  -> FAIL
```

**6. Biometric app lock (Phase 14).** The known bug:

```
Open Weekend -> enable biometric lock -> background the app -> reopen
EXPECT: biometric prompt appears
```

Also test: failed fingerprint, device-PIN fallback, process death, restart,
successful unlock.

**3. Inspect migration history.**

```bash
supabase migration list --linked
```

Expect `027` and `028` to be **pending**, and `001`–`026` applied.

**4. Read the SQL before applying it.**

```bash
cat supabase/migrations/027_device_tokens_and_mode_queries.sql
cat supabase/migrations/028_adult_only_enforcement.sql
```

Both are non-destructive: `027` creates a new table and replaces a function;
`028` creates triggers, adds functions and replaces `search_profiles`.
Migration 028 emits a NOTICE counting under-18 and null-DOB rows first — note
those numbers, because the section that follows decides what to do with them.

**5. Apply.**

```bash
supabase db push --linked
```

**6. Confirm the recorded history.**

```bash
supabase migration list --linked
```

027 and 028 must show as applied with version numbers matching the filenames.

### HOW TO VERIFY

```bash
apksigner verify --verbose --print-certs \
  build/app/outputs/flutter-apk/app-release.apk | grep -i "SHA-256\|DN:"
```

Expect something like `CN=Weekend, OU=..., O=..., L=..., ST=..., C=...`.
Record the SHA-256 fingerprint — Play App Signing needs it to enrol the upload
key, and `assetlinks.json` needs it for passkeys to work on a release build.

### THEN: PLAY APP SIGNING

After the first AAB is uploaded:

1. **Play Console → Setup → App integrity → App signing** → enrol in Play App
   Signing (mandatory for new apps).
2. Choose "Use Play App Signing for app signing key security" so Google holds
   the app-signing key and your upload key is only for uploads.
3. Record Play's app-signing certificate SHA-1 and SHA-256.
4. Add **both** fingerprints to `assetlinks.json` so passkeys work on the Play
   build (debug and release certs are different).
5. Enrol in **Play App Signing** for the upload key, and enable **Play Integrity
   API** if desired.

**Never upload the debug-signed AAB.** Doing so consumes the first signing key
irreversibly.

### AND: BACK UP THE KEY

Store the keystore, its passphrase and the alias in a password manager
(1Password/Bitwarden/Vault), plus one offline encrypted copy. Record the SHA-256
fingerprint in your team documentation.
Once the URLs are live, add a "Legal" section to
`lib/features/settings/settings_dialog.dart` and the onboarding flow, linking
all five via `url_launcher` (already a dependency).

### WHAT TO PROVIDE BACK
The five final public URLs.

### HOW TO VERIFY

```powershell
$urls = @('https://<host>/privacy','https://<host>/terms',
          'https://<host>/community-guidelines','https://<host>/safety',
          'https://<host>/child-safety')
foreach ($u in $urls) {
  $r = Invoke-WebRequest -Uri $u -UseBasicParsing
  "{0} -> {1}, {2} bytes" -f $u, $r.StatusCode, $r.RawContentLength
}
```

Then confirm each is genuine:

- each response is **more than 1 KB** (the parked stub is 114 bytes)
- the body contains "Weekend"
- the body contains the expected heading ("Privacy", "Terms", ...)
- no response contains `window.location.href="/lander"`

Check from a phone browser and while signed out.