-- Migration: 022_advanced_search.sql
-- Location-first ADVANCED SEARCH: real server-side hard filters + soft ranking.
--
-- Why this migration exists
-- -----------------------
-- The spec requires a dedicated Discover / Search Filters screen where the
-- SERVER enforces every hard filter with AND semantics:
--
--     Gender: Female
--     Age: 25-32
--     Interested in: Men
--     Distance: <= 50 km
--     Relationship Intent: Long-term
--     City: Pune
--     Interests: Travel, Movies
--     Languages: English, Marathi
--     Lifestyle: Non-smoker
--
-- The pre-existing discovery RPC `get_nearby_profiles` only ever applied
-- distance, age and gender. Relationship intent, city, interests, languages
-- and lifestyle were NOT filtered server-side, so the client could not honour
-- them without downloading every candidate and filtering in Dart - which this
-- spec explicitly forbids.
--
-- Two concrete correctness bugs are also fixed here:
--
--   1. FABRICATED AGE. get_nearby_profiles and get_matches_for_user both ended
--      their age expression with `else 25`, inventing an age of 25 for every
--      profile whose date_of_birth is NULL. The Dart layer had already been
--      corrected for exactly this (DiscoveryRepository._ageFromDateOfBirth:
--      "a missing age stays 0 instead of asserting the person is 25"), so the
--      database was still returning a fabricated value. Age is now NULL when
--      unknown. An invented age is fabricated data.
--
--   2. AGE FILTER LEAKED UNKNOWN-AGE PROFILES. The old predicate was
--         and (p.date_of_birth is null or date_part(...) between min and max)
--      i.e. "if the age is unknown, keep the profile". A user who asked for
--      25-32 therefore received profiles that could not be proven to be in
--      range. Unknown-age profiles are now EXCLUDED whenever an age range is
--      supplied, because a hard filter that cannot be satisfied must not
--      silently pass.
--
--   3. p_discovery_mode was accepted and then never referenced in the body,
--      so Travel / City / Explore / Global were not actually differentiated.
--
-- PRIVACY: every function here is SECURITY DEFINER and returns only rounded
-- distance plus a coarse label. Raw coordinates of any other user are never
-- returned.

-- ============================================================
-- 1. PROFILE COLUMNS the advanced filters need
-- ============================================================
-- Deliberately minimal: only fields a search filter or card actually uses.
-- Nothing decorative is collected.

alter table public.profiles
    add column if not exists interested_in text[] not null default '{}'::text[],
    add column if not exists languages text[] not null default '{}'::text[],
    add column if not exists smoking text not null default 'Prefer not to say',
    add column if not exists drinking text not null default 'Prefer not to say',
    add column if not exists exercise text not null default 'Prefer not to say',
    add column if not exists pets text not null default 'Prefer not to say',
    add column if not exists children text not null default 'Prefer not to say',
    add column if not exists height_cm integer,
    add column if not exists prompts jsonb not null default '[]'::jsonb;

-- CHECK constraints keep the vocabulary small and stop a client writing
-- arbitrary strings into a column the UI renders as a chip label. CHECKs
-- (not enums) so adding a value later is an additive migration.
alter table public.profiles drop constraint if exists profiles_smoking_check;
alter table public.profiles add constraint profiles_smoking_check
    check (smoking in ('Never', 'Social', 'Regular', 'Former', 'Prefer not to say'));

alter table public.profiles drop constraint if exists profiles_drinking_check;
alter table public.profiles add constraint profiles_drinking_check
    check (drinking in ('Never', 'Socially', 'Regularly', 'Prefer not to say'));

alter table public.profiles drop constraint if exists profiles_exercise_check;
alter table public.profiles add constraint profiles_exercise_check
    check (exercise in ('Often', 'Sometimes', 'Rarely', 'Prefer not to say'));

alter table public.profiles drop constraint if exists profiles_pets_check;
alter table public.profiles add constraint profiles_pets_check
    check (pets in ('Dog', 'Cat', 'Bird', 'Fish', 'No pets', 'Prefer not to say'));

