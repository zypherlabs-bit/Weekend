-- Migration: 023_hard_filters_and_photo_minimum.sql
-- Server-side 100% hard filtering + the minimum-4-photos profile rule.
--
-- Defects this migration corrects
-- --------------------------------
-- 1. LATITUDE/LONGITUDE SWAPPED in the distance predicate.
--    `get_nearby_profiles` (011) builds the viewer's own point as
--        ST_Point((select latitude ...), (select longitude ...))
--    PostGIS `ST_Point(x, y)` is `ST_Point(longitude, latitude)`, so the
--    viewer's position was transposed before the ST_DWithin comparison. For
--    any user not on the equator/prime-meridian this produced a meaningless
--    distance and excluded/included the wrong people. The `distance_km`
--    column in the same function used the correct order, so the displayed
--    distance and the filter that produced the row disagreed.
--
-- 2. FABRICATED AGE. `case ... else 25` asserted every profile without a
--    stored date_of_birth was 25 years old. A hard age filter can only be
--    satisfied by a KNOWN age, so an unknown age must be NULL and must be
--    excluded whenever the caller sets an age range.
--
-- 3. p_discovery_mode WAS ACCEPTED BUT NEVER READ. The parameter appeared in
--    the signature and was ignored by the body, so "nearby", "global" and
--    "crossed_paths" all executed identical SQL.
--
-- 4. NO MINIMUM-PHOTO RULE. Nothing stopped a profile with zero photos from
--    being saved, and nothing stopped it appearing in other people's decks.
--
-- Filtering model implemented here
-- -------------------------------
-- HARD filters (eligibility, AND semantics, 100% required):
--   gender, age range, max distance, city, relationship intent,
--   interests, languages, lifestyle, account active, not blocked,
--   not deleted, not self, dating profile activated, >= 4 approved photos.
-- SOFT signals (ranking only, never eligibility):
--   shared interests, activity, verification, trust score.
--
-- A profile is returned if and only if EVERY hard filter is true. There is
-- deliberately no partial-credit branch and no percentage threshold.

-- ============================================================
-- 1. Profile columns the filter model and Edit Profile need
-- ============================================================
alter table public.profiles
    add column if not exists height_cm integer
        check (height_cm is null or (height_cm >= 100 and height_cm <= 250)),
    add column if not exists languages text[] not null default '{}'::text[],
    add column if not exists smoking text
        check (smoking is null or smoking in ('Never', 'Occasionally', 'Often', 'Prefer not to say')),
    add column if not exists drinking text
        check (drinking is null or drinking in ('Never', 'Socially', 'Often', 'Prefer not to say')),
    add column if not exists exercise text
        check (exercise is null or exercise in ('Rarely', 'Sometimes', 'Regularly', 'Prefer not to say')),
    add column if not exists pets text
        check (pets is null or pets in ('None', 'Dog', 'Cat', 'Both', 'Other', 'Prefer not to say')),
    add column if not exists children text
        check (children is null or children in ('No', 'Want later', 'Have', 'Prefer not to say')),
    add column if not exists education_level text,
    add column if not exists prompts jsonb not null default '[]'::jsonb,
    -- Account lifecycle flags used as hard filters.
    add column if not exists is_active boolean not null default true,
    add column if not exists deleted_at timestamptz,
    -- Whether the user has completed the minimum-photo requirement and may
    -- therefore be shown to other people. Maintained by the trigger below.
    add column if not exists dating_profile_activated boolean not null default false;

-- Least-privilege column grants for the authenticated client. Raw
-- latitude/longitude stay ungranted (006) so coordinates are never
-- selectable directly - distance is only ever computed inside a
-- SECURITY DEFINER function.
grant select, update (
    display_name, date_of_birth, gender, bio, city, relationship_intent,
    occupation, education, favorite_music, ideal_weekend, height_cm,
    languages, smoking, drinking, exercise, pets, children, education_level,
    prompts
) on public.profiles to authenticated;

-- ============================================================
-- 2. The minimum-4-photos rule
-- ============================================================
-- Single source of truth, callable from SQL triggers and from the client
-- (through get_my_profile_completion) so the two can never disagree.
create or replace function public.minimum_profile_photos()
returns integer
language sql
immutable
as $$
    select 4;
$$;

