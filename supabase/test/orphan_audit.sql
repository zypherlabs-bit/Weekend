-- orphan_audit.sql -- safe orphan audit for the Weekend project.
--
-- Run as a privileged role (SQL editor / Management API). Prints COUNTS and
-- UUIDs only: no emails, no metadata, no personal data.
--
-- Expected after migration 020 is applied:
--     missing_profiles     = 0
--     missing_user_settings = 0
--     missing_preferences  = 0

-- 1. Summary counts
select
    (select count(*) from auth.users)                                              as total_auth_users,
    (select count(*) from public.profiles)                                          as profiles_rows,
    (select count(*) from auth.users u
      where not exists (select 1 from public.profiles p where p.id = u.id))         as missing_profiles,
    (select count(*) from public.user_settings)                                     as user_settings_rows,
    (select count(*) from public.profiles p
      where not exists (select 1 from public.user_settings s where s.user_id = p.id))
                                                                                    as missing_user_settings,
    (select count(*) from public.preferences)                                       as preferences_rows,
    (select count(*) from public.profiles p
      where not exists (select 1 from public.preferences pr where pr.user_id = p.id))
                                                                                    as missing_preferences;

-- 2. Orphaned auth user ids (UUIDs only; never join out emails)
select u.id as orphaned_auth_user_id
from auth.users u
where not exists (select 1 from public.profiles p where p.id = u.id)
order by u.created_at;

-- 3. Profiles missing child rows (UUIDs only)
select p.id as profile_missing_settings_or_preferences
from public.profiles p
where not exists (select 1 from public.user_settings s where s.user_id = p.id)
   or not exists (select 1 from public.preferences pr where pr.user_id = p.id)
order by p.created_at;

-- 4. RLS sanity: confirm the three tables still have RLS enabled and the
--    ownership policies are present (must all be true)
select c.relname as table_name,
       c.relrowsecurity as rls_enabled,
       count(p.polname) as policy_count
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
left join pg_policy p on p.polrelid = c.oid
where n.nspname = 'public'
  and c.relname in ('profiles', 'user_settings', 'preferences')
group by c.relname, c.relrowsecurity
order by c.relname;

-- 5. Signup trigger sanity: handle_new_user must exist and be attached to
--    auth.users after insert
select tgname as trigger_name,
       pg_get_triggerdef(oid) as definition
from pg_trigger
where tgrelid = 'auth.users'::regclass
  and not tgisinternal;
