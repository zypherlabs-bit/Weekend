# Security

Weekend is open source, which means the following assumptions are built in:

- Anyone can read the source code and decompile the APK.
- Anyone can inspect network traffic to their own device.
- Anyone can call the Supabase API or Edge Functions directly with their own
  credentials.

Therefore the app is treated as **fully untrusted**, and every authorization
decision is made server-side.

> Reporting a vulnerability? Follow [../SECURITY.md](../SECURITY.md) — please do
> not open a public issue.

---

## 1. Server-side enforcement

| Mechanism | Where | Effect |
|-----------|-------|--------|
| Row Level Security on every table | `supabase/migrations/002_rls_policies.sql` | A user can only read/write rows the policies allow |
| Least-privilege RPCs | `003_database_functions.sql`, `006_security_fixes.sql` | Discovery, matches and referral stats run as `security definer`, derive the caller from `auth.uid()` and verify it with `assert_self(...)` |
| Privileged column protection | `protect_profile_columns`, `protect_photo_moderation` | Clients cannot write verification, moderation or trust fields |
| Message validation | `enforce_message_rules` | Rejects inserts into conversations the caller is not a member of, and blocks messages to/from blocked users |
| Mutual-match integrity | `check_mutual_like` | Matches and conversations are created only by the trigger, not by the client |
| Account deletion | `delete_user_account` + `account-deletion` Edge Function | Deletes profile data, related rows and the auth user server-side |
| Ad-event validation | `serve-ad` Edge Function + `record_ad_event` RPC | Ad impressions/clicks are validated and attributed server-side |

**Consequence:** a modified client cannot unlock data that RLS does not expose —
there is nothing to "bypass" in the app binary, because the app has no authority
of its own.

---

## 2. Authentication and sessions

- Supabase Auth with email + password (`AuthRepository.signUpWithEmail`,
  `signInWithEmail`, `resetPassword`).
- Sessions are restored on launch; GoRouter redirects unauthenticated users to
  onboarding/auth and authenticated users away from the entry screens.
- Edge Functions authenticate the caller's JWT before doing work, so an
  invocation without a valid session is rejected.
- Email confirmation behaviour depends on your own Supabase Auth settings.

**Not implemented:** OAuth/Google sign-in, multi-factor authentication and
passkeys. Do not assume they exist.

---

## 3. Secrets

| Secret | Where it may live | Where it must never live |
|--------|-------------------|--------------------------|
| `SUPABASE_URL` | Client build (`--dart-define`), `.env.example` | — (public by design) |
| `SUPABASE_ANON_KEY` | Client build (`--dart-define`) | — (public by design; RLS protects data) |
| `service_role` key | Supabase server side / CI secrets only | Never in the app, repo or `.env.example` |
| Database password | Developer machine / CI secrets only | Never in the repo |
| `GEMINI_API_KEY` | Supabase Edge Function secret | Never in the app or repo |
| Keystore + `key.properties` | Local machine, secure backup | Never committed (`.gitignore`) |

Rules enforced in this repository:

- `.gitignore` excludes `.env`, `.env.local`, `.env.production`, `*.apk`,
  `*.aab`, `*.jks`, `*.keystore`, `*.sha256`, `SHA256SUMS.txt`,
  `key.properties` and `supabase/.env`.
- Only `.env.example` and `android/key.properties.example` are tracked.
- `.env` files are not read at runtime at all; the app reads compile-time
  `--dart-define` values.
- CI does not embed any production secret in the APK it builds for verification.

---

## 4. Storage and media

- Bucket `profile-photos` is **private**, limited to 10 MB, and restricted to
  `image/jpeg`, `image/png`, `image/webp`.
- Users may only write inside their own `<uid>/…` folder (storage policies in
  `004_storage_policies.sql`).
- Other users can read only objects whose `profile_photos.moderation_status` is
  `approved`.
- Uploaded images are optimised client-side before upload (`ImageOptimizer`);
  original bytes stay private.

---

## 5. Client-side protections

| Protection | Implementation |
|-----------|----------------|
| Biometric app lock | `local_auth` with device-credential fallback; re-locks on background/resume (`main.dart`) |
| Secure local storage | `flutter_secure_storage` (Android Keystore) for sensitive preferences |
| No OS cloud backup | `android:allowBackup="false"` in the manifest |
| TLS only | `usesCleartextTraffic="false"` + network security config |
| Minimal permissions | Manifest declares internet, network state, camera, location and notifications only |
| Safe navigation | GoRouter redirect rules based on auth state |

Weekend never stores biometric templates; matching happens inside Android's
biometric stack.

---

## 6. Release integrity

- Release APKs are built by `.github/workflows/release.yml` from a `v*` tag.
- Each release publishes `Weekend-v<version>-release.apk` **and**
  `Weekend-v<version>-release.apk.sha256`.
- Verify before installing:

  ```powershell
  Get-FileHash .\Weekend-v2.0.1-release.apk -Algorithm SHA256
  ```

- CI (`.github/workflows/ci.yml`) runs analysis, tests and a release build on
  every push and pull request, so a broken or non-building commit is visible.
- Release signing requires an untracked `android/key.properties`; without it,
  builds fall back to debug signing (development only, never for distribution).

---

## 7. Anti-abuse

- Blocking is enforced in discovery and messaging, not just hidden in the UI.
- Reporting writes structured reasons to the `reports` table for moderation.
- Photo verification and moderation state gate whether a photo is visible.
- Ad interactions are validated server-side; hidden ads are not re-served.
- Rate limiting is inherited from Supabase (Auth and API limits) — configure
  tighter limits for your own deployment if needed.

---

## 8. Known limitations (security-relevant)

Documented so users and reviewers are not misled:

- The in-app account-deletion confirmation is **not yet wired** to the deletion
  function; server-side deletion exists and must be triggered by a maintainer or
  a direct call.
- Email confirmation and password policies depend on your Supabase project
  settings, not on app code.
- No remote push provider is integrated, so no push tokens are collected or
  leaked — but also no notifications when the app is closed.
- Weekend cannot promise to be immune to denial of service, device compromise or
  every class of attack; it implements defense in depth, not invulnerability.

---

## 9. Related documents

- [../SECURITY.md](../SECURITY.md) — reporting policy and supported versions
- [privacy.md](privacy.md) — data handling and controls
- [supabase.md](supabase.md) — RLS, storage and production checklist
- [architecture.md](architecture.md) — where enforcement lives in the code