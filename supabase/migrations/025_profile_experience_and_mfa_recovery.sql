-- Migration: 025_profile_experience_and_mfa_recovery.sql
-- ---------------------------------------------------------------------------
-- Weekend profile experience (mature profile editing) + MFA recovery codes.
--
-- Why this migration exists
-- -------------------------
-- Audit of the LIVE project (ocypgybqfushqfzisnvs) found:
--
--   * `supabase_migrations.schema_migrations` stops at 021, but `search_profiles`
--     is already live with its 022 signature (applied out-of-band). Migration 023
--     was NEVER applied, and it cannot be applied as written: 023 filters on
--     `profiles.dating_profile_activated`, which no earlier migration creates.
--     Consequence: `minimum_profile_photos()` does not exist, the "4 photos"
--     rule is enforced nowhere, and `profile_photos` has no ordering column,
--     so a user cannot reorder photos or choose a primary one.
--
--   * Supabase Auth TOTP MFA has no native recovery-code support. Without a
--     recovery path a user who loses their authenticator is locked out of their
--     own account forever - exactly the "2FA is broken" report this removes.
--
-- Everything below is additive and idempotent. It is written against the schema
-- that is actually live (verified column-by-column), NOT against the
-- not-yet-applied 023, so it can be pushed on its own.
-- ---------------------------------------------------------------------------

-- ============================================================
-- 0. Extensions
-- ============================================================
-- `digest()` lives in the `extensions` schema on Supabase. Referring to it
-- schema-qualified keeps this file independent of the caller's search_path.
create extension if not exists pgcrypto with schema extensions;

-- ============================================================
-- 1. Photo ordering
-- ============================================================

alter table public.profile_photos
    add column if not exists sort_order integer not null default 0;

comment on column public.profile_photos.sort_order is
    '0-based display order inside the owner''s profile.';

-- Backfill so existing rows get a deterministic order (oldest = first) rather
-- than all collapsing onto 0.
with ranked as (
    select id,
           row_number() over (
               partition by user_id order by created_at asc nulls last, id asc
           ) - 1 as pos
    from public.profile_photos
)
update public.profile_photos pp
set sort_order = ranked.pos
from ranked
where pp.id = ranked.id
  and pp.sort_order = 0;

create index if not exists idx_profile_photos_user_order
    on public.profile_photos (user_id, sort_order);

-- ============================================================
-- 2. The minimum-photo threshold, server-side and configurable
-- ============================================================

create table if not exists public.profile_requirements (
    id          boolean primary key default true,
    min_photos  integer not null default 4 check (min_photos between 1 and 10),
    max_photos  integer not null default 6 check (max_photos between 1 and 10),
    constraint profile_requirements_max_ge_min check (max_photos >= min_photos),
    constraint profile_requirements_singleton check (id)
);

insert into public.profile_requirements (id, min_photos, max_photos)
values (true, 4, 6)
on conflict (id) do nothing;

-- Definer-owned so no client can raise the bar for everybody by writing this
-- table. Read-only for callers.
create or replace function public.minimum_profile_photos()
returns integer
language sql
stable
security definer
set search_path = public
as $fn$
    select min_photos from public.profile_requirements where id
$fn$;

revoke all on function public.minimum_profile_photos() from public;
grant execute on function public.minimum_profile_photos() to authenticated;

create or replace function public.maximum_profile_photos()
returns integer
language sql
stable
security definer
set search_path = public
as $fn$
    select max_photos from public.profile_requirements where id
$fn$;

revoke all on function public.maximum_profile_photos() from public;
grant execute on function public.maximum_profile_photos() to authenticated;

-- `has_minimum_photos` is what Edit Profile and the discovery filters both
-- read, so a trigger maintains it and it can never drift from the real rows.
alter table public.profiles
    add column if not exists has_minimum_photos boolean not null default false;

create or replace function public.sync_profile_photo_counters()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
    v_owner    uuid;
    v_approved integer;
begin
    v_owner := coalesce(new.user_id, old.user_id);

    select count(*)
      into v_approved
      from public.profile_photos pp
     where pp.user_id = v_owner
       -- A rejected photo must not count toward the completion bar.
       and pp.moderation_status is distinct from 'rejected';

    update public.profiles
       set has_minimum_photos = (v_approved >= public.minimum_profile_photos()),
           updated_at = now()
     where id = v_owner;

    return coalesce(new, old);
end;
$fn$;

drop trigger if exists trg_sync_profile_photo_counters on public.profile_photos;
create trigger trg_sync_profile_photo_counters
    after insert or update or delete on public.profile_photos
    for each row execute function public.sync_profile_photo_counters();

