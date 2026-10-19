# Held-back migrations

Migrations in this folder are deliberately **not** part of `supabase/migrations/`
and are therefore not applied by `supabase db push`.

| File | Reason held back |
|------|------------------|
| `029_enable_rls_spatial_ref_sys.sql` | `public.spatial_ref_sys` is owned by `supabase_admin` (the `postgis` extension is installed in `public` with `extrelocatable=false`). The `postgres` role is not the owner, not a member of `supabase_admin`, and not superuser, so `ALTER TABLE ... ENABLE ROW LEVEL SECURITY` is refused with `42501 must be owner of table`. This was confirmed against production and via the Supabase SQL editor. The alternative (`REVOKE SELECT ... FROM anon, authenticated, public`) is a silent no-op because the grants were made by `supabase_admin`, not `postgres`. |
| `035_search_profiles_legacy_overload_privacy_wrapper.sql` | Written and dry-run verified (fixture-proven fix for the incognito/snooze bypass through the legacy 13-arg `search_profiles` overload — see [../docs/live-backend-audit-2026-10-19.md](../docs/live-backend-audit-2026-10-19.md), finding F1). **Not applied**: it changes discovery behaviour for every existing user, so it waits for an explicit go-ahead. It lives here rather than in `supabase/migrations/` so `supabase db push` cannot apply it unreviewed, and so the static search-SQL tests keep measuring the surface that is actually live. |

## Status

- `029` — **BLOCKED / REQUIRES VENDOR ACTION.** Applying this file requires a
  `supabase_admin` (or superuser) database connection, which no Supabase user
  role or dashboard path provides. Once such access exists, run:

  ```sql
  ALTER TABLE public.spatial_ref_sys ENABLE ROW LEVEL SECURITY;
  ```

  then record it with `supabase migration repair --status applied 029` and move
  the file back into `supabase/migrations/`.

  Risk while blocked: `public.spatial_ref_sys` exposes EPSG coordinate-system
  metadata (8500 rows), **zero user data**.

- `035` — **AWAITING APPROVAL.** Ready to apply (`supabase migration repair
  --status applied 035` after moving it back, or the same transaction wrapper
  the other 031–034 migrations used). Until then the bypass described in F1
  remains exploitable through the advanced-search screen.
