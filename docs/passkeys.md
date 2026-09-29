# Passkeys on Android — what is configured, and what is still missing

Weekend uses standards-based WebAuthn passkeys through Android's Credential
Manager and Supabase Auth's native passkey API. This document records the exact
server and build configuration, and the one prerequisite that **cannot** be
satisfied from inside the app.

## 1. The flow (no step is simulated)

```
Create Account / Sign In
        v
Supabase GoTrue issues a challenge
  POST /auth/v1/passkeys/registration/options     (authenticated)
  POST /auth/v1/passkeys/authentication/options   (unauthenticated)
        v
Android Credential Manager runs the ceremony
  create() -> user verification -> credential
  get()     -> user verification -> signed assertion
        v
Supabase verifies and issues a REAL session
  POST /auth/v1/passkeys/registration/verify
  POST /auth/v1/passkeys/authentication/verify
```

`PasskeyCeremonyResult.success` is only ever true when Credential Manager
returned a credential. `PasskeyOperationResult.session` is only ever non-null
when GoTrue returned one. There is no code path that sets a session, or a
"logged in" flag, without the server.

## 2. Server configuration (verified live on this project)

Project: `ocypgybqfushqfzisnvs`

| Setting | Value | Where |
| --- | --- | --- |
| Passkey authentication | **enabled** | Auth -> Passkeys |
| WebAuthn RP display name | `Weekend` | Auth -> URL Configuration |
| WebAuthn relying-party ID | `ocypgybqfushqfzisnvs.supabase.co` | Auth -> URL Configuration |
| WebAuthn RP origins | `https://ocypgybqfushqfzisnvs.supabase.co` | Auth -> URL Configuration |
| Site URL | `https://ocypgybqfushqfzisnvs.supabase.co` | Auth -> URL Configuration |

Before this work the project reported `passkeys_enabled: false`, an **empty**
RP ID and a Site URL of `http://localhost:3000`. Every passkey request
answered `HTTP 404 {"error_code":"passkey_disabled"}`, which is the server-side
root cause of "passkeys do nothing".

To read or change them:

```bash
export SUPABASE_ACCESS_TOKEN=<personal access token>
supabase projects api-keys --project-ref ocypgybqfushqfzisnvs   # or:
curl -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" \
  https://api.supabase.com/v1/projects/ocypgybqfushqfzisnvs/config/auth
```

## 3. App configuration

* `lib/services/passkey_service.dart` owns the Credential Manager lifecycle.
  **It calls `CredentialManagerPlatform.instance.init(...)` first.** The Android
  plugin holds its `CredentialManager` in a `lateinit var` that only `init`
  assigns; calling a ceremony without it throws
  `UninitializedPropertyAccessException`. The previous code never called `init`,
  which is the second root cause of the same symptom.
* `userVerification` is forced to `required` on both registration and
  authentication. GoTrue asks for `preferred`, which permits a device with no
  screen lock to satisfy the ceremony.
* `getCredentials` is called with
  `FetchOptionsAndroid(passKey: true, googleCredential: false, passwordCredential: false)`.
  The plugin default also requests saved passwords and Google IDs, which
  downgrades the ceremony.
* `android/app/build.gradle.kts` derives the RP ID from `SUPABASE_URL` and
  writes it into `AndroidManifest.xml` via the `weekendRpId` placeholder, so the
  manifest and the server can never disagree.

Check what a build will use:

```bash
cd android
SUPABASE_URL=https://ocypgybqfushqfzisnvs.supabase.co ./gradlew :app:logPasskeyConfig
```

Build flags:

| Flag | Effect |
| --- | --- |
| `PASSKEY_RP_ID` | Override the RP ID (use when a custom domain fronts the project). |
| `PASSKEY_REQUIRE_RP_ID=true` | Fail the build when no RP ID can be derived. |

## 4. The remaining prerequisite: Digital Asset Links

**Android will not complete a passkey ceremony unless the relying party is
associated with the installed app.** For an APK that is not distributed through
Google Play, that association is proved by a file served at:

```
https://<relying-party-id>/.well-known/assetlinks.json
```

containing the package name and the SHA-256 of the certificate that signed the
APK.

This file cannot be served from the Supabase project domain: the platform
custom domain at `*.supabase.co` does not serve `/.well-known/`. Weekend needs a
domain it controls that serves that path. Until one exists and the file is
published, Android Credential Manager rejects every passkey request with a
provider-side asset-linkage error, which surfaces in the app as a generic
"Passkey could not be completed".

### Producing the statement

```bash
python tool/gen_assetlinks.py              # both digests, with a diagnosis
python tool/gen_assetlinks.py --emit-release
```

The script reads the real keystores and never emits a placeholder digest. A
release APK signed by a different key than the one published will **not** be
associated, which is why debug and release need separate digests.

### Publishing it

Serve the JSON over HTTPS with `Content-Type: application/json`, e.g. on the
domain you point `PASSKEY_RP_ID` at. Verify afterwards:

```bash
curl -fsSL https://<rp-id>/.well-known/assetlinks.json | python -m json.tool
```

Google's asset-linter can confirm the association:

```
https://digitalassetlinks.googleapis.com/v1/statements:list?source.web.site=https://<rp-id>&relation=delegate_permission/common.handle_all_urls
```

## 5. What has and has not been verified

| Check | Result |
| --- | --- |
| Passkeys enabled, RP ID, RP origin on the live project | **PASS** — read back from the Management API |
| GoTrue issues a real creation challenge for a signed-in user | **PASS** — `challenge_id` + full `PublicKeyCredentialCreationOptionsJSON` returned |
| GoTrue issues a real authentication challenge anonymously | **PASS** |
| Credential Manager registration, assertion, session issuance | **NOT VERIFIED** — requires a physical Android device; see the final audit report |
| Digital Asset Links association | **NOT SATISFIED** — no Weekend-controlled domain currently serves the file (section 4) |

Static tests and a compiling build are explicitly **not** evidence for the last
two rows. `tests/python/test_passkey.py` reports them as `NOT VERIFIED`.