-- Recompute for anyone who already had photos before this migration landed.
update public.profiles p
set has_minimum_photos = (
        select count(*) from public.profile_photos pp
         where pp.user_id = p.id
           and pp.moderation_status is distinct from 'rejected'
    ) >= public.minimum_profile_photos()
where exists (select 1 from public.profile_photos pp where pp.user_id = p.id);

grant select (has_minimum_photos) on public.profiles to authenticated;

-- ============================================================
-- 3. Photo management RPCs (owner-scoped: no IDOR is possible)
-- ============================================================

-- Reorder: the caller sends the full ordered list of their own photo ids.
-- Anything not owned by the caller is rejected outright.
create or replace function public.set_profile_photo_order(p_photo_ids uuid[])
returns integer
language plpgsql
security definer
set search_path = public
as $fn$
declare
    v_uid   uuid := auth.uid();
    v_owned integer;
    v_pos   integer := 0;
    v_id    uuid;
begin
    if v_uid is null then
        raise exception 'Not authenticated' using errcode = '42501';
    end if;

    if p_photo_ids is null or coalesce(array_length(p_photo_ids, 1), 0) = 0 then
        raise exception 'No photo ids supplied' using errcode = '22023';
    end if;

    select count(*) into v_owned
      from public.profile_photos pp
     where pp.id = any (p_photo_ids)
       and pp.user_id = v_uid;

    if v_owned <> coalesce(array_length(p_photo_ids, 1), 0) then
        raise exception 'One or more photos do not belong to you'
            using errcode = '42501';
    end if;

    foreach v_id in array p_photo_ids loop
        update public.profile_photos
           set sort_order = v_pos
         where id = v_id
           and user_id = v_uid;
        v_pos := v_pos + 1;
    end loop;

    return v_pos;
end;
$fn$;

revoke all on function public.set_profile_photo_order(uuid[]) from public;
grant execute on function public.set_profile_photo_order(uuid[]) to authenticated;

