# Android Package Migration Report — Weekend

**Migration:** `com.weekend.app` → `com.zypherlabs.weekend`
**Date:** 2026-11-11
**Status:** **CONDITIONALLY COMPLETE** — every locally verifiable check passed; Google Play Console and Firebase registration still require manual action.
**App name (unchanged):** `Weekend`
**Toolchain:** Flutter 3.41.9 / Dart 3.11.5, AGP 8.11.1, Kotlin 2.2.20, JDK 17.0.21

---

## 1. Previous and new package name

| | Value |
|---|---|
| Previous package name | `com.weekend.app` |
| New package name | `com.zypherlabs.weekend` |
| Android namespace | `com.zypherlabs.weekend` |
| Launcher activity | `com.zypherlabs.weekend.MainActivity` |
| Application label | `Weekend` (unchanged) |
| iOS bundle identifier | `com.aistudio.weekend.appwk.weekend` (unchanged — outside the scope of an Android package migration) |

### What the migration is, and is not

`com.zypherlabs.weekend` is a **new Android application identity**. It is not a
rename of the existing `com.weekend.app` listing. Google Play assigns the
application ID when a Play listing is created and **it cannot be changed
afterwards** for that listing. `com.zypherlabs.weekend` therefore requires its
own Play Console listing, its own upload, and its own release track.

The Android **signing key is unchanged** (see §7), so the uploaded AAB is
signed by the same certificate the project already used.

---

## 2. State of the repository when the audit began

The working tree already contained a **partial, uncommitted** migration to
`com.zypherlabs.weekend` (the committed `HEAD` still used `com.weekend.app`).
The partial edit had already changed the Gradle `namespace`/`applicationId`,
moved the Kotlin sources and updated the Dart-side channel names — but it had
also introduced two defects that would have broken a release build:

| Defect introduced by the partial edit | Impact | Resolution |
|---|---|---|
| `android/app/proguard-rules.pro` was **deleted** while `build.gradle.kts` still referenced it in `proguardFiles(...)` | Release build fails: R8 cannot open the missing rules file. `isMinifyEnabled = true` is set for the release build type. | Restored from `HEAD` and extended with keep rules for the new package (§3.6). |
| `docs/PLAYSTORE_LAUNCH_CERTIFICATION.md` was re-encoded from UTF-8 to **CP1252** | Every em-dash/en-dash in the file became byte `0x97` (invalid UTF-8), and characters CP1252 cannot represent were replaced with `?`. The file was no longer valid UTF-8. | Restored the `HEAD` bytes and re-applied only the package-name substitution, preserving the UTF-8 BOM and CRLF line endings. The diff is now exactly 2 changed lines. |

The migration was then completed, verified, and the build re-run end to end.

---

## 3. Files changed

### 3.1 Android Gradle configuration

| File | Change |
|---|---|
| `android/app/build.gradle.kts` | `namespace` → `com.zypherlabs.weekend`; `applicationId` → `com.zypherlabs.weekend`; the `logPasskeyConfig` task's `assetlinks.json` example now names `com.zypherlabs.weekend`. |

`versionCode` / `versionName` still come from `flutter.versionCode` /
`flutter.versionName` (i.e. `pubspec.yaml` remains the single source of truth),
and `minSdk = 24`, `targetSdk = flutter.targetSdkVersion` are unchanged.

### 3.2 Android sources (directories migrated)

| From | To |
|---|---|
| `android/app/src/main/kotlin/com/weekend/app/MainActivity.kt` | `android/app/src/main/kotlin/com/zypherlabs/weekend/MainActivity.kt` |
| `android/app/src/main/kotlin/com/weekend/app/VpnSecurityChannel.kt` | `android/app/src/main/kotlin/com/zypherlabs/weekend/VpnSecurityChannel.kt` |

