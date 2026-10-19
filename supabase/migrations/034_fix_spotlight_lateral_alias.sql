-- ============================================================
-- 034 - fix: search_profiles (21-arg) spotlight lateral alias
-- ============================================================
--
-- 031 introduced the SOFT spotlight ranking in the 21-argument
-- public.search_profiles by joining
--
--     left join lateral (... limit 1) sw on true
--
-- but the lateral's select list aliased its constant as `mid`, while the
-- outer query reads `sw.id` twice (the +40 ranking term and the is_spotlit
-- output column). Postgres resolves those at execution time, so the function
-- compiled cleanly and then failed on every call with
--
--     ERROR: 42703: column sw.id does not exist
--
-- i.e. the hardened discovery feed returned HTTP 400 while the 13-argument
-- legacy overload (still used by the advanced-search screen) kept working,
-- which masked the defect.
--
-- This migration is a single CREATE OR REPLACE with `select 1 as id`, matching
-- the identical lateral already used in get_nearby_profiles. The OUT row type
-- is unchanged, so no DROP is required and nothing else is touched.
--
-- Additive and idempotent: safe to re-run.

create or replace function public.search_profiles(p_user_id uuid, p_limit integer DEFAULT 20, p_offset integer DEFAULT 0, p_max_distance_km double precision DEFAULT 50, p_search_lat double precision DEFAULT NULL::double precision, p_search_lon double precision DEFAULT NULL::double precision, p_search_city text DEFAULT NULL::text, p_genders text[] DEFAULT ARRAY[]::text[], p_age_min integer DEFAULT NULL::integer, p_age_max integer DEFAULT NULL::integer, p_interested_in text[] DEFAULT ARRAY[]::text[], p_relationship_intents text[] DEFAULT ARRAY[]::text[], p_cities text[] DEFAULT ARRAY[]::text[], p_interests text[] DEFAULT ARRAY[]::text[], p_languages text[] DEFAULT ARRAY[]::text[], p_smoking text DEFAULT NULL::text, p_drinking text DEFAULT NULL::text, p_exercise text DEFAULT NULL::text, p_children text DEFAULT NULL::text, p_pets text DEFAULT NULL::text, p_include_dealt boolean DEFAULT false)
 RETURNS TABLE(profile_id uuid, display_name text, age integer, gender text, bio text, city text, locality text, distance_km double precision, distance_label text, relationship_intent text, is_photo_verified boolean, verification_status text, trust_score integer, profile_completion integer, primary_photo_id uuid, primary_photo_path text, interests text[], languages text[], last_active_at timestamp with time zone, is_online boolean, is_spotlit boolean, compatibility_score numeric)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
        left join public.user_settings us on us.user_id = p.id
        where p.id <> p_user_id
          -- SNOOZE exclusion
          and not (coalesce(us.snooze_mode, false)
                   and (us.snooze_until is null or us.snooze_until > now()))
          -- INCOGNITO exclusion
          and (not coalesce(us.incognito_mode, false)
               or exists (select 1 from public.likes l2
                          where l2.liker_id = p.id
                            and l2.liked_id = p_user_id))
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
        -- Photo impressions need the real photo uuid: the client cannot
        -- invent one, so discovery reports the primary photo's id alongside
        -- its (privacy-safe) signed-URL path.
        (select pp.id from public.profile_photos pp
          where pp.user_id = c.id and pp.moderation_status = 'approved'
          order by pp.is_primary desc, pp.created_at asc limit 1) as primary_photo_id,
        (select pp.storage_path from public.profile_photos pp
          where pp.user_id = c.id and pp.moderation_status = 'approved'
          order by pp.is_primary desc, pp.created_at asc limit 1) as primary_photo_path,
        c.interests,
        c.languages,
        -- Raw last-seen only leaves the API when the owner consents.
        case when coalesce((select us2.show_online_now
              from public.user_settings us2 where us2.user_id = c.id), true)
             then c.last_active_at else null end as last_active_at,
        -- Online Now flag: consented + fresh.
        (coalesce((select us3.show_online_now
              from public.user_settings us3 where us3.user_id = c.id), true)
         and c.last_active_at > now() - interval '5 minutes') as is_online,
        (sw.id is not null) as is_spotlit,
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
              -- Spotlight: +40 while the candidate's window is live (soft only)
            + (case when sw.id is not null then 40 else 0 end)
        )::numeric as compatibility_score
    from candidate c
    left join lateral (
        select 1 as id from public.spotlight_windows w
        where w.user_id = c.id and w.starts_at <= now() and w.ends_at > now()
        limit 1
    ) sw on true
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
        -- already-processed profiles stay out of the deck unless asked for.
        -- NOTE: the OR semantics below are PRESERVED FROM 023/030 VERBATIM -
        -- see the migration header for why this rewrite does not change them.
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
    order by is_spotlit desc nulls last,
             compatibility_score desc nulls last,
             distance_km asc nulls last,
             c.last_active_at desc nulls last
    limit p_limit offset p_offset;
end;
$function$;

revoke all on function public.search_profiles(
    uuid, integer, integer, double precision, double precision, double precision,
    text, text[], integer, integer, text[], text[], text[], text[], text[], text,
    text, text, text, text, boolean
) from public, anon;
grant execute on function public.search_profiles(
    uuid, integer, integer, double precision, double precision, double precision,
    text, text[], integer, integer, text[], text[], text[], text[], text[], text,
    text, text, text, text, boolean
) to authenticated;
