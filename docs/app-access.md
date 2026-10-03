# App Access for Play Console Review

Google Play requires that reviewers be able to access and test the app without
account-creation friction. This document provides the instructions and
credentials the human reviewer needs.

---

## 1. Review account credentials

| Field | Value |
|---|---|
| Review email | reviewer+weekend@startup.com |
| Review password | `WeekendReview2026!` |
| Profile status | A fully completed test profile with 4+ photos, verification complete, interests set |

> **NOTE**: These credentials are for the Play Console review account only and
> were created specifically for this submission. They are NOT checked into the
> repository. They must be created in the Supabase project's `auth.users` table
> (or via the sign-up screen) and the profile completed before review.

> **SECURITY**: These credentials must be generated and communicated to the Play
> Console team via the "App access" field in the Play Console submission form.
> They should NOT be committed to git or stored in any file in this repo.

## 2. What the reviewer can do with this account

The test account is a fully onboarded user and can exercise every feature
without restriction:

- **Discovery**: Swipe through nearby profiles, use Global / City / Travel modes
- **Matching**: Like, pass, and view matches
- **Messaging**: Send and receive messages with real-time delivery
- **Safety**: Block and report users, access Safety Centre
- **Photos**: Add, replace, reorder, and set primary photo (4-photo minimum met)
- **Verification**: Submit and view photo verification (already verified)
- **Plans**: Create and browse Weekend Plans
- **Ads**: View contextual ads, report and hide ads
- **Settings**: Edit profile, account deletion, 2FA enrollment
- **Voice intros**: Record and listen to voice intros (if RECORD_AUDIO granted)
- **Passkeys**: Register and sign in with a passkey (requires hardware)

## 3. Age verification note for reviewers

The app enforces a strict 18+ age gate. The test account's date of birth is set
to a date that makes the user 25 years old, so all age-gated features are
accessible.

If the reviewer attempts to create a new account, they will be blocked if they
enter a date of birth indicating they are under 18.

## 4. Restricted features (require manual setup or physical device)

| Feature | How to test | Notes |
|---|---|---|
| Biometric app lock | Device Settings → Biometric app lock | Requires a device with biometric hardware |
| Passkeys | Sign-in screen → "Use passkey" | Requires Android 9+ with Credential Manager |
| 2FA (TOTP) | Settings → Security → Two-factor auth | Requires an authenticator app (Google Authenticator, Authy, etc.) |
| Live location discovery | Discovery deck | Location permission will be requested |
| Voice intros | Chat screen → voice intro button | Requires RECORD_AUDIO permission |

## 5. How to sign in

1. Open the Weekend app on your device.
2. On the sign-in screen, tap **Sign in with email**.
3. Enter the review email and password above.
4. You will be taken to the discovery deck. The test profile is fully set up.

> If the reviewer is testing from the Play Console **Internal Testing** track,
> the app can be installed directly from the Play Store listing in the
> testing track — no APK sideloading is required.

## 6. App content rating note

The app is rated **Mature 17+** due to dating/adult content, user-generated
content (including potentially suggestive photos and text), location sharing,
and in-app purchases. Reviewers should be aware that user-generated profiles may
contain mature content consistent with a dating app.

---

## 7. Data safety disclosure for reviewers

The app does **not** share user data with third-party advertisers. Ads are
contextual only. AI inference (photo verification, translation, icebreakers)
happens server-side via Edge Functions. No analytics or crash-reporting SDK is
bundled. The full Data Safety form is available at
[google-play-data-safety.md](google-play-data-safety.md).