-- Exactly one primary photo: the function clears the previous primary inside
-- the same transaction, so two primaries cannot exist even transiently.
create or replace function public.set_primary_profile_photo(p_photo_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $fn$
declare
    v_uid uuid := auth.uid();
begin
    if v_uid is null then
        raise exception 'Not authenticated' using errcode = '42501';
    end if;

    if not exists (
        select 1 from public.profile_photos where id = p_photo_id and user_id = v_uid
    ) then
        raise exception 'That photo does not belong to you' using errcode = '42501';
    end if;

    update public.profile_photos
       set is_primary = false
     where user_id = v_uid
       and is_primary;

    -- `sort_order = 0` is the first slot the card renders.
    update public.profile_photos
       set is_primary = true, sort_order = 0
     where id = p_photo_id
       and user_id = v_uid;

    update public.profile_photos
       set sort_order = sort_order - 1
     where user_id = v_uid
       and id <> p_photo_id
       and sort_order > 0;
end;
$fn$;

revoke all on function public.set_primary_profile_photo(uuid) from public;
grant execute on function public.set_primary_profile_photo(uuid) to authenticated;

create unique index if not exists uniq_profile_photos_one_primary
    on public.profile_photos (user_id)
    where is_primary;

-- ============================================================
-- 4. Prompt / profile-question integrity
-- ============================================================
-- `profiles.prompts` is jsonb: an array of {"prompt": str, "answer": str}.
-- A loose jsonb column is how a malformed value reaches the profile card and
-- breaks a user's deck for everybody, so the shape is enforced here.

create or replace function public.profile_prompts_are_valid(v jsonb)
returns boolean
language sql
immutable
security definer
set search_path = public
as $fn$
    select
        v is not null
        and jsonb_typeof(v) = 'array'
        and jsonb_array_length(v) <= 4
        and not exists (
            select 1
              from jsonb_array_elements(v) as el
             where jsonb_typeof(el) <> 'object'
                or not (el ? 'prompt')
                or not (el ? 'answer')
                or jsonb_typeof(el -> 'prompt') <> 'string'
                or jsonb_typeof(el -> 'answer') <> 'string'
                or length(el ->> 'answer') > 300
        )
$fn$;

revoke all on function public.profile_prompts_are_valid(jsonb) from public;
grant execute on function public.profile_prompts_are_valid(jsonb) to authenticated;

alter table public.profiles
    drop constraint if exists profile_prompts_shape;
alter table public.profiles
    add constraint profile_prompts_shape
    check (public.profile_prompts_are_valid(prompts));

-- ============================================================
-- 5. Interests taxonomy
-- ============================================================
-- Normalised, so a renamed interest does not orphan a user's selection and the
-- Edit Profile chips are backed by real rows rather than hard-coded text.
-- `category` groups the chips in the picker; the pre-023 table had no grouping.
alter table public.interests
    add column if not exists category text not null default 'Other';

create index if not exists idx_interests_category
    on public.interests (category, name);

insert into public.interests (name, category)
values
    ('Travel',          'Outdoors'),
    ('Camping',         'Outdoors'),
    ('Hiking',          'Outdoors'),
    ('Nature walks',    'Outdoors'),
    ('Beach days',      'Outdoors'),
    ('Road trips',      'Outdoors'),
    ('Movies',          'Culture'),
    ('Live music',      'Culture'),
    ('Stand-up comedy', 'Culture'),
    ('Theatre',         'Culture'),
    ('Art galleries',   'Culture'),
    ('Museums',         'Culture'),
    ('Bookshops',       'Culture'),
    ('Reading',         'Culture'),
    ('Board games',     'Culture'),
    ('Music festivals', 'Culture'),
    ('Cooking',         'Food & drink'),
    ('Baking',          'Food & drink'),
    ('Street food',     'Food & drink'),
    ('Coffee',          'Food & drink'),
    ('Wine',            'Food & drink'),
    ('Craft beer',      'Food & drink'),
    ('Restaurants',     'Food & drink'),
    ('Fitness',         'Active'),
    ('Cycling',         'Active'),
    ('Running',         'Active'),
    ('Yoga',            'Active'),
    ('Swimming',        'Active'),
    ('Team sports',     'Active'),
    ('Climbing',        'Active'),
    ('Football',        'Active'),
    ('Cricket',         'Active'),
    ('Gaming',          'Screen'),
    ('Streaming',       'Screen'),
    ('Podcasts',        'Screen'),
    ('Photography',     'Creative'),
    ('Design',          'Creative'),
    ('Writing',         'Creative'),
    ('Making',          'Creative'),
    ('Gardening',       'Creative'),
    ('Technology',      'Creative'),
    ('Startups',        'Creative'),
    ('Volunteering',    'Community'),
    ('Weekend markets', 'Community'),
    ('Live sport',      'Community'),
    ('Volunteer runs',  'Community'),
    ('Local festivals', 'Community')
on conflict (name) do update
    set category = excluded.category;

-- ============================================================
-- 6. MFA recovery codes
-- ============================================================
-- Supabase Auth TOTP has no native recovery-code primitive, so this is
-- implemented server-side. Design constraints:
--
--   * Only the SHA-256 of the code is stored, salted with the user id, so a
--     database leak cannot be replayed against the account.
--   * Codes are generated by Postgres (gen_random_bytes), never by a client,
--     so they cannot be biased or observed in transit.
--   * Consumption is a single atomic UPDATE ... WHERE used_at is null, so a
--     code can never be spent twice even under concurrent requests.
--   * Regenerating revokes every previous code.

create table if not exists public.mfa_recovery_codes (
    id          uuid primary key default gen_random_uuid(),
    user_id     uuid not null references public.profiles (id) on delete cascade,
    code_hash   text not null,
    label       text,
    created_at  timestamptz not null default now(),
    used_at     timestamptz,
    constraint mfa_recovery_code_not_blank check (length(code_hash) = 64)
);

create index if not exists idx_mfa_recovery_codes_user
    on public.mfa_recovery_codes (user_id)
    where used_at is null;

alter table public.mfa_recovery_codes enable row level security;

-- No client policy for write/delete: the table is reached exclusively through
-- the two SECURITY DEFINER functions below, which are the only way in or out.
revoke insert, update, delete on public.mfa_recovery_codes from authenticated;

drop policy if exists "mfa_recovery_codes_own_select" on public.mfa_recovery_codes;
create policy "mfa_recovery_codes_own_select"
    on public.mfa_recovery_codes
    for select
    to authenticated
    using (auth.uid() = user_id);

-- Only SELECT is granted. INSERT/UPDATE/DELETE are deliberately absent: the
-- table is reached exclusively through the SECURITY DEFINER functions below,
-- so a client cannot mint, forge or destroy its own recovery set by writing to
-- the table directly.
grant select on public.mfa_recovery_codes to authenticated;

-- Deterministic, salted hash. Deterministic is required (the server has to be
-- able to match a presented code); the per-user salt is what stops a stolen
-- table being turned into a rainbow table for any other account.
create or replace function public.mfa_recovery_code_hash(p_user_id uuid, p_code text)
returns text
language sql
immutable
security definer
set search_path = public
as $fn$
    select encode(
        extensions.digest(
            -- upper() FIRST, then strip separators. The other order silently
            -- deletes the lowercase letters instead of folding their case, so a
            -- user typing a recovery code in lowercase would have half of it
            -- removed and be denied.
            regexp_replace(upper(coalesce(p_code, '')), '[^0-9A-Z]', '', 'g')
            || ':' || p_user_id::text,
            'sha256'
        ),
        'hex'
    )
$fn$;

revoke all on function public.mfa_recovery_code_hash(uuid, text) from public;
grant execute on function public.mfa_recovery_code_hash(uuid, text) to authenticated;

-- Issue a fresh set. Every previously issued code is destroyed first, so the
-- caller always holds the only valid set. Plaintext is returned exactly once
-- and never stored.
create or replace function public.generate_mfa_recovery_codes(p_count integer default 8)
returns table (code text, label text)
language plpgsql
security definer
set search_path = public
as $fn$
declare
    v_uid   uuid := auth.uid();
    v_count integer := least(greatest(coalesce(p_count, 8), 1), 20);
    i       integer;
    v_code  text;
    v_hash  text;
    v_label text;
begin
    if v_uid is null then
        raise exception 'Not authenticated' using errcode = '42501';
    end if;

    if not exists (select 1 from public.profiles where id = v_uid) then
        raise exception 'Profile not found' using errcode = '42501';
    end if;

    delete from public.mfa_recovery_codes where user_id = v_uid;

    for i in 1..v_count loop
        -- 8 bytes of CSPRNG output per half, rendered as 16 uppercase hex
        -- characters and grouped for legibility: 64 bits of entropy per code.
        v_code := upper(encode(extensions.gen_random_bytes(8), 'hex'))
               || '-'
               || upper(encode(extensions.gen_random_bytes(8), 'hex'));
        v_label := 'Recovery code ' || i;
        v_hash  := public.mfa_recovery_code_hash(v_uid, v_code);

        insert into public.mfa_recovery_codes (user_id, code_hash, label)
        values (v_uid, v_hash, v_label);

        code := v_code;
        label := v_label;
        return next;
    end loop;
end;
$fn$;

revoke all on function public.generate_mfa_recovery_codes(integer) from public;
grant execute on function public.generate_mfa_recovery_codes(integer) to authenticated;

-- Spend one code. Returns false for an unknown or already-used code - the
-- same answer for every failure mode, so the response cannot be used as an
-- oracle for "which codes exist".
create or replace function public.consume_mfa_recovery_code(p_code text)
returns boolean
language plpgsql
security definer
set search_path = public
as $fn$
declare
    v_uid  uuid := auth.uid();
    v_hash text;
begin
    if v_uid is null then
        raise exception 'Not authenticated' using errcode = '42501';
    end if;

    v_hash := public.mfa_recovery_code_hash(v_uid, p_code);

    update public.mfa_recovery_codes
       set used_at = now()
     where user_id = v_uid
       and code_hash = v_hash
       and used_at is null;

    return found;
end;
$fn$;

revoke all on function public.consume_mfa_recovery_code(text) from public;
grant execute on function public.consume_mfa_recovery_code(text) to authenticated;

create or replace function public.mfa_recovery_code_count()
returns integer
language sql
stable
security definer
set search_path = public
as $fn$
    select count(*)::integer
      from public.mfa_recovery_codes
     where user_id = auth.uid()
       and used_at is null
$fn$;

revoke all on function public.mfa_recovery_code_count() from public;
grant execute on function public.mfa_recovery_code_count() to authenticated;

-- ============================================================
-- 7. Account-deletion cleanup must also drop recovery codes
-- ============================================================
-- `delete_user_account` (009) removes dependent profile rows and `profiles` is
-- the parent of `mfa_recovery_codes`, so ON DELETE CASCADE already covers the
-- hard-delete path. This covers the soft-delete path, where the profile row
-- survives and the codes would otherwise stay spendable.
create or replace function public.mark_profile_deleted(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $fn$
begin
    perform public.assert_self(p_user_id);
    delete from public.mfa_recovery_codes where user_id = p_user_id;
end;
$fn$;

revoke all on function public.mark_profile_deleted(uuid) from public;
grant execute on function public.mark_profile_deleted(uuid) to authenticated;
