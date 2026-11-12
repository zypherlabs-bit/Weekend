# Google Play Compliance Matrix — Weekend

| Requirement | Source | Evidence | Result |
|---|---|---|---|
| Application ID | AndroidManifest/Gradle | com.zypherlabs.weekend | PASS |
| Version name/code | pubspec/AAB | 2.8.4 / 17 | PASS |
| Target SDK | AAB manifest | 36 | PASS |
| Min SDK | AAB manifest | 24 | PASS |
| APK signed | apksigner verify | V2 signer OK | PASS |
| AAB valid | bundletool validate | exit 0 | PASS |
| Privacy policy URL | repo | NOT VERIFIED (external) | NOT VERIFIED |
| Account deletion | app + edge function | implemented | PASS (code) |
| Age restrictions / child safety | Play Console | operational docs required | NOT VERIFIED |
| Data safety | Play Console | manual entry required | NOT VERIFIED |
| Physical device smoke | adb install/launch | install success, launch no crash | PASS (smoke) |
