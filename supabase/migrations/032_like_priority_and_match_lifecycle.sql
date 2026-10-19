-- ============================================================
-- 032 - Like priority/notes and the match lifecycle
-- ============================================================
--
-- Features landed: Priority Likes, Notes/Compliments attached to likes,
-- Openers (conversation-opening prompts), match initiation windows
-- (expiration + Extend + Rematch) and the women-led initiation rule for
-- heterosexual Date connections.
--
-- Design decisions (each enforced SERVER-SIDE; clients cannot bypass):
--   * priority_weight is computed inside record_like from the sender's
--     server-side entitlement - never taken from the client.
--   * A like note is optional text (<= 140 chars) validated with the same
--     social-handle policy as profile bios; attached to the LIKE (pre-match).
--   * Every NEW match gets a 24-hour initiation window (matches.expires_at)
--     plus an initiator (matches.initiator_id). Legacy matches keep
--     expires_at = null = no window = exactly today's behaviour.
--   * Women-led rule: only when BOTH participants self-report binary
--     genders ('Man'/'Woman') and they differ, the woman is the initiator
--     and must send the first message (normal text or an Opening Move)
--     within the window. In every other configuration there is no
--     initiator and either side can open. Gender is read from the
--     profiles.gender column the users THEMSELVES maintain; never inferred
--     from names, photos or any other data.
--   * Once the conversation has its first message the window is cleared:
--     the match can never silently "expire" again after it started.
--   * Extend: each participant may extend the live window once (+24h).
--   * Rematch: after expiry (and no messages), a fresh mutual like reopens
--     the match with a new window; at most one rematch per 7 days.
--   * Blocked users can never be revived - block checks precede every open,
--     relieve and extend path.
-- ============================================================

-- ============================================================
-- 1. LIKES: priority weight + note
-- ============================================================
alter table public.likes
    add column if not exists priority_weight smallint not null default 1;
alter table public.likes
    add column if not exists note text;
alter table public.likes
    add constraint likes_note_length
    check (note is null or length(btrim(note)) between 1 and 140);
alter table public.likes
    add constraint likes_priority_weight_range
    check (priority_weight in (1, 2, 3));

-- ============================================================
-- 2. record_like - note + server-computed priority + same guarantees
-- ============================================================
-- 028's version, extended additively. Both adult guard, both block guard,
-- target-existence guard and pass withdrawal are preserved verbatim.
drop function if exists public.record_like(uuid, boolean);

