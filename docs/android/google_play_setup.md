# Google Play Console — Manual Checklist for `com.zypherlabs.weekend`

**Step-by-step guide to publishing Weekend under the new Android package name.**

This document covers only the manual, console-side work. Everything that could
be done from the repository was done and is verified in
[`package_migration_report.md`](package_migration_report.md).

---

## 0. Read this first

`com.zypherlabs.weekend` is a **new Android application**, not a rename.

Google Play assigns the application ID when a listing is created and **it
cannot be changed afterwards**. If `com.weekend.app` has already been
published, that listing stays exactly as it is and keeps its own users,
ratings and release history. `com.zypherlabs.weekend` is a second, separate
listing.

Practical consequences:

| | Old listing | New listing |
|---|---|---|
| Package name | `com.weekend.app` | `com.zypherlabs.weekend` |
| Play Console entry | exists | **must be created** |
| Existing users | keep the old app | get **nothing** automatically |
| Installing the new build | n/a | installs **alongside** the old app |

To move existing users across, Google offers an explicit **app bundle
migration** (transferring the listing, ratings and the signing key) and a
**credential transfer** (releasing the old package to a different signer so
users can update in place). Both are separate Play-supported processes that
are **out of scope for this package migration** and were not performed.

---

## 1. Verify the package name is available

1. Open the **Play Console** → <https://play.google.com/console>.
2. If this is a new developer account, complete developer verification first.
   You cannot create an app listing until the account is verified.
3. Click **Create app**.
4. Enter the name and the package name:
   ```
   com.zypherlabs.weekend
   ```
5. Click **Create**.

**How to read the result:**

* The app is created → the package name was **available**.
* Play Console shows *"Package name already in use"* → it is taken. Stop and
  pick another candidate; do not attempt to work around it.

> **Verification status:** this check was **NOT performed**. No Play Console
> session was available in the build environment. The availability of
> `com.zypherlabs.weekend` is therefore **not confirmed**.

---

## 2. Create the Weekend app listing

Fill in the store listing for the new package:

| Field | Value | Source |
|---|---|---|
| App name | `Weekend` | `android:label` in `AndroidManifest.xml` |
| Default language | English | — |
| App or game | App | — |
| Free or paid | Free | — |
| Category | Dating | `docs/store-listing.md` |
| Tags | Dating, Relationships, Social Networking | `docs/store-listing.md` |
| Contact email | `support@weekend.app` | `docs/store-listing.md` |
| Privacy policy URL | `https://weekend.app/privacy` | **See the warning below** |

> **Warning — the `weekend.app` domain is a parked domain.** Every path on it
> returns the same 114-byte stub and `/lander` returns HTTP 403. Play requires
> a **reachable, publicly accessible** privacy-policy URL; a parked domain will
> be rejected. This is a pre-existing blocker recorded in
> `docs/HUMAN_ACTIONS_REQUIRED.md` and `docs/store-listing.md`, and it is
> **independent of the package rename**. Host the policy on a working domain
> before submitting.

### Required declarations (all still outstanding)

| Declaration | State | Where to fill it in |
|---|---|---|
| App content — Privacy policy | **Must be updated to the new URL** | Play Console → Policy → App content |
| App content — Ads | Declarations exist in `docs/google-play-data-safety.md` | Play Console → Policy → Ads |
| App content — Target audience & content | **Not configured** | Play Console → Policy → Target audience |
| App content — News app | Not applicable | — |
| App content — COVID-19 contact tracing | Not applicable | — |
| App access | Instructions in `docs/app-access.md`; **reviewer account not created** | Play Console → App access |
| Target audience and content | **Not configured** | Play Console → Policy |
| News app | Not applicable | — |
| Data safety | Inventory in `docs/google-play-data-safety.md`; **must be reconciled with FCM** (device token, app instance ID) | Play Console → Policy → Data safety |
| Content rating | **Not completed** | Play Console → Policy → Content rating |
| Government apps / Financial features / Health | Declarations exist | Play Console → Policy |
| Store listing graphics | **Not generated** (512×512 icon, feature graphic) | Play Console → Main store listing |
| App category & contact details | Drafted in `docs/store-listing.md` | Play Console → Main store listing |

---

## 3. Configure Google Play App Signing

1. Play Console → your new app → **Test and release** → **Setup app signing**.
2. Choose **Use Google-generated keys** (the default) for the app-signing key.
3. If Google asks for an **upload key**, upload
   `android/weekend-release-keystore.jks` using the alias and passwords from
   `android/key.properties`.

   * The existing production key can be reused as the **upload key** — it is
     already the key the AAB in this repository is signed with, and Play
     re-signs the distributed app with its own app-signing key.
   * Record the **upload key SHA-256**:
     ```
     15b2f91aebc85bb26b647e94f9b3223689410b8ecf29dde798f9c5b0cc8c2594
     ```
     (This is the real fingerprint of the real certificate, read back from the
     built APK with `apksigner verify --print-certs`.)
