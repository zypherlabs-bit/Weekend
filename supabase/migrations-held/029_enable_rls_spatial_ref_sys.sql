-- ============================================================
-- 029 - enable RLS on public.spatial_ref_sys
-- ============================================================
-- Resolves the Supabase Security Advisor finding `rls_disabled_in_public`
-- on `public.spatial_ref_sys` (PostGIS EPSG CRS reference table).
--
-- NOT YET APPLIED. Do not run until:
--   1. a fresh, verified backup exists, and
--   2. the owner / relacl / policy preconditions below have been confirmed
--      against the live database.
--
-- What this does (and does not do):
--   * Enables row level security with NO policies => non-owner roles
--     (anon, authenticated) are denied all rows for SELECT/INSERT/UPDATE/
--     DELETE by default, independent of their table GRANTs.
--   * Does NOT change ownership, GRANTs, the extension, or any index.
--   * Does NOT use FORCE ROW LEVEL SECURITY (the owner/extension internals
--     must stay unconstrained).
--   * Idempotent: ENABLE is a no-op when already enabled.
--
-- Rollback: alter table public.spatial_ref_sys disable row level security;

begin;

-- Preconditions - report, then fail loudly if the object is not what we expect.
do $$
declare
    v_owner          text;
    v_rls_before     boolean;
    v_force_rls      boolean;
    v_policy_count   integer;
begin
    select pg_get_userbyid(c.relowner), c.relrowsecurity, c.relforcerowsecurity
      into v_owner, v_rls_before, v_force_rls
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relname = 'spatial_ref_sys';

    if not found then
        raise exception 'public.spatial_ref_sys not found - aborting';
    end if;

    select count(*) into v_policy_count
      from pg_policies
     where schemaname = 'public' and tablename = 'spatial_ref_sys';

    raise notice
        'spatial_ref_sys: owner=%, rls_enabled=%, force_rls=%, policies=%',
        v_owner, v_rls_before, v_force_rls, v_policy_count;

    if v_policy_count > 0 then
        raise exception
            'spatial_ref_sys already has % policy(ies); review before enabling RLS',
            v_policy_count;
    end if;
end;
$$;

alter table public.spatial_ref_sys enable row level security;

-- Postcondition assertion inside the same transaction.
do $$
declare
    v_rls boolean;
begin
    select c.relrowsecurity into v_rls
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relname = 'spatial_ref_sys';

    if v_rls is not true then
        raise exception 'RLS was not enabled on public.spatial_ref_sys - rolling back';
    end if;
end;
$$;

commit;