Both files had their `package` declarations updated to
`package com.zypherlabs.weekend`. The old `com/weekend/app/` directory tree was
removed and no empty directory remains. **No other directory or file was
renamed** — in particular the unrelated `app/src/main/java/com/example/...`
tree at the repository root was left untouched (it is not part of any Gradle
build and does not reference the old package).

`MainActivity` is declared in the manifest as `.MainActivity`, which resolves
against the Gradle `namespace`, so no manifest edit was required.

### 3.3 Method / Event channel names

`VpnSecurityChannel` and `lib/services/vpn_security_service.dart` must agree on
the channel name string, otherwise the Dart side waits on a channel nobody
serves. Both sides were updated together:

| Side | Constant | Value |
|---|---|---|
| Kotlin | `VpnSecurityChannel.METHOD_CHANNEL` | `com.zypherlabs.weekend/vpn_security` |
| Kotlin | `VpnSecurityChannel.EVENT_CHANNEL` | `com.zypherlabs.weekend/vpn_security_events` |
| Dart | `_methodChannelName` | `com.zypherlabs.weekend/vpn_security` |
| Dart | `_eventChannelName` | `com.zypherlabs.weekend/vpn_security_events` |

### 3.4 ProGuard / R8 rules

`android/app/proguard-rules.pro` was restored and extended:

```proguard
-keep class com.zypherlabs.weekend.** { *; }
-keepclassmembers class com.zypherlabs.weekend.** {
    public static final java.lang.String *;
}
```

This is required because R8 cannot see that the Dart side matches the channel
names as strings. Without the rule, shrinking could rename or strip the
handlers and the VPN-detection feature would silently never answer.

### 3.5 Tooling and scripts

| File | Change |
|---|---|
| `tool/gen_assetlinks.py` | `PACKAGE` → `com.zypherlabs.weekend` (the generated Digital Asset Links statement). |
| `tool/drive.py` | `adb shell am start -n com.zypherlabs.weekend/.MainActivity` |
| `tool/sign_in_probe.py` | `adb shell am force-stop com.zypherlabs.weekend` and the activity launch. |
| `tool/walk_signin.py` | same two `adb` invocations. |
| `tool/walk_to_passkey.py` | same two `adb` invocations. |
| `tests/python/test_biometric.py` | The hard-coded path `kotlin/com/weekend/app/MainActivity.kt` was replaced by a glob over the Kotlin source root (`main_activity_sources()`), so the check survives any future package rename. It also now fails loudly when no `MainActivity.kt` exists, instead of asserting against an empty string. |
| `tools/play_store_audit/test_release_metadata.py` | Expects `applicationId == "com.zypherlabs.weekend"`. |
| `tools/play_store_audit/test_artifact.py` | Artifact discovery now searches the real Flutter output paths (`build/app/outputs/...`) in addition to the legacy `build/release/`. Previously it searched only `build/release/`, which no Flutter version writes to and which `flutter clean` deletes — so the audit could never find a freshly built APK/AAB. |
| `tools/play_store_audit/test_shipped_artifact.py` | **New.** Verifies the application ID, launcher activity and app label read back out of the built APK, asserts the retired package name is absent from the binary, and asserts the native platform-channel classes and name strings survived R8. |

### 3.6 Dart / application code

| File | Change |
|---|---|
| `lib/services/vpn_security_service.dart` | Channel name constants (§3.3). |
| `lib/repositories/auth_repository.dart` | Comment describing the `assetlinks.json` package name now names `com.zypherlabs.weekend`. |

**No application logic, feature, screen or backend call was altered.** The
change is limited to the two channel-name constants and one comment.

### 3.7 Documentation

