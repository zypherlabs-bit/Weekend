# Installing Weekend

This page is for **people who want to use the Weekend Android app**. If you want
to build it from source instead, read [getting-started.md](getting-started.md).

Weekend is distributed as a signed Android APK through
[GitHub Releases](https://github.com/zypherlabs-bit/Weekend/releases) — it is not
currently published on Google Play.

---

## 1. Requirements

| | |
|---|---|
| Operating system | Android 7.0 (API 24) or newer |
| Architecture | `arm64-v8a`, `armeabi-v7a` or `x86_64` |
| Storage | ~150 MB free |
| Permissions used | Internet, network state, camera (QR invitations), coarse/fine location (nearby discovery, optional), notifications (Android 13+) |

Permissions are requested in context and can be declined — location and camera
are only used for the features that need them.

---

## 2. Download

1. Open the [latest release](https://github.com/zypherlabs-bit/Weekend/releases/latest).
2. Download the current APK asset — for the current release that is
   [`app-release.apk`](https://github.com/zypherlabs-bit/Weekend/releases/download/v2.8.6/app-release.apk) (~125 MB).
3. Optionally download the matching checksum file, if the release page lists
   one (`<asset>.sha256`).

> The asset file name is chosen by the publishing workflow, so it changes with
> every release. The release page always lists the newest one, and
> `releases/latest` always resolves to the current version.

---

## 3. Verify the download (recommended)

Compare the SHA-256 hash of the file you downloaded with the published checksum.
Some releases ship a `<asset>.sha256` file next to the APK; when one is
present, compare against it.

**Windows (PowerShell)**

```powershell
Get-FileHash .\app-release.apk -Algorithm SHA256
```

**macOS / Linux**

```bash
shasum -a 256 app-release.apk
# or:
sha256sum app-release.apk
```

The output must match the contents of the `.sha256` file in the release, if one
was published. If it does not match, do not install the file and download it
again.

Hash verification confirms the file was not corrupted or modified in transit. It
does not replace verifying the signature of the APK issuer.

---

## 4. Install on Android

1. Open the downloaded `.apk` from your notification shade or file manager.
2. Android will show a security prompt explaining that the app is from a source
   outside the Play Store. Allow it for the app you are installing from (Files,
   Chrome, or your browser).
   - Modern Android offers a per-app permission such as
     *"Allow this source to install unknown apps"*.
   - **Weekend does not ask you to disable Play Protect or any other Android
     protection**, and the app never attempts to install anything silently.
3. Confirm **Install** and wait for Android to complete the installation.
4. Launch **Weekend** from your launcher.
5. Create an account with an email address and password, or sign in if you
   already have one.

If your device blocks the install, check that the APK is not quarantined by your
file manager, and confirm you downloaded it from
`github.com/zypherlabs-bit/Weekend`.

---

## 5. Updating

Download the newest APK from the [releases page](https://github.com/zypherlabs-bit/Weekend/releases)
and install it over the existing app. Android keeps your data as long as the
package (`com.zypherlabs.weekend`) and signing key are unchanged.

> **Upgrading from v2.8.5 or earlier?** Those builds were published under the
> package `com.weekend.app`. v2.8.6 is the first build published as
> `com.zypherlabs.weekend`, and Android treats a different package name as a
> **different app**. Installing it will therefore **not** upgrade the previous
> one: both will be present on the device. Uninstall `com.weekend.app` first
> if you want only the new one, then install the new APK. Your account lives
> on the server, so signing in again with the same email and password restores
> everything.

---

## 6. First run

- Weekend runs in **offline demo mode** (onboarding and sign-up on-device, no
  sample data) when it is built without Supabase credentials. Official release
  APKs are built with a backend and require sign-in for account features.
- Location, camera and notification permissions are requested only when the
  corresponding feature is opened.
- You can review what the app stores and how to limit it in
  [privacy.md](privacy.md).

---

## 7. Uninstall

Long-press the Weekend icon → **App info** → **Uninstall**. Uninstalling removes
the local app data; for server-side account data use **Settings → Delete
Account** (see the account deletion notes in
[privacy.md](privacy.md)); operators can verify the flow with
[verification-2fa-deletion.md](verification-2fa-deletion.md).

---

## Troubleshooting

| Symptom | Likely cause / fix |
|---------|--------------------|
| "App not installed" | The APK is truncated — re-download and verify the SHA-256 checksum. |
| Install blocked | The app you are installing *from* lacks the "install unknown apps" permission. Grant it for that app only. |
| App opens but shows sample profiles | The build is in offline demo mode (no Supabase configuration). |
| Nearby discovery is empty | Location permission denied, location services disabled, or discovery radius set too small. |
| Camera does not open in the QR scanner | Camera permission was denied — enable it in Android settings and try again. |
