# Held-back migrations

Migrations in this folder are deliberately **not** part of `supabase/migrations/`
and are therefore not applied by `supabase db push`.

| File | Reason held back |
|------|------------------|
| `029_enable_rls_spatial_ref_sys.sql` | `public.spatial_ref_sys` is owned by `supabase_admin` (the `postgis` extension is installed in `public` with `extrelocatable=false`). The `postgres` role is not the owner, not a member of `supabase_admin`, and not superuser, so `ALTER TABLE ... ENABLE ROW LEVEL SECURITY` is refused with `42501 must be owner of table`. This was confirmed against production and via the Supabase SQL editor. The alternative (`REVOKE SELECT ... FROM anon, authenticated, public`) is a silent no-op because the grants were made by `supabase_admin`, not `postgres`. |

`035_search_profiles_legacy_overload_privacy_wrapper.sql` used to live here. It
was reviewed, dry-run, **applied** to the live project and then moved to
`supabase/migrations/` where it now belongs, together with `036`. There is only
one held-back file left.

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

- `035` — **APPLIED AND MOVED.** Approved, applied to the live project and
  moved to `supabase/migrations/`. The F1 bypass is closed and was re-proved
  with fixtures afterwards (`tool/privacy_bypass_probe.py` now reports
  `no bypass observed`). No further action.