| File | Change |
|---|---|
| `docs/architecture.md` | Kotlin source path and `applicationId`. |
| `docs/vpn-and-screenshot-protection.md` | Kotlin source path. |
| `docs/store-listing.md` | Package field. |
| `docs/playstore-baseline.md` | Package ID. |
| `docs/play_store_compliance_matrix.md` | Application ID row. |
| `docs/LIVE_SCREEN_AUDIT.md` | Package. |
| `docs/PLAYSTORE_FINAL_CERTIFICATION.md` | Package. |
| `docs/PLAYSTORE_LAUNCH_CERTIFICATION.md` | Package (2 occurrences; file also re-encoded back to UTF-8). |
| `docs/PLAYSTORE_REMEDIATION_STATUS.md` | Package. |
| `docs/HUMAN_ACTIONS_REQUIRED.md` | `adb shell am kill com.zypherlabs.weekend`. |
| `CHANGELOG.md` | Package in two historical release entries. |
| `aab_manifest.txt` | Regenerated from the newly built AAB (§5). |

The application name **Weekend** was not changed anywhere. The parked
`weekend.app` **domain** referenced in the legal/policy documents is a web
domain, not an Android package, and was deliberately left alone — changing it
would alter published legal URLs.

---

## 4. External services

### 4.1 Firebase — **manual action required**

Firebase is **not configured in this repository**:

* `android/app/google-services.json` does **not** exist.
* The `com.google.gms.google-services` Gradle plugin is **not applied** (verified
  in `android/settings.gradle.kts` and `android/app/build.gradle.kts`).
* `lib/firebase_options.dart` is a hand-written placeholder whose every field is
  `String.fromEnvironment('WEEKEND_FIREBASE_*')`, and the release workflow
  passes only `SUPABASE_URL` and `SUPABASE_ANON_KEY`.

Consequently `Firebase.initializeApp` throws, `notification_service.dart`
catches it, and **no FCM token is generated, transmitted or stored**. This is
pre-existing and unchanged by the migration (see `docs/third-party-sdks.md`).

**Consequence for this migration:** because the app is registered with Firebase
by its package name, **if a Firebase project is later configured, the Android
app must be registered there under `com.zypherlabs.weekend`** — a Firebase
Android app entry for `com.weekend.app` does not cover the new package. No new
Firebase *project* is required; add one Android app to the existing project.

**What the developer must download manually (if FCM is enabled):**

1. Firebase Console → the existing project → **Add app → Android**.
2. Package name: `com.zypherlabs.weekend` (must match exactly).
3. Download `google-services.json`.
4. Apply the `com.google.gms.google-services` plugin to
   `android/app/build.gradle.kts` and `android/settings.gradle.kts`.
5. Replace `lib/firebase_options.dart` with a `flutterfire configure` output
   for the new package, and pass the `WEEKEND_FIREBASE_*` dart-defines.
6. Re-run `flutterfire configure` so `messagingSenderId`, `appId` and
   `projectId` match the new registration.

> Not verified: no Firebase project, console session or credential was
> available in this environment. **No claim is made that Firebase has been
> registered, re-registered or re-downloaded for the new package name.**

### 4.2 Supabase — **no change required**

The Supabase project (`ocypgybqfushqfzisnvs`) is **preserved exactly**:
same project ref, same database, same tables, same rows, same Storage bucket
(`profile-photos`) and same Row Level Security policies. No migration was
applied, no table was touched, no edge function was modified, and no data was
deleted or recreated.

The Android package name does **not** appear in any Supabase server-side
configuration, because none of it is package-bound:

| Setting | Package-dependent? | Action |
|---|---|---|
| Project ref / URL / anon key | No | None. |
| Database, tables, RLS policies, Storage | No | None. |
| Edge Functions (`serve-ad`, `passkey-*`, `account-deletion`, …) | No | None. |
| `webauthn_rp_id` / `webauthn_rp_origin` | No — derived from the Supabase host | None. |
| Auth **Redirect URLs** allow-list | No — these are HTTPS URLs | None. |
| Email verification / password-recovery redirect | No — `--dart-define=AUTH_EMAIL_REDIRECT_URL` | None. |

