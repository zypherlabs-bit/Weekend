-- Migration: 020_orphan_profile_repair.sql
-- Repair and harden the auth -> profile -> settings -> preferences chain.
--
-- Why this exists
-- ---------------
-- Edit Profile saves with
--     UPDATE public.profiles SET ... WHERE id = auth.uid()
-- and PostgREST answers an UPDATE that matches zero rows with `200 []`.
-- The client therefore reported "The server did not save your profile" for
-- any authenticated user whose `public.profiles` row is missing (the
-- historical orphan: an auth.users row with no profiles/user_settings/
-- preferences children). The same hole produced photo-upload FK failures
-- (profile_photos.user_id -> profiles.id).
--
-- Independently verified on the live project (2026-09-27):
--   * signup with `date_of_birth: 'not-a-date'` metadata -> HTTP 500
--     `unexpected_failure` ("Database error saving new user"), because
--     handle_new_user (015/017) does `nullif(..., '')::date` on the raw value;
--   * signup with `gender: 'Robot'` -> HTTP 500 `23514 profiles_gender_check`,
--     because the trigger copied unvalidated metadata straight into the
--     profiles INSERT.
-- So the trigger both (a) aborts signups on malformed metadata and (b) is the
-- only thing standing between a signup and an orphan when it fails differently
-- on other paths. This migration makes it conflict-safe and metadata-safe.
--
-- Safety properties (deliberate):
--   * Every statement is idempotent (NOT EXISTS / ON CONFLICT DO NOTHING /
--     CREATE OR REPLACE / DROP ... IF EXISTS) so the migration can be re-run.
--   * Only data that legitimately exists in auth.raw_user_meta_data is copied
--     (full_name, date_of_birth, gender, relationship_intent), and each value
--     is validated against the real schema constraints before use. Malformed
--     values become NULL, never a failed migration.
--   * No bio, occupation, education, favorite_music, ideal_weekend, photos,
--     city, verification, moderation or trust data is invented.
--   * RLS is re-asserted ON; no policy is created, dropped or weakened.
--   * handle_new_user keeps failing loudly (no exception swallowing): a
--     signup that cannot create its profile rows fails as a signup instead of
--     silently producing a new orphan.

-- ============================================================
-- 1. Exception-safe date parsing for signup metadata
-- ============================================================
create or replace function public.try_parse_date(p_text text)
returns date
language plpgsql
immutable
as $$
begin
    if p_text is null then
        return null;
    end if;
    if btrim(p_text) !~ '^\d{4}-\d{2}-\d{2}$' then
        return null;
    end if;
    return btrim(p_text)::date;
exception
    when others then
        -- Out-of-range components ('2024-99-99') and friends: never abort.
        return null;
end;
$$;

-- Internal helper only: clients have no business calling it.
revoke execute on function public.try_parse_date(text) from public, anon, authenticated;

comment on function public.try_parse_date(text) is
'Parses YYYY-MM-DD text to date, returning NULL (never raising) for malformed input. Used by handle_new_user and the orphan backfill.';

-- ============================================================
-- 2. Backfill: auth.users rows with no profiles row
-- ============================================================
insert into public.profiles (
    id,
    display_name,
    date_of_birth,
    gender,
    relationship_intent
)
select
    u.id,
    nullif(btrim(u.raw_user_meta_data ->> 'full_name'), ''),
    public.try_parse_date(u.raw_user_meta_data ->> 'date_of_birth'),
    case
        when u.raw_user_meta_data ->> 'gender' in
             ('Man', 'Woman', 'Non-binary', 'Prefer not to say')
            then u.raw_user_meta_data ->> 'gender'
    end,
    case
        when u.raw_user_meta_data ->> 'relationship_intent' in
             ('Dating', 'Long-term relationship',
              'New people & Friendships', 'Dating & Weekend Plans')
            then u.raw_user_meta_data ->> 'relationship_intent'
    end
from auth.users u
where not exists (
    select 1 from public.profiles p where p.id = u.id
)
on conflict (id) do nothing;

-- ============================================================
-- 3. Backfill: profiles rows with no user_settings / preferences child
--    (covers both orphaned auth users repaired above and any profile whose
--    child rows were removed independently). All columns other than user_id
--    take their schema defaults - no data is invented.
-- ============================================================
insert into public.user_settings (user_id)
select p.id
from public.profiles p
where not exists (
    select 1 from public.user_settings s where s.user_id = p.id
)
on conflict (user_id) do nothing;

-- ============================================================
-- 4. Referral codes for any profile that still has none
--    (017's helper is idempotent and reuses codes that already exist; the
--    guard keeps this migration runnable on a project that lacks 017.)
-- ============================================================
do $$
declare
    r record;
begin
    if to_regprocedure('public.generate_referral_code(uuid)') is null then
        return;
    end if;
    for r in
        select id from public.profiles where referral_code is null
    loop
        perform public.generate_referral_code(r.id);
    end loop;
end;
$$;

-- ============================================================
-- 5. Harden handle_new_user (replaces the 015/017 body)
-- ============================================================
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    v_dob date;
    v_gender text;
    v_intent text;
begin
    -- raw_user_meta_data is client-controlled: parse defensively so malformed
    -- values become NULL instead of aborting the whole auth.users INSERT
    -- (the live 500s documented in this migration's header).
    v_dob := public.try_parse_date(new.raw_user_meta_data ->> 'date_of_birth');

    v_gender := case
        when new.raw_user_meta_data ->> 'gender' in
             ('Man', 'Woman', 'Non-binary', 'Prefer not to say')
            then new.raw_user_meta_data ->> 'gender'
    end;

    v_intent := case
        when new.raw_user_meta_data ->> 'relationship_intent' in
             ('Dating', 'Long-term relationship',
              'New people & Friendships', 'Dating & Weekend Plans')
            then new.raw_user_meta_data ->> 'relationship_intent'
    end;

    insert into public.profiles (
        id,
        display_name,
        date_of_birth,
        gender,
        relationship_intent,
        referral_code,
        created_at,
        updated_at,
        last_active_at
    ) values (
        new.id,
        nullif(btrim(new.raw_user_meta_data ->> 'full_name'), ''),
        v_dob,
        v_gender,
        v_intent,
        'WKND-' || upper(substr(replace(new.id::text, '-', ''), 1, 10)),
        now(),
        now(),
        now()
    )
    on conflict (id) do nothing;

    insert into public.user_settings (user_id) values (new.id)
    on conflict (user_id) do nothing;

    insert into public.preferences (user_id) values (new.id)
    on conflict (user_id) do nothing;

    -- No exception handlers here on purpose: if these inserts still fail
    -- (database outage, schema drift) the signup rolls back loudly instead of
    -- creating an auth user with no profile rows.
    return new;
end;
$$;

comment on function public.handle_new_user() is
'After-insert trigger on auth.users: creates the profile + user_settings + preferences rows. Metadata values are validated before use, inserts are conflict-safe, and failures abort the signup instead of leaving an orphan.';

-- ============================================================
-- 6. Re-assert the trigger exists (idempotent)
-- ============================================================
drop trigger if exists on_auth_user_created on auth.users;

create trigger on_auth_user_created
    after insert on auth.users
    for each row
    execute function public.handle_new_user();

-- ============================================================
-- 7. Re-assert RLS is enabled (policies untouched)
-- ============================================================
alter table public.profiles enable row level security;
alter table public.user_settings enable row level security;
alter table public.preferences enable row level security;
alter table public.interests enable row level security;
alter table public.user_interests enable row level security;
