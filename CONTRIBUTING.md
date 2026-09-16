# Contributing to Weekend

Thanks for your interest in **Weekend** — a free, open-source dating and social
discovery app for Android (Flutter + Kotlin + Supabase). Contributions of all
kinds are welcome: code, documentation, tests, design and translations.

This project and everyone participating in it is governed by the
[Code of Conduct](CODE_OF_CONDUCT.md). By taking part you agree to uphold it.

Deeper guidance lives in [docs/contributing.md](docs/contributing.md).

---

## Quick start

```bash
git clone https://github.com/zypherlabs-bit/Weekend.git
cd Weekend
flutter pub get
flutter run            # offline demo mode works with no backend

flutter analyze        # must be clean
flutter test           # must pass
```

- Flutter **3.41.9** (bundles Dart 3.11.5), JDK **17**, Android SDK for the build.
- Full setup, including connecting a Supabase project:
  [docs/getting-started.md](docs/getting-started.md) and
  [docs/supabase.md](docs/supabase.md).

---

## Ways to help

| Contribution | How |
|--------------|-----|
| Bug report | Open an issue with the [bug template](.github/ISSUE_TEMPLATE/bug_report.md) |
| Feature idea | Open an issue with the [feature template](.github/ISSUE_TEMPLATE/feature_request.md) |
| Documentation | Pull request against `README.md`, `docs/` or the policy files |
| Code change | Pull request with tests and an updated changelog entry |
| Security issue | **Privately**, following [SECURITY.md](SECURITY.md) |

---

## Reporting bugs

Before filing, search [existing issues](https://github.com/zypherlabs-bit/Weekend/issues).

Include:

- clear title and description,
- steps to reproduce,
- expected vs actual behaviour,
- screenshots if useful,
- Android version, device model and app version,
- whether Supabase was configured (offline demo mode behaves differently).

Never paste real credentials, tokens or another person's data.

---

## Suggesting features

Describe the problem first, then the proposed solution, then alternatives you
considered. Features that fit Weekend's existing direction (location-aware,
privacy-first, free, open source) are easiest to accept. If a feature is not
implemented yet, please say so rather than describing it as shipped.

---

## Development workflow

1. **Fork** the repository.
2. **Branch** from the default branch (`master`):
   ```bash
   git checkout -b feature/your-feature-name
   ```
3. **Implement** the change following the conventions below.
4. **Verify**:
   ```bash
   flutter analyze
   flutter test
   ```
5. **Commit** with a clear message (imperative mood, ≤ 72 characters, explain why).
6. **Push** to your fork and **open a pull request** using the repository
   template. Reference the issue it fixes.

Keep pull requests focused: one logical change each.

---

## Coding standards

**Dart / Flutter**

- Follow [Effective Dart](https://dart.dev/effective-dart) and
  [Flutter style](https://docs.flutter.dev/development/ui/widgets) guidelines.
- Respect the layering: screens in `lib/features/`, data access in
  `lib/repositories/`, platform logic in `lib/services/`, state in
  `lib/providers/`, data classes in `lib/models/`, shared UI in `lib/widgets/`.
- Repositories must handle the offline demo case (`SupabaseConfig.client == null`)
  by returning empty results instead of throwing.
- Import geolocator as `geolocator` to avoid clashing with `LocationPreferences`.
- Prefer `const` constructors and small, extracted widgets.
- Never hardcode secrets: client config comes from `--dart-define`
  (`String.fromEnvironment`); provider keys belong to Edge Function secrets.

**SQL migrations**

- Migrations are append-only: add a new numbered file, never edit an applied one.
- Enable RLS on new tables and add policies in the same change.
- Cross-user reads belong in `security definer` functions that verify the caller
  (`assert_self`) rather than trusting a client-supplied user id.

**Edge Functions (Deno/TypeScript)**

- Authenticate the caller's JWT before doing work.
- Keep provider keys in function secrets and never return them to the client.

---

## Tests

```bash
flutter analyze
flutter test
flutter test --coverage
```

Add or extend tests for behavioural changes. Useful starting points:
`test/geohash_test.dart`, `test/location_service_test.dart`,
`test/ad_service_timer_test.dart`, `test/ad_card_test.dart`,
`test/discovery_repository_test.dart`. For schema or policy changes, add a case
to `supabase/test/rls_test.sql`. See [docs/testing.md](docs/testing.md).

---

## Documentation

If you change behaviour that documentation describes, update the relevant page in
the same pull request — `README.md`, `docs/*.md`, `SECURITY.md`,
`CONTRIBUTING.md`, and add an entry to `CHANGELOG.md`. Document only what the code
actually does; mark planned work as planned.

Screenshots in `docs/screenshots/` must show the current UI and contain no
personal data, credentials or third-party branding.

---

## Security rules for contributors

- Never commit `.env` files, keystores, `key.properties`, API keys, tokens or
  personal data.
- Do not weaken RLS, column protection or authentication to make a feature
  convenient.
- Do not log tokens, passwords or message contents.
- Report vulnerabilities privately via [SECURITY.md](SECURITY.md).

---

## Code review

- All changes are reviewed before merging.
- Maintainers review as time allows; focused pull requests move faster.
- Requested changes are normal — update the same branch.
- CI (`.github/workflows/ci.yml`) must be green before merge.

---

## Questions

Open an [issue](https://github.com/zypherlabs-bit/Weekend/issues) with the
question label, or start a discussion if Discussions are enabled for the
repository.

Thank you for contributing to Weekend!