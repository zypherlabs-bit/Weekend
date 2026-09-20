# Live Verification Plan — Two-Factor Auth & Account Deletion

Audience: operators / QA verifying a **live** Supabase project (hosted or
self-hosted) before opening a Weekend deployment to users. Every case below
maps to real code paths; run it top-to-bottom against a **staging** project,
never against production data.

Scope:

1. Supabase TOTP two-factor auth — enroll → challenge → verify → disable —
   plus the client-side lockout guard and the router gate.
2. Server-side account deletion — `account-deletion` Edge Function +
   `delete_user_account` RPC — including the negative/authorization cases.

Part of the Weekend documentation set — start at [README.md](README.md).

---

## 0. Findings from static review (read first)

While planning this verification, two defects on the deletion path were found
and are fixed by `009_account_deletion_service_role.sql`; DEL-01 and DEL-04
verify the fix live:

- **(fixed by 009) Missing function permission.** Migration 006 revoked
  `EXECUTE` from `PUBLIC` and re-granted only to `authenticated`, so the
  service role could no longer run `delete_user_account` at all — the Edge
  Function path failed with *permission denied* before touching any data.
- **(fixed by 009) Ownership guard vs. service role.** `assert_self` raises
  whenever `auth.uid()` is null, which is *always* the case for the
  service-role call the Edge Function makes. 009 lets the service role bypass
  `assert_self` (the function already validates the caller's JWT and rejects
  cross-account deletion in `authenticate()`), while direct authenticated
  callers remain guarded.
- **(open observation) Deletion audit trail.** `moderation_events.user_id`
  references `profiles (on delete cascade)` (001), so the `delete` audit row
  written inside the RPC is itself cascade-deleted when the profile goes.
  Compliance-sensitive deployments should consider `on delete set null` or a
  separate durable deletion log in a future migration.

## 1. Prerequisites

| Item | Requirement |
|---|---|
| Supabase project | A dedicated **staging** project (never production data) |
| CLI | `supabase` CLI ≥ current, logged in (`supabase login`) |
| Database | Migrations `001`–`009` applied in order (see [supabase.md](supabase.md) §3) |
| Edge Function | `account-deletion` deployed and listed under Edge Functions |
| Auth setting | Email confirmation chosen deliberately (it gates AUTH-01) |
| TOTP MFA | Hosted Supabase: TOTP MFA works out of the box. Self-hosted GoTrue: the MFA feature must be enabled |
| Test accounts | `verify-1@example.com`, `verify-2@example.com` (password auth), both with completed profiles |
| Authenticator app | Google Authenticator / Aegis / 1Password — anything TOTP-capable |
| App build | Release APK or `flutter run` with `--dart-define=SUPABASE_URL=… --dart-define=SUPABASE_ANON_KEY=…` pointing at the staging project |
| Tools | `curl`, `psql` (or the Dashboard SQL editor) |

## 2. Environment preparation

```bash
supabase login
supabase link --project-ref <staging-project-ref>
supabase db push            # applies 001…009 in order
supabase functions deploy account-deletion
```

Capture for the recipes below:

```bash
export SUPABASE_URL=https://<staging-project-ref>.supabase.co
export SUPABASE_ANON_KEY=<anon/public key>
```

Sign in as a test user to obtain an access token (the app does the equivalent
via `signInWithPassword`):

```bash
export ACCESS_TOKEN=$(curl -s -X POST "$SUPABASE_URL/auth/v1/token?grant_type=password" \
  -H "apikey: $SUPABASE_ANON_KEY" -H "Content-Type: application/json" \
  -d '{"email":"verify-1@example.com","password":"<password>"}' | sed -n 's/.*"access_token":"\([^"]*\)".*/\1/p')
```

## 3. Test matrix

### 3.1 Authentication baseline (no MFA enrolled yet)

| ID | Case | Steps | Expected |
|---|---|---|---|
| AUTH-01 | Sign-up + confirmation gate | Sign up a fresh user in the app | If email confirmation is on: unauthenticated + "check your email" message; after confirming, sign-in succeeds |
| AUTH-02 | Plain sign-in | Sign in as a user with **no** MFA factor | Straight to `/home`; `assuranceLevel` reports `current: aal1, next: aal1`; no challenge screen |

### 3.2 Two-factor authentication (TOTP)

Client code under test: `AuthRepository` (`enrollTotp`, `verifyEnrollment`,
`verifyLoginCode`, `listFactors`, `assuranceLevel`, `unenrollFactor`),
`AuthNotifier.verifyMfaChallenge` + `MfaAttemptLimiter`, `MfaChallengeScreen`,
`MfaEnrollmentScreen`, and the redirect rules in `app_router.dart:42-46`.

| ID | Case | Steps | Expected |
|---|---|---|---|
| MFA-01 | Enrollment happy path | Settings → Security → Two-Factor → enable → scan QR (or paste secret) → enter current 6-digit code | Snackbar "Two-factor authentication enabled."; screen shows 2FA enabled; assurance `next: aal2`; the TOTP secret appears **only once** and is never persisted client-side |
| MFA-02 | Sign-in step-up gate | Sign out, sign in again with the same credentials | Router pins the session on `/mfa-challenge` (`needsMfaChallenge`); other routes redirect back to it |
| MFA-03 | Wrong codes → lockout | Enter an incorrect code 4×, then a 5th | Failures 1–4 show "Incorrect or expired code. N attempt(s) left…"; the 5th trips the client lockout: "Two-factor verification is locked for 5 minutes." |
| MFA-04 | Correct code after recovery | Wait out the lockout, enter a valid code | Session promoted to AAL2, router releases to `/home`, location preferences load |
| MFA-05 | Cancel challenge | Tap back / "Use a different account" during the challenge | `signOut` is called; app returns to `/auth`; the abandoned access token is rejected by `GET /auth/v1/user` (401) |
| MFA-06 | Disable factor | Settings → Two-Factor → Disable → confirm → sign in again | Factor unenrolled; re-login goes straight to `/home` (no step-up) |
| MFA-07 | Server-side rate limiting | With the client limiter bypassed (fresh app install), submit wrong codes beyond GoTrue's own limits | Supabase Auth itself starts rejecting attempts (4xx); the client lockout is advisory, the server stays authoritative |