create or replace function public.record_like(
    p_target_id uuid,
    p_is_stand_out boolean default false,
    p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    v_me uuid := auth.uid();
    v_match_id uuid;
    v_conversation_id uuid;
    v_blocked boolean;
    v_weight smallint := 1;
    v_note text;
begin
    if v_me is null then
        raise exception 'Not authenticated';
    end if;

    if p_target_id is null or p_target_id = v_me then
        raise exception 'Invalid target';
    end if;

    -- Both parties must be proven adults.
    if not public.is_adult_user(v_me)
       or not public.is_adult_user(p_target_id) then
        raise exception 'Only verified adults can use Weekend matching.'
            using errcode = 'check_violation';
    end if;

    select exists (
        select 1 from public.blocks b
        where (b.blocker_id = v_me and b.blocked_id = p_target_id)
           or (b.blocker_id = p_target_id and b.blocked_id = v_me)
    ) into v_blocked;

    if v_blocked then
        raise exception 'You cannot like this user';
    end if;

    if exists (
        select 1 from public.auth_user_state s
        where s.user_id = p_target_id and s.deleted_at is not null
    ) then
        raise exception 'Profile unavailable';
    end if;

    -- Note validation BEFORE any write (a note never originates from the
    -- client unvalidated).
    if p_note is not null and length(btrim(p_note)) > 0 then
        v_note := btrim(p_note);
        if length(v_note) > 140 then
            raise exception 'Note too long';
        end if;
        if (public.detect_social_media_in_text(v_note)->>'detected')::boolean then
            raise exception 'Note contains external social media identifiers';
        end if;
    end if;

    -- Priority Likes: the weight is server-computed. Never receives a
    -- client-supplied weight argument, so it cannot be fabricated.
    if public.has_feature_entitlement(v_me, 'priority_likes') then
        if p_is_stand_out then
            v_weight := 3;
        else
            v_weight := 2;
        end if;
    end if;

    delete from public.passes where user_id = v_me and target_id = p_target_id;

    insert into public.likes (liker_id, liked_id, is_stand_out,
                              priority_weight, note)
    values (v_me, p_target_id, p_is_stand_out, v_weight, v_note)
    on conflict (liker_id, liked_id) do update
        set is_stand_out = public.likes.is_stand_out or excluded.is_stand_out,
            priority_weight = excluded.priority_weight,
            note = coalesce(excluded.note, public.likes.note);

    select m.id into v_match_id
    from public.matches m
    where (m.user_a_id, m.user_b_id) in (
        (least(v_me, p_target_id), greatest(v_me, p_target_id))
    )
    limit 1;

    if v_match_id is not null then
        select c.id into v_conversation_id
        from public.conversations c
        where c.match_id = v_match_id
        limit 1;
    end if;

    return jsonb_build_object(
        'liked', true,
        'is_stand_out', p_is_stand_out,
        'priority_weight', v_weight,
        'matched', v_match_id is not null,
        'match_id', v_match_id,
        'conversation_id', v_conversation_id
    );
end;
$$;

revoke all on function public.record_like(uuid, boolean, text)
    from public, anon;
grant execute on function public.record_like(uuid, boolean, text)
    to authenticated;

-- ============================================================
-- 3. check_mutual_like - windows, initiator, rematch
-- ============================================================
-- 028's version extended: new matches get an initiator + 24h window; an
-- expired, never-started match is reopened as a rematch. Everything else
-- (adult floor, conversation creation, referral crediting) is unchanged.
create or replace function public.check_mutual_like()
returns trigger as $$
declare
    existing_like record;
    existing_match record;
    match_id uuid;
    v_a_gender text;
    v_b_gender text;
    v_initiator uuid;
begin
    if not (public.is_adult_user(new.liker_id)
            and public.is_adult_user(new.liked_id)) then
        raise exception 'Only verified adults can match on Weekend.'
            using errcode = 'check_violation';
    end if;

    select * into existing_like
    from public.likes
    where liker_id = new.liked_id and liked_id = new.liker_id;

    if existing_like.id is not null then
        select * into existing_match
        from public.matches
        where (user_a_id = new.liker_id and user_b_id = new.liked_id)
           or (user_a_id = new.liked_id and user_b_id = new.liker_id);

        if existing_match.id is not null then
            -- REMATCH: reopen a window ONLY when the previous one expired
            -- (or never existed) with zero messages, and never twice in
            -- 7 days. The existing conversation (if any) is preserved so no
            -- history is lost by a re-open.
            select mm.id into match_id
            from public.matches mm
            where mm.id = existing_match.id
              and (mm.expires_at is null or mm.expires_at <= now())
              and not exists (
                  select 1 from public.conversations cs
                  join public.messages msg on msg.conversation_id = cs.id
                  where cs.match_id = mm.id
              )
              and (mm.rematched_at is null
                   or mm.rematched_at < now() - interval '7 days')
            limit 1;

            if match_id is not null then
                -- recompute the initiation rule at reopen time
                select pr.gender into v_a_gender
                from public.profiles pr
                where pr.id = least(new.liker_id, new.liked_id);
                select pr.gender into v_b_gender
                from public.profiles pr
                where pr.id = greatest(new.liker_id, new.liked_id);

                v_initiator := case
                    when v_a_gender in ('Man', 'Woman')
                     and v_b_gender in ('Man', 'Woman')
                     and v_a_gender <> v_b_gender
                    then (case when v_a_gender = 'Woman'
                               then least(new.liker_id, new.liked_id)
                               else greatest(new.liker_id, new.liked_id)
                          end)
                    else null
                end;

                update public.matches
                   set expires_at = now() + interval '24 hours',
                       initiator_id = v_initiator,
                       extended_a_by = false,
                       extended_b_by = false,
                       rematch_count = rematch_count + 1,
                       rematched_at = now(),
                       window_opened_at = now()
                 where id = match_id;
            end if;

        else
            -- New match: order the pair, compute the initiator, open the
            -- 24-hour initiation window and create the conversation.
            if new.liker_id < new.liked_id then
                match_id := gen_random_uuid();
                insert into public.matches (id, user_a_id, user_b_id, created_at)
                values (match_id, new.liker_id, new.liked_id, now());
            else
                match_id := gen_random_uuid();
                insert into public.matches (id, user_a_id, user_b_id, created_at)
                values (match_id, new.liked_id, new.liker_id, now());
            end if;

            select pr.gender into v_a_gender
            from public.profiles pr
            where pr.id = least(new.liker_id, new.liked_id);
            select pr.gender into v_b_gender
            from public.profiles pr
            where pr.id = greatest(new.liker_id, new.liked_id);

            v_initiator := case
                when v_a_gender in ('Man', 'Woman')
                 and v_b_gender in ('Man', 'Woman')
                 and v_a_gender <> v_b_gender
                then (case when v_a_gender = 'Woman'
                           then least(new.liker_id, new.liked_id)
                           else greatest(new.liker_id, new.liked_id)
                      end)
                else null
            end;

            update public.matches
               set initiator_id = v_initiator,
                   expires_at = now() + interval '24 hours',
                   window_opened_at = now()
             where id = match_id;

            insert into public.conversations (id, match_id, created_at, updated_at)
            values (gen_random_uuid(), match_id, now(), now())
            returning id into match_id;

            insert into public.conversation_members (conversation_id, user_id, joined_at)
            values (match_id, new.liker_id, now());
            insert into public.conversation_members (conversation_id, user_id, joined_at)
            values (match_id, new.liked_id, now());

            insert into public.referral_events (referral_id, event_type, created_at)
            select r.id, 'successful', now()
            from public.referrals r
            where r.referee_id = new.liked_id
              and r.status = 'pending'
            on conflict do nothing;

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

alter function public.check_mutual_like() set search_path = public, pg_temp;

-- ============================================================
-- 4. MATCHES: window columns
-- ============================================================
alter table public.matches
    add column if not exists expires_at timestamptz;
alter table public.matches
    add column if not exists initiator_id uuid references public.profiles on delete set null;
alter table public.matches
    add column if not exists extended_a_by boolean not null default false;
alter table public.matches
    add column if not exists extended_b_by boolean not null default false;
alter table public.matches
    add column if not exists rematch_count smallint not null default 0;
alter table public.matches
    add column if not exists rematched_at timestamptz;
alter table public.matches
    add column if not exists window_opened_at timestamptz;
alter table public.matches
    add constraint matches_window_sanity
    check (expires_at is null or window_opened_at is null
           or expires_at > window_opened_at);
create index if not exists idx_matches_expires
    on public.matches(expires_at);

-- ============================================================
-- 5. enforce_message_rules - initiation + expiry enforcement
-- ============================================================
-- 026's version extended. Blocking symmetric guard, member-of-conversation
-- guard and the 20 msgs/minute cap are preserved verbatim. New:
--   * the conversation's first message must come from matches.initiator_id
--     when one is set (women-led rule / assisted initiation);
--   * no new message may be sent while a deadline has passed without any
--     prior message (the window expired).
create or replace function public.enforce_message_rules()
returns trigger as $$
declare
    v_other uuid;
    v_blocked boolean;
    v_recent integer;
    v_match public.matches%rowtype;
    v_has_messages boolean;
begin
    -- The recipient of this message.
    select cm.user_id into v_other
    from public.conversation_members cm
    where cm.conversation_id = new.conversation_id
      and cm.user_id is distinct from new.sender_id
    limit 1;

    if v_other is null then
        raise exception 'Not a member of this conversation';
    end if;

    -- Blocking is symmetric: EITHER side having blocked the pair stops all
    -- new messages in both directions.
    select exists (
        select 1
        from public.blocks b
        where (b.blocker_id = new.sender_id and b.blocked_id = v_other)
           or (b.blocker_id = v_other and b.blocked_id = new.sender_id)
    ) into v_blocked;

    if v_blocked then
        raise exception 'You cannot message this user';
    end if;

    -- Conversation was created from a match; obtain it for initiation rules.
    select m.* into v_match
    from public.conversations cs
    join public.matches m on m.id = cs.match_id
    where cs.id = new.conversation_id;

    if v_match.id is not null then
        select exists (
            select 1 from public.messages m2
            where m2.conversation_id = new.conversation_id
        ) into v_has_messages;

        if not v_has_messages then
            -- The window expired without anyone opening - no message may
            -- revive it silently. Rematching is the documented path.
            if v_match.expires_at is not null
               and v_match.expires_at <= now() then
                raise exception 'Match window expired';
            end if;

            -- Women-led initiation: the initiator sends the first message.
            if v_match.initiator_id is not null
               and new.sender_id <> v_match.initiator_id then
                raise exception 'Waiting for their opening message';
            end if;
        end if;
    end if;

    -- Existing 20 messages/minute cap, unchanged.
    select count(*) into v_recent
    from public.messages m
    where m.sender_id = new.sender_id
      and m.created_at > now() - interval '1 minute';

    if v_recent >= 20 then
        raise exception 'Message rate limit exceeded';
    end if;

    return new;
end;
$$ language plpgsql security definer
set search_path = public, pg_temp;

drop trigger if exists on_message_insert_rules on public.messages;
create trigger on_message_insert_rules
    before insert on public.messages
    for each row
    execute function public.enforce_message_rules();

-- The window only governs INITIATION. First message clears it so the match
-- can never "expire" retroactively after it began.
create or replace function public.settle_first_message_window()
returns trigger as $$
begin
    update public.matches m
       set expires_at = null,
           window_opened_at = null
    from public.conversations cs
    where cs.id = new.conversation_id
      and cs.match_id = m.id
      and m.window_opened_at is not null;
    return new;
end;
$$ language plpgsql
set search_path = public, pg_temp;

drop trigger if exists on_message_first_settles_window on public.messages;
create trigger on_message_first_settles_window
    after insert on public.messages
    for each row
    execute function public.settle_first_message_window();

-- ============================================================
-- 6. extend_match
-- ============================================================
create or replace function public.extend_match(p_match_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    v_me uuid := auth.uid();
    v_row public.matches%rowtype;
    v_is_a boolean;
    v_conversation_id uuid;
    v_has_messages boolean;
begin
    if v_me is null then
        raise exception 'Not authenticated';
    end if;
    if p_match_id is null then
        raise exception 'Invalid match';
    end if;

    select * into v_row
    from public.matches
    where id = p_match_id
      and (user_a_id = v_me or user_b_id = v_me);

    if v_row.id is null then
        raise exception 'Match not found';
    end if;

    -- A block between the pair ends every window activity.
    if exists (
        select 1 from public.blocks b
        where (b.blocker_id = v_row.user_a_id and b.blocked_id = v_row.user_b_id)
           or (b.blocker_id = v_row.user_b_id and b.blocked_id = v_row.user_a_id)
    ) then
        raise exception 'You cannot extend this match';
    end if;

    select c.id into v_conversation_id
    from public.conversations c
    where c.match_id = v_row.id
    limit 1;

    select exists (
        select 1 from public.messages m
        where m.conversation_id = v_conversation_id
    ) into v_has_messages;

    if v_has_messages then
        raise exception 'Match already started';
    end if;

    if v_row.expires_at is not null and v_row.expires_at <= now() then
        raise exception 'Window already expired';
    end if;

    v_is_a := (v_row.user_a_id = v_me);

    -- One extension per participant per window. The conditional UPDATE makes
    -- two identical concurrent requests idempotent: only one succeeds.
    if v_is_a then
        update public.matches m
           set expires_at = greatest(coalesce(m.expires_at, now() + interval '24 hours'),
                                     now() + interval '24 hours'),
               extended_a_by = true
         where m.id = v_row.id
           and m.extended_a_by = false
           and m.user_a_id = v_me;
        if not found then
            raise exception 'Already extended';
        end if;
    else
        update public.matches m
           set expires_at = greatest(coalesce(m.expires_at, now() + interval '24 hours'),
                                     now() + interval '24 hours'),
               extended_b_by = true
         where m.id = v_row.id
           and m.extended_b_by = false
           and m.user_b_id = v_me;
        if not found then
            raise exception 'Already extended';
        end if;
    end if;

    -- report the renewed deadline
    select m.expires_at into v_row.expires_at from public.matches m where m.id = v_row.id;
    return jsonb_build_object(
        'extended', true,
        'expires_at', v_row.expires_at
    );
end;
$$;

revoke all on function public.extend_match(uuid) from public, anon;
grant execute on function public.extend_match(uuid) to authenticated;

-- ============================================================
-- 7. get_matches_for_user - window/away/conversation surface
-- ============================================================
-- Same signature as 026. New OUTPUT columns only:
--   conversation_id (needed by the extend UI), initiation_status,
--   window_ends_at, away_message.
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
    relationship_intent text,
    primary_photo_path text,
    interests text[],
    shared_interests text[],
    matched_at timestamptz,
    last_message_text text,
    last_message_time timestamptz,
    unread_count integer,
    distance_km double precision,
    is_photo_verified boolean,
    trust_score integer,
    conversation_id uuid,
    initiation_status text,
    window_ends_at timestamptz,
    away_message text
)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
    perform public.assert_self(p_user_id);
    p_limit := least(coalesce(p_limit, 50), 100);
    p_offset := greatest(coalesce(p_offset, 0), 0);

    return query
    with mine as (
        select l.interest_id
        from public.user_interests l
        where l.user_id = p_user_id
    ),
    located as (
        select
            m.id                       as match_id,
            m.created_at               as matched_at,
            m.expires_at               as window_ends_at,
            m.initiator_id             as match_initiator_id,
            p.id                       as other_user_id,
            p.display_name,
            case when p.date_of_birth is not null
                 then date_part('years', age(p.date_of_birth))::int
                 else null end         as age,
            p.gender,
            p.bio,
            p.city,
            p.relationship_intent,
            p.is_photo_verified,
            p.trust_score,
            p.latitude,
            p.longitude,
            -- The link runs matches -> conversations via conversations.match_id.
            c.id                       as conversation_id
        from public.matches m
        join public.profiles p
          on p.id = case when m.user_a_id = p_user_id
                         then m.user_b_id else m.user_a_id end
        left join public.conversations c on c.match_id = m.id
        where (m.user_a_id = p_user_id or m.user_b_id = p_user_id)
          -- Blocking hides a match even when the unwind trigger has not yet
          -- run (e.g. the block predates this migration).
          and not exists (
              select 1 from public.blocks b
              where (b.blocker_id = p_user_id and b.blocked_id = p.id)
                 or (b.blocker_id = p.id and b.blocked_id = p_user_id)
          )
          and not exists (
              select 1 from public.auth_user_state s
              where s.user_id = p.id and s.deleted_at is not null
          )
    ),
    enriched as (
        select
            l.*,
            (select pp.storage_path
               from public.profile_photos pp
              where pp.user_id = l.other_user_id
                and pp.moderation_status = 'approved'
              order by pp.is_primary desc, pp.sort_order asc, pp.created_at asc
              limit 1) as primary_photo_path,
            (select m2.text
               from public.messages m2
              where m2.conversation_id = l.conversation_id
              order by m2.created_at desc
              limit 1) as last_message_text,
            (select m2.created_at
               from public.messages m2
              where m2.conversation_id = l.conversation_id
              order by m2.created_at desc
              limit 1) as last_message_time,
            coalesce((
                select cm.unread_count
                  from public.conversation_members cm
                 where cm.conversation_id = l.conversation_id
                   and cm.user_id = p_user_id
            ), 0) as unread_count,
            coalesce((
                select array_agg(i.name order by i.name)
                  from public.user_interests ui
                  join public.interests i on i.id = ui.interest_id
                 where ui.user_id = l.other_user_id
            ), '{}'::text[]) as interests,
            coalesce((
                select array_agg(i.name order by i.name)
                  from public.user_interests ui
                  join public.interests i on i.id = ui.interest_id
                 where ui.user_id = l.other_user_id
                   and ui.interest_id in (select interest_id from mine)
            ), '{}'::text[]) as shared_interests,
            -- Distance is derived server-side from approximate coordinates
            -- the client itself persisted. No precise location is exposed.
            case
                when l.latitude is null or l.longitude is null
                  or (select mp.latitude from public.profiles mp where mp.id = p_user_id) is null
                then null
                else st_distance(
                    st_point(l.longitude, l.latitude)::geography,
                    st_point(
                        (select mp.longitude from public.profiles mp where mp.id = p_user_id),
                        (select mp.latitude from public.profiles mp where mp.id = p_user_id)
                    )::geography
                ) / 1000.0
            end as distance_km,
            -- initiation status is computed per caller with server data only
            case
                when l.conversation_id is not null and exists (
                        select 1 from public.messages m3
                        where m3.conversation_id = l.conversation_id)
                    then 'active'
                when l.window_ends_at is null
                    then 'no_window'
                when l.window_ends_at <= now()
                    then 'expired'
                -- initiator_id is the member expected to send the first
                -- message (women-led rule, see enforce_message_rules), so
                -- initiator == other member means the turn is mine.
                when l.match_initiator_id is not null
                 and l.match_initiator_id = l.other_user_id
                    then 'awaiting_you'
                when l.match_initiator_id is not null
                    then 'awaiting_them'
                else 'active'
            end as initiation_status,
            -- Away status of the other member: only to connections, only
            -- while their own window is active.
            case
                when us.away_status is not null
                 and (us.away_until is null or us.away_until > now())
                then us.away_status
                else null
            end as away_message
        from located l
        left join public.user_settings us on us.user_id = l.other_user_id
    )
    select
        e.match_id,
        e.other_user_id,
        e.display_name,
        e.age,
        e.gender,
        e.bio,
        e.city,
        e.relationship_intent,
        e.primary_photo_path,
        e.interests,
        e.shared_interests,
        e.matched_at,
        e.last_message_text,
        e.last_message_time,
        e.unread_count,
        e.distance_km,
        e.is_photo_verified,
        e.trust_score,
        e.conversation_id,
        e.initiation_status,
        e.window_ends_at,
        e.away_message
    from enriched e
    order by coalesce(e.last_message_time, e.matched_at) desc
    limit p_limit offset p_offset;
end;
$$;

revoke all on function public.get_matches_for_user(uuid, integer, integer)
    from public, anon;
grant execute on function public.get_matches_for_user(uuid, integer, integer)
    to authenticated;

-- ============================================================
-- 8. get_received_likes - priority ordering + note
-- ============================================================
-- Same two parameters. Notes attach to the LIKE (pre-match, like the
-- compliment feature); ordering is stand-out > priority weight > newest.
--
-- The 026 version returned a DIFFERENT OUT row type (13 columns, no note /
-- priority_weight), and Postgres refuses CREATE OR REPLACE across a row-type
-- change, so the previous overload is dropped first (same pattern as
-- get_matches_for_user directly above).
drop function if exists public.get_received_likes(integer, integer);

create or replace function public.get_received_likes(
    p_limit integer default 50,
    p_offset integer default 0
)
returns table (
    like_id uuid,
    other_user_id uuid,
    display_name text,
    age integer,
    gender text,
    bio text,
    city text,
    relationship_intent text,
    primary_photo_path text,
    is_stand_out boolean,
    liked_at timestamptz,
    is_photo_verified boolean,
    trust_score integer,
    note text,
    priority_weight smallint
)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    v_me uuid := auth.uid();
begin
    if v_me is null then
        raise exception 'Not authenticated';
    end if;

    p_limit := least(coalesce(p_limit, 50), 100);
    p_offset := greatest(coalesce(p_offset, 0), 0);

    return query
    select
        l.id,
        p.id,
        p.display_name,
        case when p.date_of_birth is not null
             then date_part('years', age(p.date_of_birth))::int
             else null end,
        p.gender,
        p.bio,
        p.city,
        p.relationship_intent,
        (select pp.storage_path
           from public.profile_photos pp
          where pp.user_id = p.id
            and pp.moderation_status = 'approved'
          order by pp.is_primary desc, pp.sort_order asc, pp.created_at asc
          limit 1),
        l.is_stand_out,
        l.created_at,
        p.is_photo_verified,
        p.trust_score,
        l.note,
        l.priority_weight
    from public.likes l
    join public.profiles p on p.id = l.liker_id
    where l.liked_id = v_me
      -- Mutual likes are matches, not received likes.
      and not exists (
          select 1 from public.matches m
          where (m.user_a_id, m.user_b_id) in (
              (least(v_me, p.id), greatest(v_me, p.id))
          )
      )
      -- A pass means you declined and it should not resurface.
      and not exists (
          select 1 from public.passes ps
          where ps.user_id = v_me and ps.target_id = p.id
      )
      and not exists (
          select 1 from public.blocks b
          where (b.blocker_id = v_me and b.blocked_id = p.id)
             or (b.blocker_id = p.id and b.blocked_id = v_me)
      )
      and not exists (
          select 1 from public.auth_user_state s
          where s.user_id = p.id and s.deleted_at is not null
      )
    order by l.is_stand_out desc,
             l.priority_weight desc,
             l.created_at desc
    limit p_limit offset p_offset;
end;
$$;

revoke all on function public.get_received_likes(integer, integer)
    from public, anon;
grant execute on function public.get_received_likes(integer, integer)
    to authenticated;

-- ============================================================
-- 9. OPENING MOVES
-- ============================================================
-- Up to three conversation-opening prompts per user. A prompt may reference
-- one of the user's OWN approved photos (prompt-based opener).
create table if not exists public.opening_moves (
    id uuid primary key default uuid_generate_v4(),
    user_id uuid not null references public.profiles on delete cascade,
    sort_order smallint not null check (sort_order between 1 and 3),
    prompt text not null check (length(btrim(prompt)) between 1 and 160),
    photo_id uuid references public.profile_photos on delete set null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique (user_id, sort_order)
);
alter table public.opening_moves enable row level security;

drop policy if exists opening_moves_select_own on public.opening_moves;
create policy opening_moves_select_own on public.opening_moves
    for select to authenticated
    using (user_id = auth.uid());

drop policy if exists opening_moves_insert_own on public.opening_moves;
create policy opening_moves_insert_own on public.opening_moves
    for insert to authenticated
    with check (user_id = auth.uid());

drop policy if exists opening_moves_update_own on public.opening_moves;
create policy opening_moves_update_own on public.opening_moves
    for update to authenticated
    using (user_id = auth.uid())
    with check (user_id = auth.uid());

drop policy if exists opening_moves_delete_own on public.opening_moves;
create policy opening_moves_delete_own on public.opening_moves
    for delete to authenticated
    using (user_id = auth.uid());

-- Validate the referenced photo belongs to the same user and is approved.
create or replace function public.validate_opening_move()
returns trigger as $$
declare
    v_detected boolean;
begin
    new.prompt := btrim(new.prompt);

    if (public.detect_social_media_in_text(new.prompt)->>'detected')::boolean then
        raise exception 'Opening Move contains external social media identifiers';
    end if;

    -- Duplicate prompts in the same slot map are not allowed.
    if exists (
        select 1 from public.opening_moves om
        where om.user_id = new.user_id
          and om.id is distinct from new.id
          and om.sort_order = new.sort_order
    ) then
        -- unique (user_id, sort_order) also enforces this; keep a friendly error
        raise exception 'A prompt already exists in that slot'
            using errcode = 'unique_violation';
    end if;

    if new.photo_id is not null then
        if not exists (
            select 1 from public.profile_photos pp
            where pp.id = new.photo_id
              and pp.user_id = new.user_id
              and pp.moderation_status = 'approved'
        ) then
            raise exception 'Photo does not belong to you or is not approved';
        end if;
    end if;

    return new;
end;
$$ language plpgsql
set search_path = public, pg_temp;

drop trigger if exists on_opening_move_validate on public.opening_moves;
create trigger on_opening_move_validate
    before insert or update on public.opening_moves
    for each row
    execute function public.validate_opening_move();

revoke all on public.opening_moves from anon, public;
grant select, insert, update, delete on public.opening_moves to authenticated;
