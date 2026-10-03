-- Migration: 027_device_tokens_and_mode_queries.sql
-- Adds:
--   1. device_tokens table for FCM remote push delivery
--   2. Mode-specific discovery parameters to get_nearby_profiles RPC
--
-- The notifications table already exists and is in the realtime publication
-- (migration 010). What was missing:
--   - A table to store FCM tokens so the backend can send push notifications
--   - Per-mode SQL filtering (modes shared one proximity query)

-- ============================================================
-- 1. Device tokens for FCM push
-- ============================================================

create table if not exists device_tokens (
    id              uuid         primary key default gen_random_uuid(),
    user_id         uuid         not null references auth.users on delete cascade,
    device_id       text         not null,
    token           text         not null,
    platform        text         not null check (platform in ('android', 'ios')),
    created_at      timestamp    not null default now(),
    last_seen_at    timestamp    not null default now(),
    unique (user_id, device_id)
);

-- Indexes for efficient lookups
create index if not exists device_tokens_user_id_idx on device_tokens (user_id);
create index if not exists device_tokens_token_idx on device_tokens (token);

-- RLS
alter table device_tokens enable row level security;

create policy "Users can read their own device tokens"
    on device_tokens for select
    using (auth.uid()::text = user_id::text);

create policy "Users can insert their own device tokens"
    on device_tokens for insert
    with check (auth.uid()::text = user_id::text);

create policy "Users can update their own device tokens"
    on device_tokens for update
    using (auth.uid()::text = user_id::text)
    with check (auth.uid()::text = user_id::text);

-- ============================================================
-- 2. Mode-specific discovery queries
-- ============================================================
-- Updates get_nearby_profiles to apply different SQL filters based on
-- the p_discovery_mode parameter, rather than sharing one query.

