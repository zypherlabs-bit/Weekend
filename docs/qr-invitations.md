# QR Invitations & Referrals

Weekend invites people **app to app** using QR codes instead of a public marketing
website: an existing user shows a code, a new user scans it inside Weekend, and
the sign-up is attributed to the inviter.

Key files: `lib/services/qr_invitation_service.dart`,
`lib/features/qr/qr_invite_screen.dart`,
`lib/features/qr/qr_scanner_screen.dart`, `lib/models/models.dart`
(`QRInvitation`, `QRInvitationResult`),
`supabase/migrations/001_initial_schema.sql` (`referrals`,
`referral_events`), `supabase/migrations/003_database_functions.sql`
(`get_referral_stats`, `check_mutual_like` referral credit).

---

## 1. Flow

```text
Create a Weekend invitation (in app)
        ↓
Generate a signed QR code
        ↓
Another person scans it with the Weekend in-app scanner
        ↓
Weekend validates the invitation (format → signature → expiry → server lookup)
        ↓
Sign up or sign in
        ↓
Referral attribution
```

| Step | Implementation |
|------|----------------|
| Create | `QRInviteScreen` builds an invitation from the signed-in user's `referralCode`, id and display name, then renders it with `qr_flutter` |
| Scan | `QRScannerScreen` uses `mobile_scanner` with the device camera; camera permission is requested for this screen only |
| Validate | `QRInvitationService.validateInvitationServerSide(payload)` |
| Attribute | The scanner records the referral for the current user; the database credits the referral when the referee matches (`check_mutual_like`) |

Invitations exist only to onboard people into Weekend — there is no web landing
page, no link-that-installs-an-app, and no email marketing funnel.

---

## 2. Invitation payload

An invitation is a single `|`-separated record, versioned so the format can
evolve safely:

| Field | Purpose |
|-------|---------|
| Prefix | Identifies the string as a Weekend invitation |
| Invite id | Random identifier for this specific invitation |
| Referral code | The inviter's referral code |
| Inviter id | The inviter's user id |
| Inviter name | Display name shown to the scanning user |
| Version | Payload version (`1` today); unknown versions are rejected |
| Created at | Creation timestamp |
| Expires at | Creation + **30 days** |
| Signature | Integrity value computed over the preceding fields |

The signature is an HMAC-SHA256 digest, base64url-encoded (padding stripped).
Invitations are **not** stored server-side before being scanned: the QR carries
the data, and the server is consulted to confirm the referral code is real and
still usable.

### Security note

The signature is produced with a key the app ships with, so it functions as a
**tamper and corruption check**, not as a trust boundary — the authoritative
checks are the server-side lookup and the `referrals` table state. A future
iteration could move signing to a server-held secret; until then, treat a scanned
invitation as untrusted input that is validated against the database rather than
as proof of identity.

---

## 3. Validation order

`validateInvitationServerSide` runs cheap, local checks first and only then talks
to the server:

1. **Format** — the payload must parse into the expected shape; otherwise
   `QRInvitationResult.invalid('Invalid invitation format: …')`.
2. **Version** — must equal the supported version (`Unsupported invitation
   version`).
3. **Expiry** — `expiresAt` must be in the future (`Invitation has expired`).
4. **Signature** — recompute and compare (`Invalid invitation signature`).
5. **Server lookup** — query `referrals` for the code **and** the inviter id
   (`Referral code not found` when there is no match).
6. **Reuse check** — if the referral is already `successful`, the scan is
   rejected (`This referral has already been used`).

In offline demo mode (`SupabaseConfig.client == null`) the local checks still run;
there is simply no server to confirm against.

Self-referrals are detected separately: `QRInvitationService.isSelfReferral`
compares the scanned code with the scanning user's own `profiles.referral_code`
and rejects it.

---

## 4. Database side

| Table | Role |
|-------|------|
| `referrals` | One row per referral: `referral_code`, `referrer_id`, `referee_id`, `status`, `credited_at` |
| `referral_events` | Append-only log of referral events (for example `successful`) |
| `profiles.referral_code` | The referral code shown on your invitation |
| `get_referral_stats(p_user_id)` | RPC returning referral statistics for the caller (ownership enforced with `assert_self`) |

Credit on completion: when two users match, the `check_mutual_like` trigger marks
a pending referral whose `referee_id` is the matched user as `successful` and
writes a `referral_events` row.

**Current limitation.** Creating the pending referral row from a scanned
invitation depends on a `record_referral` RPC that is not yet defined in
`supabase/migrations`. Generating, scanning and validating invitations works, and
the credit-on-match logic exists in the database; the row-creation step is a
roadmap item. See [Known limitations](../README.md#known-limitations).

---

## 5. Referral anti-abuse

- Self-referrals are rejected before the server is called.
- Reusing a `successful` referral is rejected server-side.
- Invitations expire after 30 days.
- Unknown versions are rejected, so an old client cannot push a malformed record
  through a newer server.
- The server lookup requires **both** the referral code and the inviter id to
  match the same row, so a code cannot be paired with a different inviter.

---

## 6. Related documents

- [architecture.md](architecture.md) — where the QR service sits
- [security.md](security.md) — broader threat model
- [privacy.md](privacy.md) — what invitation data is stored
- [../README.md](../README.md#qr-invitations) — the user-facing summary