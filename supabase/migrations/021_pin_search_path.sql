-- Migration: 021_pin_search_path.sql
-- Pin `search_path` on every SECURITY DEFINER function.
--
-- The vulnerability
-- -----------------
-- A SECURITY DEFINER function runs with the privileges of its owner, but
-- resolves unqualified names using the CALLER's search_path. If any schema
-- earlier than `public` in that path is writable by an attacker - which
-- includes the default `pg_temp` - a malicious object shadows a legitimate
-- one and the function executes attacker code as the definer.
--
-- Thirteen functions in this database were created as SECURITY DEFINER
-- without `set search_path`, including `handle_new_user` (the auth signup
-- trigger) and every `get_nearby_profiles` / `get_matches_for_user` /
-- `delete_user_account` revision prior to 020.
--
-- The fix
-- -------
-- `ALTER FUNCTION ... SET search_path` pins the path without recreating the
-- body, so no logic is re-implemented and no definition can drift. This is
-- the standard hardening for definer functions and changes no behaviour:
-- every function here already qualifies its tables as `public.<name>`, so
-- the pinned path only affects unqualified resolution inside the body.
--
-- Idempotent: re-running is a no-op.

-- ============================================================
-- 1. Trigger functions on auth.users
-- ============================================================
do $$
declare
    r record;
begin
    -- Discover every SECURITY DEFINER function in the public schema rather
    -- than hard-coding a list that would go stale on the next migration.
    for r in
        select p.oid::regprocedure as signature
        from pg_proc p
        join pg_namespace n on n.oid = p.pronamespace
        where n.nspname = 'public'
          and p.prosecdef
          and (p.proconfig is null
               or not exists (
                   select 1
                   from unnest(p.proconfig) cfg
                   where cfg like 'search\_path=%'
               ))
    loop
        begin
            execute format(
                'alter function %s set search_path = public, pg_temp',
                r.signature
            );
        exception when others then
            -- A function we cannot alter must not abort the whole migration;
            -- it is reported so it can be fixed by hand.
            raise warning 'could not pin search_path for %: %', r.signature, sqlerrm;
        end;
    end loop;
end;
$$;

-- ============================================================
-- 2. Explicit assertions for the security-critical functions
-- ============================================================
-- Belt and braces: if the loop above silently skipped something (a missing
-- owner privilege, say), these fail loudly at apply time rather than leaving
-- the database quietly exposed.
do $$
declare
    r record;
begin
    for r in
        select p.oid::regprocedure as signature
        from pg_proc p
        join pg_namespace n on n.oid = p.pronamespace
        where n.nspname = 'public'
          and p.prosecdef
          and not exists (
              select 1
              from unnest(coalesce(p.proconfig, '{}'::text[])) cfg
              where cfg like 'search\_path=%'
          )
    loop
        raise exception 'SECURITY DEFINER function % still has an unpinned search_path',
            r.signature;
    end loop;
end;
$$;

-- ============================================================
-- 3. Verification query (safe to run by hand)
-- ============================================================
-- Expect zero rows.
--
--   select p.oid::regprocedure
--   from pg_proc p
--   join pg_namespace n on n.oid = p.pronamespace
--   where n.nspname = 'public'
--     and p.prosecdef
--     and not exists (
--         select 1 from unnest(coalesce(p.proconfig, '{}')) cfg
--         where cfg like 'search\_path=%'
--     );
