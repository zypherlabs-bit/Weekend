# Safety Policy

Weekend is a dating and social-discovery app for adults 18 and older. This
document sets out the safety measures built into the app and the policies users
must follow.

---

## 1. Age requirement

- **Minimum age: 18.** You must be 18 or older to register. The date-of-birth
  picker at sign-up prevents selecting a birth date that would make you under 18
  (`lib/features/profile/edit_profile.dart`).
- If you have a birthday and forget to update your profile, we will not reduce
  your access based solely on a calculated age change — but your account will
  be reviewed if reported as potentially underage.

## 2. Blocking

- You can block any other user. Blocking is mutual: a blocked user cannot see
  your profile, message you, or appear in your discovery deck.
- Blocks are enforced in both directions at the database level
  (`blocks` table, RLS).
- Blocking is idempotent and reversible from the Safety Centre.

## 3. Reporting

Report a user for any of the following reasons:

| Category | What belongs here |
|---|---|
| Harassment / bullying | Repeated unwanted messages, threats, hate |
| Spam / scam | Fake profiles, phishing, financial fraud |
| Impersonation / fake | Stolen photos, pretending to be someone else |
| Inappropriate photo | Non-consensual, explicit, or policy-violating images |
| Underage / minor | Any user suspected of being under 18 |
| Unsafe behavior | Threats of violence or self-harm |
| Message | A single message that violates policy |
| Inappropriate content | Bio, prompt answer, or shared link |
| Other | Anything that does not fit the above |

Reports are submitted through the `submit_report` RPC, are immutable once
created, and are rate-limited to 20 per day per reporter to prevent abuse.

## 4. Content moderation

### Photo moderation

- Every photo goes through moderation before it is visible to others.
- Status values: `pending` → `approved` or `rejected`.
- Only `approved` photos appear in discovery or on your profile.
- Clients cannot set `moderation_status` — it is protected by database triggers
  (`protect_photo_moderation` in migration 006).

### Prompt and bio validation

- Prompt answers are capped at 4, length-bounded, and blank answers are dropped.
- The `profile_prompts_are_valid` database function enforces the shape
  (migration 025).

## 5. Rate limiting

- Likes and passes are rate-limited via the `record_like` and `record_pass`
  RPCs (migration 026). The client cannot write to `likes` or `passes` directly.
- Reports are rate-limited to 20 per day per reporter.

## 6. Self-harm and crisis

If a user indicates intent to harm themselves or others, report it immediately
using the **Unsafe behavior** category. We encourage users in crisis to contact
local emergency services.

## 7. Data and safety

- Your exact GPS coordinates are never shared with other users. Only rounded
  distances and city/locality are visible.
- Your coordinates are stored only on your own profile row for server-side
  distance computation.
- See [privacy.md](privacy.md) for full data-handling details.

## 8. Reporting an emergency

If someone's life is in danger, contact local emergency services (e.g. 911 in
the US) immediately. Weekend does not provide emergency services or monitoring.

## 9. Account security

- Passkey authentication (native WebAuthn/credential manager) is available for
  supported devices.
- Password authentication is backed by Supabase Auth.
- Two-factor authentication (TOTP) is available under Security settings.
- Biometric app lock is available for supported devices.

## 10. Violations and consequences

- First offense: warning or temporary restriction.
- Repeat offenses or serious violations (harassment, scams, impersonation):
  account suspension.
- Underage accounts: immediate suspension pending verification; if age cannot
  be confirmed, the account is permanently deleted.
- Legal violations: account terminated and reported to authorities.