### 3.3 Account deletion

Server code under test: `account-deletion/index.ts` (JWT authentication →
self-ownership guard → `delete_user_account` RPC → `auth.admin.deleteUser` →
storage cleanup → session revocation) and `delete_user_account` (009).

| ID | Case | Steps | Expected |
|---|---|---|---|
| DEL-01 | Happy path (post-009) | Give `verify-1` a photo, a match and a message, then Settings → Delete Account → confirm | Function returns `success: true`; app signs out to onboarding. §4.2 post-conditions all pass |
| DEL-02 | Unauthenticated call | `curl` the function **without** the user's `Authorization: Bearer` | `401/403` — apikey alone is not a user identity |
| DEL-03 | Cross-user call | User A's valid JWT with user B's `userId` in the body | `403` "Unauthorized: cannot delete another user's account"; B's data untouched |
| DEL-04 | RPC ownership (post-009) | (a) As `authenticated`, call the RPC with another user's id; (b) confirm the service-role path succeeds as in DEL-01 | (a) raises `Not authorized to access another user's data`; (b) succeeds — the 009 contract |
| DEL-05 | Session revocation | After DEL-01, reuse the deleted user's old access token | `GET /auth/v1/user` → `401` (`signOutAllSessions` ran) |
| DEL-06 | Offline/demo build | Run without `--dart-define`s → Settings → Delete Account | In-app error "Account deletion is unavailable without a backend connection."; no crash, state intact |
| DEL-07 | Factors die with the user | After DEL-01, check `auth.mfa_factors` | Zero rows for the deleted user |

## 4. Copy-paste recipes

### 4.1 Edge Function calls (curl)

```bash
# DEL-02 — no Authorization header
curl -s -o /dev/null -w '%{http_code}\n' -X POST "$SUPABASE_URL/functions/v1/account-deletion" \
  -H "apikey: $SUPABASE_ANON_KEY" -H "Content-Type: application/json" \
  -d '{"userId":"00000000-0000-0000-0000-000000000000"}'
# expected: 401 or 403

# DEL-03 — valid JWT but a foreign userId
curl -s -X POST "$SUPABASE_URL/functions/v1/account-deletion" \
  -H "apikey: $SUPABASE_ANON_KEY" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"userId":"<user-b-uuid>"}'
# expected: 403 {"error":"Unauthorized: cannot delete another user's account"}

# DEL-01 — self deletion (userId must equal the token's sub)
curl -s -X POST "$SUPABASE_URL/functions/v1/account-deletion" \
  -H "apikey: $SUPABASE_ANON_KEY" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"userId":"<user-a-uuid>","reason":"verification_run"}'
# expected: 200 {"success":true,...,"cleanedUp":{"success":true,...}}
```

### 4.2 SQL post-conditions (psql or Dashboard SQL editor)

```sql
-- DEL-01 post-conditions for <user-a-uuid>: every count must be 0.
select count(*) from auth.users            where id = '<user-a-uuid>';
select count(*) from public.profiles       where id = '<user-a-uuid>';
select count(*) from public.messages       where sender_id = '<user-a-uuid>';
select count(*) from public.matches        where user1_id = '<user-a-uuid>'
                                             or user2_id = '<user-a-uuid>';
select count(*) from public.blocks         where blocker_id = '<user-a-uuid>';
-- DEL-07: no orphaned factors.
select count(*) from auth.mfa_factors      where user_id = '<user-a-uuid>';

-- DEL-04 (a): a direct cross-user call as a normal user must raise:
set local role authenticated;
set local request.jwt.claims = '{"sub":"<user-a-uuid>","role":"authenticated"}';
select public.delete_user_account('<user-b-uuid>', 'idor_probe');  -- Not authorized …
reset all;
```

> Audit-trail note (§0 open observation): `moderation_events` rows for the
> deleted user are gone after deletion — the row written by the RPC is
> cascade-deleted with the profile (001). Record this as a known limitation
> unless the durable-audit migration lands first.

## 5. Go / No-Go

| Gate | Verdict |
|---|---|
| AUTH-01/02 pass | ☐ |
| MFA-01…06 pass (enroll, gate, lockout, recovery, cancel, disable) | ☐ |
| MFA-07: server rejects attempts without relying on the client limiter | ☐ |
| DEL-01 passes with all §4.2 post-conditions | ☐ |
| DEL-02…05 negative cases pass | ☐ |
| DEL-06: unconfigured build degrades gracefully | ☐ |
| Migrations 001–009 applied; `account-deletion` deployed | ☐ |

**Go** requires every box checked. Any failure → fix, re-run the affected
cases, and re-push/deploy before tagging a release.

## 6. Release follow-ups

1. Record results in the release ticket; attach the §4.1 outputs.
2. Refresh `SHA256SUMS.txt` from the **CI-built** APK of the new tag (never a
   local build artifact).
3. Track the durable deletion-audit observation from §0 as a backlog item.

## Related documents

- [supabase.md](supabase.md) — project setup, migrations, function deployment
- [security.md](security.md) — server-side enforcement model and threat model
- [testing.md](testing.md) — local suites (`flutter test`, `supabase/test/rls_test.sql`)