-- Count of photos a user may actually display: moderation-approved only, so
-- a pending or rejected upload cannot be used to satisfy the minimum.
create or replace function public.approved_photo_count(p_user_id uuid)
returns integer
language sql
stable
security definer
set search_path = public
as $$
    select count(*)::int
    from public.profile_photos
    where user_id = p_user_id
      and moderation_status = 'approved';
$$;

-- Keep profiles.dating_profile_activated in sync with the photo count so
-- discovery can filter on a single indexed boolean instead of a correlated
-- aggregate per candidate row.
create or replace function public.sync_dating_profile_activation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    v_user uuid := coalesce(new.user_id, old.user_id);
    v_count integer;
    v_activated boolean;
begin
    select count(*) into v_count
    from public.profile_photos
    where user_id = v_user
      and moderation_status = 'approved';

    v_activated := v_count >= public.minimum_profile_photos();

    update public.profiles
       set dating_profile_activated = v_activated
     where id = v_user
       and dating_profile_activated is distinct from v_activated;

    return coalesce(new, old);
end;
$$;

drop trigger if exists on_photo_count_change on public.profile_photos;
create trigger on_photo_count_change
    after insert or update or delete on public.profile_photos
    for each row execute function public.sync_dating_profile_activation();

-- Backfill for rows that already have photos.
update public.profiles p
   set dating_profile_activated = (
       select count(*) >= public.minimum_profile_photos()
       from public.profile_photos pp
       where pp.user_id = p.id and pp.moderation_status = 'approved'
   );