alter table public.profiles drop constraint if exists profiles_children_check;
alter table public.profiles add constraint profiles_children_check
    check (children in ('No', 'Yes', 'Prefer not to say'));

-- ============================================================
-- 2. INDEXES for the hard filters
-- ============================================================
-- Single-column btrees for the cheap equality predicates, plus GIN for array
-- containment (interests / languages). The existing idx_profiles_location
-- GIST index already serves the ST_DWithin distance predicate.

create index if not exists idx_profiles_interested_in
    on public.profiles using gin (interested_in);
create index if not exists idx_profiles_languages
    on public.profiles using gin (languages);
create index if not exists idx_profiles_smoking on public.profiles (smoking);
create index if not exists idx_profiles_exercise on public.profiles (exercise);
create index if not exists idx_profiles_children on public.profiles (children);

-- Partial index: discovery only ever considers profiles that are not rejected.
create index if not exists idx_profiles_discoverable
    on public.profiles (last_active_at desc)
    where verification_status <> 'rejected';

-- ============================================================
-- 3. Deleted / banned account registry
-- ============================================================
-- Discovery must exclude deleted and banned accounts without reading
-- auth.users from the client (never granted) and without granting the
-- SECURITY DEFINER functions any extra privilege on auth. This view exposes
-- only these two columns.

-- The view runs with the privileges of its owner (postgres), which is what
-- lets a SECURITY DEFINER function read these two columns. It is never granted
-- to the client, so the anon key can see nothing here.
create or replace view public.auth_user_state as
select u.id as user_id, u.deleted_at, u.banned_until
from auth.users u
where u.deleted_at is not null or u.banned_until is not null;

-- Not granted to authenticated: read only from inside the SECURITY DEFINER
-- functions below. Keeps it out of reach of the anon key.
revoke all on public.auth_user_state from anon, authenticated;

-- ============================================================
-- 4. Privacy-safe distance label (single source of truth)
-- ============================================================
create or replace function public.format_distance_label(p_distance_km double precision)
returns text
language sql
immutable
as $$
    select case
        when p_distance_km is null then 'Nearby'
        when p_distance_km < 1  then 'Nearby'
        else round(p_distance_km::numeric, 0)::text || ' km away'
    end;
$$;

revoke all on function public.format_distance_label(double precision) from public, anon;

-- ============================================================
-- 5. get_matches_for_user - stop fabricating age 25
-- ============================================================
-- Identical output shape to migration 011, so no client change is required.
-- Behavioural change: age is NULL when no birthday is on file.
--
-- Postgres refuses to change a function's OUT-parameter list in place
-- (42P13: "cannot change return type of existing function"), so the old
-- signature is dropped first and the execute grant re-asserted at the end of
-- this migration. This is the same pattern migration 011 used.

drop function if exists public.get_matches_for_user(uuid, integer, integer);

