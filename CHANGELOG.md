# Changelog

All notable changes to Weekend are documented here. This project follows a
handful of conventions that are worth stating once:

- **Every change is verifiable.** A feature is only listed as working when the
  matching check in `python tests/python/run_all_tests.py` reports `PASS`.
  Anything that could not be proven is listed under *Not verified* with the
  evidence that is missing, rather than being quietly dropped.
- **Server-side enforcement.** Search filters, distance computation and access
  control live in PostgreSQL, not in the client.

## [2.7.0] - 2026-09-30

### Added - Date Ideas UI (was BROKEN)

The `date-ideas` Edge Function was implemented server-side but never invoked from the client. Now surfaced in the chat screen:

- `lib/repositories/date_ideas_repository.dart` — calls the `date-ideas` Edge Function via `client.functions.invoke()`
- `lib/widgets/date_ideas_widget.dart` — `DateIdeasButton` + `DateIdeasSheet` (bottom sheet with loading/empty/refresh states)
- `generateDateIdeas()` method on `WeekendNotifier` (`lib/providers/weekend_provider.dart`)
- Wired `DateIdeasButton` into `ChatScreen` app bar
- `test/date_ideas_test.dart` (3 tests for no-backend fallback behavior)

### Added - GitHub page documentation (Phases 0-4)

- `docs/github-page-baseline.md` — baseline snapshot of repo state
- `docs/product-feature-audit.md` — 44-area feature audit
- `docs/github-user-journey.md` — user journey mapping
- `docs/github-discovery.md` — GitHub topics and discovery strategy

### Changed - README & docs

- README known limitations: updated icebreakers/date ideas entry — date ideas now surfaced in chat; icebreakers remain server-side only
- README roadmap: date ideas marked shipped; icebreakers remain planned
- Updated `docs/feature_parity_matrix.md` summary to reflect 44 COMPLETE, 1 MISSING
- README download section references v2.7.0

### Verification

- `flutter analyze` — No issues found!
- `flutter test` — 295 passed (292 existing + 3 new date ideas tests)
- `python tool/seo_audit.py` — 18 PASS, 0 FAIL, 1 WARNING (online check skipped)

---

## [Unreleased]

### Changed - README rebuilt as a user-first landing page

- README restructured for end users: hero, screenshots, Why Weekend, How it
  works, per-feature sections with implementation paths, a free-dating
  comparison, a v2.6.0 download CTA (release link + direct APK + SHA-256), a
  17-question FAQ, known limitations, roadmap and a documentation index.
- **Screenshot honesty overhaul.** Four real captures from a running build were
  added (`docs/screenshots/onboarding-welcome.jpg`,
  `onboarding-discover.jpg`, `onboarding-plans.jpg`,
  `signup-email-step.jpg`); the gallery now separates real captures from brand
  artwork with an explicit note. Seven duplicate files were deleted — `docs/`
  previously held 13 image files containing only 6 unique images; every image
  is now unique bytes (enforced by the audit below).
