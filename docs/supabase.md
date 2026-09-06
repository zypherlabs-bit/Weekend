# Weekend — Supabase Backend Guide

Weekend's entire backend runs on Supabase: **Auth**, **PostgreSQL (+ PostGIS)**, **Storage**, **Realtime** and **Edge Functions**. There is no second backend.

This guide covers project setup, configuration, migrations, security, and local/production workflows.

---

## 1. Creating a Supabase project

1. Go to [supabase.com/dashboard](https://supabase.com/dashboard) and create a new project.
2. Choose a region close to your target users.
3. Save the database password somewhere secure (needed for migrations via `db push`). **Never** put it in the app.
4. From **Project Settings → API** copy:
   - **Project URL** → `SUPABASE_URL`
   - **anon/public key** → `SUPABASE_ANON_KEY`

The mobile app only ever uses the URL + anon key. The **service-role key** and **database password** stay on the server (Edge Function environment / CI secrets) and must never be committed or shipped in the APK.

## 2. Environment configuration

Copy `.env.example` to `.env` in the repository root:

```properties
SUPABASE_URL=https://your-project-ref.supabase.co
SUPABASE_ANON_KEY=public-anon-key-here
GOOGLE_CLIENT_ID=your-google-client-id.apps.googleusercontent.com   # optional
```

- The [secrets-gradle-plugin](https://github.com/google/secrets-gradle-plugin) exposes these as `BuildConfig` fields; `SupabaseClient` reads them at startup.
- `.gitignore` excludes `.env` / `.env.*`. Never commit real keys.
- If `.env` is missing or placeholder, the app runs in **offline demo mode** (sample data, no crash).

### Environment separation

Use separate Supabase projects for development / staging / production and one `.env` per environment (e.g. `.env.dev`). Never point a development build at production data. For CI, set `SUPABASE_URL` and `SUPABASE_ANON_KEY` as GitHub Secrets.

## 3. Applying database migrations

Migrations live in `supabase/migrations/` and must be applied in order:

| Migration | Contents |
|---|---|
| `001_initial_schema.sql` | Tables, constraints, PostGIS, indexes |
| `002_rls_policies.sql` | Row Level Security on every table |
| `003_database_functions.sql` | Triggers (profile creation, mutual-like matching, deletion) and RPCs (`get_nearby_profiles`, `get_matches_for_user`, `get_referral_stats`, `delete_user_account`) |
| `004_storage_policies.sql` | Private `profile-photos` bucket + storage policies |
| `005_security_hardening.sql` | Protected columns, `is_photo_verified`/`referral_code`, interest helpers |

### Option A — Supabase CLI (recommended)

```bash
npm install -g supabase        # or: brew install supabase/tap/supabase
supabase login
supabase link --project-ref <your-project-ref>
supabase db push               # applies supabase/migrations in order
```

### Option B — SQL editor

Paste each migration into **Dashboard → SQL Editor** in order. Only use this for bootstrapping; prefer the CLI afterwards.

## 4. Data model overview

```text
auth.users (Supabase Auth)
    │ 1:1 (trigger handle_new_user)
    ▼
profiles ─┬─ profile_photos          (private bucket storage_path + moderation_status)
          ├─ user_interests ── interests
          ├─ user_settings / preferences
          ├─ likes ──► passes        (mutual like trigger creates…)
          ├─ matches ── conversations ── conversation_members ── messages
          ├─ blocks / reports        (safety)
          ├─ notifications
          ├─ plans ── plan_participants
          ├─ favorite_places / crossed_paths
          └─ referrals ── referral_events
verification_requests / moderation_events        (moderation pipeline)
```

Key behaviors implemented as **database triggers/functions** (never client logic):

- **`check_mutual_like`** — A likes B + B likes A ⇒ unique `matches` row + conversation + members + referral success event.
- **`get_nearby_profiles`** — nearby-first discovery: excludes blocked/liked/passed users, respects preferences, PostGIS distance ranking with pagination.
- **`handle_user_deletion` / `delete_user_account`** — cascade-safe account deletion.

## 5. Row Level Security (RLS)

RLS is enabled on **every** user table. Policy highlights:

| Table | SELECT | INSERT | UPDATE | DELETE |
|---|---|---|---|---|
| `profiles` | authenticated users (no raw coordinates returned by RPCs) | own row (`auth.uid() = id`) | own row | never (backend only) |
| `profile_photos` | approved photos or own | own | own (metadata only) | own |
| `messages` | conversation members only | conversation members only | — | — |
| `blocks` | own blocks only | own | — | own |
| `reports` | own reports only | own | — | — |
| `verification_requests` / `moderation_events` | own / none | own / none | never | never |

**Protected columns** (migration `005`): a trigger blocks any non-service-role write to `profiles.verification_status`, `profiles.trust_score` and `profiles.profile_completion`. The client cannot mark itself verified or inflate its trust score.

### Testing RLS

For each table, verify with the SQL editor or two test accounts:

1. **Anonymous** (`anon` key, no session) → cannot read/write user rows.
2. **Authenticated as A** → can read public profiles, cannot read B's private conversations, cannot modify B's rows.
3. **Blocked user** → excluded from discovery RPC and messaging.
4. **Self-verification attempt** → `update profiles set verification_status='verified'` must fail with the column-protection exception.

## 6. Storage

- Bucket: **`profile-photos`** — **private**, 10 MB limit, MIME-restricted to `image/jpeg`, `image/png`, `image/webp`.
- Users upload only into their own folder (`<uid>/...`), enforced by storage policies.
- Other users can read only photos whose `profile_photos.moderation_status = 'approved'`.
- The app renders approved photos via signed/public URLs; original bytes stay private.

## 7. Realtime

- Chat: channel per conversation (`messages:<conversation_id>`) with `postgres_change` filters on `conversation_id` — RLS guarantees participants only receive their own rows.
- Notifications: channel per user (`notifications:<uid>`).
- Enable replication for `messages` and `notifications` under **Dashboard → Database → Replication**.

## 8. Edge Functions

Located in `supabase/functions/`:

| Function | Purpose |
|---|---|
| `photo-verification` | Trusted multi-signal photo verification (human face, AI/synthetic image, illustration, screenshot…); writes the moderation/verification result server-side |
| `account-deletion` | Secure server-side deletion of profile data + auth user |
| `icebreaker` | AI conversation starters (Gemini key stays server-side) |
| `date-ideas` | AI weekend date ideas |
| `translate-message` | Message translation (provider key stays server-side) |

Deploy:

```bash
supabase functions deploy photo-verification
supabase functions deploy account-deletion
# ... or all at once:
supabase functions deploy
supabase secrets set GEMINI_API_KEY=...   # server-side only, never in the app
```

## 9. Local development

```bash
supabase init                 # once, creates supabase/config.toml (git-ignored)
supabase start                # local stack (PostgREST, GoTrue, Storage, Realtime…)
supabase db reset             # re-run all migrations against local DB
supabase functions serve      # serve Edge Functions locally
```

Then point `.env` at the local URLs (e.g. `http://10.0.2.2:54321`) and run the app from Android Studio.

## 10. Production checklist

- [ ] Migrations applied in order (`supabase db push`)
- [ ] RLS verified per table (anonymous / other-user / blocked-user tests)
- [ ] Storage bucket private with policies from `004_storage_policies.sql`
- [ ] Realtime replication enabled for `messages` + `notifications`
- [ ] Edge Functions deployed; `GEMINI_API_KEY` set as a server secret only
- [ ] Email confirmation enabled in Auth settings (or handled explicitly)
- [ ] Separate dev/staging/prod projects; app `.env` points at the right one
- [ ] No service-role key or DB password in the repo, `.env`, CI logs or APK

## 11. Backups & recovery

- **Database:** Supabase Pro includes daily backups; additionally export with `supabase db dump` before risky changes.
- **Migrations:** all schema lives in version-controlled SQL — recovery means re-running `supabase db push` on a restored/blank database.
- **Storage:** objects are not covered by SQL dumps; periodically sync the `profile-photos` bucket to object storage if photo durability matters to you.
- **Rollback:** never edit applied migrations — add a new numbered migration that reverses the change, then `supabase db push`.
- **Monitoring:** watch Dashboard → Logs (API, Auth, Storage, Realtime, Functions). Never log passwords, tokens, or private message contents.
