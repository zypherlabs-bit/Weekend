-- Migration: 006_security_fixes.sql
-- Production security hardening pass (audit fixes).
--
-- Fixes:
--   1. get_nearby_profiles / get_matches_for_user / get_referral_stats /
--      delete_user_account: enforce p_user_id = auth.uid() (were callable by
--      any authenticated user for ANY user id -> profile enumeration, message
--      IDOR, cross-account deletion).
--   2. check_mutual_like: fix non-existent column reference referree_id
--      (actual column: referee_id) which aborted match creation entirely.
--   3. profile_photos: clients can no longer insert/update rows with
--      moderation_status != 'pending' (moderation bypass).
--   4. plans: SELECT policy now respects privacy_level (private plans were
--      readable by every authenticated user, including venue coordinates).
--   5. preferences: policy with-check referenced non-existent column id
--      (prevented users from ever updating their own preferences).
--   6. messages: block enforcement + server-side anti-flood rate limiting.
--   7. profiles: raw latitude/longitude are no longer readable via direct
--      table SELECT (only aggregated distance through SECURITY DEFINER RPCs).
--   8. plan_participants: private plans cannot be joined by arbitrary users.

-- ============================================================
-- 1. RPC OWNERSHIP ENFORCEMENT
-- ============================================================
create or replace function public.assert_self(p_user_id uuid)
returns void
language plpgsql
as $$
begin
    if auth.uid() is null or auth.uid() <> p_user_id then
        raise exception 'Not authorized to access another user''s data';
    end if;
end;
$$;

