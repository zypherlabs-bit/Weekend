-- ============================================================
-- 035 - fix: privacy-mode bypass in the 13-argument search_profiles
-- ============================================================
--
-- Two overloads of public.search_profiles are live at the same time:
--
--   13-arg  (p_genders, p_age_min, p_age_max, p_max_distance_km, p_city,
--            p_relationship_intents, p_interests, p_languages, p_lifestyle,
--            p_location_mode, p_page, p_page_size)     <- created by 022
--   21-arg  (p_user_id, p_limit, p_offset, ...)        <- hardened by 031
--
-- The Flutter advanced-search screen calls the 13-argument signature
-- (lib/models/discovery_preferences.dart -> toRpcParams), so it never picked up
-- the privacy work that 031 added to the 21-argument version: excluding
-- candidates who are in incognito mode, who are in snooze mode, or who have
-- switched online-status consent off, and withholding last_active_at unless
-- that consent is present.
--
-- Measured on the live project (tool/privacy_bypass_probe.py) with two
-- synthetic accounts at identical coordinates:
--
--     incognito OFF:  21-arg sees the candidate, 13-arg sees the candidate
--     incognito ON:   21-arg does NOT see her, 13-arg STILL does  <- bypass
--
-- This migration keeps the client contract intact (same name, same 13
-- arguments, same OUT row type, same grants) but delegates to the hardened
-- 21-argument function, translating page/page_size into limit/offset and the
-- jsonb lifestyle blob into the discrete lifestyle parameters. Result: the
-- already-shipped client inherits the privacy filters without an app release.
--
-- The OUT row type is deliberately identical to 022's (this is CREATE OR
-- REPLACE, which refuses an OUT row-type change), and `match_score` carries the
-- hardened function's compatibility_score. The client does not read match_score.
--
-- Additive and idempotent: safe to re-run.

create or replace function public.search_profiles(
    p_user_id uuid,
    p_genders text[] default null,
    p_age_min integer default 18,
    p_age_max integer default 99,
    p_max_distance_km double precision default 50,
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
    last_active_at timestamp with time zone,
    match_score numeric
)
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $$
    select
        r.profile_id,
        r.display_name,
        r.age,
        r.gender,
        r.bio,
        r.city,
        r.distance_km,
        r.is_photo_verified,
        r.trust_score,
        r.primary_photo_path,
        r.interests,
        r.relationship_intent,
        r.last_active_at,
        r.compatibility_score as match_score
    from public.search_profiles(
        p_user_id               => p_user_id,
        p_limit                 => greatest(coalesce(p_page_size, 20), 1),
        p_offset                => greatest(coalesce(p_page, 1) - 1, 0)
                                   * greatest(coalesce(p_page_size, 20), 1),
        p_max_distance_km       => coalesce(p_max_distance_km, 50),
        -- Let the hardened function derive the search origin (its own travel /
        -- profile coordinates) exactly as the discovery feed does.
        p_search_lat            => null,
        p_search_lon            => null,
        p_search_city           => p_city,
        p_genders               => p_genders,
        p_age_min               => p_age_min,
        p_age_max               => p_age_max,
        p_interested_in         => null,
        p_relationship_intents  => p_relationship_intents,
        p_cities                => case when p_city is null then null else array[p_city] end,
        p_interests             => p_interests,
        p_languages             => p_languages,
        p_smoking               => p_lifestyle ->> 'smoking',
        p_drinking              => p_lifestyle ->> 'drinking',
        p_exercise              => p_lifestyle ->> 'exercise',
        p_children              => p_lifestyle ->> 'children',
        p_pets                  => p_lifestyle ->> 'pets',
        p_include_dealt         => false
    ) r;
$$;

-- Keep the existing privilege posture (authenticated only) explicit.
revoke all on function public.search_profiles(
    uuid, text[], integer, integer, double precision, text, text[], text[], text[],
    jsonb, text, integer, integer
) from public, anon;

grant execute on function public.search_profiles(
    uuid, text[], integer, integer, double precision, text, text[], text[], text[],
    jsonb, text, integer, integer
) to authenticated;