- **Stale "bundled sample data" claims corrected** in README,
  `docs/getting-started.md`, `docs/supabase.md`, `docs/installation.md` and the
  bug-report template. Since 2.1.0 unconfigured builds fabricate no data;
  verified by running an unconfigured build on an emulator (onboarding and the
  sign-up wizard work on-device; account actions report "not connected to a
  backend").
- New: `docs/SEO.md` (keyword strategy, README structure, image and version
  rules) and `tool/seo_audit.py` (read-only PASS/FAIL/WARNING audit). Latest
  run: `python tool/seo_audit.py --online` — 19 PASS, 0 FAIL, 0 WARNING.
  `flutter analyze`, `flutter test` (231 tests) and
  `python tests/python/run_all_tests.py` are green.

## [2.6.0] - 2026-09-29

Audit and repair of Edit Profile, Profile Card, Passkeys, the biometric app lock
and 2FA. Root causes were identified before anything was changed; each is listed
with the evidence that established it.

### Fixed - passkeys could not work (three independent causes)

- **Server: passkeys were disabled.** The live project reported
  `passkeys_enabled: false` and an empty WebAuthn relying-party ID, so every
  request answered `404 passkey_disabled`. Passkeys are now enabled, with
  `webauthn_rp_id = ocypgybqfushqfzisnvs.supabase.co`, the matching RP origin,
  and a real Site URL (it was `http://localhost:3000`).
- **Build: Credential Manager was never initialised.** The Android plugin holds
  its `CredentialManager` in a `lateinit var` assigned only by `init()`, so every
  ceremony threw before starting. `PasskeyService.ensureInitialized()` now
  performs it once and caches the in-flight future.
- **Build: the relying party could not be associated.** `AndroidManifest.xml`
  declared `weekend.app` - a parked domain serving no `assetlinks.json`. The RP
  ID is now derived from `SUPABASE_URL` at build time
  (`gradle :app:logPasskeyConfig`) and baked in via `${weekendRpId}`, verified
  present in the shipped APK.
- WebAuthn options are now shaped defensively. `userVerification` is forced to
  `required` on both ceremonies, and credential fetch is passkey-only. The
  plugin's `AuthenticatorSelectionCriteria.fromJson` throws on the keys GoTrue
  omits, so the selection criteria are built from the raw map instead.
- New: `lib/services/passkey_service.dart`, `docs/passkeys.md`,
  `tool/gen_assetlinks.py`, `test/passkey_service_test.dart`.

### Fixed - the biometric app lock never re-locked the app

- The lock was an `OverlayEntry` inserted from the state of the widget that
  *builds* `MaterialApp.router` - above the MaterialApp, where no Overlay
  exists. The call threw inside an async gap and was swallowed, which is why
  the prompt never appeared. It is now a real widget installed through
  `MaterialApp.builder` (`BiometricLockGate`).
- `AppLifecycleState.inactive` was treated as backgrounding. Android emits it
  whenever a system surface takes focus - including Android's own
  `BiometricPrompt` and Credential Manager sheet - so the lock re-armed while the
  prompt was on screen, and an `inactive -> resumed` pair unlocked the app with
  no authentication at all. `AppLockService` now ignores `inactive` and arms only
  on `paused` / `hidden` / `detached`.
- Unlocking no longer calls `context.go('/home')`, which threw the user out of
  whatever they were doing.
- New: `lib/services/app_lock_service.dart`, `test/app_lock_lifecycle_test.dart`.

### Added - 2FA recovery codes and re-authenticated 2FA changes

- Supabase TOTP has no native recovery codes, so a lost phone locked the account
  permanently. `mfa_recovery_codes` stores only a per-user salted SHA-256;
  codes are CSPRNG-generated server-side and consumed atomically, so one code
  cannot be spent twice.
- Disabling 2FA now requires a live authenticator code and an AAL2 step-up
  first. GoTrue already enforces AAL2; asking explicitly means a stolen AAL1
  session gets a clear message instead of a silent failure.
- New: recovery-code management in Settings -> Security, `tests/python/test_2fa.py`.

### Added - mature profile experience

- **Photos**: add, replace, reorder, set-primary and delete, with per-tile
  progress. Order is persisted in `profile_photos.sort_order` through
  owner-scoped RPCs, and the 4-photo minimum is enforced by a database trigger
  (`profile_requirements`, configurable) as well as the UI.
- **Prompts**: 15 question prompts in two sections, plus lifestyle attributes,
  a normalised interest taxonomy and languages. Blank answers are dropped and
  the count shown on the card is disclosed rather than silently truncated.
- **Save flow**: validation -> auth -> photo minimum -> write -> prompts ->
  interests -> preferences -> server confirmation -> refresh -> navigate. A
  failure keeps the user on the screen with a retry.
- New: `lib/models/profile_schema.dart`.

### Fixed - fields that were rendered but never saved

- **Date of birth** was collected by the form but never written; the model
  carries a derived `age`, so the user's real birth date was discarded. Now
  persisted, with an 18+ check.
- **Languages** were editable but never written.
- **Interests** were only deleted when the new list was non-empty, so
  deselecting the *last* interest silently did nothing.
- **Lifestyle columns** are written only when the value satisfies the column's
  CHECK constraint, so a save can neither violate it nor erase good data.

### Added - progressive profile card

- Media-first: a full-bleed photo pager with the identity overlaid, and the
  rest behind an explicit "Show more" sheet. Hierarchy is media > name > age >
  city > distance > bio > interests > relationship intent > prompts >
  lifestyle. An unknown age is omitted rather than rendered as 0.
- Location stays privacy-safe: only the server's `distance_label` or a rounded
  "km away" string. The card contains no latitude or longitude.

### Fixed - database

- **Migration 025** (`profile_experience_and_mfa_recovery.sql`) adds photo
  ordering, the configurable photo minimum, prompt-shape validation, the
  interest taxonomy and MFA recovery codes. Applied to the live project.
- Migrations 022-024 were never applied (023 cannot be: it filters on
  `profiles.dating_profile_activated`, which no earlier migration creates). 025
  is written against the schema that is actually live and does not depend on
  023. That gap is still open and is listed under *Not verified*.

### Tests

- 231 Flutter tests (was 210) and 311 Python checks (was 306).
- New suites: `test_passkey.py`, `test_biometric.py`, `test_2fa.py`,
  `test_edit_profile.py`, `test_profile_card.py`, `test_profile_data.py`.
- Verified live against the running project: a wrong OTP is refused (HTTP 422),
  an RFC 6238 code computed from the real enrollment secret is accepted (200), a
  spent recovery code is refused, and GoTrue issues a real passkey challenge.
- `run_all_tests.py` now separates 32 verified checks from 10 that cannot be
  proven without a handset.

### Not verified

- **Passkey registration and sign-in on a physical handset.** No device was
  attached. The server half is verified; the Credential Manager half is not.
- **Passkey Digital Asset Links.** Android will not complete a ceremony until
  `https://<rp-id>/.well-known/assetlinks.json` proves the association, and
  Weekend controls no domain that serves it. `tool/gen_assetlinks.py` computes
  the real digests; publishing them is a deployment step. See
  `docs/passkeys.md`.
- **Fingerprint prompt, unlock, cancellation and wrong-finger behaviour**, and
  the on-device 2FA flows. All require a handset with an enrolled biometric.
- The release APK was signed with the Android **debug** certificate because
  `android/key.properties` is absent, so its asset-linkage digest differs from
  any future release-signed build.
## [2.5.1] - 2026-09-29

Bugfix release. Every change below was in the working tree and in no published
APK, which is why the installed app still behaved as it did in 2.5.0.

### Fixed - the biometric app lock could never open a prompt on Android

`MainActivity` extended `FlutterActivity`, which extends `android.app.Activity`,
not `FragmentActivity`. `local_auth_android` hosts the AndroidX
`BiometricPrompt` through a fragment and checks the foreground activity before
it will show anything, so it refused every attempt:

```
LocalAuthException(code: uiUnavailable,
                   description: 'The current Activity must be a FragmentActivity.')
```

`MainActivity` now extends `FlutterFragmentActivity`, the class AndroidX itself
documents for `BiometricPrompt`. The predictive-back comment block was rewritten
to match: `enableOnBackInvokedCallback` lives on `ComponentActivity`, which
`FlutterFragmentActivity` already extends, so the original justification for
staying on `FlutterActivity` no longer applies and the biometric requirement
outranks it. Back gestures still route into Dart through GoRouter.

### Fixed - biometric failures reported raw plugin strings

`BiometricAuthService` caught `PlatformException` and switched on `local_auth` 2.x
string codes (`'NotAvailable'`, `'NotEnrolled'`, ...). `local_auth` 3.x throws
`LocalAuthException` with a typed `LocalAuthExceptionCode`, so that handler never
matched a real plugin failure. Every failure fell through to a bare `catch` that
returned `e.toString()`, and the lock screen showed the user a raw
`LocalAuthException(code ..., ...)` string.

All of `LocalAuthExceptionCode` is now mapped explicitly, with the distinction
that matters most:

- `uiUnavailable` no longer masquerades as "no biometrics enrolled". Reporting it
  as `notEnrolled` sent the user to change settings that were already correct.
- `userRequestedFallback` is treated as a cancellation, so the retry button is
  offered instead of an error the user cannot act on.
- No code returns the plugin's own text. `test/biometric_error_mapping_test.dart`
  iterates every value in `LocalAuthExceptionCode` and asserts each one maps to
  an error code without leaking its description, so a future `local_auth` release
  cannot reopen the gap.

### Changed - intro videos run full-bleed on onboarding and sign-in

The clips were still boxed into a 180px panel above the sign-in form, and sat in
a column on the onboarding slides.

- Both screens now stack the player edge to edge behind the content, with a
  gradient scrim so the copy stays readable on the brighter frames.
- The scrim is wrapped in `IgnorePointer`, which is required rather than
  cosmetic: `RenderDecoratedBox` reports `hitTestSelf == true`, so without it
  the scrim would sit over the form and swallow taps meant for the text fields.
- Onboarding copy is `IgnorePointer`-wrapped too, so a horizontal swipe that
  starts on the text still turns the `PageView`.
- `IntroVideoPlayer` takes a `fit` parameter, and its fallback now honours the
  widget's `borderRadius` instead of a hardcoded 24, which is what full-bleed
  slides need.

### Fixed - the download links pointed at an APK that no longer exists

`README.md` and `docs/installation.md` advertised
`Weekend-v2.3.0-release.apk` through `releases/latest/download/`. That form is
broken by construction: `latest` resolves the tag dynamically, but the filename
in the path is static, so the link 404s as soon as the next release ships. Both
now name the current release against a pinned tag
(`releases/download/v2.5.1/...`).

`tests/python/test_release.py` gains two static checks that keep this from
rotting, and would have caught the state described above:

- `test_documented_version_matches_pubspec` - every `Weekend-vX.Y.Z-release.apk`
  named in a marketing doc must match the version in `pubspec.yaml`, because a
  stale name points at an asset that returns 404.
- `test_download_urls_are_not_pinned_to_a_stale_release` - rejects a versioned
  filename under `releases/latest/download/`.

### Verified

- `flutter analyze`: no issues
- `flutter test`: 208 passed
- The biometric fix is verified on the emulator rather than a device; the
  `DEVICE`-evidence checks in `python tests/python/run_all_tests.py` remain
  NOT VERIFIED here.

## [2.5.0] - 2026-09-28

### Added - intro videos on onboarding and sign-in

The three pre-login slides now play video instead of showing a static icon,
and the sign-in screen cycles the same three clips above the form.

- **`assets/videos/weekend{1,2,3}.mp4`** - the three clips, 115.7 MB of
  original footage compressed to 43.5 MB (-62%).
- **`lib/widgets/intro_video_player.dart`** - one reusable player shared by
  both screens, so the clip list has a single source of truth
  (`kIntroClips`).
- **`tool/compress_videos.py`** - the encoder. Re-runs are idempotent and
  re-verify quality instead of trusting the previous output.
- **`test/intro_video_player_test.dart`** - covers the clip catalogue and the
  player-failure path.

Quality is measured, not assumed. Every clip is re-encoded and gated against
a high-quality resized reference, and the build is rejected unless it holds:

| Clip | Source | Shipped | Size | SSIM | PSNR |
| --- | --- | --- | --- | --- | --- |
| `weekend1.mp4` | 2160x4096 | 1012x1920 | 8.72 MB | 0.9829 | 45.5 dB |
| `weekend2.mp4` | 2160x3840 | 1080x1920 | 4.98 MB | 0.9832 | 43.5 dB |
| `weekend3.mp4` | 1080x1920 | 1080x1920 | 29.80 MB | 0.9888 | 45.1 dB |

All three clear the SSIM >= 0.98 / PSNR >= 40 dB gates. `weekend1` is 1012px
wide rather than 1080 because its source is a 0.527 aspect ratio; padding or
stretching it to fill 1080 would have distorted it, so it ships at its native
shape and is centre-cropped in the layout.

Originals are preserved twice and neither copy is committed:
`assets/videos/source/` is gitignored, and an external copy lives at
`D:\WeekendVideosBackup`.

Player behaviour worth knowing about:

- Only the visible slide decodes; the other two pause and drop their frame
  callbacks, so a swipe never leaves three decoders competing.
- A clip that fails to load falls back to a gradient graphic. It does not
  throw and it does not leave a progress indicator spinning forever.
- `MediaQuery.disableAnimations` is honoured: no autoplay, and the sign-in
  carousel stops auto-advancing.
- The clips are muted and looping, and expose a manual pause control.

### Fixed - endless spinner on a failed intro clip

The loading indicator was shown while a clip was loading *and* after it had
already failed to load, so a broken asset left an animation running that never
stopped. Found because four existing widget tests began timing out on
`pumpAndSettle` once the player landed; `test/intro_video_player_test.dart`
now pins the behaviour.

### Fixed - committed merge conflict markers in this file

The v2.4.1 merge committed `<<<<<<< HEAD` / `=======` / `>>>>>>> origin/master`
into `CHANGELOG.md`, so every release since shipped a file with raw conflict
markers in it. Both sides were real release notes, so the resolution keeps the
union rather than picking a side: the `origin/master` content (the Edit Profile
referral-code recovery and the audit docs) belongs to unreleased work and now
joins the `## [Unreleased]` section, while the `## [2.4.1]` and `## [2.4.0]`
notes stay put. `tool/fix_changelog_conflict.py` performs the repair and is
safe to re-run.

Left alone deliberately: `## 2.4.0` appears twice (once under `# Changelog` at
the top, once as `## [2.4.0] - 2026-09-28` in the history below), and the file
carries two intro paragraphs. That duplication also predates this release. It
is cosmetic and reconciling it means deciding which branch's notes are
canonical, so it is flagged here rather than silently rewritten.

### Build size - please read before shipping

Adding the clips takes the release APK from **76.6 MB to 121.1 MB** (+58%) and
the app bundle to 101.8 MB. The videos are already-compressed H.264, so they
are stored in the APK rather than recompressed, and all 43.5 MB lands on every
install and on Play's delivery quota.

This is a deliberate trade and it is reversible. To shrink it, re-run
`python tool/compress_videos.py` after lowering `--max-height`/`--crf` in that
script, or move the clips out of the bundle and load them from a CDN. The
quality gates there will refuse an encode that visibly degrades, so the trade
stays an explicit decision rather than a silent one.

### Not verified

- **Playback on a physical Android device.** No device was connected, so
  real-device decode, first-frame latency and battery draw are unmeasured. The
  clips are H.264 / yuv420p with fast-start metadata at 1080x1920, which is
  within the range of every Android device the app supports (min SDK 24), but
  "should work" is not "has been seen to work".
- **Release APK on hardware.** The APK builds and installs in the sense that
  it was produced and its assets verified as present in the archive; it has
  not been installed and launched on a device.

## 2.4.0

### Added â€” Advanced search with server-side hard filters

- **`search_profiles` Postgres function** (migration 022). Enforces every hard
  filter with `AND` semantics in the database: gender / interested-in, age
  range, distance, relationship intent, city, interests, languages and the
  lifestyle attributes (smoking, drinking, exercise, children, pets). Soft
  signals (shared interests, intent match, completeness, verification, recency)
  affect `ORDER BY` only and can never admit a profile a hard filter rejected.
- **Discover / Search Filters screen** (`/search`, also reachable from the tune
  icon on Discover) with radius, gender, age, intent, city, interests,
  languages and lifestyle controls, plus removable filter chips.
- **Truthful empty state**: "No profiles match all your filters" with explicit
  *Adjust filters*, *Increase distance* and *Expand age range* actions. The app
  never relaxes a filter on its own.
- **New profile columns**: `interested_in`, `languages`, `smoking`, `drinking`,
  `exercise`, `pets`, `children`, `height_cm`, `prompts`, with CHECK
  constraints and GIN/btree indexes for the new predicates.
- **`SearchFilters` model**, `searchProvider`, and
  `DiscoveryRepository.searchProfiles`.
- Deleted, banned, rejected and opted-out accounts are excluded from search via
  the new `auth_user_state` view.

### Added â€” Verification suite

- `tests/python/` â€” a pytest-compatible suite that separates **STATIC**,
  **RUNTIME** and **DEVICE** evidence and reports only `PASS`, `FAIL` or
  `NOT VERIFIED`.
  - `test_project_structure.py`, `test_security.py`, `test_passkey.py`,
    `test_location.py`, `test_filter_logic.py`, `test_navigation.py`,
    `test_supabase.py`, `test_release.py`, `run_all_tests.py`.
  - `test_filter_logic.py` includes an executable reference implementation of
    the hard-filter contract, exercised with the specification's own fixture
    data (profiles Aâ€“D).
  - Emulator runs are explicitly **not** accepted as device evidence.
- `test/search_filters_test.dart` â€” 16 unit tests for the `SearchFilters`
  contract.
- `tool/apply_one_migration.ps1` â€” applies a migration statement-by-statement
  with a pre-flight structural check, so a truncated function body can never
  half-apply against the live project.

### Fixed

- **Fabricated age removed.** `get_nearby_profiles` and `get_matches_for_user`
  both ended their age expression with `else 25`, inventing an age of 25 for
  every profile without a stated birthday. Age is now `NULL`, and the UI
  renders "Age not stated".
- **Age hard filter can no longer be bypassed.** The old predicate kept
  profiles whose age was unknown (`date_of_birth is null or ...`). Because an
  unknown age cannot satisfy a requested range, those profiles are now
  excluded instead of passed.
- **Discovery modes are honoured.** `p_discovery_mode` was accepted and then
  ignored; `global` and `city` now actually ignore the radius.
- **`get_matches_for_user` excludes deleted accounts** and a blocked match.
- **Passkey implementation replaced.** The previous code drove the WebAuthn
  *MFA factor* API (`mfa.enroll(factorType: webauthn)` / `mfa.listFactors()`),
  both of which require an already-authenticated session â€” impossible during
  sign-up, and impossible during usernameless sign-in. It then posted the
  ceremony to `passkey-register` / `passkey-authenticate` Edge Functions that
  do not exist in this repository. It is now a real WebAuthn flow built on
  Supabase's native passkey API and the Android Credential Manager.
- **Passkey management UI** (Settings â†’ Passkeys) to register, list and remove
  passkeys.
- GoTrue error codes are mapped to safe, actionable messages instead of raw
  SDK text.

### Changed

- `supabase_flutter` raised to `^2.15.0`, the minimum that exposes
  `client.auth.passkey`. The old `2.8.4` pin could not have supported passkeys.
- Release builds now record their SHA-256 to `build/release/apk.sha256` so the
  verification suite can compare the local artefact against what GitHub
  actually serves.
- README documents the advanced-search filter contract, the passkey flow and
  the verification-status model.

### Not verified

- **Passkeys are not enabled on the live Supabase project.** The client is
  complete and the challenge endpoint is reachable, but the project answers
  `passkey_disabled`, so passkey sign-in does not work yet. The app says so
  rather than pretending. See the README for the dashboard steps.
- **No physical-device testing was performed.** No Android handset was
  connected; only an emulator was available, which is not accepted as evidence
  for Credential Manager, a real biometric prompt or the Android Photo Picker.
  `PASSKEY DEVICE TEST` and `PHYSICAL DEVICE TESTS` report `NOT VERIFIED`.

All notable changes to **Weekend** are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and
the project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
Releases are published as GitHub Releases with a versioned APK and a SHA-256
checksum.
## [Unreleased]

### Fixed - Edit Profile save failure for orphaned accounts

- Root cause: an authenticated user missing their `public.profiles` row made
  the save's `UPDATE ... WHERE id = auth.uid()` match zero rows â€” PostgREST
  answers that with `200 []`, surfaced as "The server did not save your
  profile".
- `ProfileRepository.updateProfile` now runs UPDATE â†’ (zero rows) â†’ confirm â†’
  INSERT under the session's own id â†’ verify, so a missing profile row is
  repaired on save instead of failing. Ownership stays derived from the auth
  session; the payload never carries an `id`.
- `WeekendNotifier.updateProfile` delegates the primary write to the
  repository, restores a missing `preferences` row, upserts `user_settings`
  with an explicit `onConflict: 'user_id'`, and pre-checks bios against the
  014 `detect_social_media_in_text` RPC (the DB trigger stays the enforcement
  authority).
- New `ProfileSaveException` with stable `PROFILE_UPDATE_*` diagnostic codes:
  failures are classified (auth / RLS / constraint / validation / network /
  schema / no-row / unknown), logged as code+stage only, and shown to users as
  actionable text â€” never raw PostgREST/row data, never a fake success.
- New migration `020_orphan_profile_repair.sql` (idempotent): backfills
  `profiles`/`user_settings`/`preferences` for orphaned auth users using only
  validated signup metadata (malformed values become NULL, never a failed
  migration), hardens `handle_new_user` (conflict-safe inserts, exception-safe
  date parsing â€” fixes the live HTTP 500 signups caused by malformed
  `date_of_birth`/`gender` metadata), re-asserts the `on_auth_user_created`
  trigger and RLS. After applying, run `supabase/test/orphan_audit.sql` and
  expect all three orphan counts to be 0.
- New `test/profile_save_recovery_test.dart`: payload/ownership, INSERT
  recovery, 23505 race retry, honest no-row failure, and error-classification
  contract tests.

### Fixed - LIVE-only auth

- Auth repository auth calls now throw a clear "not connected to a backend"
  error instead of silently returning. The silent return made signup look
  accepted ("check your email") on builds with no backend while nothing was
  ever sent.
- Release CI refuses to build when `SUPABASE_URL` / `SUPABASE_ANON_KEY`
  secrets are missing or still placeholders, so a release APK can never be an
  offline demo build.

### Added - passkey plumbing

- Credential-manager based passkey save/get in `auth_repository.dart`
  (`credential_manager` 5.1.0).

### Fixed - Android release build

- `credential_manager_android` 4.1.0 configures `kotlin { ... }` in its own
  `build.gradle` without ever applying the Kotlin plugin â€” it assumes AGP 9's
  built-in Kotlin (its buildscript pins AGP 9.0.1). This project resolves the
  Android Gradle plugin to 8.11.1, so `assembleRelease` died with
  "Could not find method kotlin() ... on project ':credential_manager_android'".
  The root `android/build.gradle.kts` now puts `kotlin-gradle-plugin:2.2.20`
  (matching `settings.gradle.kts`) on the buildscript classpath inherited by
  subprojects and applies `org.jetbrains.kotlin.android` to that module the
  moment its Android library plugin is attached â€” before its script reaches the
  `kotlin { ... }` block.

### Fixed - Edit Profile recovery dropped the user's referral code

Found while auditing `fix/edit-profile-save-recovery` against the live
project. The recovery path introduced in this branch re-creates a missing
`profiles` row with a direct `INSERT`, which bypasses `handle_new_user` â€” the
only place a `referral_code` is ever assigned. A recovered profile therefore
came back with `referral_code = NULL`, silently breaking the Referral Code
field, its Copy button, QR invitations, and any invite link already shared.

- New migration `021_referral_code_on_insert.sql`: a `BEFORE INSERT` trigger
  on `public.profiles` fills a missing code using the same deterministic
  scheme as 017, so a recovered profile keeps its *original* code. An
  explicitly supplied code is never overwritten. Idempotent; RLS untouched.
- Verified end-to-end on the live project: after deleting the row and saving
  from the app, the profile returned with its original `WKND-8C352EC95D`.

### Added

- `docs/LIVE_SCREEN_AUDIT.md` â€” per-screen audit of the Android build against
  the live backend, including the 8-scenario Edit Profile save/recovery
  lifecycle and the referral-code regression.
- `docs/PRODUCTION_VERIFICATION_REPORT.md` â€” release readiness, blockers, and
  what remains unverified.
- `scripts/audit_weekend_live.py` â€” read-only live-project health checks
  (migrations, orphans, blank names, RLS coverage, social-handle pattern,
  referral-code invariant). `--cleanup` deletes only rows carrying the
  `WKND_AUDIT` marker.
- `tool/ui_drive.ps1` â€” small adb wrapper for driving the app on an emulator
  during audits.

## [2.4.1] - 2026-09-28

Reconciles the parallel v2.4.0 work with the hard-filter and photo-minimum
branch. Both sides independently fixed the same discovery defects, so this
release carries the union rather than choosing a side.

### Added

- **Preferred Match screen** (`/preferred-match`): gender, age range, distance,
  city, location mode, relationship intent, interests, lifestyle and
  languages. Every selection is a hard filter and the screen says so.
- **Minimum 4 photos**, enforced on both sides. `minimum_profile_photos()` is
  the single source of truth in SQL; a trigger keeps
  `profiles.dating_profile_activated` in sync and discovery excludes any
  profile that has not met it.
- **`get_my_profile_completion` RPC**, so the UI and the filter can never
  disagree about what is complete.
- **Open Source screen** with a QR code resolving to this repository
  (Settings -> Open Source).

### Security

- **`search_path` pinned on every SECURITY DEFINER function** (migration 024).
  Thirteen functions - including the `handle_new_user` auth trigger and the
  search RPCs added in 020-022 - were created without `set search_path`, which
  lets an attacker shadow an unqualified name with an object in a writable
  schema and run code as the definer. The sweep is driven from
  `pg_proc.prosecdef` so a function added tomorrow cannot be missed, and it
  raises if anything is left unpinned.
- Removed a live Supabase anon key committed to `.vscode/launch.json`.

### Fixed

- **The Profile screen never displayed the user's age.** Name and age are now
  rendered together, with the city on its own line rather than crammed into
  the relationship-intent pill.
- **The image pipeline declared a size budget but never enforced it.**
  `optimize()` now steps the quality tier down until the payload fits instead
  of letting a multi-megabyte file fail at Storage with an opaque error, and
  rejects sources below a minimum resolution so a 64px icon cannot be
  upscaled into a blurry "profile photo".
- **The security scan matched its own detection patterns.** It now excludes
  itself from the file walk.

### Not verified on a device

Passkey registration, the four-photo upload flow on a real handset, and
Google Play Console review all require hardware or a console and are reported
as NOT VERIFIED by the verification suite.

## [2.4.0] - 2026-09-28

Exact-match discovery, a real Preferred Match screen, and four defects that
were silently returning wrong results.

### Added

- **Preferred Match screen** (`/preferred-match`). Gender, age range, distance,
  city, location mode, relationship intent, interests, lifestyle and
  languages. Every selection is a hard filter, and the screen says so.
- **`search_profiles` RPC** (migration 023) â€” server-side filtering with strict
  AND semantics. A candidate is returned only if it satisfies *every*
  supplied criterion. Soft signals (shared interests, activity, verification,
  trust) rank the eligible set and never decide eligibility.
- **Minimum 4 photos**, enforced on both sides. `minimum_profile_photos()`
  is the single source of truth in SQL; a trigger keeps
  `profiles.dating_profile_activated` in sync, and discovery excludes any
  profile that has not met it.
- **`get_my_profile_completion` RPC** â€” the server's view of name, birthdate,
  city and photo count, so the UI and the filter can never disagree.
- **Open Source screen** with a QR code resolving to this repository
  (Settings -> Open Source).
- **pytest verification suite** (`tests/python/`) with a single entry point:
  `python tests/python/run_all_tests.py`.
- **`tool/build_release.py`** â€” builds the release APK with credentials read
  from `.env` and never echoes them, and writes the SHA-256 sidecar.

### Fixed

- **Latitude/longitude were transposed in the distance filter.**
  `get_nearby_profiles` built the viewer's position as
  `ST_Point(latitude, longitude)`; PostGIS expects `ST_Point(longitude,
  latitude)`. For anyone off the equator/prime-meridian this computed a
  meaningless distance, so the radius filter and the displayed distance
  disagreed and the wrong people were excluded.
- **Fabricated age.** The RPC reported age 25 for any profile with no stored
  date of birth, which silently satisfied a 25â€“32 request. An unknown age is
  now NULL and is excluded whenever an age range is set.
- **`p_discovery_mode` was accepted and ignored**, so "nearby", "global" and
  "crossed_paths" all ran identical SQL. The mode now selects the predicate.
- **The Profile screen never displayed the user's age.** Name and age are now
  shown together, with the city on its own line rather than crammed into the
  relationship-intent pill.
- **Passkey flows reported false success.** A missing session fell through to
  `signInWithPassword(email: '', password: '')` and still returned
  `success: true`; the authentication path returned `success: true` with a
  null session. Both now fail honestly with an actionable message.
- **A live Supabase anon key was committed** to `.vscode/launch.json`. Removed;
  the launch config now reads from environment variables.
- **A committed credential also appeared in the security scan's own patterns**
  â€” the scanner now excludes itself from the file walk.

### Security

- **`search_path` pinned on every SECURITY DEFINER function** (migration 024).
  Thirteen functions â€” including the `handle_new_user` auth trigger â€” were
  created without `set search_path`, which lets an attacker shadow an
  unqualified name with an object in a writable schema and run code as the
  definer. Migration 021 pins the path from the catalog so a future function
  cannot be missed, and raises if anything is left unpinned.
- Discovery never returns coordinates; distance is computed inside the
  definer function and only the number crosses the wire.

### Not verified on a device

Passkey registration, the four-photo upload flow on a real handset, and
Google Play Console review all require hardware or a console and are reported
as NOT VERIFIED by the verification suite. See the run output.


## [2.3.1] - 2026-09-26

### Fixed - Edit Profile photo upload + save

- Photo upload maps Storage + `profile_photos` rejections to actionable
  messages instead of opaque "server error"; `moderation_status` is no longer
  sent from the client (server decides per 006/011).
- Edit Profile save maps `profiles` UPDATE rejections (RLS/stale session,
  relationship-intent CHECK, social-media bio trigger 014, missing-column
  42703) to actionable messages; raw SDK prefixes stripped before display.
- New migration `018_edit_profile_live_fixes.sql`: grants on
  `profile_photos`/`interests`/`user_interests`, RLS for shared `interests`
  list (links stay owner-only), idempotent re-assert of the private
  `profile-photos` bucket + owner-folder storage policies. Apply with
  `supabase db push` before testing the release APK.
- New migration `019_weekend_availability_shape_fix.sql`: 016 guarded
  `user_settings.weekend_availability` with JSONB *containment*
  (`<@ '{"Saturday":true,"Sunday":true}'`), but containment compares values â€”
  so the `false` the client writes for an unselected day raised
  `23514 ... violates check constraint "user_settings_weekend_availability_shape"`
  and the save failed. 019 replaces it with a key-set + value-type check
  (`weekend_availability_is_valid`) that still refuses unknown keys and
  non-boolean values.
- Migrations **015â€“019 are now applied to the LIVE Supabase project**
  (001â€“013 were already applied out-of-band and have been baselined in
  `supabase_migrations.schema_migrations`, which did not exist before).

## [2.3.0] - 2026-09-22

### Fixed - signup, email confirmation and navigation

- **Duplicate screens after signup are gone.** `appRouterProvider` no longer
  `ref.watch`es the auth state. Watching rebuilt the provider on every
  auth-state emission and constructed a brand-new `GoRouter`, which restarts at
  `/` and replayed splash -> entry screens instead of continuing forward. The
  state now reaches the router through `refreshListenable`, so exactly one
  router instance survives the whole flow.
- **"Check your email" is no longer a dead end.** When Supabase returns a user
  with no session (`mailer_autoconfirm = false`) the app records an explicit
  `awaitingEmailConfirmation` state instead of a red error banner and continues
  to a dedicated confirmation step.
- **New `/confirm-email` step** with a genuine Supabase re-send
  (`auth.resend(type: signup)`), an "I've confirmed - Sign in" action and a
  "Use a different email" escape. No local verification flag is ever set.
- **Real session synchronisation.** `AuthNotifier` subscribes to
  `onAuthStateChange`, so a session created outside the widget tree (the
  confirmation link opened in a browser) is adopted without restarting the app.
  The listener never satisfies a pending 2FA step-up.
- **Stale errors no longer persist.** `WeekendAuthState.copyWith` gained
  `clearError` / `clearPendingEmail`. Previously `error: null` was silently
  ignored, so an old error banner followed the user between forms.
- **Readable auth error mapping** for unconfirmed emails, invalid credentials,
  existing accounts, send rate limits and rejected addresses instead of raw SDK
  text.
- **Signing in with an unconfirmed account** (`email_not_confirmed`) now routes
  to the confirmation step instead of reporting a credential failure.
- **"Get Started" opens the sign-up form** (`/auth?mode=signup`) instead of
  showing the sign-in form first.
- `emailRedirectTo` plumbing (`--dart-define=AUTH_EMAIL_REDIRECT_URL=...`) for
  signup and password-reset emails. When unset, Supabase keeps using the
  project's Site URL, which is GoTrue's documented behaviour.

### Added - tests

- `test/app_router_stability_test.dart` fails if an auth-state change ever
  reconstructs the router again.
- `test/widget_test.dart` now asserts onboarding -> sign-up directly, including
  that the sign-in form is not shown first.

### Verified against the live project

- Live project ref `ocypgybqfushqfzisnvs` is the only backend in the release
  path (confirmed by scanning the packaged Dart snapshot).
- Signup, confirmation-email delivery and password sign-in were exercised end
  to end against the live project.

### Requires Supabase dashboard action (operator)

The live project still uses Supabase defaults for two mailer settings. Neither
can be changed from the repository, and both must be changed before
confirmation can complete on a phone:

1. **Authentication -> URL Configuration -> Site URL** is still
   `http://localhost:3000`, so the emailed confirmation link redirects to
   localhost. Set it (and add the app URL to *Redirect URLs*) to the real
   production origin.
2. **Project Settings -> Auth -> SMTP** still uses Supabase's built-in shared
   mailer (`noreply@mail.app.supabase.io`), which is rate limited and frequently
   spam-filtered. Configure a custom SMTP provider.


## [2.2.0] â€” 2026-09-20

### Added â€” release and distribution

- **Production release APK built with real Supabase credentials** (v2.2.0+4).
- **Verified installation on Android emulator** â€” app launches successfully,
  connects to Supabase backend.
- **GitHub release published** with versioned APK and SHA-256 checksum.
- **README updated** to point to v2.2.0 download links.

### Fixed â€” build and verification

- All 94 automated tests pass.
- Flutter analyze reports no issues.
- APK signed and verified: package `com.weekend.app`, version 2.2.0 (code 4),
  minSdk 24, targetSdk 36.
- SHA-256: `592BFAD4772B37E5C01144C11854D84AD14774734DDF31F65FC80701B602F4FB`

### Updated â€” documentation

- README download section points to v2.2.0 APK.
- SHA-256 checksum file included in release assets.

## [2.1.0] â€” 2026-09-16

### Fixed â€” production data integrity

- **Removed every source of fabricated users.** The offline sample deck,
  sample matches, sample chats, sample plans and sample crossed paths
  (`DemoData`) are deleted. Builds without a backend now show genuine empty
  states instead of fictional people, and unconfigured builds show an honest
  "backend not configured" message instead of a simulated login.
- **The placeholder signed-in user no longer carries fabricated identity.**
  The real profile is loaded from Supabase on app start.

### Fixed â€” matching and discovery

- Matches are now actually loaded (via the `get_matches_for_user` RPC) â€” the
  Matches tab previously stayed empty in production even after real matches.
- Passes are persisted to the `passes` table so passed profiles stay excluded.
- Like/match logic consolidated through `MatchRepository`: the client only
  records the like; the `check_mutual_like` database trigger transactionally
  creates the match, conversation and referral credit. Client-side writes to
  `matches` (which RLS forbids) are removed.
- Duplicate swipes are guarded against double-submission.

### Fixed â€” plans, safety, chat

- Weekend Plans create/join/leave now persist to `plans`/`plan_participants`
  with optimistic UI and authoritative re-sync; creator names resolve from
  real profiles.
- Block and Report now persist to `blocks`/`reports` (mapped to the schema's
  `report_type` enum) instead of touching only local state.
- Chat sends no longer double-write (local echo + repository); failures now
  surface a retry-able snackbar and restore the draft.

### Changed â€” release engineering

- Release builds embed `SUPABASE_URL`/`SUPABASE_ANON_KEY` from repository
  secrets as compile-time defines; the anon key is client-safe and protected
  by RLS. No service-role or privileged credential is ever embedded.
- `profiles` reads use explicit column lists compatible with the
  column-level grants introduced in migration 006.

### Unreleased (previous)


### Security

- Added `009_account_deletion_service_role.sql`: the live `account-deletion`
  path could never succeed â€” 006 revoked the service role's `EXECUTE` on
  `delete_user_account`, and `assert_self` raises for service-role calls
  (`auth.uid()` is null without a user JWT). The service role now gets an
  explicit grant and bypasses `assert_self`; the Edge Function still
  authenticates the caller's JWT and rejects cross-account deletion, and
  direct authenticated callers remain guarded.
- Added the operator verification plan for TOTP 2FA and account deletion
  (`docs/verification-2fa-deletion.md`).

### Documentation

- Rewrote `README.md` as a complete project landing page: features, screenshots,
  architecture, technology stack, installation, security, privacy, FAQ and
  roadmap.
- Added developer and user documentation: `docs/getting-started.md`,
  `docs/installation.md`, `docs/architecture.md`, `docs/location-discovery.md`,
  `docs/qr-invitations.md`, `docs/security.md`, `docs/privacy.md`,
  `docs/testing.md`, `docs/contributing.md` and a `docs/README.md` index.
- Rewrote `SECURITY.md` (supported versions, private reporting, scope, secret
  handling, APK verification) and `CONTRIBUTING.md`.
- Documented current limitations honestly instead of implying unimplemented
  features ship today (see the *Known limitations* section of the README).

### Fixed

- Added the missing `assets/images/placeholder_avatar.png` artwork referenced by
  the Explore screen. The `assets/images/` directory is now tracked, which also
  fixes the `asset_directory_does_not_exist` warning that made `flutter analyze`
  fail in a fresh clone (and therefore in CI).
- Added `tool/generate_placeholder_assets.dart` so the placeholder artwork can be
  regenerated deterministically, following the existing `tool/` convention.
- Fixed release builds on machines without a debug keystore (including CI and
  fresh clones). When `android/key.properties` is absent, the build now reuses or
  generates the standard Android debug keystore at `$HOME/.android/debug.keystore`
  instead of failing in `:app:validateSigningRelease`. Such APKs are development
  builds signed with a generated key and are logged with an explicit warning;
  production releases still require a real `key.properties`.

## [2.0.1] - 2026-09-13

### Changed

- Updated production APK configuration and Weekend branding for distribution.
- Improved the referral-code experience in the invitation flow.
- Notification taps now route to the relevant destination.
- Weekend Plans UI improvements.

### Build & repository hygiene

- Removed committed build artifacts and Flutter build caches from version
  control; local release artifacts are now git-ignored.

## [2.0.0] - 2026-09-06

### Major Changes

- **Flutter migration** â€” Migrated from Kotlin/Compose to Flutter/Dart for cross-platform capability
- **In-feed advertisements** â€” Added privacy-preserving, server-validated ad system with 120-second active discovery interval
- **Ad management** â€” Ad cards with ADVERTISEMENT/Sponsored labels, report/hide functionality, server-side event validation via `serve-ad` Edge Function
- **Crossed Paths** â€” Geohash-based privacy-safe crossed-path detection
- **User location buckets** â€” Privacy-preserving location storage for discovery features
- **Location radius filter** â€” Distance-based discovery filtering in the discovery feed
- **Ad config** â€” Configurable ad intervals and display settings

### Features

- **Authentication** â€” Email/password
- **Profile creation and editing** â€” Full profile management with photos, prompts, interests
- **Profile display** â€” Detailed profile view with compatibility explanation
- **Discovery** â€” Swipe-based discovery with nearby, crossed-paths, and global modes
- **Location-aware discovery** â€” PostGIS-powered proximity search, privacy-safe location handling
- **Distance/radius filtering** â€” Configurable discovery radius
- **Nearby profiles** â€” GPS-based discovery with approximate distance
- **Crossed Paths** â€” Historical location overlap detection using geohash buckets
- **Global discovery** â€” Browse profiles worldwide or by city
- **Likes and passes** â€” Unlimited likes and passes
- **Mutual matches** â€” Match when both users express interest
- **Unlimited messaging** â€” No message limits
- **Realtime chat** â€” Instant messaging with matches via Supabase Realtime
- **Notifications** â€” Relevant notifications for matches and messages
- **Blocking and reporting** â€” Full user safety controls
- **Unmatching** â€” Remove matches
- **Verification** â€” Photo verification with multi-signal detection
- **Privacy controls** â€” Location discovery toggles, profile visibility settings
- **Weekend Plans** â€” Create and join local plans and activities
- **In-feed advertisements** â€” Clearly labeled ads after 120 seconds of active discovery
- **Image optimization** â€” Automatic resizing, compression, and thumbnail generation
- **Referral system** â€” Invite friends with referral codes and tracking
- **Row Level Security** â€” RLS enabled on all database tables
- **Storage policies** â€” Privacy-safe photo storage with per-user folder policies
- **Realtime** â€” Chat and notification streams via Supabase Realtime
- **Edge Functions** â€” AI features, account deletion, ad serving

### Security

- JWT authentication on all Supabase Edge Functions
- Row Level Security (RLS) enabled on all database tables
- Server-side authorization for all security-critical operations
- Location privacy â€” exact GPS coordinates never exposed
- Rate limiting and abuse detection
- Complete server-side account deletion
- Ad event validation server-side via `serve-ad` Edge Function
- Ad destination URL validation (HTTPS only)
- Privacy-preserving geohash-based location handling

### Technical

- **Flutter** 3.41.9 / **Dart** 3.11.5
- **Supabase** 2.x (Auth, PostgreSQL + PostGIS, Storage, Realtime, Edge Functions)
- **Riverpod** 2.6.1 for state management
- **GoRouter** 14.8.1 for navigation
- **geolocator** for location services
- **cached_network_image** for image loading

### Build

- Release APK: ~54 MB
- Min SDK: 24 (Android 7.0)
- Target SDK: 35

## [1.0.0] - 2026-09-06

### Added

- First public Weekend release and GitHub landing page.
- Android application distribution through GitHub Releases.

### Notes

- 1.0.0 belongs to the earlier Kotlin/Compose-era codebase. It is superseded by
  the 2.0.x Flutter line and is no longer maintained; see the supported-versions
  table in [SECURITY.md](SECURITY.md).

[Unreleased]: https://github.com/zypherlabs-bit/Weekend/compare/v2.7.0...HEAD
[2.7.0]: https://github.com/zypherlabs-bit/Weekend/compare/v2.6.0...v2.7.0
[2.6.0]: https://github.com/zypherlabs-bit/Weekend/compare/v2.3.0...v2.6.0
[2.3.0]: https://github.com/zypherlabs-bit/Weekend/compare/v2.2.0...v2.3.0
[2.2.0]: https://github.com/zypherlabs-bit/Weekend/compare/v2.1.0...v2.2.0
[2.0.1]: https://github.com/zypherlabs-bit/Weekend/compare/v2.0.0...v2.0.1
[2.0.0]: https://github.com/zypherlabs-bit/Weekend/compare/v1.0.0...v2.0.0
[1.0.0]: https://github.com/zypherlabs-bit/Weekend/releases/tag/v1.0.0
