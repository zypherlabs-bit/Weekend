-- Migration: 003_database_functions.sql
-- Triggers, functions for matching, discovery, and profile maintenance

-- ============================================================
-- TRIGGERS: Update timestamps
-- ============================================================
create or replace function public.update_updated_at()
returns trigger as $$
begin
    new.updated_at = now();
    return new;
end;
$$ language plpgsql;

create trigger profiles_updated_at
    before update on public.profiles
    for each row
    execute function public.update_updated_at();

create trigger plans_updated_at
    before update on public.plans
    for each row
    execute function public.update_updated_at();

create trigger preferences_updated_at
    before update on public.preferences
    for each row
    execute function public.update_updated_at();

create trigger user_settings_updated_at
    before update on public.user_settings
    for each row
    execute function public.update_updated_at();

create trigger referrals_updated_at
    before update on public.referrals
    for each row
    execute function public.update_updated_at();

-- ============================================================
-- TRIGGER: Auto-create profile on auth.users insert
-- ============================================================
create or replace function public.handle_new_user()
returns trigger as $$
begin
    insert into public.profiles (
        id,
        display_name,
        created_at,
        updated_at,
        last_active_at
    ) values (
        new.id,
        new.raw_user_meta_data->>'full_name',
        now(),
        now(),
        now()
    );

    insert into public.user_settings (user_id) values (new.id);
    insert into public.preferences (user_id) values (new.id);

    return new;
end;
$$ language plpgsql security definer;

create trigger on_auth_user_created
    after insert on auth.users
    for each row
    execute function public.handle_new_user();

-- ============================================================
-- TRIGGER: Create match when mutual like occurs
-- ============================================================
create or replace function public.check_mutual_like()
returns trigger as $$
declare
    existing_like record;
    existing_match record;
    match_id uuid;
begin
    -- Check if the liked user also liked the liker (mutual)
    select * into existing_like
    from public.likes
    where liker_id = new.liked_id and liked_id = new.liker_id;

    if existing_like.id is not null then
        -- Check if match already exists
        select * into existing_match
        from public.matches
        where (user_a_id = new.liker_id and user_b_id = new.liked_id)
           or (user_a_id = new.liked_id and user_b_id = new.liker_id);

        if existing_match.id is null then
            -- Create match with user_a_id as the smaller UUID
            if new.liker_id < new.liked_id then
                match_id := gen_random_uuid();
                insert into public.matches (id, user_a_id, user_b_id, created_at)
                values (match_id, new.liker_id, new.liked_id, now());
            else
                match_id := gen_random_uuid();
                insert into public.matches (id, user_a_id, user_b_id, created_at)
                values (match_id, new.liked_id, new.liker_id, now());
            end if;

            -- Create conversation for the match
            insert into public.conversations (id, match_id, created_at, updated_at)
            values (gen_random_uuid(), match_id, now(), now())
            returning id into match_id;

            -- Add both users as conversation members
            insert into public.conversation_members (conversation_id, user_id, joined_at)
            values (match_id, new.liker_id, now());
            insert into public.conversation_members (conversation_id, user_id, joined_at)
            values (match_id, new.liked_id, now());

            -- Check for referral credit
            insert into public.referral_events (referral_id, event_type, created_at)
            select r.id, 'successful', now()
            from public.referrals r
            where r.referree_id = new.liked_id
              and r.status = 'pending'
            on conflict do nothing;

            -- Update referral to successful
            update public.referrals
            set status = 'successful',
                credited_at = now()
            where referee_id = new.liked_id
              and status = 'pending';
        end if;
    end if;

    return new;
end;
$$ language plpgsql security definer;

create trigger on_like_insert
    after insert on public.likes
    for each row
    execute function public.check_mutual_like();

-- ============================================================
-- TRIGGER: Update last_active_at on user activity
-- ============================================================
create or replace function public.update_last_active()
returns trigger as $$
begin
    update public.profiles
    set last_active_at = now()
    where id = auth.uid();
    return new;
end;
$$ language plpgsql security definer;

