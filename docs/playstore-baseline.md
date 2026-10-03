# Weekend — Google Play Store Launch Baseline

**Last updated:** 2026-10-02 (post-fix)

## Phase 0: Safe Baseline

### Last commit
- **Hash**: `8d01432` — Merge branch 'master' of https://github.com/zypherlabs-bit/Weekend
- **Branch**: `master` (1 commit behind `origin/master`)
- **Remote**: `origin https://github.com/zypherlabs-bit/Weekend.git`

### Version
- **pubspec.yaml**: `version: 2.7.0+12`
- **Package ID**: `com.weekend.app`

### SDK / Toolchain
| Component | Version |
|-----------|---------|
| Flutter | 3.41.9 (stable) |
| Dart | 3.11.5 |
| AGP | 8.11.1 |
| Kotlin | 2.2.20 |
| Gradle | 8.14 |
| Android SDK | 36.1.0 |
| JDK | 17 |
| compileSdk | 36 (verified in APK badging) |
| targetSdk | 36 (verified in APK badging) |
| minSdk | 24 |

### Build status
- `flutter analyze`: **No issues found!** (30.9s)
- `flutter test`: **295 tests passed**
- `flutter build apk --release`: **Built** — 121.8 MB
- `flutter build appbundle --release`: **Built** — 107.4 MB
  - **SHA-256 (AAB)**: `5490e9515dbaf7dbe992f636946c0bbe4c3646180e1e807fb773848d8c5cfdff`

### Signing
- **Status**: No `android/key.properties` file present (only `.example` template).
- **Fallback**: Release build signed with generated development key (`~/.android/debug.keystore`).
- `.gitignore` excludes `key.properties`, `*.jks`, `*.keystore`.

### Permissions in manifest (post-fix)
- `INTERNET`
- `ACCESS_NETWORK_STATE`
- `CAMERA`
- `ACCESS_COARSE_LOCATION`
- `ACCESS_FINE_LOCATION`
- `POST_NOTIFICATIONS`
- `RECORD_AUDIO` (voice intros feature)
- `USE_BIOMETRIC`
- `USE_FINGERPRINT`
- `VIBRATE` (transitive, from dependencies)
- `WAKE_LOCK` (transitive, from dependencies)
- `com.google.android.c2dm.permission.RECEIVE` (from firebase_messaging)
- `DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION` (transitive)

**Removed**: `WRITE_EXTERNAL_STORAGE`, `READ_EXTERNAL_STORAGE` (deprecated since
API 30 / unavailable on API 36; app uses Photo Picker + scoped storage).

### Supabase
- **Project ref**: `ocypgybqfushqfzisnvs`
- **Configured via**: `--dart-define=SUPABASE_URL`, `--dart-define=SUPABASE_ANON_KEY`
- **Bucket**: `profile-photos` (private)
- **AssetLinks**: **NOT SATISFIED** — no Weekend-controlled domain serving `/.well-known/assetlinks.json`.

### Working tree changes (uncommitted)
- `android/app/src/main/AndroidManifest.xml` — removed storage permissions, kept RECORD_AUDIO
- `lib/features/chat/chat_screen.dart` — added icebreaker + translation UI
- `lib/features/settings/settings_dialog.dart` — confirmation text for account deletion
- `lib/services/notification_service.dart` — FCM integration, debugPrint fixed
- `lib/widgets/widgets.dart` — added icebreaker_widget export
- `pubspec.yaml` + `pubspec.lock` — added deps (record, audioplayers, firebase_core, firebase_messaging)
- `supabase/migrations/027_device_tokens_and_mode_queries.sql` — device_tokens table + discovery queries (**FIXED**: added `set search_path = public`, `assert_self` ownership check, `revoke all` before grant)
- `tests/python/test_android_playstore.py` — added RECORD_AUDIO to allowed permissions

**New untracked files**: `lib/firebase_options.dart`, `lib/repositories/icebreaker_repository.dart`, `lib/services/voice_intro_service.dart`, `lib/widgets/icebreaker_widget.dart`

### Documentation
| File | Present? |
|------|----------|
| docs/privacy.md | Yes — technical privacy doc |
| docs/security.md | Yes — security architecture |
| docs/child-safety.md | **CREATED** — age gate, underage reporting |
| docs/safety-policy.md | **CREATED** — safety policy & content moderation |
| docs/community-guidelines.md | **CREATED** — acceptable use |
| docs/terms.md | **CREATED** — Terms of Service |
| docs/google-play-data-safety.md | **CREATED** — Data Safety form responses |
| docs/store-listing.md | **CREATED** — store listing assets & copy |
| docs/app-access.md | **CREATED** — Play Console review credentials |
| docs/PLAYSTORE_LAUNCH_CERTIFICATION.md | **CREATED** — final GO/NO-GO report |
| docs/POST_LAUNCH_OPERATIONS.md | Not created |