The app authenticates with email + password and native passkeys
(`client.auth.signInWithPassword`, `client.auth.signUp`,
`resetPasswordForEmail`, `client.auth.passkey.*`). It uses **no OAuth social
provider** (no Google/Apple sign-in), so there is no provider client ID or
OAuth redirect to re-register.

> Not verified: no live Supabase dashboard session or management token was
> available. The live project was **not** re-inspected after the migration.

### 4.3 Deep links, intent filters and App Links

The manifest declares one App Links intent filter:

```xml
<intent-filter android:autoVerify="true">
    <action android:name="android.intent.action.VIEW"/>
    <category android:name="android.intent.category.DEFAULT"/>
    <category android:name="android.intent.category.BROWSABLE"/>
    <data android:scheme="https" android:host="${weekendRpId}"/>
</intent-filter>
```

The host is the build-time `${weekendRpId}` placeholder, derived from
`SUPABASE_URL` — it is **not** package-bound and required no change. There is
**no custom URL scheme** (no `weekend://`) anywhere in the project, so no
scheme registration was needed.

**Digital Asset Links — manual action required.** Android will only complete a
WebAuthn ceremony for an associated app, which is proved by a file served at
`https://<rp-id>/.well-known/assetlinks.json` listing the package name and the
SHA-256 of the signing certificate. That file **must now name the new
package**. `tool/gen_assetlinks.py` was updated to emit it, and the release
digest it computes was verified to match the certificate the built APK is
actually signed with:

```bash
python tool/gen_assetlinks.py --emit-release
```

```
[{"relation":["delegate_permission/common.handle_all_urls"],"target":{"namespace":"android_app","package_name":"com.zypherlabs.weekend","sha256_cert_fingerprints":["FbL5GuvIW7JrZH6U+bMiNolBC47PKd3nmPnFsMyMJZQ"]}}]
```

The digest `FbL5GuvIW7JrZH6U+bMiNolBC47PKd3nmPnFsMyMJZQ` was produced by the
script from the real keystore and independently confirmed against
`apksigner verify --print-certs` on the built APK
(`SHA-256 digest: 15b2f91aebc85bb26b647e94f9b3223689410b8ecf29dde798f9c5b0cc8c2594`
→ base64, unpadded, matches exactly).

> **No digest was invented.** The value above is the real fingerprint of the
> real signing certificate. `assetslinks.json` still has to be **published** on
> a domain that serves `/.well-known/` — see §9.

### 4.4 Other integrations

| Integration | Package-dependent? | Action |
|---|---|---|
| `local_auth` (biometric app lock) | No | None. |
| `flutter_secure_storage` | No | None. |
| `mobile_scanner` / ML Kit | No | None. |
| `credential_manager` (passkeys) | Only via `assetlinks.json` | Publish the new statement (§4.3). |
| `image_picker`, `image_editor` | No — providers derive their authority from `applicationId` automatically (verified in the built manifest: `com.zypherlabs.weekend.flutter.image_provider`). | None. |
| `share_plus` | No — same, `com.zypherlabs.weekend.flutter.share_provider`. | None. |
| `flutter_local_notifications` | No | None. |
| `firebase_core` / `firebase_messaging` | Yes, at Firebase-console level | §4.1. |
| `geolocator`, `geocoding`, `permission_handler`, `connectivity_plus` | No | None. |

No payment, analytics, social-login or push provider outside this list is
integrated.

---

## 5. Build results

All commands were run in the project root with the live Supabase credentials
from the untracked `.env` and `-PPASSKEY_REQUIRE_RP_ID=true`, so the manifest's
WebAuthn relying-party ID was resolved rather than left empty.

| Step | Command | Result |
|---|---|---|
| Clean | `flutter clean` | OK |
| Dependencies | `flutter pub get` | OK — 151 packages have newer versions incompatible with the current constraints (pre-existing, not changed) |
| Format | `dart format lib test tool scripts tools` | OK — 147 files, 3 reformatted (pre-existing formatting drift in `tool/readme_capture/`) |
| Analyse | `flutter analyze` | **No issues found!** (28.4 s) |
| Test | `flutter test` | **All 386 tests passed** |
| Release APK | `flutter build apk --release` | **OK** — `build/app/outputs/flutter-apk/app-release.apk`, 125.0 MB, 686.4 s |
| Release AAB | `flutter build appbundle --release` | **OK** — `build/app/outputs/bundle/release/app-release.aab`, 104.8 MB, 86.3 s |

