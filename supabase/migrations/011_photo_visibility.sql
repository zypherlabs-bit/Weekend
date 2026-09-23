-- Migration: 011_photo_visibility.sql
-- Photo visibility: private bucket + signed-URL delivery + launch policy.
--
-- Live two-user verification found a dead-end: uploads were forced to
-- moderation_status='pending' and nothing ever approved them (the
-- photo-verification Edge Function requires an external Gemini key and
-- returns 500 without one), so no photo was ever visible to anyone.
-- On top of that, the client stored PUBLIC urls for a PRIVATE bucket,
-- which can never render.
--
-- Policy after this migration:
--   * the bucket stays PRIVATE; authorization rules are unchanged
--   * the client cannot choose a moderation status; the SERVER auto-approves
--     the upload at INSERT time (launch policy: real user uploads become
--     visible immediately; the photo-verification Edge Function - service
--     role - may still reject later when a Gemini key is configured)
--   * clients still can never flip moderation_status on UPDATE
--   * RPCs expose the private storage PATH instead of a URL; clients obtain
--     short-lived signed URLs through the get-photo-urls Edge Function,
--     which only signs approved photos or the caller's own uploads

-- ============================================================
-- 1. MODERATION: server-decided status
-- ============================================================
create or replace function public.enforce_photo_moderation()
returns trigger as $$
begin
    if tg_op = 'INSERT' then
        -- Server decides the initial status (launch policy: auto-approve).
        -- The client-supplied value is ignored. photo-verification can still
        -- reject server-side later.
        new.moderation_status := 'approved';
        return new;
    end if;

    -- UPDATE: trusted backend is allowed to change the status; clients never.
    if auth.role() = 'service_role' or auth.uid() is null then
        return new;
    end if;

    if new.moderation_status is distinct from old.moderation_status then
        raise exception 'moderation_status can only be changed by the backend';
    end if;
    return new;
end;
$$ language plpgsql security definer
set search_path = public;

drop trigger if exists on_photo_moderation_change on public.profile_photos;
drop trigger if exists enforce_photo_moderation_trigger on public.profile_photos;
create trigger enforce_photo_moderation_trigger
    before insert or update on public.profile_photos
    for each row
    execute function public.enforce_photo_moderation();

-- ============================================================
-- 2. RPC SIGNATURES: expose the storage PATH, not a URL
-- ============================================================
-- Postgres cannot change a function's OUT parameter names in place, so the
-- RPCs are dropped here and immediately recreated from their 006 definitions
-- (kept as the single source of truth) with `primary_photo_path` instead of
-- `primary_photo_url`. The execute grants from 006 section 14 are re-applied
-- by the provisioning step right after the functions are recreated.
drop function if exists public.get_nearby_profiles(
    uuid, integer, integer, double precision, text[], integer, integer, text
);
drop function if exists public.get_matches_for_user(uuid, integer, integer);


-- ---- Recreated definitions (path-based photo exposure) ----

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
security definer
set search_path = public
as $$
begin
    -- Only the caller's own discovery results may be computed. This blocks
    -- full-database enumeration with arbitrary filters and keeps the
    -- expensive PostGIS queries bound to real authenticated users.
    perform public.assert_self(p_user_id);

    -- Cap page sizes to keep the RPC cheap and resistant to abuse.
    p_limit := least(coalesce(p_limit, 20), 50);
    p_offset := greatest(coalesce(p_offset, 0), 0);

    return query
    select
        p.id as profile_id,
        p.display_name,
        case
            when p.date_of_birth is not null
            then date_part('years', age(p.date_of_birth))::int
            else 25
        end as age,
        p.gender,
        p.bio,
        p.city,
        case
            when p.latitude is not null and p.longitude is not null
            then round(
                (
                    ST_Distance(
                        ST_Point(p.longitude, p.latitude)::geography,
                        ST_Point(
                            (select longitude from public.profiles where id = p_user_id),
                            (select latitude from public.profiles where id = p_user_id)
                        )::geography
                    ) / 1000
                )::numeric,
                1
            )::double precision
            else 0
        end as distance_km,
        p.is_photo_verified,
        p.trust_score,
        (select storage_path from public.profile_photos where user_id = p.id and moderation_status = 'approved' order by is_primary desc, created_at asc limit 1) as primary_photo_path,
        (select array_agg(i.name) from public.user_interests ui join public.interests i on ui.interest_id = i.id where ui.user_id = p.id) as interests,
        p.relationship_intent,
        p.last_active_at,
        -- Suggested-for-you ranking: distance, activity, verification and
        -- trust signals. Deliberately NOT presented to users as a scientific
        -- compatibility prediction.
        (
            (p.trust_score * 0.3)
            + (least(round(coalesce(distance_km, 50))::numeric, 50) / 50 * 20)
            + (case when p.is_photo_verified then 15 else 0 end)
            + (case when p.last_active_at > now() - interval '7 days' then 20 else 0 end)
        ) as compatibility_score
    from public.profiles p
    where p.id <> p_user_id
      and (
        p_max_distance_km >= 1000
        or ST_DWithin(
            ST_Point(p.longitude, p.latitude)::geography,
            ST_Point(
                (select latitude from public.profiles where id = p_user_id),
                (select longitude from public.profiles where id = p_user_id)
            )::geography,
            p_max_distance_km * 1000
        )
      )
      and (p.date_of_birth is null
           or date_part('years', age(p.date_of_birth)) between p_age_min and p_age_max)
      and (p_preferred_genders is null or array_length(p_preferred_genders, 1) = 0 or p.gender = any(p_preferred_genders))
      and not exists (select 1 from public.blocks where blocker_id = p_user_id and blocked_id = p.id)
      and not exists (select 1 from public.blocks where blocker_id = p.id and blocked_id = p_user_id)
      and not exists (select 1 from public.passes where user_id = p_user_id and target_id = p.id)
      and not exists (select 1 from public.likes where liker_id = p_user_id and liked_id = p.id)
      and not exists (
          select 1 from public.matches
          where (user_a_id = p_user_id and user_b_id = p.id)
             or (user_a_id = p.id and user_b_id = p_user_id)
      )
      and not exists (select 1 from public.reports where reporter_id = p_user_id and reported_id = p.id)
    order by distance_km asc nulls last,
             compatibility_score desc,
             p.last_active_at desc
    limit p_limit offset p_offset;