-- ============================================================
-- TRIGGER: Clean up user data on account deletion
-- ============================================================
create or replace function public.handle_user_deletion()
returns trigger as $$
begin
    -- The cascade on foreign keys handles most cleanup
    -- This is for additional cleanup if needed
    delete from public.crossed_paths
    where user_a_id = old.id or user_b_id = old.id;

    delete from public.verification_requests
    where user_id = old.id;

    delete from public.moderation_events
    where user_id = old.id;

    return old;
end;
$$ language plpgsql security definer;

create trigger on_user_delete
    before delete on auth.users
    for each row
    execute function public.handle_user_deletion();

-- ============================================================
-- DISCOVERY RPC: get_nearby_profiles
-- Returns profiles near the current user, excluding blocked,
-- already-liked, already-passed, and respecting preferences
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
as $$
begin
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
        -- Compatibility score based on distance, activity, interests, verification
        (
            (p.trust_score * 0.3)
            + (least(distance_km::numeric, 50) / 50 * 20)
            + (case when p.is_photo_verified then 15 else 0 end)
            + (case when p.last_active_at > now() - interval '7 days' then 20 else 0 end)
        ) as compatibility_score
    from public.profiles p
    where p.id <> p_user_id
      -- Distance filter
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
      -- Age filter
      and (p.date_of_birth is null
           or date_part('years', age(p.date_of_birth)) between p_age_min and p_age_max)
      -- Gender filter
      and (p_preferred_genders is null or array_length(p_preferred_genders, 1) = 0 or p.gender = any(p_preferred_genders))
      -- Exclude blocked users
      and not exists (select 1 from public.blocks where blocker_id = p_user_id and blocked_id = p.id)
      and not exists (select 1 from public.blocks where blocker_id = p.id and blocked_id = p_user_id)
      -- Exclude already liked (passed) users
      and not exists (select 1 from public.passes where user_id = p_user_id and target_id = p.id)
      and not exists (select 1 from public.likes where liker_id = p_user_id and liked_id = p.id)
      -- Exclude already matched users
      and not exists (
          select 1 from public.matches
          where (user_a_id = p_user_id and user_b_id = p.id)
             or (user_a_id = p.id and user_b_id = p_user_id)
      )
      -- Exclude reported users
      and not exists (select 1 from public.reports where reporter_id = p_user_id and reported_id = p.id)
    order by distance_km asc nulls last,
             compatibility_score desc,
             p.last_active_at desc
    limit p_limit offset p_offset;
end;
$$;

-- ============================================================
-- DISCOVERY RPC: get_matches_for_user
-- Returns all matches for the current user with last message preview
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
as $$
begin
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
-- DISCOVERY RPC: get_referral_stats
-- Returns referral statistics for a user
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
as $$
declare
    v_code text;
begin
    select referral_code into v_code
    from public.referrals
    where referrer_id = p_user_id
    order by created_at desc
    limit 1;

    if v_code is null then
        v_code := 'WEEKEND-' || upper(substr(p_user_id::text, 1, 4));
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
        'https://weekend.app/invite/' || v_code as link_url
    from public.referrals
    where referrer_id = p_user_id;
end;
$$;

-- ============================================================
-- UTILITY FUNCTION: delete_user_account
-- Secure server-side account deletion
-- ============================================================
create or replace function public.delete_user_account(
    p_user_id uuid,
    p_reason text default 'user_request'
)
returns jsonb
language plpgsql
security definer
as $$
declare
    v_result jsonb;
begin
    -- Log the deletion request
    insert into public.moderation_events (user_id, action, reason, performed_by, created_at)
    values (p_user_id, 'delete', p_reason, p_user_id, now());

    -- Delete referral relationships where this user is the referrer
    delete from public.referrals where referrer_id = p_user_id;

    -- Delete referral relationships where this user is the referee
    delete from public.referrals where referee_id = p_user_id;

    -- Delete verification requests
    delete from public.verification_requests where user_id = p_user_id;

    -- Delete plans created by this user
    delete from public.plans where creator_id = p_user_id;

    -- The profile, photos, matches, messages, blocks, reports, etc.
    -- will be cascade-deleted via foreign key constraints

    v_result := jsonb_build_object(
        'success', true,
        'user_id', p_user_id,
        'reason', p_reason,
        'deleted_at', now()
    );

    return v_result;
end;
$$;