### Build metadata actually read back from the artifacts

The application ID was confirmed from the **built binaries**, not from the
Gradle configuration alone.

`aapt2 dump badging` on the APK:

```
package: name='com.zypherlabs.weekend' versionCode='18' versionName='2.8.5'
         compileSdkVersion='36' targetSdkVersion='36'
minSdkVersion:'24'
application-label:'Weekend'
launchable-activity: name='com.zypherlabs.weekend.MainActivity'
```

`bundletool dump manifest` on the AAB:

```xml
<manifest ... package="com.zypherlabs.weekend" ...>
  <activity android:name="com.zypherlabs.weekend.MainActivity" ...>
  <intent-filter android:autoVerify="true">
    <data android:host="ocypgybqfushqfzisnvs.supabase.co" android:scheme="https"/>
  </intent-filter>
  <meta-data android:name="android.credentials.webauthn.relying_party_id"
             android:value="ocypgybqfushqfzisnvs.supabase.co"/>
```

Byte-level check of the shipped APK's DEX and resources:

| Check | Result |
|---|---|
| `Lcom/zypherlabs/weekend/MainActivity;` present | PASS |
| `Lcom/zypherlabs/weekend/VpnSecurityChannel;` present | PASS |
| `com.zypherlabs.weekend/vpn_security` present | PASS |
| `com.zypherlabs.weekend/vpn_security_events` present | PASS |
| `com.weekend.app` absent from the shipped binary | PASS |

### Artifact identity

| Artifact | Size | SHA-256 |
|---|---|---|
| `app-release.apk` | 125.0 MB | `127AB9EBCBCF7BC7E7C8F4FE423AA4037E73A88D23660D51372E5557BB8215FA` |
| `app-release.aab` | 104.8 MB | `5B7720994E7D67584F8FC9ADA54318A05DBF6D366385D64D8A6F43020E7204E2` |

### Release signing

`apksigner verify --print-certs` on the release APK:

```
Verifies
Verified using v2 scheme (APK Signature Scheme v2): true
Number of signers: 1
Signer #1 certificate DN: CN=Weekend, OU=Weekend, O=ZypherLabs, L=Unknown, ST=Unknown, C=US
Signer #1 certificate SHA-256 digest: 15b2f91aebc85bb26b647e94f9b3223689410b8ecf29dde798f9c5b0cc8c2594
Signer #1 key algorithm: RSA
Signer #1 key size (bits): 4096
```

The release is signed with the project's **real production keystore** (RSA-4096,
`CN=Weekend, O=ZypherLabs`) — **not** the Android debug key. The
`build.gradle.kts` release guard (which refuses to build a release artifact
without `android/key.properties`, unless `-PallowDebugSigning=true` is passed
explicitly) was satisfied by the real `android/key.properties`.

---

## 6. Test results

| Suite | Command | Result |
|---|---|---|
| Flutter unit/widget tests | `flutter test` | **386 passed** |
| Python audit suite | `python -m pytest tests/python -q` | **344 passed, 1 skipped** |
| Play Store audit suite | `python -m pytest tools/play_store_audit -q` | **65 passed, 1 skipped** |

Two pre-existing test defects were found and fixed as part of the
verification, both of which the migration surfaced, and one new guard was
added:

1. `tests/python/test_biometric.py::test_fragment_activity_is_preserved` failed
   because it addressed `MainActivity.kt` through the **old** package path. The
   helper it uses returns `""` for a missing file, so the failure surfaced as
   a confusing `assert 'FlutterFragmentActivity' in ''`. The path is now
   discovered by glob, and the test fails with a clear message if the file is
   missing entirely.