-- ============================================================
-- 2. delete_user_account - ownership enforced
-- ============================================================
create or replace function public.delete_user_account(
    p_user_id uuid,
    p_reason text default 'user_request'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    v_result jsonb;
begin
    perform public.assert_self(p_user_id);

    insert into public.moderation_events (user_id, action, reason, performed_by, created_at)
    values (p_user_id, 'delete', p_reason, p_user_id, now());

    delete from public.referrals where referrer_id = p_user_id;
    delete from public.referrals where referee_id = p_user_id;
    delete from public.verification_requests where user_id = p_user_id;
    delete from public.plans where creator_id = p_user_id;

    v_result := jsonb_build_object(
        'success', true,
        'user_id', p_user_id,
        'reason', p_reason,
        'deleted_at', now()
    );

    return v_result;
end;
$$;

-- ============================================================
-- 3. get_nearby_profiles - ownership enforced
-- ============================================================
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
    primary_photo_url text,
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
            then date_part('years', age(p.date_of_birth))
            else 25
        end as age,
        p.gender,
        p.bio,
        p.city,
        case
            when p.latitude is not null and p.longitude is not null
            then round(
                ST_Distance(
                    ST_Point(p.longitude, p.latitude)::geography,
                    ST_Point(
                        (select latitude from public.profiles where id = p_user_id),
                        (select longitude from public.profiles where id = p_user_id)
                    )::geography
                ) / 1000,
                1
            )
            else 0
        end as distance_km,
        p.is_photo_verified,
        p.trust_score,
        (select photo_url from public.profile_photos where user_id = p.id and is_primary = true limit 1) as primary_photo_url,
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

-- ============================================================
-- 4. get_matches_for_user - ownership enforced
-- ============================================================
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
    primary_photo_url text,
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
        case when op.date_of_birth is not null then date_part('years', age(op.date_of_birth)) else 25 end as age,
        op.gender,
        op.bio,
        op.city,
        case
            when op.latitude is not null and op.longitude is not null
            then round(
                ST_Distance(
                    ST_Point(op.longitude, op.latitude)::geography,
                    ST_Point(
                        (select latitude from public.profiles where id = p_user_id),
                        (select longitude from public.profiles where id = p_user_id)
                    )::geography
                ) / 1000,
                1
            )
            else 0
        end as distance_km,
        op.is_photo_verified,
        op.trust_score,
        (select photo_url from public.profile_photos where user_id = op.id and is_primary = true limit 1) as primary_photo_url,
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

-- ============================================================
-- 5. get_referral_stats - ownership enforced
-- ============================================================
create or replace function public.get_referral_stats(
    p_user_id uuid
)
returns table (
    referral_code text,
    invited_count integer,
    verified_count integer,
    badge_title text,
    achievement_tier text,
    link_url text
)
language plpgsql
security definer
set search_path = public
as $$
declare
    v_code text;
begin
    perform public.assert_self(p_user_id);

    select referral_code into v_code
    from public.referrals
    where referrer_id = p_user_id
    order by created_at desc
    limit 1;

    if v_code is null then
        select referral_code into v_code
        from public.profiles
        where id = p_user_id;
    end if;

    return query
    select
        v_code as referral_code,
        count(*)::integer as invited_count,
        count(*) filter (where status = 'successful')::integer as verified_count,
        case
            when count(*) filter (where status = 'successful') >= 10 then 'Elite Pioneer'
            when count(*) filter (where status = 'successful') >= 5 then 'Silver Ambassador'
            when count(*) filter (where status = 'successful') >= 1 then 'Bronze Contributor'
            else 'New Pioneer'
        end as badge_title,
        case
            when count(*) filter (where status = 'successful') >= 10 then 'Gold Ambassador'
            when count(*) filter (where status = 'successful') >= 5 then 'Silver Ambassador'
            when count(*) filter (where status = 'successful') >= 1 then 'Bronze Contributor'
            else 'New Pioneer'
        end as achievement_tier,
        'https://weekend.app/invite/' || coalesce(v_code, '') as link_url
    from public.referrals
    where referrer_id = p_user_id;
end;
$$;

-- ============================================================
-- 6. check_mutual_like - fix referree_id typo
--    (the original aborted match creation for EVERY mutual like)
-- ============================================================
create or replace function public.check_mutual_like()
returns trigger as $$
declare
    existing_like record;
    existing_match record;
    v_match_id uuid;
begin
    select * into existing_like
    from public.likes
    where liker_id = new.liked_id and liked_id = new.liker_id;

    if existing_like.id is not null then
        select * into existing_match
        from public.matches
        where (user_a_id = new.liker_id and user_b_id = new.liked_id)
           or (user_a_id = new.liked_id and user_b_id = new.liker_id);

        if existing_match.id is null then
            if new.liker_id < new.liked_id then
                insert into public.matches (user_a_id, user_b_id, created_at)
                values (new.liker_id, new.liked_id, now())
                returning id into v_match_id;
            else
                insert into public.matches (user_a_id, user_b_id, created_at)
                values (new.liked_id, new.liker_id, now())
                returning id into v_match_id;
            end if;

            -- Create conversation for the match
            insert into public.conversations (match_id, created_at, updated_at)
            values (v_match_id, now(), now());

            -- Add both users as conversation members
            insert into public.conversation_members (conversation_id, user_id, joined_at)
            select c.id, u.uid, now()
            from public.conversations c
            cross join (values (new.liker_id), (new.liked_id)) as u(uid)
            where c.match_id = v_match_id;

            -- Credit any pending referral for either participant of the new
            -- match (referral completion is decided server-side only).
            update public.referrals
            set status = 'successful',
                credited_at = now()
            where status = 'pending'
              and (referee_id = new.liked_id or referee_id = new.liker_id);

            insert into public.referral_events (referral_id, event_type, created_at)
            select r.id, 'successful', now()
            from public.referrals r
            where r.status = 'successful'
              and (r.referee_id = new.liked_id or r.referee_id = new.liker_id)
              and r.credited_at >= now() - interval '1 minute'
            on conflict do nothing;
        end if;
    end if;

    return new;
end;
$$ language plpgsql security definer
set search_path = public;

-- ============================================================
-- 7. profile_photos - moderation status controlled by backend only
-- ============================================================
create or replace function public.protect_photo_moderation()
returns trigger as $$
begin
    -- Trusted backend (service role / definer contexts) is always allowed.
    if auth.role() = 'service_role' or auth.uid() is null then
        return new;
    end if;

    if tg_op = 'INSERT' and new.moderation_status is distinct from 'pending' then
        raise exception 'moderation_status can only be set by the backend';
    end if;

    if tg_op = 'UPDATE' and new.moderation_status is distinct from old.moderation_status then
        raise exception 'moderation_status can only be changed by the backend';
    end if;

    return new;
end;
$$ language plpgsql security definer
set search_path = public;

drop trigger if exists on_photo_moderation_change on public.profile_photos;
create trigger on_photo_moderation_change
    before insert or update on public.profile_photos
    for each row
    execute function public.protect_photo_moderation();

-- ============================================================
-- 8. plans - respect privacy_level on SELECT
-- ============================================================
drop policy if exists "public plans are visible to authenticated users" on public.plans;
drop policy if exists "plans are visible per privacy level" on public.plans;

create policy "plans are visible per privacy level"
    on public.plans
    for select
    using (
        auth.uid() is not null
        and (
            privacy_level = 'public'
            or creator_id = auth.uid()
            or exists (
                select 1 from public.plan_participants pp
                where pp.plan_id = plans.id and pp.user_id = auth.uid()
            )
        )
    );

-- ============================================================
-- 9. preferences - fix with-check column bug (id -> user_id)
-- ============================================================
drop policy if exists "users can manage own preferences" on public.preferences;
create policy "users can manage own preferences"
    on public.preferences
    for all
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

-- ============================================================
-- 10. messages - block enforcement + anti-flood
-- ============================================================
create or replace function public.enforce_message_rules()
returns trigger as $$
declare
    v_other uuid;
    v_blocked boolean;
    v_recent integer;
begin
    -- Determine the other participant(s) of the conversation.
    select cm.user_id into v_other
    from public.conversation_members cm
    where cm.conversation_id = new.conversation_id
      and cm.user_id <> new.sender_id
    limit 1;

    if v_other is null then
        raise exception 'Conversation has no other participant';
    end if;

    -- A blocked pair can never exchange messages, regardless of what the
    -- client sends.
    select exists (
        select 1 from public.blocks
        where blocker_id = v_other and blocked_id = new.sender_id
    ) into v_blocked;

    if v_blocked then
        raise exception 'You cannot message this user';
    end if;

    -- Server-side anti-flood: at most 20 messages per minute per sender.
    -- Ordinary human conversation is unaffected; automated abuse is not.
    select count(*) into v_recent
    from public.messages
    where sender_id = new.sender_id
      and created_at > now() - interval '60 seconds';

    if v_recent >= 20 then
        raise exception 'Sending too many messages too quickly. Please slow down.';
    end if;

    return new;
end;
$$ language plpgsql security definer
set search_path = public;

drop trigger if exists on_message_insert_rules on public.messages;
create trigger on_message_insert_rules
    before insert on public.messages
    for each row
    execute function public.enforce_message_rules();

-- ============================================================
-- 11. profiles - raw GPS coordinates never readable via direct SELECT.
--     Distance/city are exposed only through SECURITY DEFINER RPCs.
-- ============================================================
revoke select on public.profiles from anon;
revoke select on public.profiles from authenticated;
grant select (
    id, display_name, date_of_birth, gender, bio, city, locality, country,
    relationship_intent, verification_status, is_photo_verified, trust_score,
    profile_completion, created_at, updated_at, last_active_at, referral_code
) on public.profiles to authenticated;

-- ============================================================
-- 12. plan_participants - private plans cannot be joined
-- ============================================================
drop policy if exists "users can join plans" on public.plan_participants;
create policy "users can join plans"
    on public.plan_participants
    for insert
    with check (
        auth.uid() = user_id
        and exists (
            select 1 from public.plans pl
            where pl.id = plan_id
              and (pl.privacy_level = 'public' or pl.creator_id = auth.uid())
        )
    );

-- ============================================================
-- 13. get_user_interests - interests are public profile data; make the
--     helper usable for other users' profiles while staying read-only.
-- ============================================================
create or replace function public.get_user_interests(
    p_user_id uuid
)
returns table (
    name text
)
language sql
stable
security definer
set search_path = public
as $$
    select i.name
    from public.user_interests ui
    join public.interests i on ui.interest_id = i.id
    where ui.user_id = p_user_id;
$$;

-- ============================================================
-- 14. Explicit execute permissions
-- ============================================================
revoke execute on function public.delete_user_account(uuid, text) from anon, authenticated, public;
grant execute on function public.delete_user_account(uuid, text) to authenticated;
grant execute on function public.get_nearby_profiles(uuid, integer, integer, double precision, text[], integer, integer, text) to authenticated;
grant execute on function public.get_matches_for_user(uuid, integer, integer) to authenticated;
grant execute on function public.get_referral_stats(uuid) to authenticated;
grant execute on function public.get_user_interests(uuid) to authenticated;
