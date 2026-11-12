# Google Play Compliance Matrix — Weekend

| Requirement | Source | Evidence | Result |
|---|---|---|---|
| Application ID | AndroidManifest/Gradle | com.zypherlabs.weekend | PASS |
| Version name/code | pubspec/AAB | 2.8.6 / 19 | PASS |
| Target SDK | AAB manifest | 36 | PASS |
| Min SDK | AAB manifest | 24 | PASS |
| APK signed | apksigner verify | V2 signer OK, CN=Weekend O=ZypherLabs | PASS |
| AAB valid | bundletool dump manifest | package=com.zypherlabs.weekend, versionCode=19 | PASS |
| Privacy policy URL | repo | NOT VERIFIED (external) | NOT VERIFIED |
| Account deletion | app + edge function | implemented | PASS (code) |
| Age restrictions / child safety | Play Console | operational docs required | NOT VERIFIED |
| Data safety | Play Console | manual entry required | NOT VERIFIED |
| Physical device smoke | adb install/launch | install success, launch no crash | PASS (smoke) |
| Store icon + feature graphic | `docs/store-assets/` | 512×512 and 1024×500, RGB, no alpha | PASS |
| Screenshots | `docs/screenshots/` | 4 device captures (>= 2 required) | PASS (count) |
| Package availability in Play Console | Play Console | not checked from this environment | NOT VERIFIED |
| Firebase Android app | Firebase Console | project not configured in repo | NOT VERIFIED |
| Digital Asset Links | served file | assetlinks.json not published | NOT VERIFIED |