2. `tools/play_store_audit/test_artifact.py` failed to find the APK/AAB
   because it searched only `build/release/`, a path no current Flutter
   version writes to and which `flutter clean` removes. Artifact discovery now
   searches the real output directories.
3. `tools/play_store_audit/test_shipped_artifact.py` was **added** by this
   migration. It reads the application ID, the launcher activity and the app
   label back out of the **built APK** with `aapt2`, asserts that the retired
   package name is absent from the shipped binary, and asserts that the
   native `MainActivity` / `VpnSecurityChannel` classes and their
   platform-channel name strings survived R8 shrinking. This turns the
   manual byte-level verification in §5 into a permanent, repeatable
   regression guard.

One environment issue was **not** caused by the migration and remains:
the gitignored `.pytest_cache/` directory at the repository root has a broken
ACL that denies access even to the local administrator, so `dart format .` and
`pytest`'s cache provider cannot traverse it. It is not tracked by git and
could not be repaired or deleted from this session. `dart format` was
therefore run over the source trees (`lib`, `test`, `tool`, `scripts`,
`tools`), which covers every Dart file in the project.

---

## 7. Security verification

| Check | Result |
|---|---|
| Private signing key committed | **No.** `android/weekend-release-keystore.jks` and `android/key.properties` are matched by `android/.gitignore` (`**/*.jks`, `**/*.keystore`, `key.properties`) and are **not** tracked by git (`git ls-files` returns only `android/key.properties.example`). |
| Keystore / key passwords exposed | **No.** `android/key.properties` is untracked and gitignored. The build reads `storePassword`, `keyPassword`, `keyAlias` and `storeFile` from it at build time only. |
| Release signing key changed | **No.** The release APK is signed with the pre-existing production certificate (`CN=Weekend, O=ZypherLabs`, RSA-4096). The same digest is emitted by the pre-existing `tool/gen_assetlinks.py`. |
| Firebase service-account credentials exposed | **No.** No service-account JSON exists in the repository. |
| Supabase service-role key in Flutter code | **No.** The app uses the **anon/public** key only, injected via `--dart-define=SUPABASE_ANON_KEY`. The service-role key is never referenced from Dart. |
| `.env` committed | **No.** `.env` is matched by `.gitignore` and is untracked. It holds the live Supabase URL/anon key and probe credentials. |
| Personal information / developer secrets committed | **No.** No personal data, credentials or tokens were added by this migration. |
| Backend access controls intact | **Yes.** No SQL migration was added, changed or applied; no RLS policy was touched; no table, function or bucket was altered. |
| Secret leakage in build artifacts | **No.** No `--dart-define` value other than the public Supabase URL and anon key is embedded; the service-role key and the keystore passwords are not. |
| No new hardcoded secrets introduced | **Yes.** Every credential remains in `.env` / `android/key.properties` / CI secrets, exactly as before. |

---

## 8. Functionality preserved

This was a package migration only. The following were verified as **unchanged**
— no screen, service, repository, provider or route was removed, replaced,
simplified or disabled, and no mock or dummy backend was introduced:

Registration · Login · Password recovery · Profile creation · Profile editing ·
Photo uploads · Discover · Explore · For You · Nearby · City · Global ·
Travel Mode · Likes and passes · Matching · Chat and messaging ·
Notifications · Settings · Privacy · Security · Blocking · Reporting ·
Account deletion · Premium features.

Evidence: `flutter analyze` reports no issues, all 386 Flutter tests pass, and
all 409 Python-side audit checks pass (344 + 65). The static regression guards
in `tests/python/test_android_playstore.py` confirm the app label is still
`Weekend`, the manifest still declares exactly one exported activity, backup
and cleartext traffic remain disabled, the age gate, account-deletion
confirmation, blocking and reporting are all still present, and the release
build type is still minified and signed.

