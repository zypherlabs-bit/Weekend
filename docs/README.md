# Weekend Documentation

**Weekend — Make Every Weekend Brighter.**
Free, open-source dating and social discovery app for Android (Flutter + Kotlin +
Supabase).

This folder holds the project's technical and end-user documentation. Every page
is written against the code in this repository — if something is planned rather
than shipped, it is marked as such.

| Document | Audience | Contents |
|----------|----------|----------|
| [installation.md](installation.md) | Users | Downloading, verifying and installing the Android APK |
| [getting-started.md](getting-started.md) | Developers | Clone → configure Supabase → run → build |
| [architecture.md](architecture.md) | Developers | Layers, data flow, folder layout, design decisions |
| [supabase.md](supabase.md) | Developers / operators | Supabase project setup, migrations, RLS, storage, realtime, Edge Functions, production checklist |
| [location-discovery.md](location-discovery.md) | Developers | Discovery modes, radius, travel mode, geohashing and location privacy |
| [qr-invitations.md](qr-invitations.md) | Developers | The QR invitation payload, validation order and referral flow |
| [security.md](security.md) | Developers / security researchers | Threat model, server-side enforcement, secrets, release integrity |
| [verification-2fa-deletion.md](verification-2fa-deletion.md) | Operators / QA | Executable live-project verification plan for TOTP 2FA and account deletion |
| [privacy.md](privacy.md) | Users / developers | What data Weekend handles and the privacy controls available |
| [SEO.md](SEO.md) | Maintainers | SEO strategy: keywords, README structure, audit tooling (`tool/seo_audit.py`) |
| [readme/redesign_report.md](readme/redesign_report.md) | Maintainers | The GitHub landing page redesign: assets, capture method, verified links, open findings |
| [testing.md](testing.md) | Contributors | Test suites, commands, conventions |
| [contributing.md](contributing.md) | Contributors | Workflow, standards, review expectations |
| [android/package_migration_report.md](android/package_migration_report.md) | Maintainers / release engineers | The `com.weekend.app` → `com.zypherlabs.weekend` package migration: files changed, external services, build and test results, remaining manual steps |
| [android/google_play_setup.md](android/google_play_setup.md) | Release engineers | Manual Google Play Console checklist for publishing under the new package name |

Related project files:

- [../README.md](../README.md) — project overview and download links
- [../SECURITY.md](../SECURITY.md) — vulnerability disclosure policy
- [../CONTRIBUTING.md](../CONTRIBUTING.md) — contribution guide
- [../CHANGELOG.md](../CHANGELOG.md) — release history
- [../CODE_OF_CONDUCT.md](../CODE_OF_CONDUCT.md) — community expectations
- [../LICENSE](../LICENSE) — MIT licence
- [analytics/](analytics/) — live analytics dashboard (GitHub Pages): repository visitors and APK downloads

## Quick facts

| | |
|---|---|
| Project | Weekend — free, open-source dating & social discovery app |
| Platform | Android 7.0+ (API 24), `targetSdk` 36, `com.zypherlabs.weekend` |
| App stack | Flutter 3.41.9, Dart 3.11.5, Riverpod 2.6.1, GoRouter 14.8.1 |
| Android host | Kotlin `FlutterFragmentActivity`, Gradle Kotlin DSL, JDK 17 |
| Backend | Supabase — PostgreSQL + PostGIS, Auth, Storage, Realtime, Edge Functions (Deno) |
| Licence | MIT |
| Latest release | <https://github.com/zypherlabs-bit/Weekend/releases/latest> |
| Analytics dashboard | <https://zypherlabs-bit.github.io/Weekend/analytics/> |
