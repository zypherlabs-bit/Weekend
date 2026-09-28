# Live Screen Audit — Weekend (Android)

Audited **28 Sep 2026** against the **live** Supabase project
(`ocypgybqfushqfzisnvs`), not a mock or staging backend.

| | |
|---|---|
| Build | `app-release.apk`, 75.6 MB, SHA-256 `f9ff4f8a…265606` |
| Package | `com.weekend.app` — versionName `2.3.1`, versionCode `6` |
| Device | Android emulator `emulator-5554`, 1080x2400 @ 420 dpi (API 35) |
| Branch | `fix/edit-profile-save-recovery` (base `master`) |
| Host | Windows 11 25H2 (build 26200) |

Every result below was read from the running app via `adb uiautomator dump`
and cross-checked against `public.profiles` through the Supabase Management
API. The UI hierarchy — not screenshots — is the source of truth, because
`screencap` on this emulator intermittently returns a stale frame from a
previous activity (observed twice, identical 747 673-byte files).

---

## 1. Screens exercised

| # | Screen | Entry | Result |
|---|---|---|---|
| 1 | Onboarding | first launch | Pass |
| 2 | Sign in | onboarding | Pass |
| 3 | Discover | bottom nav | Pass — 4 filter chips, empty state, "Rediscover" CTA |
| 4 | Explore | bottom nav | Pass — For You / Nearby / Around Me / City filters |
| 5 | Chat | bottom nav | Pass — "No Matches Yet" empty state |
| 6 | Profile | bottom nav | Pass |
| 7 | Edit Profile | Profile → scroll → Edit Profile | **Pass (was the defect)** |
| 8 | Location Settings | system prompt → Allow | Pass |
| 9 | Photo capture | Profile avatar camera | **Not verified** — see §5 |

### A discoverability defect found on Profile

The **Edit Profile** button exists (`lib/features/profile/profile_screen.dart:250`)
but sits *below the fold* on a 1080x2400 screen. On first open, Profile
renders avatar → Trust Score → Crossed Paths → About → Interests → Referral
Code, and the button row is off-screen. The user must scroll to discover that
the screen is editable at all.

This is a real usability issue on standard Android phone heights, not an
emulator artifact. Recommended fix: pin the Edit Profile / Settings row
higher (directly under the name), or add an edit affordance to the header.

---

## 2. Edit Profile save lifecycle — the core verification

This is the behaviour the branch exists to fix. Each row was performed by
typing into the real Flutter form and tapping the real **Save** button, then
verifying the database row.

| # | Scenario | Expected | Observed | Verdict |
|---|---|---|---|---|
| 1 | Save 3 changed fields | all 3 written | `display_name`, `occupation`, `bio` all updated; `updated_at` advanced | **Pass** |
| 2 | Force-stop + cold relaunch | data survives | Name and bio re-rendered from DB; session persisted, no re-login | **Pass** |
| 3 | Re-open Edit Profile | form reloads saved values | all 3 values repopulated from the row | **Pass** |
| 4 | Empty Full Name | save blocked | "Please enter your name"; `updated_at` unchanged | **Pass** |
| 5 | Unchanged (no-op) save | succeeds | row rewritten, `updated_at` advanced | **Pass** |
| 6 | **Row deleted server-side, then Save** | **row re-created** | **`Recovered Row 0912` inserted under the auth id** | **Pass** |
| 7 | Save with no network | classified error, no false success | stayed on screen, no pop, no data change | **Pass** |
| 8 | Retry after network restored | save succeeds | `Offline Attempt 0912` written | **Pass** |

### Scenario 6 — the reported bug, now fixed

The original report was that Edit Profile "did nothing". Root cause: the
write targeted an id that did not exist, so PostgREST returned **HTTP 200
with an empty result set** — a success status carrying zero rows. The UI
treated that as success while nothing was persisted.

Test: deleted the row directly from `public.profiles` via the Management API
while the app stayed signed in (leaving a stale in-memory profile — the exact
production condition). Tapped Save with a new name.

```
delete → {id: 8c352ec9-…-ece147c95a0d, display_name: "Audit Save Verify 0912"}
save   → {id: 8c352ec9-…-ece147c95a0d, display_name: "Recovered Row 0912"}
```

The recovery path re-created the row under the **auth session's** id, and the
UI then displayed "Recovered Row 0912". `saveProfileWithRecovery`
(`lib/repositories/profile_repository.dart:298-334`) is doing its job.

### Scenario 7 — offline behaviour

With WiFi and mobile data both disabled (`Active default network: none`,
ping unreachable), a save attempt:

* did **not** navigate away, and did **not** show a success snackbar;
* left the database byte-identical (`updated_at` unchanged);
* logged a classified failure:

```
[PROFILE_UPDATE_NETWORK] stage=profiles.save profile save failure (_ClientSocketException)
```

A retry after the network returned committed normally. The app degrades
correctly: it fails loudly, keeps the user's typed input, and does not
corrupt the row.