---

## 9. Remaining manual steps

These require access that is not available from a build environment.

### Google Play Console

1. **Verify the package name is available.** Play Console → *Create app* →
   enter `com.zypherlabs.weekend`. If the name is taken, Play Console rejects
   it immediately. *(Not verified in this environment — no Play Console
   session was available. Availability of `com.zypherlabs.weekend` is NOT
   confirmed.)*
2. **Create the app listing.** This creates a brand-new Play listing, separate
   from any existing `com.weekend.app` listing. The existing listing's
   application ID cannot be changed.
3. **Configure Play App Signing.** Upload the AAB and enrol in Play App
   Signing. The upload key can be the existing `android/weekend-release-keystore.jks`
   — Play re-signs the distributed app with its own app-signing key.
4. **Upload `build/app/outputs/bundle/release/app-release.aab`** (104.8 MB,
   SHA-256 `5B7720994E7D67584F8FC9ADA54318A05DBF6D366385D64D8A6F43020E7204E2`).
   Play requires the AAB — the APK cannot be uploaded for a new listing.
5. **Configure the internal testing track** and push the release to it.
6. **Invite testers** via the Google Groups / email-list tester management
   screen, then publish the internal-testing release.
7. **Verify installation** from the internal-testing Play link on a physical
   device, and confirm with:
   ```bash
   adb shell pm list packages | findstr zypherlabs
   # package:com.zypherlabs.weekend
   ```

> Reminder: this is a **new** Play listing. Existing production users of the
> `com.weekend.app` build will **not** receive the new package as an update —
> it installs alongside the old app. A Play listing migration (and a
> credential transfer between the two packages) is a separate, Play-supported
> process that is out of scope here.

### Firebase (only if FCM is enabled — see §4.1)

Register an **Android app** named `com.zypherlabs.weekend` in the **existing**
Firebase project, download the new `google-services.json`, apply the
`com.google.gms.google-services` plugin and regenerate
`lib/firebase_options.dart`. Do not create a second Firebase project.

### Digital Asset Links (only if passkeys are enabled)

Publish the statement from §4.3 at
`https://<rp-id>/.well-known/assetlinks.json`, with
`Content-Type: application/json`, naming `com.zypherlabs.weekend` and the
release fingerprint `FbL5GuvIW7JrZH6U+bMiNolBC47PKd3nmPnFsMyMJZQ`. Verify
with:

```bash
curl -fsSL https://<rp-id>/.well-known/assetlinks.json | python -m json.tool
```

Note that `*.supabase.co` does not serve `/.well-known/`, so a
Weekend-controlled domain is required (this limitation predates the migration).

### Repository housekeeping

The migration is complete in the working tree but **not committed**. Review and
commit the changes, including the two Kotlin files under
`android/app/src/main/kotlin/com/zypherlabs/weekend/` (currently untracked).

---

## 10. Summary of verified vs. unverified claims

**Verified in this environment (by building and inspecting the artifacts):**

* The application ID in the built APK and AAB is `com.zypherlabs.weekend`.
* The Android namespace is `com.zypherlabs.weekend` and matches the
  application ID.
* Kotlin and Java compilation succeeds; the release APK and AAB both build.
* `flutter analyze` reports no issues.
* All Flutter, Python and Play Store audit tests pass.
* The release artifact is signed with the pre-existing production key.
* The old package name is absent from the repository and from the shipped
  binary.
* The WebAuthn relying-party ID resolves to the live Supabase host.
* The assetlinks release digest matches the APK's signing certificate.

**NOT verified — requires manual access:**

* Google Play Console availability of `com.zypherlabs.weekend`.
* Creation of the Play listing, enrolment in Play App Signing, AAB upload,
  internal-track release and tester invitations.
* Firebase Android app registration under the new package name.
* Live Supabase authentication, redirect allow-list and passkey ceremonies on
  a physical device.
* Publication of `assetlinks.json`.