4. If you instead choose **Use my own keys**, enrol the existing certificate
   (SHA-256 `15b2f91a…c2594`) and note that Play will then sign the app with
   it. This keeps the app's signing identity identical to the old package's,
   which is what makes a future credential transfer seamless.

---

## 4. Upload the newly generated AAB

Play requires an **Android App Bundle** for a new listing. The APK cannot be
uploaded.

| | Value |
|---|---|
| File | `build/app/outputs/bundle/release/app-release.aab` |
| Size | 104.8 MB |
| SHA-256 | `FD6F67A487D79F7326B4FE34D1825998870F24DF10CB125287E0B8A6158D87A3` |
| versionName / versionCode | 2.8.6 / 19 |
| Application ID | `com.zypherlabs.weekend` |
| minSdk / targetSdk | 24 / 36 |
| Signing certificate | `CN=Weekend, O=ZypherLabs` (RSA-4096), SHA-256 `15b2f91a…c2594` — the **same** key the previous releases used |

Steps:

1. Play Console → your app → **Test and release** → **Testing** → **Internal
   testing** → **Create new release**.
2. Upload the AAB.
3. Confirm the console shows:
   * Application ID: `com.zypherlabs.weekend`
   * Version: `2.8.5` (`18`)
   * Target SDK: 36
   * Signing certificate: the enrolled key from §3
4. Play may also offer a **"Use app bundle"** prompt if it detects an APK
   upload — do not upload the APK.

Verify the checksum before uploading:

```powershell
Get-FileHash .\build\app\outputs\bundle\release\app-release.aab -Algorithm SHA256
```

---

## 5. Configure the internal testing track

1. **Test and release** → **Testing** → **Internal testing**.
2. Set the release to **Internal testing** (maximum 100 testers).
3. Add **Release notes** describing the package migration, e.g.:
   ```
   Weekend for Android, now published under the package
   com.zypherlabs.weekend. If you previously installed a build published
   under a different package name, install this one alongside it.
   ```
4. Click **Save** → **Review release** → **Start rollout to Internal testing**.

---

## 6. Invite testers

1. **Internal testing** → **Testers** tab → **Create email list**.
2. Add the tester's Google account email addresses (or select a Google Group).
3. Under **"How testers join"**, copy the **"Copy link" / opt-in URL** and send
   it to the testers. They must follow the link and accept the invitation
   before the app becomes visible to them.
4. Alternatively use a **Google Group** as the tester group so membership can
   be managed centrally.

---

## 7. Verify the installation from Google Play

On a **physical device** (emulators without Play Services cannot install from
Play):

1. Follow the tester opt-in link, accept the invitation.
2. Open the **Google Play Store** → **Library** → **Get more** / the
   internal-testing section → install **Weekend**.
3. Confirm the installed package is the new one:
   ```bash
   adb shell pm list packages | findstr zypherlabs
   # package:com.zypherlabs.weekend
   ```
   and confirm the OLD package is still absent unless the old build was
   installed separately:
   ```bash
   adb shell pm list packages | findstr weekend
   ```
4. Launch the app and confirm it starts, then sign in or create an account to
   confirm the Supabase backend is reachable.
5. Check for crash-free sessions in **Play Console → Vitals**.

### Optional device checks after the package change

```bash
# The package name changed, so any adb command in the docs must use the new one.
adb shell am start -n com.zypherlabs.weekend/.MainActivity
adb shell am kill com.zypherlabs.weekend
```

---

## 8. Post-upload checklist

| Item | Where |
|---|---|
| Firebase Android app registered as `com.zypherlabs.weekend` (only if FCM is enabled) | Firebase Console → Project settings → Your apps → Add app → Android |
| `assetlinks.json` published with the new package name (only if passkeys are enabled) | `https://<rp-id>/.well-known/assetlinks.json` |
| Privacy policy reachable over HTTPS on a live domain | Play Console → Policy → App content |
| Reviewer credentials created and supplied | Play Console → App access |
| Store listing graphics produced | Play Console → Main store listing |
| Data safety form reconciled with FCM | Play Console → Policy → Data safety |

See [`package_migration_report.md`](package_migration_report.md) §9 for the
exact Firebase and assetlinks steps.

---

## 9. Promotion beyond internal testing

> **Not verified, and out of scope for the package migration.** Play's
> production track requires a **closed test** with **12 testers opted in for
> 14 continuous days** before the app can apply for production access. That
> requirement is unchanged by the package rename and is recorded as an open
> blocker in `docs/PLAYSTORE_LAUNCH_CERTIFICATION.md`.

Order of operations:

1. Internal testing → verify the install (§7).
2. Closed testing → 12 testers, 14 continuous days.
3. Production access → apply once the closed-test requirement is satisfied.
4. Production release → upload the next AAB and roll out.

Do not skip to production: uploading an AAB to a new listing does not
by itself grant production access.
