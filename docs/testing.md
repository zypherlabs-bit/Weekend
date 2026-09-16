# Testing

Weekend uses the standard Flutter test tooling: `flutter_test` for unit and widget
tests plus `mocktail` for test doubles. There is no custom test runner.

---

## 1. Commands

```bash
flutter pub get                  # first time only
flutter analyze                  # lints and static analysis (must be clean)
flutter test                     # run every test
flutter test --coverage          # also write coverage/lcov.info
flutter test test/geohash_test.dart        # a single file
flutter test --name "geohash"              # tests matching a name
flutter test --watch                       # re-run on change (dev loop)
```

CI runs `flutter analyze`, `flutter test` and a release APK build on every push
and pull request (`.github/workflows/ci.yml`), so a red build is visible
immediately.

---

## 2. Existing suites

| File | What it covers | Why it matters |
|------|----------------|----------------|
| `test/geohash_test.dart` | Geohash encode/decode, round-tripping, reference values | Crossed-path correctness depends on it |
| `test/location_service_test.dart` | Distance calculations, radius helpers, distance formatting | Discovery filters rely on it |
| `test/ad_service_timer_test.dart` | The 120-second ad interval, lifecycle pausing, event recording | Ads must not appear early or double-count |
| `test/ad_card_test.dart` | Ad card rendering, label presence, report/hide interactions | User controls must work |
| `test/discovery_repository_test.dart` | Mapping of RPC rows into `UserProfile` (including missing/null fields) | Protects against schema drift |
| `test/widget_test.dart` | App-level widget smoke test | Catches startup regressions |

Also present:

- `integration_test/` — entrypoints for integration testing on a device/emulator
  (`flutter test integration_test`).
- `supabase/test/rls_test.sql` — a manual SQL script for verifying Row Level
  Security behaviour (anonymous, other-user and blocked-user access) against a
  real project.

---

## 3. Conventions used in this repository

- One test file per production file or concern, named `<subject>_test.dart`.
- Prefer plain `test`/`group` structure; use `mocktail` when a class must be
  faked, and avoid adding new mocking packages.
- Tests must run **without** network access: repositories already return early
  when `SupabaseConfig.client` is `null`, so demo-mode behaviour is the natural
  unit-test surface.
- Keep tests deterministic: no reliance on wall-clock timing beyond what
  `fakeAsync`/`tester.pump` provides, and no real geolocation.
- Assert on behaviour and output, not on implementation details such as private
  fields.

---

## 4. What to test when you change code

| Change | Add/extend |
|--------|-----------|
| Location or geohash logic | `geohash_test.dart`, `location_service_test.dart` |
| Discovery RPC mapping | `discovery_repository_test.dart` |
| Ad interval, lifecycle or events | `ad_service_timer_test.dart`, `ad_card_test.dart` |
| New screen or widget | A widget test that pumps the widget with a stubbed provider |
| Database function or policy | A case in `supabase/test/rls_test.sql` executed against a test project |

---

## 5. Running the RLS checks

`supabase/test/rls_test.sql` is executed manually against a project (local stack
or a disposable cloud project) because RLS behaviour depends on real JWTs:

```bash
supabase start            # or use a scratch cloud project
supabase db reset         # apply migrations in order
# then run supabase/test/rls_test.sql in the SQL editor or with psql
```

At minimum verify: anonymous access is denied, one user cannot read another
user's private rows, blocked users are excluded from discovery and messaging, and
a client cannot set verification/moderation columns.

---

## 6. Release verification

Before cutting a release:

```bash
flutter analyze
flutter test
flutter build apk --release \
  --dart-define=SUPABASE_URL=... \
  --dart-define=SUPABASE_ANON_KEY=...
```

Then confirm the produced APK installs and that the tag-driven release workflow
published both `Weekend-v<version>-release.apk` and its `.sha256` file.

---

## 7. Related documents

- [contributing.md](contributing.md) — workflow and review expectations
- [architecture.md](architecture.md) — what the layering means for tests
- [supabase.md](supabase.md) — local stack and migrations
- [security.md](security.md) — what the RLS script should prove