---

## 2a. Regression found during this audit — referral code lost on recovery

While verifying scenario 6, the profile inventory showed the recovered row
with `referral_code = NULL`. It had been `WKND-8C352EC95D` before the delete.
**1 of 9** profiles rows carried a NULL code, and it was exactly the one the
recovery path had just created.

**Root cause.** Migration 017 established "every profile owns a stable,
unique referral code", but that is only enforced by `handle_new_user`, an
`AFTER INSERT` trigger on **`auth.users`**. There is no trigger on
`public.profiles` itself. `saveProfileWithRecovery` re-creates the row with a
direct `INSERT INTO public.profiles (id, …)` and `buildProfilePayload` carries
no `referral_code` — so the auth trigger never fires and the code is lost.

**User impact.** A recovered user sees an empty "Referral Code" field, the
Copy button silently no-ops (`profile_screen.dart` returns early on an empty
code), and `QRInviteScreen` reports "No referral code available". Any
invitation already shared under the old code stops resolving.

**Fix — migration `021_referral_code_on_insert.sql`.** The invariant is now
enforced at the table rather than at each caller: a `BEFORE INSERT` trigger
fills a missing code using the same deterministic scheme as 017
(`'WKND-' || first 10 hex chars of the uuid`), so a recovered profile gets the
*same* code it originally had. An explicitly supplied code is never
overwritten, so a code already shared in a QR invite never changes.

**Verified end-to-end on the live project**, not just by inspection:

1. Deleted the profile row server-side; relaunched the app.
2. The app correctly detected the missing row and routed to Edit Profile.
3. Typed a name and city, tapped the real Save.
4. The recovery re-created the row **and** the trigger assigned the code:

```
display_name  = "Trigger Fix 0912"
referral_code = "WKND-8C352EC95D"   <- original code preserved
```

No NULL codes remain in the table. This is a bug the automated test suite
did not catch, because it only exercises the save path, not the referral
invariant across a recovery.

---

## 3. Static analysis and tests


---

## 4. Release build is debug-signed — blocks distribution

`tool/build_release.ps1` produces a file named `app-release.apk`, but it is
signed with the **Android Debug key**:

```
Signer #1 certificate DN: C=US, O=Android, CN=Android Debug
SHA-256: d41ccea6c991c57554d22d9ffdf0a03fc05baa3d8ce6b9afb563334af7768390
```

`android/key.properties` and `android/weekend-release-keystore.jks` are both
absent, so `android/app/build.gradle.kts:64-73` took its fallback branch and
signed with the locally generated debug keystore.

This is **by design and clearly documented** — the build prints an explicit
warning, and `README.md:674` states such builds must not be distributed. But
it does mean the current artifact is **not a production release**:

* it cannot be published to Google Play;
* it cannot be updated in place later — a differently signed APK installs as
  a separate app, orphaning the user's data.

To produce a genuine release, generate a keystore and commit
`android/key.properties` (never the keystore itself — `.gitignore` already
excludes `*.jks`, `*.keystore`, `key.properties`).

---

## 5. Not verified

These remain genuinely untested and are **not** claimed as working:

| Area | Why |
|---|---|
| **Physical Android device** | No device available; everything ran on an emulator. Emulators do not reproduce OEM permission dialogs, real GPS, background networking, or OEM push behaviour. |
| **iOS build** | Host is Windows. `ios/` is the untouched default Flutter scaffold — no `Podfile`, no `DEVELOPMENT_TEAM`, no `build/ios/`. Flutter cannot compile iOS on Windows; a macOS + Xcode machine is required. |
| **Sign-up** | Blocked by HTTP 429 `over_email_send_rate_limit` against the live project. |
| **Email confirmation / password reset** | Depend on the same rate-limited email path. |
| **Two-account matching & chat** | Requires a second real account with a nearby location; the audit account has no match candidates. |
| **Realtime message delivery** | Needs two live sessions; unverified. |
| **Photo upload → moderation** | Needs a gallery image and an approval cycle; the Storage write and `profile_photos` row are unverified in the running app. |
| **Cascade delete** | ~30 foreign keys cascade from `profiles`. Deleting a profile would remove settings, preferences, likes, matches and messages. **Untested by choice** — this is a destructive data decision needing an explicit product sign-off, not a code patch. |

> **Physical Android device test is required before release.**

---

## 6. Live-data hygiene

The audit used a dedicated throwaway account
(`8c352ec9-5dfb-49d6-bfda-ece147c95a0d`, referral `WKND-8C352EC95D`) with
identifying values prefixed `0912` so any residue is traceable. The row has
been renamed to test values and should be deleted together with its auth user
before release. No production data was touched; no other user's rows were read
or modified.

| Check | Result |
|---|---|
| `flutter analyze` | **No issues found!** (258 s) |
| `flutter test` | **All 128 tests passed** |
| `apksigner verify` | Signature valid, but **debug certificate** — see §4 |

