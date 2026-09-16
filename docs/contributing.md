# Contributing (in depth)

This is the long-form companion to [../CONTRIBUTING.md](../CONTRIBUTING.md):
conventions, expectations and the practical details of getting a change merged
into Weekend.

By taking part you agree to follow the
[Code of Conduct](../CODE_OF_CONDUCT.md).

---

## 1. Ways to contribute

| Contribution | Where |
|--------------|-------|
| Bug report | [Issues](https://github.com/zypherlabs-bit/Weekend/issues) — use the bug-report template |
| Feature request | Issues — use the feature-request template |
| Documentation fix | Pull request against `docs/`, `README.md`, `SECURITY.md`, `CONTRIBUTING.md` |
| Code change | Pull request with tests |
| Security issue | **Privately**, per [../SECURITY.md](../SECURITY.md) — never a public issue |
| Screenshots | Pull request replacing files in `docs/screenshots/` (no personal data, current UI only) |

---

## 2. Development setup

```bash
git clone https://github.com/zypherlabs-bit/Weekend.git
cd Weekend
flutter pub get
flutter run            # offline demo mode works without a backend
```

To work against a real backend, follow [getting-started.md](getting-started.md)
and [supabase.md](supabase.md). Development-only Supabase credentials must never
be committed.

---

## 3. Branch and commit conventions

- Branch from the default branch (`master`) and use a descriptive name:
  `feature/qr-invite-history`, `fix/chat-scroll`, `docs/location-privacy`.
- Commit messages: imperative mood, present tense, first line ≤ 72 characters,
  then a body describing *why*. Reference issues where relevant.

  ```text
  Add crossed-path aggregation test

  - Cover bucket edge cases at precision 7
  - Assert counts are stable across re-runs

  Fixes #123
  ```

- Keep commits focused. One logical change per commit where possible; avoid
  unrelated reformatting inside a functional change.
- Never commit: `.env`, keystores, `key.properties`, built APKs, personal data,
  or debug output files.

---

## 4. Coding standards

**Dart / Flutter**

- Effective Dart style; run `flutter analyze` before pushing (CI will too).
- `lib/features/` holds screens; business logic belongs in `lib/services/` or
  `lib/repositories/`, and shared state in `lib/providers/`.
- Repositories are the only layer that talks to Supabase. They must handle
  `SupabaseConfig.client == null` (offline demo mode) — return empty results
  rather than throwing.
- Import geolocator as `geolocator` (`import 'package:geolocator/geolocator.dart' as geolocator;`)
  to avoid clashing with the project's `LocationPreferences`.
- Prefer `const` constructors, small widgets and extracted reusable components.
- Never hardcode secrets. Configuration comes from `--dart-define`
  (`String.fromEnvironment`); provider keys belong to Edge Function secrets.

**SQL**

- Migrations are immutable once applied: add a new numbered file rather than
  editing history.
- Enable RLS on any new table, and add policies in the same change.
- Cross-user reads belong in `security definer` functions that verify the caller
  (`assert_self`) instead of trusting a client-supplied user id.
- Keep function grants explicit (`grant execute … to authenticated`).

**Edge Functions (Deno/TypeScript)**

- Authenticate the caller's JWT before doing work.
- Keep provider keys in function secrets; never return them to the client.
- Validate all input; return structured errors.

---

## 5. Tests

```bash
flutter analyze
flutter test
```

Add or extend tests for behavioural changes:

| Change | Test |
|--------|------|
| Location/geohash | `test/geohash_test.dart`, `test/location_service_test.dart` |
| Discovery mapping | `test/discovery_repository_test.dart` |
| Ads | `test/ad_service_timer_test.dart`, `test/ad_card_test.dart` |
| New widget/screen | A widget test using a stubbed provider |
| New table/policy | A case in `supabase/test/rls_test.sql` |

See [testing.md](testing.md) for details and conventions.

---

## 6. Documentation expectations

- If you change behaviour that this documentation describes, update the matching
  page in the same pull request (`docs/*.md`, `README.md`, `CHANGELOG.md`).
- New features that are not user-visible yet should be described as planned —
  do not document intent as if it shipped.
- Screenshots must show the current UI, contain no personal data, credentials or
  unrelated branding, and use the Weekend logo.

---

## 7. Pull requests

The template in `.github/pull_request_template.md` asks for:

1. A summary of the change and the issue it addresses.
2. The type of change (bug fix, feature, breaking change, docs, performance,
   refactor).
3. How it was tested — `flutter analyze`, `flutter test`, and manual verification
   on a device/emulator where relevant.
4. A security checklist: no secrets, no debug artifacts, server-side enforcement
   for new data access, and RLS considerations for schema changes.

Review expectations:

- Maintainers review as time allows; small, focused pull requests are reviewed
  faster than large ones.
- Requested changes are normal — respond in the same branch.
- A change is merged only when CI is green on the default branch and the PR has
  been reviewed.

---

## 8. Reporting bugs usefully

Include: app version, Android version and device, steps to reproduce, expected vs
actual behaviour, screenshots if relevant, and whether Supabase was configured
(offline demo mode behaves differently). Do not paste real user data, tokens or
credentials.

---

## 9. Related documents

- [../CONTRIBUTING.md](../CONTRIBUTING.md) — the short version
- [getting-started.md](getting-started.md) — environment setup
- [architecture.md](architecture.md) — layering rules
- [testing.md](testing.md) — test conventions
- [supabase.md](supabase.md) — migrations, RLS, functions
- [security.md](security.md) — security model