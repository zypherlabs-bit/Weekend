# Security Policy

Weekend is an **open-source** dating and social discovery app for Android
(Flutter + Kotlin + Supabase). Because the source code and the shipped APK can be
inspected by anyone, the project assumes a fully untrusted client and enforces
authorization server-side. See [docs/security.md](docs/security.md) for the full
technical description.

---

## Supported versions

| Version | Supported | Notes |
|---------|-----------|-------|
| 2.2.x | ✅ | Current release line (`v2.2.0` is the latest published release) |
| 1.0.x | ❌ | Historic Kotlin/Compose-era release, no longer maintained |

Security fixes are applied to the latest released version and to `master`.

---

## Reporting a vulnerability

Please report security issues **privately**.

1. **Do not** open a public GitHub issue for a vulnerability.
2. Use GitHub's private reporting: go to the [Security tab](https://github.com/zypherlabs-bit/Weekend/security)
   and choose **Report a vulnerability**, or contact the maintainers directly.
3. Include:
   - a description of the issue and its impact,
   - steps to reproduce (a minimal proof of concept helps),
   - the affected version or commit,
   - any suggested mitigation.
4. Allow reasonable time for a fix before public disclosure.

Please do not access, modify or exfiltrate other users' data while researching,
and do not run denial-of-service or automated mass-scanning tests against a live
backend.

### What to expect

- Acknowledgement of the report as soon as maintainers are available.
- An assessment, and either a fix or a reasoned explanation.
- Credit in the release notes if you would like it (opt-in).

There is no bug-bounty programme and no payment for reports.

---

## Scope

**In scope**

- The Android app in this repository (`lib/`, `android/`)
- The database schema, RPCs, triggers and RLS policies (`supabase/migrations/`)
- The Edge Functions (`supabase/functions/`)
- The build and release pipeline (`.github/workflows/`)
- Privacy-sensitive behaviour such as location handling and photo access

**Out of scope**

- Any third-party Supabase deployment that is not the one this project
  configures
- Supabase platform vulnerabilities (report those to Supabase)
- Denial of service, spam, or social-engineering against maintainers
- Findings that require physical access to an unlocked device
- Missing security-hardening headers on non-existent services

---

## Security model in brief

| Control | Implementation |
|---------|----------------|
| Row Level Security | Enabled on every table (`002_rls_policies.sql`), hardened in `006_security_fixes.sql` |
| Caller verification | Cross-user RPCs are `security definer` and call `assert_self(auth.uid())` |
| Protected columns | `protect_profile_columns`, `protect_photo_moderation`, `sync_photo_verified` |
| Message integrity | `enforce_message_rules` rejects non-member or blocked-party inserts |
| Private storage | Private `profile-photos` bucket with per-user folder policies and moderation gating |
| Authenticated functions | Edge Functions verify the caller's JWT before doing work |
| Secrets | Only the anon key ships in the app; provider keys live in function secrets |
| Transport | HTTPS only, `usesCleartextTraffic="false"`, network security config |
| Local data | `flutter_secure_storage` (Android Keystore); `allowBackup="false"` |
| Biometric lock | `local_auth` with device-credential fallback; no biometric templates stored |
| Release integrity | Every release ships a `.sha256` checksum; CI builds the APK |
| Ad integrity | Events validated server-side; destination URLs must be HTTPS |

### Verifying a release APK

```powershell
Get-FileHash .\Weekend-v2.2.0-release.apk -Algorithm SHA256   # Windows
```

```bash
shasum -a 256 Weekend-v2.2.0-release.apk                      # macOS / Linux
```

Compare with the published `Weekend-v2.2.0-release.apk.sha256` asset.

---

## Handling secrets

Never commit: `.env` files, the `service_role` key, database passwords, provider
API keys, keystores (`*.jks`, `*.keystore`), or `key.properties`. These paths are
git-ignored; if you find a secret committed anywhere in the repository or its
history, please report it privately rather than opening a public issue.

---

## Dependencies

Keep the Flutter dependency tree current and review advisories:

```bash
flutter pub outdated            # outdated direct and transitive packages
flutter pub deps                # full dependency graph
flutter pub upgrade --major-versions   # apply major upgrades (review first)
```

CI installs dependencies from `pubspec.yaml` / `pubspec.lock` on every push, so a
broken or unavailable package fails the build.

---

## Known limitations

Weekend does not claim to be immune to every class of attack. In particular, the
in-app account-deletion action is not yet wired to the server-side deletion
function, and email confirmation depends on the operator's Supabase Auth
settings. The [Known limitations](README.md#known-limitations) section lists the
current gaps in the product itself.

---

## Responsible disclosure

We appreciate responsible security research and will acknowledge researchers who
help improve Weekend's security. Thank you for reporting privately.
