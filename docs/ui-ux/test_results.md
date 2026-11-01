# Weekend Test Results

## Flutter checks

- `flutter clean` — executed.
- `flutter pub get` — executed (dependencies resolved).
- `dart format .` — executed (no formatting changes required / applied).
- `flutter analyze` — **No issues found!** (ran ~16s).
- `flutter test` — **All 386 tests passed!** (~1 min).

## Test suites executed (sample)
- geohash_test.dart
- location_service_test.dart
- ad_service_timer_test.dart
- ad_card_test.dart
- discovery_repository_test.dart
- image_optimizer_test.dart
- (full suite: 386 tests)

## Additional
- Light/Dark theme: covered by widget tests and manual review.
- Backend integration: live Supabase configured via .env; not exercised in unit tests
  (no service-role keys in client).
## Build artifacts

- APK: build/app/outputs/flutter-apk/app-release.apk (125.0 MB, SHA256 41e9fff946757391bc599d0fb2a78146b34821379d08ade1a53574d701697076)
- AAB: build/app/outputs/bundle/release/app-release.aab (104.8 MB)

- Android device run: not executed in this environment (no device connected).
- APK build: see build artifacts.

## Remaining
- Physical Android device verification pending (no device connected in this environment).
