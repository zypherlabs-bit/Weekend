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
| [privacy.md](privacy.md) | Users / developers | What data Weekend handles and the privacy controls available |
| [testing.md](testing.md) | Contributors | Test suites, commands, conventions |
| [contributing.md](contributing.md) | Contributors | Workflow, standards, review expectations |

Related project files:

- [../README.md](../README.md) — project overview and FAQ
- [../SECURITY.md](../SECURITY.md) — vulnerability disclosure policy
- [../CONTRIBUTING.md](../CONTRIBUTING.md) — contribution guide
- [../CHANGELOG.md](../CHANGELOG.md) — release history
- [../CODE_OF_CONDUCT.md](../CODE_OF_CONDUCT.md) — community expectations
- [../LICENSE](../LICENSE) — MIT licence

## Quick facts

| | |
|---|---|
| Project | Weekend — free, open-source dating & social discovery app |
| Platform | Android 7.0+ (API 24), `targetSdk` 36, `com.weekend.app` |
| App stack | Flutter 3.41.9, Dart 3.11.5, Riverpod 2.6.1, GoRouter 14.8.1 |
| Android host | Kotlin `FlutterActivity`, Gradle Kotlin DSL, JDK 17 |
| Backend | Supabase — PostgreSQL + PostGIS, Auth, Storage, Realtime, Edge Functions (Deno) |
| Licence | MIT |
| Latest release | <https://github.com/zypherlabs-bit/Weekend/releases/latest> |