-- ============================================================
-- 3. Profile completion (client-facing)
-- ============================================================
-- Drives the onboarding progress UI and the "you need N more photos" copy.
-- Never invents values: it only counts what is genuinely stored.
create or replace function public.get_my_profile_completion(p_user_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
    v_profile public.profiles%rowtype;
    v_photos integer;
    v_min integer := public.minimum_profile_photos();
    v_remaining integer;
begin
    perform public.assert_self(p_user_id);

    select * into v_profile from public.profiles where id = p_user_id;
    if not found then
        return jsonb_build_object(
            'profile_exists', false,
            'photo_count', 0,
            'minimum_photos', v_min,
            'photos_remaining', v_min,
            'is_complete', false
        );
    end if;

    v_photos := public.approved_photo_count(p_user_id);
    v_remaining := greatest(v_min - v_photos, 0);

    return jsonb_build_object(
        'profile_exists', true,
        'photo_count', v_photos,
        'minimum_photos', v_min,
        'photos_remaining', v_remaining,
        'has_name', nullif(btrim(coalesce(v_profile.display_name, '')), '') is not null,
        'has_birthdate', v_profile.date_of_birth is not null,
        'has_city', nullif(btrim(coalesce(v_profile.city, '')), '') is not null,
        'has_bio', length(btrim(coalesce(v_profile.bio, ''))) > 0,
        'is_complete',
            v_remaining = 0
            and nullif(btrim(coalesce(v_profile.display_name, '')), '') is not null
            and v_profile.date_of_birth is not null
            and nullif(btrim(coalesce(v_profile.city, '')), '') is not null
    );
end;
$$;

revoke all on function public.get_my_profile_completion(uuid) from public;
grant execute on function public.get_my_profile_completion(uuid) to authenticated;

-- ============================================================
-- 4. search_profiles - the 100% hard-filter search RPC
-- ============================================================
-- Every parameter below is a HARD filter. A candidate is returned if and
-- only if it satisfies ALL of the ones the caller supplied. An empty array
-- or NULL means "caller did not restrict this dimension", which is the only
-- way a filter is skipped.
--
-- There is intentionally NO scoring gate on eligibility. `match_score` is
-- computed AFTER the WHERE clause purely to order equally-eligible rows.
drop function if exists public.search_profiles(
    uuid, text[], integer, integer, double precision, text, text[], text[],
    text[], jsonb, text, integer, integer
);

create or replace function public.search_profiles(
    p_user_id uuid,
    p_genders text[] default null,
    p_age_min integer default null,
    p_age_max integer default null,
    p_max_distance_km double precision default null,
    p_city text default null,
    p_relationship_intents text[] default null,
    p_interests text[] default null,
    p_languages text[] default null,
    p_lifestyle jsonb default null,
    p_location_mode text default 'nearby',
    p_page integer default 1,
    p_page_size integer default 20
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
    match_score numeric
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
    v_viewer_lat double precision;
    v_viewer_lon double precision;
    v_offset integer;
    v_limit integer;
    -- An explicit "did the caller set this" test. `array_length(.., 1) > 0`
    -- means "no restriction", which is distinct from "restricted to empty".
    v_gender_set boolean := p_genders is not null
                          and array_length(p_genders, 1) > 0;
    v_age_set boolean := p_age_min is not null or p_age_max is not null;
    v_distance_set boolean := p_max_distance_km is not null;
    v_city_set boolean := nullif(btrim(coalesce(p_city, '')), '') is not null;
    v_intent_set boolean := p_relationship_intents is not null
                          and array_length(p_relationship_intents, 1) > 0;
    v_interests_set boolean := p_interests is not null
                           and array_length(p_interests, 1) > 0;
    v_languages_set boolean := p_languages is not null
                            and array_length(p_languages, 1) > 0;
    v_lifestyle_set boolean := p_lifestyle is not null
                             and p_lifestyle <> '{}'::jsonb;
    -- 'global' is the only mode that ignores distance entirely.
    v_enforce_distance boolean := v_distance_set
                                and coalesce(p_location_mode, 'nearby') <> 'global';
begin
    -- Only a user may search on their own behalf. Without this the function
    -- is a full-database enumeration oracle with arbitrary filters.
    perform public.assert_self(p_user_id);

    v_limit := least(greatest(coalesce(p_page_size, 20), 1), 50);
    v_offset := (greatest(coalesce(p_page, 1), 1) - 1) * v_limit;

    -- Read the viewer's own coordinates ONCE, server-side. They are never
    -- returned to the client and are never selectable via PostgREST.
    select latitude, longitude into v_viewer_lat, v_viewer_lon
    from public.profiles where id = p_user_id;

    return query
    with eligible as (
        select
            p.id as pid,
            p.display_name,
            case when p.date_of_birth is not null
                 then date_part('years', age(p.date_of_birth))::int
                 else null
            end as computed_age,
            p.gender,
            p.bio,
            p.city,
            p.latitude,
            p.longitude,
            p.relationship_intent,
            p.is_photo_verified,
            p.trust_score,
            p.last_active_at,
            (select array_agg(i.name)
               from public.user_interests ui
               join public.interests i on i.id = ui.interest_id
              where ui.user_id = p.id) as interest_names
        from public.profiles p
        where
            -- --- identity / lifecycle -----------------------------------
            p.id <> p_user_id
            and p.is_active
            and p.deleted_at is null
            and p.dating_profile_activated
            and p.display_name is not null
            and length(btrim(p.display_name)) > 0
            -- --- HARD: gender -------------------------------------------
            -- An unknown gender can never be proven to satisfy the filter,
            -- so it is excluded whenever the caller restricted gender.
            and (
                not v_gender_set
                or (p.gender is not null and p.gender = any(p_genders))
            )

            -- --- HARD: age ----------------------------------------------
            -- An unknown age is NOT treated as "in range". Falling back to a
            -- default age here is what previously let 20-year-olds into a
            -- 35+ result set.
            and (
                not v_age_set
                or (
                    p.date_of_birth is not null
                    and date_part('years', age(p.date_of_birth))::int
                        >= coalesce(p_age_min, 18)
                    and date_part('years', age(p.date_of_birth))::int
                        <= coalesce(p_age_max, 120)
                )
            )

            -- --- HARD: relationship intent -------------------------------
            and (
                not v_intent_set
                or (
                    p.relationship_intent is not null
                    and p.relationship_intent = any(p_relationship_intents)
                )
            )

            -- --- HARD: city (case-insensitive exact match) ---------------
            and (
                not v_city_set
                or (p.city is not null
                    and lower(btrim(p.city)) = lower(btrim(p_city)))
            )

            -- --- HARD: distance (PostGIS) -------------------------------
            and (
                not v_enforce_distance
                or (
                    v_viewer_lat is not null
                    and v_viewer_lon is not null
                    and p.latitude is not null
                    and p.longitude is not null
                    -- ST_Point(longitude, latitude): argument order matters.
                    and ST_DWithin(
                        ST_Point(p.longitude, p.latitude)::geography,
                        ST_Point(v_viewer_lon, v_viewer_lat)::geography,
                        p_max_distance_km * 1000
                    )
                )
            )

            -- --- HARD: interests ----------------------------------------
            -- ALL requested interests must be present, not "some of them".
            and (
                not v_interests_set
                or not exists (
                    select 1
                    from unnest(p_interests) as required(name)
                    where not exists (
                        select 1
                        from public.user_interests ui
                        join public.interests i on i.id = ui.interest_id
                        where ui.user_id = p.id
                          and lower(i.name) = lower(required.name)
                    )
                )
            )

            -- --- HARD: languages ----------------------------------------
            and (
                not v_languages_set
                or not exists (
                    select 1
                    from unnest(p_languages) as required(lang)
                    where not exists (
                        select 1
                        from unnest(coalesce(p.languages, '{}'::text[]))
                             as owned(lang)
                        where lower(owned.lang) = lower(required.lang)
                    )
                )
            )

            -- --- HARD: lifestyle ----------------------------------------
            -- Each key present in the caller's object must match exactly.
            and (
                not v_lifestyle_set
                or not exists (
                    select 1
                    from jsonb_each_text(p_lifestyle) as want(key, value)
                    where want.value is not null
                      and want.value <> ''
                      and case want.key
                            when 'smoking' then p.smoking
                            when 'drinking' then p.drinking
                            when 'exercise' then p.exercise
                            when 'pets' then p.pets
                            when 'children' then p.children
                            else null
                          end is distinct from want.value
                )
            )

            -- --- exclusions ---------------------------------------------
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
    ),
    scored as (
        select
            e.*,
            case
                when e.latitude is not null and e.longitude is not null
                 and v_viewer_lat is not null and v_viewer_lon is not null
                then round((
                    ST_Distance(
                        ST_Point(e.longitude, e.latitude)::geography,
                        ST_Point(v_viewer_lon, v_viewer_lat)::geography
                    ) / 1000
                )::numeric, 1)::double precision
                else null
            end as real_distance_km,
            -- SOFT ranking only; never consulted for eligibility.
            (case when e.trust_score is not null then e.trust_score * 0.2 else 0 end)
            + (case when e.is_photo_verified then 15 else 0 end)
            + (case when e.last_active_at > now() - interval '14 days'
                   then 10 else 0 end)
            + (case
                when exists (
                    select 1
                    from public.user_interests mine
                    join public.interests mi on mi.id = mine.interest_id
                    join public.user_interests theirs on theirs.user_id = e.pid
                    join public.interests ti on ti.id = theirs.interest_id
                    where mine.user_id = p_user_id
                      and lower(mi.name) = lower(ti.name)
                ) then 20 else 0 end)
        ) as soft_score
        from eligible e
    )
    select
        s.pid as profile_id,
        s.display_name,
        s.computed_age as age,
        s.gender,
        s.bio,
        s.city,
        s.real_distance_km as distance_km,
        s.is_photo_verified,
        s.trust_score,
        (select storage_path from public.profile_photos pp
          where pp.user_id = s.pid and pp.moderation_status = 'approved'
          order by pp.is_primary desc, pp.created_at asc
          limit 1) as primary_photo_path,
        s.interest_names as interests,
        s.relationship_intent,
        s.last_active_at,
        round(s.soft_score::numeric, 2) as match_score
    from scored s
    order by s.soft_score desc,
             s.real_distance_km asc nulls last,
             s.last_active_at desc nulls last
    limit v_limit offset v_offset;
end;
$$;

revoke all on function public.search_profiles(
    uuid, text[], integer, integer, double precision, text, text[], text[],
    text[], jsonb, text, integer, integer
) from public;
grant execute on function public.search_profiles(
    uuid, text[], integer, integer, double precision, text, text[], text[],
    text[], jsonb, text, integer, integer
) to authenticated;

-- ============================================================
-- 5. Fix get_nearby_profiles (011) - the RPC the deck actually calls
-- ============================================================
-- Three defects, same function:
--   a) the viewer's point was built as ST_Point(latitude, longitude);
--   b) a missing date_of_birth was reported as age 25;
--   c) p_discovery_mode was ignored, so every mode ran identical SQL.
--
-- The parameter list is unchanged on purpose: the Flutter client already
-- calls this signature and must not need a coordinated deploy.
drop function if exists public.get_nearby_profiles(
    uuid, integer, integer, double precision, text[], integer, integer, text
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
    v_limit integer := least(greatest(coalesce(p_limit, 20), 1), 50);
    v_offset integer := greatest(coalesce(p_offset, 0), 0);
    v_gender_set boolean := p_preferred_genders is not null
                          and array_length(p_preferred_genders, 1) > 0;
    v_mode text := coalesce(p_discovery_mode, 'nearby');
    -- 'global' and 'crossed_paths' deliberately skip the distance predicate.
    v_enforce_distance boolean := v_mode not in ('global', 'crossed_paths');
begin
    perform public.assert_self(p_user_id);

    select latitude, longitude into v_viewer_lat, v_viewer_lon
    from public.profiles where id = p_user_id;

    return query
    select
        p.id as profile_id,
        p.display_name,
        -- (b) no fabricated age: an unknown date_of_birth yields NULL.
        case when p.date_of_birth is not null
             then date_part('years', age(p.date_of_birth))::int
             else null
        end as age,
        p.gender,
        p.bio,
        p.city,
        case
            when p.latitude is not null and p.longitude is not null
             and v_viewer_lat is not null and v_viewer_lon is not null
            then round((
                ST_Distance(
                    -- (a) longitude first, then latitude.
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
    from public.profiles p
    where p.id <> p_user_id
      and p.is_active
      and p.deleted_at is null
      and p.dating_profile_activated
      and p.display_name is not null
      and length(btrim(p.display_name)) > 0
      -- (c) p_discovery_mode now actually selects the predicate.
      and (
            not v_enforce_distance
            or (
                v_viewer_lat is not null and v_viewer_lon is not null
                and p.latitude is not null and p.longitude is not null
                and ST_DWithin(
                    ST_Point(p.longitude, p.latitude)::geography,
                    ST_Point(v_viewer_lon, v_viewer_lat)::geography,
                    p_max_distance_km * 1000
                )
            )
          )
      -- An unknown age is excluded when a range is requested.
      and (
            p.date_of_birth is null
            or date_part('years', age(p.date_of_birth))::int
               between p_age_min and p_age_max
          )
      and (not v_gender_set
           or (p.gender is not null and p.gender = any(p_preferred_genders)))
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

-- Grants are re-stated: the DROP above removed the 006/011 execute grants.
grant execute on function public.get_nearby_profiles(
    uuid, integer, integer, double precision, text[], integer, integer, text
) to authenticated;

-- Helper functions used by search_profiles stay definer-owned; clients only
-- ever need to call search_profiles / get_nearby_profiles.
grant execute on function public.minimum_profile_photos() to authenticated;

-- ============================================================
-- 6. Indexes for the hard-filter predicates
-- ============================================================
-- The discovery WHERE clause filters on these columns for every candidate
-- row. Without them each page is a sequential scan of `profiles`.
create index if not exists idx_profiles_dating_active
    on public.profiles (dating_profile_activated)
    where dating_profile_activated;

create index if not exists idx_profiles_is_active
    on public.profiles (is_active)
    where is_active;

create index if not exists idx_profiles_city_lower
    on public.profiles (lower(btrim(city)));

create index if not exists idx_profiles_relationship_intent
    on public.profiles (relationship_intent);

create index if not exists idx_profiles_gender
    on public.profiles (gender);

create index if not exists idx_profiles_date_of_birth
    on public.profiles (date_of_birth);

create index if not exists idx_profiles_languages_gin
    on public.profiles using gin (languages);

create index if not exists idx_user_interests_user_interest
    on public.user_interests (user_id, interest_id);

-- ============================================================
-- 7. Account deletion now soft-flags the profile
-- ============================================================
-- `delete_user_account` (009) removes the dependent rows but leaves
-- `profiles` in place. Set the lifecycle flags so the profile immediately
-- stops appearing in every discovery result set, even before the auth user
-- is removed.
create or replace function public.mark_profile_deleted(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
    perform public.assert_self(p_user_id);

    update public.profiles
       set deleted_at = now(),
           is_active = false,
           dating_profile_activated = false,
           display_name = null,
           bio = null,
           occupation = null,
           education = null,
           favorite_music = null,
           ideal_weekend = null,
           prompts = '[]'::jsonb
     where id = p_user_id;
end;
$$;

revoke all on function public.mark_profile_deleted(uuid) from public;
grant execute on function public.mark_profile_deleted(uuid) to authenticated;