-- DEFECT FOUND 2026-10-02 (audited before Play Store launch)
-- ---------------------------------------------------------
-- The version of this function that shipped in this migration could never
-- have worked. It selected columns that do not exist on `public.profiles`:
-- `user_id` (the PK is `id`), `age`, `primary_photo_path`, `location` and
-- `interests` - none of which are stored columns. Age, interests and the
-- photo path are DERIVED per row by subquery, and location is held as
-- latitude/longitude double precision. It also filtered `passes` on
-- `passer_id`/`passed_id`, but that table's columns are `user_id`/`target_id`.
--
-- Postgres does not validate a plpgsql body at CREATE time, so the function
-- compiled, CREATE OR REPLACE succeeded, and every call would raise
-- `column prof.user_id does not exist` at runtime - discovery returns an
-- empty list for every user with no error surfaced, because
-- `loadDiscoveryProfiles` catches and returns [].
--
-- It also declared a DIFFERENT signature than the Flutter client calls:
-- `DiscoveryRepository` sends p_max_distance_km / p_preferred_genders
-- (migration 023's signature); this one used p_radius_km / p_genders.
--
-- The body below restates migration 023's working function - same signature,
-- same columns the client reads - with the adult floor folded in.
drop function if exists public.get_nearby_profiles(
    uuid, integer, integer, numeric, text, text[], integer, integer
);

create or replace function public.get_nearby_profiles(
    p_user_id uuid,
    p_limit integer default 20,
    p_offset integer default 0,
    p_max_distance_km double precision default 50,
    p_preferred_genders text[] default array[]::text[],
    p_age_min integer default 18,
    p_age_max integer default 100,
    p_discovery_mode text default 'nearby'
)
returns table (
    profile_id uuid,
    display_name text,
    age integer,
    gender text,
    bio text,
    city text,
    distance_km double precision,
    is_photo_verified boolean,
    trust_score integer,
    primary_photo_path text,
    interests text[],
    relationship_intent text,
    last_active_at timestamptz,
    compatibility_score numeric
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
    v_viewer_lat double precision;
    v_viewer_lon double precision;
    v_viewer_city text;
    v_limit integer := least(greatest(coalesce(p_limit, 20), 1), 50);
    v_offset integer := greatest(coalesce(p_offset, 0), 0);
    v_gender_set boolean := p_preferred_genders is not null
                          and array_length(p_preferred_genders, 1) > 0;
    -- Normalised once, then switched on per row. 023 accepted
    -- p_discovery_mode and ignored it; this is the fix for that.
    v_mode text := coalesce(p_discovery_mode, 'nearby');
    -- 'global' and 'crossed_paths' deliberately skip the distance predicate.
    v_enforce_distance boolean := v_mode not in ('global', 'crossed_paths');
begin
    perform public.assert_self(p_user_id);

    -- The viewer's own coordinates and city are read ONCE, server-side. They
    -- are never returned to the client and are not directly selectable.
    select latitude, longitude, city
      into v_viewer_lat, v_viewer_lon, v_viewer_city
    from public.profiles where id = p_user_id;

    return query
    select
        p.id as profile_id,
        p.display_name,
        -- No fabricated age: an unknown date_of_birth yields NULL.
        case when p.date_of_birth is not null
             then date_part('years', age(p.date_of_birth))::int
             else null
        end as age,
        p.gender,
        p.bio,
        p.city,
        case
            when v_enforce_distance and p.latitude is not null
                 and p.longitude is not null
                 and v_viewer_lat is not null and v_viewer_lon is not null
            then round((
                ST_Distance(
                    -- longitude first, then latitude.
                    ST_Point(p.longitude, p.latitude)::geography,
                    ST_Point(v_viewer_lon, v_viewer_lat)::geography
                ) / 1000
            )::numeric, 1)::double precision
            else 0
        end as distance_km,
        p.is_photo_verified,
        p.trust_score,
        (select storage_path from public.profile_photos pp
          where pp.user_id = p.id and pp.moderation_status = 'approved'
          order by pp.is_primary desc, pp.created_at asc
          limit 1) as primary_photo_path,
        (select array_agg(i.name)
           from public.user_interests ui
           join public.interests i on i.id = ui.interest_id
          where ui.user_id = p.id) as interests,
        p.relationship_intent,
        p.last_active_at,
        (p.trust_score * 0.3)
        + (case when p.is_photo_verified then 15 else 0 end)
        + (case when p.last_active_at > now() - interval '7 days' then 20 else 0 end)
            as compatibility_score
    from public.profiles p
    where p.id <> p_user_id
      and p.is_active
      and p.deleted_at is null
      and p.dating_profile_activated
      and p.display_name is not null
      and length(btrim(p.display_name)) > 0
      -- ADULT FLOOR (migration 028): unconditional, and applied BEFORE the
      -- caller's own age range, so neither an omitted range nor a
      -- caller-supplied p_age_min below 18 can surface a minor or a profile
      -- whose age cannot be proven.
      and p.date_of_birth is not null
      and date_part('years', age(p.date_of_birth))::int >= 18
      and date_part('years', age(p.date_of_birth))::int
            >= greatest(coalesce(p_age_min, 18), 18)
      and date_part('years', age(p.date_of_birth))::int
            <= coalesce(p_age_max, 120)
      and (not v_gender_set
           or (p.gender is not null and p.gender = any(p_preferred_genders)))
      -- --- PER-MODE SCOPE -------------------------------------------
      -- 023 accepted p_discovery_mode and ignored it, so every mode ran
      -- identical SQL. Each mode now selects its own predicate:
      --   nearby        - within the radius
      --   global        - no geographic scope at all
      --   city          - same city as the viewer, no radius
      --   crossed_paths - within the radius (crossed-path detection is a
      --                   separate feature, so this stays a distance filter)
      --
      -- NOTE: there is deliberately no 'travel' predicate. `user_settings`
      -- has `travel_mode_enabled` (016) but no travel-city column, and
      -- referencing a non-existent column would make the whole function
      -- raise at runtime - which is the defect being repaired here. An
      -- unrecognised mode falls through to the distance filter.
      and (
            v_mode not in ('global', 'city')
         or v_mode = 'global'
         or (v_mode = 'city' and p.city is not null
             and lower(btrim(p.city)) = lower(btrim(coalesce(v_viewer_city, ''))))
      )
      and not exists (select 1 from public.blocks
                       where blocker_id = p_user_id and blocked_id = p.id)
      and not exists (select 1 from public.blocks
                       where blocker_id = p.id and blocked_id = p_user_id)
      and not exists (select 1 from public.passes
                       where user_id = p_user_id and target_id = p.id)
      and not exists (select 1 from public.likes
                       where liker_id = p_user_id and liked_id = p.id)
      and not exists (select 1 from public.reports
                       where reporter_id = p_user_id and reported_id = p.id)
      and not exists (
            select 1 from public.matches
            where (user_a_id = p_user_id and user_b_id = p.id)
               or (user_b_id = p_user_id and user_a_id = p.id)
          )
    order by distance_km asc nulls last,
             p.last_active_at desc
    limit v_limit offset v_offset;
end;
$$;

revoke all on function public.get_nearby_profiles(
    uuid, integer, integer, double precision, text[], integer, integer, text
) from public, anon;
grant execute on function public.get_nearby_profiles(
    uuid, integer, integer, double precision, text[], integer, integer, text
) to authenticated;
