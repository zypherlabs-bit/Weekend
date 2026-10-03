# Post-Launch Operations

This runbook documents the ongoing responsibilities after Weekend is published
to the Google Play Store.

---

## 1. Monitoring

### 1.1 Crash reporting

Weekend ships **no crash-reporting SDK**. If a crash-reporting solution is added
in the future (e.g., Sentry), it must be:

- Opt-in (user consent required).
- Configured to scrub PII (no emails, profile IDs, or location in breadcrumbs).
- Scoped to crash-only collection (no analytics).

### 1.2 Play Console crash and ANR

- Check **Android Vitals** in the Play Console daily for the first week after
  launch.
- Watch for ANR rate > 0.1% or crash rate > 1%.
- Investigate any spike within 24 hours.

### 1.3 Backend health

- Supabase logs: check Edge Function invocations and database query latency.
- `serve-ad`, `account-deletion`, `photo-verification`, and `translate-message`
  functions should have < 500ms p95 latency.
- Database: watch for slow queries on `search_profiles` and
  `get_nearby_profiles` (PostGIS spatial queries).

## 2. Content moderation

### 2.1 Reports

- All `underage` reports trigger immediate human review (highest priority).
- Other report categories are triaged during business hours.
- SLA: First response within 24 hours; resolution within 72 hours.

### 2.2 Photo moderation

- New photos enter `pending` automatically via the `enforce_photo_moderation`
  trigger (migration 006).
- Review queue: Supabase Studio or a custom moderation tool.
- Rejected photos are hidden from other users; the uploader is notified.

## 3. Release process

### 3.1 Version codes

- Every Play Store release must increment `versionCode`. This is managed via
  `pubspec.yaml` → `version: 2.7.0+12` (the `+12` suffix is the versionCode).
- Do **not** reuse a versionCode. Play Console will reject it.

### 3.2 AAB submission

```bash
flutter build appbundle --release \
  --dart-define=SUPABASE_URL=$SUPABASE_URL \
  --dart-define=SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY
```

Upload `build/app/outputs/bundle/release/app-release.aab` to Play Console.

### 3.3 Signing

- The production keystore is enrolled with **Play App Signing**. The app is
  re-signed by Google; do not attempt to self-sign for Play uploads.
- Backup the keystore and `key.properties` in a secure secret manager
  (not in git).
- Never commit `key.properties` (it is in `.gitignore`).

## 4. Policy compliance maintenance

### 4.1 Target API updates

- Monitor Google's annual Fall release for new target API requirements.
- Update `compileSdkVersion` and `targetSdkVersion` at least 3 months before
  the deadline.
- Test on the new Android version before updating.

### 4.2 Data Safety form updates

- If any data type is added, removed, or repurposed, update the **Data Safety**
  section in the Play Console and this document.
- Review quarterly.

### 4.3 Age-restricted content

- Update the age gate and Community Guidelines whenever content policies change.
- Maintain the underage report escalation procedure.

## 5. Incident response

### 5.1 Data breach

If a data breach is discovered:

1. Contain the breach (disable affected Edge Functions, revoke compromised keys).
2. Assess the scope (which tables, which users).
3. Notify Google within 72 hours if PII is compromised.
4. Communicate to affected users via email.
5. Document in `docs/security-incident-log.md`.

### 5.2 Underage account

When an underage report is confirmed:

1. Suspend the account (set `profiles.verification_status = 'rejected'`).
2. Contact the user for age verification.
3. If no valid ID is provided, escalate to `account-deletion` Edge Function.
4. Log the action in the moderation audit trail.

## 6. Quarterly review

| Item | Owner | Frequency |
|---|---|---|
| Play Console policy updates | Product lead | Quarterly |
| Data Safety form accuracy | Privacy lead | Quarterly |
| Content moderation queue | Community team | Weekly |
| Crash and ANR metrics | Engineering lead | Daily first week, weekly thereafter |
| Age gate effectiveness | Trust & Safety | Monthly |
| Signing key backup verification | DevOps | Semi-annual |

## 7. Rollback procedure

If a release causes a critical issue:

1. **Pause the rollout** in Play Console.
2. **Revert the code** to the last stable commit.
3. **Build a new AAB** from the stable branch.
4. **Upload as a higher versionCode** (do not reuse; Play Console enforces
   monotonically increasing version codes).
5. **Resume rollout** once validated.

If the rollback requires backend changes (migration), apply a new migration
that reverses the change. **Never modify a committed migration** — always add
a new one.