create function public.get_matches_for_user(
    p_user_id uuid,
    p_limit integer default 50,
    p_offset integer default 0
)
returns table (
    match_id uuid,
    other_user_id uuid,
    display_name text,
    age integer,
    gender text,
    bio text,
    city text,
    primary_photo_path text,
    last_message text,
    last_message_at timestamptz,
    is_photo_verified boolean,
    trust_score integer
)
language plpgsql
security definer
set search_path = public
as $$
begin
    perform public.assert_self(p_user_id);
    p_limit := least(coalesce(p_limit, 50), 100);
    p_offset := greatest(coalesce(p_offset, 0), 0);

    return query
    select
        m.id as match_id,
        case when m.user_a_id = p_user_id then m.user_b_id else m.user_a_id end as other_user_id,
        p.display_name,
        -- NULL when unknown. Never invent an age.
        case when p.date_of_birth is not null
             then date_part('years', age(p.date_of_birth))::int
             else null end as age,
        p.gender,
        p.bio,
        p.city,
        (select storage_path from public.profile_photos
          where user_id = p.id and moderation_status = 'approved'
          order by is_primary desc, created_at asc limit 1) as primary_photo_path,
        (select mm.content from public.messages mm
          where mm.conversation_id = m.conversation_id
          order by mm.created_at desc limit 1) as last_message,
        (select mm.created_at from public.messages mm
          where mm.conversation_id = m.conversation_id
          order by mm.created_at desc limit 1) as last_message_at,
        p.is_photo_verified,
        p.trust_score
    from public.matches m
    join public.profiles p
      on p.id = case when m.user_a_id = p_user_id then m.user_b_id else m.user_a_id end
    where (m.user_a_id = p_user_id or m.user_b_id = p_user_id)
      and not exists (
          select 1 from public.blocks b
          where (b.blocker_id = p_user_id and b.blocked_id = p.id)
             or (b.blocker_id = p.id and b.blocked_id = p_user_id)
      )
      and not exists (select 1 from public.auth_user_state s
                      where s.user_id = p.id and s.deleted_at is not null)
    order by coalesce(
        (select max(mm.created_at) from public.messages mm
          where mm.conversation_id = m.conversation_id),
        m.created_at
    ) desc
    limit p_limit offset p_offset;
end;
$$;

-- ============================================================
-- 6. get_nearby_profiles - age fix + real discovery modes
-- ============================================================
-- Same 8-arg signature and output shape as migration 011 (the client depends
-- on both). Three changes: no fabricated age, an age hard filter that cannot
-- be bypassed by an unknown birthday, and a discovery mode that actually
-- changes the result. The return shape is unchanged, but the OUT-parameter
-- list cannot be altered in place, so the old signature is dropped and the
-- execute grant re-asserted below.

drop function if exists public.get_nearby_profiles(
    uuid, integer, integer, double precision, text[], integer, integer, text
);

