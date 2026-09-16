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
| Storage | ~80 MB free |
| Permissions used | Internet, network state, camera (QR invitations), coarse/fine location (nearby discovery, optional), notifications (Android 13+) |

Permissions are requested in context and can be declined — location and camera
are only used for the features that need them.

---

## 2. Download

1. Open the [latest release](https://github.com/zypherlabs-bit/Weekend/releases/latest).
2. Download the current APK asset, for example
   `Weekend-v2.0.1-release.apk` (~74 MB).
3. Optionally download the matching checksum file
   `Weekend-v2.0.1-release.apk.sha256`.

> The asset file name embeds the version (`Weekend-v<version>-release.apk`), so it
> changes with every release. The release page always lists the newest one.

---

## 3. Verify the download (recommended)

Compare the SHA-256 hash of the file you downloaded with the published checksum.

**Windows (PowerShell)**

```powershell
Get-FileHash .\Weekend-v2.0.1-release.apk -Algorithm SHA256
```

**macOS / Linux**

```bash
shasum -a 256 Weekend-v2.0.1-release.apk
# or:
sha256sum Weekend-v2.0.1-release.apk
```

The output must match the contents of `Weekend-v2.0.1-release.apk.sha256` in the
release. If it does not match, do not install the file and download it again.

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
package (`com.weekend.app`) and signing key are unchanged.

---

## 6. First run

- Weekend runs in **offline demo mode** (bundled sample data) when it is built
  without Supabase credentials. Official release APKs are built with a backend
  and require sign-in for account features.
- Location, camera and notification permissions are requested only when the
  corresponding feature is opened.
- You can review what the app stores and how to limit it in
  [privacy.md](privacy.md).

---

## 7. Uninstall

Long-press the Weekend icon → **App info** → **Uninstall**. Uninstalling removes
the local app data; to remove server-side account data, see the account deletion
notes in [privacy.md](privacy.md) and the current status of the in-app deletion
flow in the [Known limitations](../README.md#known-limitations) section.

---

## Troubleshooting

| Symptom | Likely cause / fix |
|---------|--------------------|
| "App not installed" | The APK is truncated — re-download and verify the SHA-256 checksum. |
| Install blocked | The app you are installing *from* lacks the "install unknown apps" permission. Grant it for that app only. |
| App opens but shows sample profiles | The build is in offline demo mode (no Supabase configuration). |
| Nearby discovery is empty | Location permission denied, location services disabled, or discovery radius set too small. |
| Camera does not open in the QR scanner | Camera permission was denied — enable it in Android settings and try again. |