end;
$$;

create or replace function public.get_matches_for_user(
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
    distance_km double precision,
    is_photo_verified boolean,
    trust_score integer,
    primary_photo_path text,
    interests text[],
    relationship_intent text,
    matched_at timestamptz,
    last_message_text text,
    last_message_time timestamptz,
    last_message_sender uuid,
    unread_count integer,
    shared_interests text[]
)
language plpgsql
security definer
set search_path = public
as $$
begin
    -- Matches and message previews are private: callers may only read their
    -- own. Without this check any authenticated user could read anyone's
    -- conversations.
    perform public.assert_self(p_user_id);

    p_limit := least(coalesce(p_limit, 50), 100);
    p_offset := greatest(coalesce(p_offset, 0), 0);

    return query
    select
        m.id as match_id,
        case when m.user_a_id = p_user_id then m.user_b_id else m.user_a_id end as other_user_id,
        op.display_name,
        case when op.date_of_birth is not null then date_part('years', age(op.date_of_birth))::int else 25 end as age,
        op.gender,
        op.bio,
        op.city,
        case
            when op.latitude is not null and op.longitude is not null
            then round(
                (
                    ST_Distance(
                        ST_Point(op.longitude, op.latitude)::geography,
                        ST_Point(
                            (select longitude from public.profiles where id = p_user_id),
                            (select latitude from public.profiles where id = p_user_id)
                        )::geography
                    ) / 1000
                )::numeric,
                1
            )::double precision
            else 0
        end as distance_km,
        op.is_photo_verified,
        op.trust_score,
        (select storage_path from public.profile_photos where user_id = op.id and moderation_status = 'approved' order by is_primary desc, created_at asc limit 1) as primary_photo_path,
        (select array_agg(i.name) from public.user_interests ui join public.interests i on ui.interest_id = i.id where ui.user_id = op.id) as interests,
        op.relationship_intent,
        m.created_at as matched_at,
        lm.text as last_message_text,
        lm.created_at as last_message_time,
        lm.sender_id as last_message_sender,
        coalesce(cm.unread_count, 0) as unread_count,
        (select array_agg(i.name)
         from public.user_interests uia
         join public.user_interests uib on uia.interest_id = uib.interest_id
         join public.interests i on uia.interest_id = i.id
         where uia.user_id = p_user_id and uib.user_id = op.id) as shared_interests
    from public.matches m
    join public.profiles op on (case when m.user_a_id = p_user_id then m.user_b_id else m.user_a_id end) = op.id
    left join public.conversations c on c.match_id = m.id
    left join public.conversation_members cm on cm.conversation_id = c.id and cm.user_id = p_user_id
    left join lateral (
        select text, created_at, sender_id
        from public.messages
        where conversation_id = c.id
        order by created_at desc
        limit 1
    ) lm on true
    where (m.user_a_id = p_user_id or m.user_b_id = p_user_id)
      and not exists (select 1 from public.blocks b where (b.blocker_id = p_user_id and b.blocked_id = op.id)
                       or (b.blocker_id = op.id and b.blocked_id = p_user_id))
    order by m.created_at desc, c.updated_at desc
    limit p_limit offset p_offset;
end;
$$;
-- Execute grants from 006 section 14, re-applied after recreation.
revoke execute on function public.get_nearby_profiles(uuid, integer, integer, double precision, text[], integer, integer, text) from anon, authenticated, public;
grant execute on function public.get_nearby_profiles(uuid, integer, integer, double precision, text[], integer, integer, text) to authenticated;
revoke execute on function public.get_matches_for_user(uuid, integer, integer) from anon, authenticated, public;
grant execute on function public.get_matches_for_user(uuid, integer, integer) to authenticated;