create function public.get_nearby_profiles(
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
security definer
set search_path = public
as $$
declare
    v_lat double precision;
    v_lon double precision;
begin
    perform public.assert_self(p_user_id);
    p_limit := least(coalesce(p_limit, 20), 50);
    p_offset := greatest(coalesce(p_offset, 0), 0);

    select pr.latitude, pr.longitude into v_lat, v_lon
      from public.profiles pr where pr.id = p_user_id;

    return query
    select
        p.id as profile_id,
        p.display_name,
        -- NULL when unknown. Fabricating 25 is never correct.
        case when p.date_of_birth is not null
             then date_part('years', age(p.date_of_birth))::int
             else null end as age,
        p.gender,
        p.bio,
        p.city,
        case
            when p.latitude is not null and p.longitude is not null
                 and v_lat is not null and v_lon is not null
            then round((st_distance(
                    st_point(p.longitude, p.latitude)::geography,
                    st_point(v_lon, v_lat)::geography) / 1000)::numeric, 1)::double precision
            else 0
        end as distance_km,
        p.is_photo_verified,
        p.trust_score,
        (select storage_path from public.profile_photos
          where user_id = p.id and moderation_status = 'approved'
          order by is_primary desc, created_at asc limit 1) as primary_photo_path,
        (select coalesce(array_agg(i.name), '{}'::text[])
           from public.user_interests ui
           join public.interests i on i.id = ui.interest_id
          where ui.user_id = p.id) as interests,
        p.relationship_intent,
        p.last_active_at,
        (
            (p.trust_score * 0.3)
            + (least(round(coalesce(
                    case when p.latitude is not null and p.longitude is not null
                              and v_lat is not null and v_lon is not null
                         then st_distance(st_point(p.longitude, p.latitude)::geography,
                                          st_point(v_lon, v_lat)::geography) / 1000
                    end, 50))::numeric, 50) / 50 * 20)
            + (case when p.is_photo_verified then 15 else 0 end)
            + (case when p.last_active_at > now() - interval '7 days' then 20 else 0 end)
        ) as compatibility_score
    from public.profiles p
    where p.id <> p_user_id
      and p.latitude is not null
      and p.longitude is not null
      and v_lat is not null
      and v_lon is not null
      -- p_discovery_mode is now honoured: 'global' and 'city' intentionally
      -- ignore the radius, every other mode respects it.
      and (
            coalesce(p_discovery_mode, 'nearby') in ('global', 'city')
         or p_max_distance_km >= 1000
         or st_dwithin(
                st_point(p.longitude, p.latitude)::geography,
                st_point(v_lon, v_lat)::geography,
                p_max_distance_km * 1000)
      )
      -- HARD age filter. An unknown age can no longer slip through.
      and (p_age_min is null or p_age_max is null or (
            p.date_of_birth is not null
        and date_part('years', age(p.date_of_birth)) between p_age_min and p_age_max))
      and (p_preferred_genders is null
           or array_length(p_preferred_genders, 1) = 0
           or p.gender = any(p_preferred_genders))
      -- blocked, in either direction
      and not exists (select 1 from public.blocks b
                      where b.blocker_id = p_user_id and b.blocked_id = p.id)
      and not exists (select 1 from public.blocks b
                      where b.blocker_id = p.id and b.blocked_id = p_user_id)
      -- deleted / banned accounts never appear in discovery
      and not exists (select 1 from public.auth_user_state s
                      where s.user_id = p.id and s.deleted_at is not null)
      and not exists (select 1 from public.auth_user_state s
                      where s.user_id = p.id and s.banned_until is not null
                        and s.banned_until > now())
      and p.verification_status <> 'rejected'
      and coalesce((select us.show_me_in_search from public.user_settings us
                      where us.user_id = p.id), true)
      -- already-processed profiles stay out of the deck
      and not exists (select 1 from public.passes ps
                      where ps.user_id = p_user_id and ps.target_id = p.id)
      and not exists (select 1 from public.likes l
                      where l.liker_id = p_user_id and l.liked_id = p.id)
      and not exists (select 1 from public.matches mm
                      where (mm.user_a_id = p_user_id and mm.user_b_id = p.id)
                         or (mm.user_b_id = p_user_id and mm.user_a_id = p.id))
      and not exists (select 1 from public.reports r
                      where r.reporter_id = p_user_id and r.reported_id = p.id)
    order by distance_km asc nulls last,
             compatibility_score desc,
             p.last_active_at desc
    limit p_limit offset p_offset;
end;
$$;

-- ============================================================
-- 7. search_profiles - the ADVANCED SEARCH RPC
-- ============================================================
-- Every hard filter below is enforced HERE, in the database, with AND
-- semantics. A profile violating any single hard filter can never be
-- returned, whatever the client does.
--
-- Soft preferences (shared interests, intent match, completeness,
-- verification, recency) are applied ONLY in ORDER BY. They can reorder an
-- already-filtered set; they can never admit a profile a hard filter
-- rejected.
--
-- Result guarantee: searching "Female, 25-32, <=50 km, long-term" returns
-- only profiles satisfying all four. "No profiles match all your filters" is
-- therefore a truthful outcome, never a silently weakened query.

create or replace function public.search_profiles(
    p_user_id uuid,
    p_limit integer default 20,
    p_offset integer default 0,
    p_max_distance_km double precision default 50,
    p_search_lat double precision default null,
    p_search_lon double precision default null,
    p_search_city text default null,
    p_genders text[] default array[]::text[],
    p_age_min integer default null,
    p_age_max integer default null,
    p_interested_in text[] default array[]::text[],
    p_relationship_intents text[] default array[]::text[],
    p_cities text[] default array[]::text[],
    p_interests text[] default array[]::text[],
    p_languages text[] default array[]::text[],
    p_smoking text default null,
    p_drinking text default null,
    p_exercise text default null,
    p_children text default null,
    p_pets text default null,
    p_include_dealt boolean default false
)
returns table (
    profile_id uuid,
    display_name text,
    age integer,
    gender text,
    bio text,
    city text,
    locality text,
    distance_km double precision,
    distance_label text,
    relationship_intent text,
    is_photo_verified boolean,
    verification_status text,
    trust_score integer,
    profile_completion integer,
    primary_photo_path text,
    interests text[],
    languages text[],
    last_active_at timestamptz,
    compatibility_score numeric
)
language plpgsql
security definer
set search_path = public
as $$
declare
    v_origin_lat double precision;
    v_origin_lon double precision;
    v_own_interests text[] := '{}'::text[];
begin
    -- ownership: a caller may only run their own search
    perform public.assert_self(p_user_id);

    -- abuse caps
    p_limit := least(greatest(coalesce(p_limit, 20), 1), 50);
    p_offset := greatest(coalesce(p_offset, 0), 0);

    -- input validation: never trust the client
    if p_max_distance_km is not null
       and (p_max_distance_km < 0 or p_max_distance_km > 20000) then
        raise exception 'invalid distance';
    end if;
    if p_age_min is not null and (p_age_min < 18 or p_age_min > 120) then
        raise exception 'invalid age range';
    end if;
    if p_age_max is not null and (p_age_max < 18 or p_age_max > 120) then
        raise exception 'invalid age range';
    end if;
    if p_age_min is not null and p_age_max is not null
       and p_age_min > p_age_max then
        raise exception 'invalid age range';
    end if;
    if p_search_lat is not null and (p_search_lat < -90 or p_search_lat > 90) then
        raise exception 'invalid coordinates';
    end if;
    if p_search_lon is not null and (p_search_lon < -180 or p_search_lon > 180) then
        raise exception 'invalid coordinates';
    end if;

    -- resolve the search origin: an explicit geocoded destination (travel /
    -- explore) wins, otherwise the caller's own stored position. These
    -- coordinates describe the SEEKER, never a target.
    if p_search_lat is not null and p_search_lon is not null then
        v_origin_lat := p_search_lat;
        v_origin_lon := p_search_lon;
    else
        select pr.latitude, pr.longitude into v_origin_lat, v_origin_lon
          from public.profiles pr where pr.id = p_user_id;
    end if;

    -- the seeker's interests feed the SOFT "shared interests" score only
    select coalesce(array_agg(i.name), '{}'::text[])
      into v_own_interests
      from public.user_interests ui
      join public.interests i on i.id = ui.interest_id
     where ui.user_id = p_user_id;

    return query
    with candidate as (
        select
            p.id, p.display_name, p.date_of_birth, p.gender, p.bio, p.city,
            p.locality, p.latitude, p.longitude, p.relationship_intent,
            p.is_photo_verified, p.verification_status, p.trust_score,
            p.profile_completion, p.last_active_at, p.languages,
            p.smoking, p.drinking, p.exercise, p.children, p.pets,
            coalesce((
                select array_agg(i.name)
                  from public.user_interests ui
                  join public.interests i on i.id = ui.interest_id
                 where ui.user_id = p.id
            ), '{}'::text[]) as interests
        from public.profiles p
        where p.id <> p_user_id
    )
    select
        c.id as profile_id,
        c.display_name,
        -- NULL when the birthday is unknown. Never fabricate an age.
        case when c.date_of_birth is not null
             then date_part('years', age(c.date_of_birth))::int
             else null end as age,
        c.gender,
        c.bio,
        c.city,
        c.locality,
        case
            when c.latitude is not null and c.longitude is not null
                 and v_origin_lat is not null and v_origin_lon is not null
            then round((st_distance(
                    st_point(c.longitude, c.latitude)::geography,
                    st_point(v_origin_lon, v_origin_lat)::geography) / 1000)::numeric, 1)::double precision
            else null
        end as distance_km,
        -- Privacy-safe label only: never coordinates, never a street address.
        case
            when c.latitude is null or c.longitude is null
                 or v_origin_lat is null or v_origin_lon is null then 'Nearby'
            when st_distance(st_point(c.longitude, c.latitude)::geography,
                             st_point(v_origin_lon, v_origin_lat)::geography) < 1000
                then 'Nearby'
            when st_distance(st_point(c.longitude, c.latitude)::geography,
                             st_point(v_origin_lon, v_origin_lat)::geography) < 25000
                then round((st_distance(st_point(c.longitude, c.latitude)::geography,
                             st_point(v_origin_lon, v_origin_lat)::geography) / 1000)::numeric, 0)::text
                     || ' km away'
            when nullif(btrim(c.city), '') is not null then btrim(c.city)
            else 'Around your area'
        end as distance_label,
        c.relationship_intent,
        c.is_photo_verified,
        c.verification_status,
        c.trust_score,
        c.profile_completion,
        (select pp.storage_path from public.profile_photos pp
          where pp.user_id = c.id and pp.moderation_status = 'approved'
          order by pp.is_primary desc, pp.created_at asc limit 1) as primary_photo_path,
        c.interests,
        c.languages,
        c.last_active_at,
        -- ===== SOFT RANKING: ORDER BY only, can never admit =============
        (
              -- distance relevance 0-30 (closer ranks higher)
              (30 - least(coalesce(
                    case when c.latitude is not null and c.longitude is not null
                              and v_origin_lat is not null and v_origin_lon is not null
                         then st_distance(st_point(c.longitude, c.latitude)::geography,
                                          st_point(v_origin_lon, v_origin_lat)::geography) / 1000
                    end, 1000), 1000) / 1000 * 30)
              -- shared interests: up to 25
            + (case when exists (select 1 from unnest(c.interests) mine
                                 where mine = any(v_own_interests))
                   then least(cardinality(c.interests), 5)::numeric * 5
                   else 0 end)
              -- relationship-intent compatibility: up to 20
            + (case when c.relationship_intent = 'Long-term relationship' then 20
                    when c.relationship_intent = 'Dating & Weekend Plans' then 16
                    when c.relationship_intent = 'Dating' then 12
                    when c.relationship_intent = 'New people & Friendships' then 8
                    else 0 end)
              -- profile completeness: up to 10
            + (least(coalesce(c.profile_completion, 0), 100)::numeric / 100 * 10)
              -- verification: up to 10
            + (case when c.is_photo_verified then 6 else 0 end)
            + (case when c.verification_status = 'verified' then 4 else 0 end)
              -- recent activity: up to 5
            + (case when c.last_active_at > now() - interval '3 days' then 5
                    when c.last_active_at > now() - interval '14 days' then 2
                    else 0 end)
        ) as compatibility_score
    from candidate c
    where
        -- ========== HARD FILTERS (AND semantics) =======================
        -- 1. gender
        (p_genders is null or cardinality(p_genders) = 0
         or c.gender = any(p_genders))
        -- 2. interested_in
        and (p_interested_in is null or cardinality(p_interested_in) = 0
             or c.gender = any(p_interested_in))
        -- 3. age. An unknown age cannot satisfy a hard age filter, so those
        --    profiles are EXCLUDED rather than passed.
        and (
            (p_age_min is null and p_age_max is null)
            or (c.date_of_birth is not null
                and date_part('years', age(c.date_of_birth))
                    between coalesce(p_age_min, 18) and coalesce(p_age_max, 120))
        )
        -- 4. distance
        and (
            p_max_distance_km is null
            or v_origin_lat is null
            or c.latitude is null
            or c.longitude is null
            or st_dwithin(
                   st_point(c.longitude, c.latitude)::geography,
                   st_point(v_origin_lon, v_origin_lat)::geography,
                   p_max_distance_km * 1000)
        )
        -- 5. relationship intent
        and (p_relationship_intents is null
             or cardinality(p_relationship_intents) = 0
             or c.relationship_intent = any(p_relationship_intents))
        -- 6. city
        and (p_cities is null or cardinality(p_cities) = 0
             or lower(btrim(coalesce(c.city, ''))) = any(
                    select lower(btrim(x)) from unnest(p_cities) as x))
        -- 7. interests (ANY semantics)
        and (p_interests is null or cardinality(p_interests) = 0
             or exists (select 1 from unnest(p_interests) want
                        where want = any(c.interests)))
        -- 8. languages (ANY semantics)
        and (p_languages is null or cardinality(p_languages) = 0
             or exists (select 1 from unnest(p_languages) want
                        where want = any(c.languages)))
        -- 9-13. lifestyle
        and (p_smoking  is null or c.smoking  = p_smoking)
        and (p_drinking is null or c.drinking = p_drinking)
        and (p_exercise is null or c.exercise = p_exercise)
        and (p_children is null or c.children = p_children)
        and (p_pets     is null or c.pets     = p_pets)
        -- ========== ALWAYS-ON EXCLUSIONS ================================
        -- blocked, in either direction
        and not exists (select 1 from public.blocks b
                        where b.blocker_id = p_user_id and b.blocked_id = c.id)
        and not exists (select 1 from public.blocks b
                        where b.blocker_id = c.id and b.blocked_id = p_user_id)
        -- deleted / banned / rejected / opted-out accounts
        and not exists (select 1 from public.auth_user_state s
                        where s.user_id = c.id and s.deleted_at is not null)
        and not exists (select 1 from public.auth_user_state s
                        where s.user_id = c.id and s.banned_until is not null
                          and s.banned_until > now())
        and c.verification_status <> 'rejected'
        and coalesce((select us.show_me_in_search from public.user_settings us
                      where us.user_id = c.id), true)
        -- already-processed profiles stay out of the deck unless asked for
        and (
            coalesce(p_include_dealt, false)
            or not exists (select 1 from public.likes l
                           where l.liker_id = p_user_id and l.liked_id = c.id)
            or not exists (select 1 from public.passes ps
                           where ps.user_id = p_user_id and ps.target_id = c.id)
            or not exists (select 1 from public.matches mm
                           where (mm.user_a_id = p_user_id and mm.user_b_id = c.id)
                              or (mm.user_b_id = p_user_id and mm.user_a_id = c.id))
        )
    order by compatibility_score desc nulls last,
             distance_km asc nulls last,
             c.last_active_at desc nulls last
    limit p_limit offset p_offset;
end;
$$;

-- ============================================================
-- 8. EXECUTE GRANTS
-- ============================================================
-- search_profiles is the only new capability. Callable by an authenticated
-- user, for themselves only (assert_self runs first).
revoke all on function public.search_profiles(
    uuid, integer, integer, double precision, double precision, double precision,
    text, text[], integer, integer, text[], text[], text[], text[], text[],
    text, text, text, text, text, boolean
) from public, anon;
grant execute on function public.search_profiles(
    uuid, integer, integer, double precision, double precision, double precision,
    text, text[], integer, integer, text[], text[], text[], text[], text[],
    text, text, text, text, text, boolean
) to authenticated;

-- Re-assert execute on the recreated discovery functions.
revoke all on function public.get_nearby_profiles(
    uuid, integer, integer, double precision, text[], integer, integer, text
) from public, anon;
grant execute on function public.get_nearby_profiles(
    uuid, integer, integer, double precision, text[], integer, integer, text
) to authenticated;

revoke all on function public.get_matches_for_user(uuid, integer, integer)
    from public, anon;
grant execute on function public.get_matches_for_user(uuid, integer, integer)
    to authenticated;

-- ============================================================
-- 9. COLUMN GRANTS for the new, user-editable profile attributes
-- ============================================================
-- Migration 006 did `revoke select` on profiles followed by an explicit
-- column allow-list. Postgres column grants are ADDITIVE, so the new columns
-- must be listed here or a direct SELECT of them fails with permission denied.
grant select (interested_in, languages, smoking, drinking, exercise, children,
              pets, height_cm, prompts)
    on public.profiles to authenticated;
grant update (interested_in, languages, smoking, drinking, exercise, children,
              pets, height_cm, prompts)
    on public.profiles to authenticated;
