# Play Store Readiness Report — Weekend

Decision: CONDITIONAL GO — EXTERNAL ACTIONS REQUIRED

The technical work is complete and verified. Remaining items are Play Console
operational verifications (privacy policy, data safety, child-safety
standards, testing track upload) which require human/Play Console access.

**Package name:** `com.zypherlabs.weekend` (migrated from `com.weekend.app`,
which Google Play Console reported as already in use).
**Release under assessment:** v2.8.6, `versionCode` 19.

## Answers

1. Functionally complete for advertised scope? Yes for implemented scope; forgot-password deep-link handling fixed.
2. Critical user journeys working? Code-level yes; device smoke passed install/launch.
3. Forgot Password end-to-end? Client flow implemented; real email deep-link requires external Supabase redirect config verification.
4. Flutter analysis passes? Yes.
5. Full Flutter suite passes? Yes (386).
6. Full Python suite passes? Yes (344 passed, 1 skipped).
7. APK valid and signed? Yes — signed with the project release keystore
   (`CN=Weekend, O=ZypherLabs`, RSA-4096, SHA-256 `15b2f91a…c2594`), the
   same key the previous releases used. Verified with `apksigner verify`
   against the artifact downloaded back from the published release.
8. AAB valid and signed for Play upload? Yes — `bundletool validate` exits 0
   and the manifest reads `package="com.zypherlabs.weekend"`,
   `android:versionCode="19"`. Published as the `app-release.aab` asset of
   the v2.8.6 release.
9. Final APK installed/tested on physical device? Installed and launched; no crash. **Not re-verified for the migrated package** — a device re-test of the v2.8.6 build is still outstanding.
10. Dating/child-safety requirements evidenced? Partial — operational docs pending Play Console.
11. Privacy/account deletion verified? Code yes; Play Console data safety pending.
12. Version code valid for existing Play app? 19. The new package is a **separate Play listing** with its own version-code history, so it starts fresh at 19. Confirm in Play Console.
13. Source pushed to GitHub? **Yes** — `master` at `2372678`, tag `v2.8.6` pushed.
14. Verified APK published as GitHub Release asset? **Yes** — the v2.8.6 release carries `app-release.apk` (production-signed), `app-release.aab` and `app-release.apk.sha256`.
15. Can this exact build be uploaded to Google Play testing track now? Yes, AAB ready; Play Console steps remain.

## Package-name change — what a reviewer needs to know

`com.zypherlabs.weekend` is a **new Android app**, not a rename of an
existing listing. Google Play assigns the application ID when a listing is
created and cannot change it afterwards.

* The v2.8.5 release APK on GitHub carries `com.weekend.app`; v2.8.6 carries
  `com.zypherlabs.weekend`. Both are signed by the same release certificate.
* Installing v2.8.6 does **not** upgrade v2.8.5 — Android treats a different
  package as a different app, so both can be present on one device.
* Moving existing users across requires Play's own app-bundle migration or
  credential-transfer process, which is out of scope for this release.

See `docs/android/package_migration_report.md` for the full migration record
and `docs/android/google_play_setup.md` for the step-by-step Play Console
procedure.

## Outstanding external actions

| # | Action | Owner | Status |
|---|---|---|---|
| 1 | Verify `com.zypherlabs.weekend` is available in Play Console | human | **NOT VERIFIED** |
| 2 | Create the Play listing for the new package | human | **NOT VERIFIED** |
| 3 | Enrol the release keystore with Play App Signing | human | **NOT VERIFIED** |
| 4 | Upload `app-release.aab` to the internal testing track | human | **NOT VERIFIED** |
| 5 | Publish the privacy policy, terms, safety and child-safety pages on a live domain (`weekend.app` is parked and returns a stub) | human | **NOT VERIFIED** |
| 6 | Complete the Data Safety form | human | **NOT VERIFIED** |
| 7 | Complete the content rating questionnaire | human | **NOT VERIFIED** |
| 8 | Create the reviewer account for App access | human | **NOT VERIFIED** |
| 9 | Register the Firebase Android app as `com.zypherlabs.weekend` (only if FCM is enabled) | human | **NOT VERIFIED** |
| 10 | Publish `assetlinks.json` naming the new package (only if passkeys are enabled) | human | **NOT VERIFIED** |
| 11 | Re-run the device smoke test on the v2.8.6 build | human | **NOT VERIFIED** |

## CI

Both GitHub workflows were failing on every commit from 2026-11-01 until this
release. The cause was **not** a repository change: the `ubuntu-latest` runner
image moved to Ubuntu 26.04 (image `20261101.186.1`) and its default JDK
changed from 17 to 25.0.5, which AGP 8.11.1 rejects. The build failed with
the bare version string as the entire error message. Both workflows now pin
JDK 17 and are green.
