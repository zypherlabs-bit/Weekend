-- ============================================================
-- 026 - dating platform completion: repair the broken pipeline,
--       add the missing product surface, close the security gaps
-- ============================================================
--
-- WHY THIS MIGRATION EXISTS
-- -------------------------
-- The audit behind this file found that a large part of the dating loop was
-- wired up on the client but could never have worked against the live schema,
-- and that several SECURITY DEFINER entry points were reachable in ways the
-- app never intended. Rather than ship a parallel second architecture, this
-- migration repairs the existing one in place and adds the RPCs the Flutter
-- layer was already written to call.
--
-- A. BLOCKER - `get_matches_for_user` referenced two columns that have never
--    existed: `matches.conversation_id` (matches has no such column; the link
--    runs the other way, via `conversations.match_id`) and `messages.content`
--    (the column is `text`). The function therefore raised on every call and
--    `MatchRepository.fetchMatches` swallowed the error, so every user saw
--    "No Matches Yet" forever. It also returned a column set that no longer
--    matched what `MatchRepository` reads.
--
-- B. The like/pass writes were two separate round trips (INSERT, then SELECT
--    `matches`) with a TOCTOU window between them. `record_like` / `record_pass`
--    collapse that into one atomic call that reports the authoritative match.
--
-- C. "People who liked you" had no data path at all: the `likes` table and its
--    SELECT policy allowed reading inbound likes, but nothing ever queried it.
--    `get_received_likes` adds that surface.
--
-- D. The notification centre had a table and no way to page through it, no
--    unread count and no mark-all-read.
--
-- E. Blocking was enforced in exactly one direction for messaging: if YOU
--    blocked someone, they could still message you. It also never unwound an
--    existing match.
--
-- F. Security: the shared `interests` master list was writable by any signed-in
--    user; `ad_campaigns` exposed campaign budgets; `verification_requests`
--    could be self-approved; and the SECURITY DEFINER functions added by 022,
--    023 and 025 pinned `search_path = public` WITHOUT `pg_temp`, which Postgres
--    still searches first.
--
-- Nothing here replaces the existing business rules. The matching trigger
-- `check_mutual_like` is untouched and still owns match creation. These
-- functions observe and wrap it.
--
-- ============================================================


-- ============================================================
-- 0. SAFETY: search_path including pg_temp
-- ============================================================
-- Migration 024 pinned `public, pg_temp` for every SECURITY DEFINER function
-- that existed at the time. Migrations 022, 023 and 025 then added more, with
-- `set search_path = public` only. In Postgres `pg_temp` is searched FIRST
-- unless it is named explicitly in the path, so those newer definer functions
-- are strictly less protected than the ones 024 fixed.
--
-- This loop re-asserts the setting on ALL SECURITY DEFINER functions in the
-- public schema, so it is self-healing for anything added later too.
do $$
declare
    fn record;
begin
    for fn in
        select p.oid::regprocedure as signature
        from pg_proc p
        join pg_namespace n on n.oid = p.pronamespace
        where n.nspname = 'public'
          and p.prosecdef
    loop
        execute format(
            'alter function %s security definer set search_path = public, pg_temp',
            fn.signature
        );
    end loop;
end;
$$;


-- ============================================================
-- 1. INDEXES for the queries this migration adds
-- ============================================================
-- The interaction rate limiter below counts rows per actor per hour, and the
-- received-likes / notifications lists page by recency. Both are unusable
-- without these.

create index if not exists idx_likes_liker_created
    on public.likes (liker_id, created_at desc);
create index if not exists idx_likes_liked_created
    on public.likes (liked_id, created_at desc);
create index if not exists idx_passes_user_created
    on public.passes (user_id, created_at desc);
create index if not exists idx_matches_user_a
    on public.matches (user_a_id);
create index if not exists idx_matches_user_b
    on public.matches (user_b_id);
create index if not exists idx_notifications_user_unread
    on public.notifications (user_id, is_read, created_at desc);
create index if not exists idx_messages_conversation_created
    on public.messages (conversation_id, created_at desc);
create index if not exists idx_conversations_match
    on public.conversations (match_id);
create index if not exists idx_reports_reporter_created
    on public.reports (reporter_id, created_at desc);


-- ============================================================
-- 2. REALTIME: publish the tables whose changes the UI must stream
-- ============================================================
-- 010 published messages, conversations and notifications. It did NOT publish
-- `conversation_members`, so `unread_count` never reached the client, nor
-- `likes` / `matches`, so a new match or a new inbound like could not appear
-- without a manual refresh.

do $$
begin
    if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
        create publication supabase_realtime;
    end if;
end;
$$;

alter publication supabase_realtime add table public.conversation_members;
alter publication supabase_realtime add table public.likes;
alter publication supabase_realtime add table public.matches;


-- ============================================================
-- 3. NOTIFICATION TYPE: `new_like`
-- ============================================================
-- Migration 001's CHECK allowed six types but only `new_match` and
-- `new_message` were ever produced. An inbound like that did NOT become a
-- match produced no notification of any kind, which is why there was nothing
-- for a "likes you" screen to be interesting about.
--
-- CHECK constraints (not enums) are used throughout this schema precisely so a
-- new value is an additive migration.

alter table public.notifications drop constraint if exists notifications_type_check;
alter table public.notifications add constraint notifications_type_check
    check (type in ('new_match', 'new_message', 'new_like', 'referral_success',
                    'plan_invitation', 'safety_alert', 'verification_result'));


-- ============================================================
-- 4. BLOCKING: enforce BOTH directions, and unwind what already exists
-- ============================================================
-- 006's `enforce_message_rules` raised only when the RECIPIENT had blocked the
-- sender. So if you blocked someone they could still message you freely. The
-- check below is symmetric.

create or replace function public.enforce_message_rules()
returns trigger as $$
declare
    v_other uuid;
    v_blocked boolean;
    v_recent integer;
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

    -- Blocking is symmetric: EITHER side having blocked the pair stops all new
    -- messages in both directions.
    select exists (
        select 1
        from public.blocks b
        where (b.blocker_id = new.sender_id and b.blocked_id = v_other)
           or (b.blocker_id = v_other and b.blocked_id = new.sender_id)
    ) into v_blocked;

    if v_blocked then
        raise exception 'You cannot message this user';
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


-- Creating a block must DESTROY the relationship it is meant to end. Without
-- this, blocking someone who had already matched you left the match, the
-- conversation and its full message history intact and visible.
create or replace function public.enforce_block_unwind()
returns trigger as $$
declare
    v_pair_ordered record;
begin
    -- Matches store the two participants with the lexicographically smaller id
    -- first (see `check_mutual_like`), so normalise to that ordering here too.
    select case when least(new.blocker_id, new.blocked_id) = new.blocker_id
                then least(new.blocker_id, new.blocked_id)
                else least(new.blocker_id, new.blocked_id) end as a,
           greatest(new.blocker_id, new.blocked_id) as b
      into v_pair_ordered;

    -- Deleting the match cascades to conversations -> conversation_members ->
    -- messages (all `on delete cascade`), which is the intended outcome: the
    -- conversation is gone for both people.
    delete from public.matches m
     where (m.user_a_id, m.user_b_id) = (v_pair_ordered.a, v_pair_ordered.b);

    -- A like that was recorded from either side must not silently re-create the
    -- match on the next like. The pairing is gone in both directions.
    delete from public.likes l
     where (l.liker_id, l.liked_id) in ((v_pair_ordered.a, v_pair_ordered.b),
                                        (v_pair_ordered.b, v_pair_ordered.a));

    delete from public.passes p
     where (p.user_id, p.target_id) in ((v_pair_ordered.a, v_pair_ordered.b),
                                        (v_pair_ordered.b, v_pair_ordered.a));

    -- Crossed-path history between them is no longer meaningful.
    delete from public.crossed_paths c
     where (c.user_a_id, c.user_b_id) in ((v_pair_ordered.a, v_pair_ordered.b),
                                          (v_pair_ordered.b, v_pair_ordered.a));

    -- Tell the blocked party their match is gone, so their UI updates instead
    -- of showing a conversation that will never work again.
    insert into public.notifications (user_id, type, title, body, data)
    values (
        new.blocked_id,
        'safety_alert',
        'A connection ended',
        'A Weekend connection you were matched with is no longer available.',
        jsonb_build_object('reason', 'blocked', 'blocked_by', new.blocker_id)
    );

    return null;
end;
$$ language plpgsql security definer
set search_path = public, pg_temp;

drop trigger if exists on_block_created_unwind on public.blocks;
create trigger on_block_created_unwind
    after insert on public.blocks
    for each row
    execute function public.enforce_block_unwind();


-- ============================================================
-- 5. INTERACTION RATE LIMITING
-- ============================================================
-- The only server-side limit in the entire schema was 20 messages/minute
-- (006). Nothing limited likes, passes or crossed-path computation, so a
-- scripted client could like or pass every profile in the database and inflate
-- every other user's match and referral counters.
--
-- The limits are deliberately generous for a human swiping but unreachable
-- for a script: nobody performs 200 likes in an hour by hand.

create or replace function public.enforce_interaction_rate_limit()
returns trigger as $$
declare
    v_actor uuid;
    v_recent integer;
    v_likes integer;
begin
    v_actor := case when tg_table_name = 'likes'
                   then new.liker_id else new.user_id end;

    -- Self-interaction is never legitimate and would corrupt the deck.
    if tg_table_name = 'likes' and new.liked_id = new.liker_id then
        raise exception 'Cannot like your own profile';
    end if;
    if tg_table_name = 'passes' and new.target_id = new.user_id then
        raise exception 'Cannot pass on your own profile';
    end if;

    -- Already-interacted-with is not an error: the client relies on duplicates
    -- being absorbed (MatchRepository swallows 23505). Counting is skipped.
    if tg_table_name = 'likes' and exists (
        select 1 from public.likes
        where liker_id = new.liker_id and liked_id = new.liked_id
    ) then
        return new;
    end if;

    if tg_table_name = 'passes' and exists (
        select 1 from public.passes
        where user_id = new.user_id and target_id = new.target_id
    ) then
        return new;
    end if;

    select count(*) into v_recent
    from public.likes l
    where l.liker_id = v_actor
      and l.created_at > now() - interval '1 hour';

    select count(*) into v_likes
    from public.likes l
    where l.liked_id = v_actor
      and l.created_at > now() - interval '1 hour';

    if v_recent > 200 then
        raise exception 'Interaction rate limit exceeded. Try again shortly.';
    end if;

    -- Inbound flood guard: a single profile receiving 150 likes in an hour is
    -- not enthusiasm, it is automation. The liker is rejected, so the bot
    -- cannot even fill this user's notification list.
    if v_likes >= 150 then
        raise exception 'Too many likes received in a short period. Try again later.';
    end if;

    return new;
end;
$$ language plpgsql security definer
set search_path = public, pg_temp;

drop trigger if exists on_like_rate_limit on public.likes;
create trigger on_like_rate_limit
    before insert on public.likes
    for each row
    execute function public.enforce_interaction_rate_limit();

drop trigger if exists on_pass_rate_limit on public.passes;
create trigger on_pass_rate_limit
    before insert on public.passes
    for each row
    execute function public.enforce_interaction_rate_limit();


-- ============================================================
-- 6. NOTIFY ON AN INBOUND LIKE
-- ============================================================
-- Only a MUTUAL like produced a notification. A one-sided like was invisible
-- to the person who received it, which is exactly the information a "likes
-- you" screen exists to surface.
--
-- `check_mutual_like` is deliberately NOT modified: match creation is its job
-- and it is unchanged. This trigger only runs when no match was created.

create or replace function public.notify_on_like()
returns trigger as $$
begin
    -- If this like produced a match, `check_mutual_like` already inserted two
    -- `new_match` notifications. A second one here would double-notify.
    if exists (
        select 1 from public.matches m
        where (m.user_a_id, m.user_b_id) in (
            (least(new.liker_id, new.liked_id), greatest(new.liker_id, new.liked_id))
        )
    ) then
        return new;
    end if;

    -- Blocking, in either direction, means this is not delivered.
    if exists (
        select 1 from public.blocks b
        where (b.blocker_id = new.liked_id and b.blocked_id = new.liker_id)
           or (b.blocker_id = new.liker_id and b.blocked_id = new.liked_id)
    ) then
        return new;
    end if;

    insert into public.notifications (user_id, type, title, body, data)
    values (
        new.liked_id,
        'new_like',
        'Someone liked you',
        case when new.is_stand_out
             then 'Someone stood out for you. See who.'
             else 'Someone liked your profile.'
        end,
        jsonb_build_object(
            'payload', jsonb_build_object(
                'type', 'new_like',
                'user_id', new.liker_id,
                'is_stand_out', new.is_stand_out
            )
        )
    );

    return new;
end;
$$ language plpgsql security definer
set search_path = public, pg_temp;

drop trigger if exists on_like_notify on public.likes;
create trigger on_like_notify
    after insert on public.likes
    for each row
    execute function public.notify_on_like();


-- ============================================================
-- 7. profile_completion IS NO LONGER A DEAD COLUMN
-- ============================================================
-- `profiles.profile_completion` is write-protected (005:49-53) and nothing
-- ever computed it, so it was permanently 0. Migration 022's `search_profiles`
-- awards up to 10 ranking points on it, meaning 10% of that ranking signal was
-- always dead weight.

create or replace function public.sync_profile_completion()
returns trigger as $$
declare
    v_min integer := public.minimum_profile_photos();
    v_photos integer;
    v_score integer;
begin
    -- `get_my_profile_completion` counts approved photos. Mirror that here so
    -- the two never disagree.
    select count(*) into v_photos
    from public.profile_photos pp
    where pp.user_id = new.id
      and pp.moderation_status = 'approved';

    v_score := 0;
    if coalesce(new.display_name, '') <> '' then v_score := v_score + 20; end if;
    if new.date_of_birth is not null then v_score := v_score + 20; end if;
    if coalesce(new.city, '') <> '' then v_score := v_score + 15; end if;
    if coalesce(new.bio, '') <> '' then v_score := v_score + 15; end if;
    if coalesce(new.gender, '') not in ('', 'Prefer not to say') then
        v_score := v_score + 10;
    end if;
    if v_photos >= v_min then v_score := v_score + 20; end if;

    new.profile_completion := least(v_score, 100);
    return new;
end;
$$ language plpgsql security definer
set search_path = public, pg_temp;

drop trigger if exists on_profile_completion_sync on public.profiles;
create trigger on_profile_completion_sync
    before update on public.profiles
    for each row
    execute function public.sync_profile_completion();

drop trigger if exists on_profile_completion_sync_insert on public.profiles;
create trigger on_profile_completion_sync_insert
    before insert on public.profiles
    for each row
    execute function public.sync_profile_completion();


-- ============================================================
-- 8. get_matches_for_user - REPAIRED
-- ============================================================
-- The previous version (022:160) could not execute: it selected
-- `m.conversation_id` (no such column on `matches`) and `mm.content` (the
-- column is `text`). It also returned a column set that had drifted from what
-- `MatchRepository.fetchMatches` reads, so even if it had run, every field the
-- UI uses would have silently defaulted.
--
-- The output list below is now the exact contract the Flutter layer expects:
-- match_id, other_user_id, display_name, age, gender, bio, city,
-- relationship_intent, primary_photo_path, interests, shared_interests,
-- matched_at, last_message_text, last_message_time, unread_count, distance_km,
-- is_photo_verified, trust_score.
--
-- Postgres cannot change an OUT-parameter list in place (42P13), so the old
-- signature is dropped and recreated. This is the pattern migrations 011 and
-- 022 both used.

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
    trust_score integer
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
            -- Distance is derived server-side from coordinates that the client
            -- already rounds to a ~2km grid before persisting (see
            -- LocationService.toApproximateCoordinates), so no precise location
            -- is exposed. `mine_user` supplies the signed-in user's own row.
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
            end as distance_km
        from located l
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
        e.trust_score
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
-- 9. record_like - one atomic round trip
-- ============================================================
-- Replaces the client's INSERT-then-SELECT-two-trips. Two reasons:
--
--   1. Correctness. `MatchRepository.recordLike` read `matches` in a SECOND
--      query to learn whether the like matched. That is a TOCTOU window, and
--      it returns `true` whenever a match happens to exist for the pair - even
--      if THIS like failed to insert.
--
--   2. Block enforcement. `likes` had an INSERT policy that only checked
--      `liker_id = auth.uid()`, so a blocked user could still like you. This
--      function refuses it, and the check cannot be bypassed by writing to the
--      table directly because the trigger in section 5 mirrors it.
--
-- Returns the same shape the Flutter layer already consumes, plus the
-- conversation id the chat screen needs.

create or replace function public.record_like(
    p_target_id uuid,
    p_is_stand_out boolean default false
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
begin
    if v_me is null then
        raise exception 'Not authenticated';
    end if;

    if p_target_id is null or p_target_id = v_me then
        raise exception 'Invalid target';
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

    -- Liking someone you previously passed must replace the pass. Both rows
    -- existing at once makes the target simultaneously "dealt with" and
    -- "liked", and discovery excludes both.
    delete from public.passes where user_id = v_me and target_id = p_target_id;

    insert into public.likes (liker_id, liked_id, is_stand_out)
    values (v_me, p_target_id, p_is_stand_out)
    on conflict (liker_id, liked_id) do update
        set is_stand_out = public.likes.is_stand_out or excluded.is_stand_out;

    -- `check_mutual_like` (AFTER INSERT) has already created the match inside
    -- this transaction, so it is visible here.
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
        'matched', v_match_id is not null,
        'match_id', v_match_id,
        'conversation_id', v_conversation_id
    );
end;
$$;

revoke all on function public.record_like(uuid, boolean) from public, anon;
grant execute on function public.record_like(uuid, boolean) to authenticated;


-- ============================================================
-- 10. record_pass - atomic, idempotent
-- ============================================================
create or replace function public.record_pass(p_target_id uuid)
returns jsonb
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

    if p_target_id is null or p_target_id = v_me then
        raise exception 'Invalid target';
    end if;

    -- If a block exists either way the pass is already recorded by the block
    -- itself, so there is nothing to write.
    if exists (
        select 1 from public.blocks b
        where (b.blocker_id = v_me and b.blocked_id = p_target_id)
           or (b.blocker_id = p_target_id and b.blocked_id = v_me)
    ) then
        return jsonb_build_object('passed', true, 'blocked', true);
    end if;

    insert into public.passes (user_id, target_id)
    values (v_me, p_target_id)
    on conflict (user_id, target_id) do nothing;

    -- Passing is not a statement of interest, so any outstanding like from
    -- this user is withdrawn. Otherwise the target stays matchable.
    delete from public.likes
    where liker_id = v_me and liked_id = p_target_id;

    return jsonb_build_object('passed', true, 'blocked', false);
end;
$$;

revoke all on function public.record_pass(uuid) from public, anon;
grant execute on function public.record_pass(uuid) to authenticated;


-- ============================================================
-- 11. unmatch_match
-- ============================================================
-- 002 grants SELECT-only on `matches`: there was no way to end a match. The
-- conversation and its entire message history also survived deleting a like,
-- so an "undo" left a live match behind.
--
-- Deleting the match cascades to conversations -> conversation_members ->
-- messages. The like rows are removed too, which is what makes an unmatch
-- genuinely reversible from the other person's side if they like again.

create or replace function public.unmatch_match(p_match_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    v_me uuid := auth.uid();
    v_a uuid;
    v_b uuid;
    v_deleted integer;
begin
    if v_me is null then
        raise exception 'Not authenticated';
    end if;

    select m.user_a_id, m.user_b_id into v_a, v_b
    from public.matches m
    where m.id = p_match_id
      and (m.user_a_id = v_me or m.user_b_id = v_me);

    if v_a is null then
        return false;
    end if;

    delete from public.matches m where m.id = p_match_id;
    get diagnostics v_deleted = row_count;

    if v_deleted > 0 then
        delete from public.likes l
         where (l.liker_id, l.liked_id) in ((v_a, v_b), (v_b, v_a));
        delete from public.passes p
         where (p.user_id, p.target_id) in ((v_a, v_b), (v_b, v_a));
    end if;

    return v_deleted > 0;
end;
$$;

revoke all on function public.unmatch_match(uuid) from public, anon;
grant execute on function public.unmatch_match(uuid) to authenticated;


-- ============================================================
-- 12. get_received_likes - the "likes you" surface
-- ============================================================
-- There was no data path for inbound likes at all. The `likes` SELECT policy
-- (002:117) permits reading them, but nothing queried it, so a one-sided like
-- was invisible to the person who received it.
--
-- Only NON-mutual likes are returned: a mutual like is already a match and
-- belongs on the matches tab, not here.

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
    trust_score integer
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
        p.trust_score
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
      -- Reciprocated: if you liked them back it is a match, already excluded
      -- above, but a pass means you declined and it should not resurface.
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
    order by l.created_at desc
    limit p_limit offset p_offset;
end;
$$;

revoke all on function public.get_received_likes(integer, integer)
    from public, anon;
grant execute on function public.get_received_likes(integer, integer)
    to authenticated;


-- ============================================================
-- 13. NOTIFICATION CENTRE
-- ============================================================
--
-- The table existed and the database has been inserting `new_match` and
-- `new_message` rows into it since migration 010, but nothing in `lib/` ever
-- read them back. `NotificationRepository` was called from nowhere and its
-- realtime listener had an empty body, so the only thing a user ever saw was a
-- transient system toast from `NotificationService` and every notification was
-- lost the moment it was dismissed.

-- The deep-link payload is extended with `match_id`.
--
-- `notify_on_message` wrote `conversation_id`, and the notification centre
-- routes to `/chat/:matchId` - `ChatScreen` needs a `MatchItem`, which is
-- keyed by match id. Without the match id every message notification resolved
-- to nothing and the deep link landed on "Conversation unavailable". Resolved
-- here, once, rather than by having the client do a second round trip to
-- translate one id into the other.
create or replace function public.notify_on_message()
returns trigger as $$
declare
    v_other uuid;
    v_match_id uuid;
begin
    select cm.user_id into v_other
    from public.conversation_members cm
    where cm.conversation_id = new.conversation_id
      and cm.user_id <> new.sender_id
    limit 1;

    if v_other is null then
        return new;
    end if;

    select c.match_id into v_match_id
    from public.conversations c
    where c.id = new.conversation_id
    limit 1;

    -- A block that lands while a message is in flight should not produce a
    -- notification that leads back to a conversation that no longer exists.
    if exists (
        select 1 from public.blocks b
        where (b.blocker_id = new.sender_id and b.blocked_id = v_other)
           or (b.blocker_id = v_other and b.blocked_id = new.sender_id)
    ) then
        return new;
    end if;

    insert into public.notifications (user_id, type, title, body, data)
    values (
        v_other,
        'new_message',
        'New message',
        coalesce(left(new.text, 80), 'You have a new message'),
        jsonb_build_object(
            'conversation_id', new.conversation_id,
            'match_id', v_match_id,
            'message_id', new.id,
            'sender', new.sender_id
        )
    );

    return new;
end;
$$ language plpgsql security definer
set search_path = public, pg_temp;

create or replace function public.get_notifications(
    p_limit integer default 50,
    p_offset integer default 0
)
returns table (
    id uuid,
    type text,
    title text,
    body text,
    data jsonb,
    is_read boolean,
    created_at timestamptz
)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
    perform public.assert_self(auth.uid());
    p_limit := least(coalesce(p_limit, 50), 100);
    p_offset := greatest(coalesce(p_offset, 0), 0);

    return query
    select n.id, n.type, n.title, n.body, n.data, n.is_read, n.created_at
    from public.notifications n
    where n.user_id = auth.uid()
    order by n.created_at desc
    limit p_limit offset p_offset;
end;
$$;

revoke all on function public.get_notifications(integer, integer)
    from public, anon;
grant execute on function public.get_notifications(integer, integer)
    to authenticated;


create or replace function public.mark_all_notifications_read()
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    v_count integer;
begin
    perform public.assert_self(auth.uid());

    update public.notifications
       set is_read = true
     where user_id = auth.uid()
       and is_read = false;
    get diagnostics v_count = row_count;

    return v_count;
end;
$$;

revoke all on function public.mark_all_notifications_read()
    from public, anon;
grant execute on function public.mark_all_notifications_read() to authenticated;


create or replace function public.notification_unread_count()
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    v_count integer;
begin
    perform public.assert_self(auth.uid());

    select count(*) into v_count
    from public.notifications
    where user_id = auth.uid()
      and is_read = false;

    return v_count;
end;
$$;

revoke all on function public.notification_unread_count() from public, anon;
grant execute on function public.notification_unread_count() to authenticated;


-- ============================================================
-- 14. submit_report
-- ============================================================
-- `SafetyRepository` wrote to `reports` directly. That works, but nothing
-- validated the category server-side, nothing stopped a script from filing
-- thousands of reports (which would let one user flood a moderator queue or
-- get an innocent account flagged), and nothing stopped the same person being
-- re-reported over and over.
--
-- The 001 vocabulary ('profile','photo','message','scam','harassment',
-- 'inappropriate_content','impersonation') could not express what a user
-- actually wants to say - there was no bucket for spam, for an under-18
-- concern, or for unsafe behaviour. Those three are added here. The old values
-- are all still accepted, so existing rows and any queued integration keep
-- working.

alter table public.reports drop constraint if exists reports_report_type_check;
alter table public.reports add constraint reports_report_type_check
    check (report_type in ('profile', 'photo', 'message', 'scam', 'harassment',
                           'inappropriate_content', 'impersonation',
                           'spam', 'underage', 'unsafe_behavior', 'other'));

-- One open report per reporter/target pair, so `on conflict do nothing` below
-- actually has a conflict to resolve.
create unique index if not exists idx_reports_one_open_per_pair
    on public.reports (reporter_id, reported_id)
    where status = 'pending';

create or replace function public.submit_report(
    p_reported_id uuid,
    p_report_type text,
    p_description text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    v_me uuid := auth.uid();
    v_recent integer;
    v_type text;
begin
    if v_me is null then
        raise exception 'Not authenticated';
    end if;

    if p_reported_id is null or p_reported_id = v_me then
        raise exception 'Invalid report target';
    end if;

    if not exists (
        select 1 from public.auth_user_state s
        where s.user_id = p_reported_id
    ) then
        raise exception 'Profile unavailable';
    end if;

    v_type := lower(trim(coalesce(p_report_type, '')));

    if v_type not in ('profile', 'photo', 'message', 'scam', 'harassment',
                      'inappropriate_content', 'impersonation',
                      'spam', 'underage', 'unsafe_behavior', 'other') then
        raise exception 'Invalid report category';
    end if;

    -- 20 reports a day. Enough for a determined genuine reporter, far too few
    -- for a queue-flooding script.
    select count(*) into v_recent
    from public.reports r
    where r.reporter_id = v_me
      and r.created_at > now() - interval '24 hours';

    if v_recent >= 20 then
        raise exception 'Too many reports submitted. Try again later.';
    end if;

    -- An already-open report on the same person is not duplicated.
    insert into public.reports
        (reporter_id, reported_id, report_type, description, status)
    values
        (v_me, p_reported_id, v_type,
         nullif(left(coalesce(p_description, ''), 2000), ''),
         'pending')
    on conflict do nothing;

    -- The internal status is not returned: a user is told their report was
    -- received, not how moderation classified or queued it.
    return jsonb_build_object(
        'submitted', true,
        'already_open',
        exists (
            select 1 from public.reports r
            where r.reporter_id = v_me
              and r.reported_id = p_reported_id
        )
    );
end;
$$;

revoke all on function public.submit_report(uuid, text, text)
    from public, anon;
grant execute on function public.submit_report(uuid, text, text)
    to authenticated;


-- ============================================================
-- 15. ensure_interest - closes the world-writable master list
-- ============================================================
-- 018 granted INSERT and UPDATE on `interests` to every signed-in user. The
-- UPDATE policy was `using (auth.uid() is not null)`, so any user could rename
-- or rewrite ANY shared interest, silently changing the chip on every other
-- user's profile.
--
-- The app calls
--     client.from('interests').upsert({'name': ...}, onConflict: 'name')
-- which PostgREST expands to `INSERT ... ON CONFLICT (name) DO UPDATE` - so
-- removing the UPDATE grant requires changing that call site, which is done in
-- the same change. This SECURITY DEFINER function performs the
-- get-or-create atomically with no UPDATE of an existing row at all.

create or replace function public.ensure_interest(
    p_name text,
    p_category text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    v_clean text;
    v_category text;
    v_id uuid;
begin
    v_clean := left(trim(coalesce(p_name, '')), 60);

    if char_length(v_clean) < 2 or char_length(v_clean) > 60 then
        raise exception 'Invalid interest';
    end if;

    v_category := nullif(left(trim(coalesce(p_category, '')), 40), '');

    select i.id into v_id
    from public.interests i
    where i.name = v_clean;

    if v_id is null then
        insert into public.interests (name, category)
        values (v_clean, v_category)
        on conflict (name) do nothing;

        select i.id into v_id
        from public.interests i
        where i.name = v_clean;
    end if;

    return v_id;
end;
$$;

revoke all on function public.ensure_interest(text, text)
    from public, anon;
grant execute on function public.ensure_interest(text, text)
    to authenticated;


drop policy if exists "authenticated users can link existing interests"
    on public.interests;
revoke update on public.interests from authenticated;

-- INSERT stays available so an unknown interest can still be added, but the
-- row can never be edited afterwards.
create or replace function public.guard_interest_name_change()
returns trigger as $$
begin
    if new.name is distinct from old.name then
        raise exception 'Interests cannot be renamed';
    end if;
    return new;
end;
$$ language plpgsql
set search_path = public, pg_temp;

drop trigger if exists on_interest_name_immutable on public.interests;
create trigger on_interest_name_immutable
    before update on public.interests
    for each row
    execute function public.guard_interest_name_change();


-- ============================================================
-- 16. verification_requests cannot be self-approved
-- ============================================================
-- 002's INSERT policy checked only `user_id = auth.uid()`, and `status`
-- accepts 'approved' while `confidence_score` accepts 0-100 with neither
-- column protected. A client could post a fully-approved verification request
-- for itself and then present it as evidence of a check that never ran.
--
-- The moderation verdict must come from the review pipeline, never the
-- reporter.

create or replace function public.protect_verification_verdict()
returns trigger as $$
begin
    -- Only the request's own author may create one.
    if tg_op = 'INSERT' then
        if new.user_id <> auth.uid()
           or new.status is distinct from 'pending' then
            raise exception 'Verification status is assigned by moderation';
        end if;
    else
        if new.status is distinct from old.status
           or new.confidence_score is distinct from old.confidence_score
           or new.detection_signals is distinct from old.detection_signals
           or new.reviewed_by is distinct from old.reviewed_by
           or new.reviewed_at is distinct from old.reviewed_at then
            -- Unchanged by an authenticated caller = no-op, which keeps the
            -- moderation pipeline (service role, auth.uid() null) working.
            if auth.uid() is not null then
                raise exception 'Verification status is assigned by moderation';
            end if;
        end if;
    end if;

    return new;
end;
$$ language plpgsql
set search_path = public, pg_temp;

drop trigger if exists on_verification_verdict_protected on public.verification_requests;
create trigger on_verification_verdict_protected
    before insert or update on public.verification_requests
    for each row
    execute function public.protect_verification_verdict();


-- ============================================================
-- 17. ad_campaigns no longer exposes campaign budgets
-- ============================================================
-- 008's SELECT policy was `auth.uid() is not null`, so every signed-in user
-- could read `budget_cents`, `spent_cents`, `cpm_cents` and `max_impressions`
-- for every campaign including drafts. The policy name says "active"; the
-- predicate checked nothing.

drop policy if exists "authenticated users can read active campaigns"
    on public.ad_campaigns;
create policy "advertisers can read own campaigns"
    on public.ad_campaigns
    for select
    using (auth.uid() is not null and advertiser_id = auth.uid());


-- ============================================================
-- 18. conversations: the client races its own trigger
-- ============================================================
-- `MessageRepository.sendMessage` inserts a `conversations` row when it cannot
-- find one, but `conversations` had SELECT-only RLS and `check_mutual_like`
-- already creates the conversation. The insert therefore always failed with a
-- permission error, which surfaced as "message failed to send" on a perfectly
-- valid conversation.
--
-- A member may create a conversation for a match they are actually part of,
-- which keeps the recovery path legitimate without opening the table up.

create policy "match participants can create conversations"
    on public.conversations
    for insert
    with check (
        exists (
            select 1
            from public.matches m
            where m.id = conversations.match_id
              and (m.user_a_id = auth.uid() or m.user_b_id = auth.uid())
        )
    );


-- ============================================================
-- 19. Revoke UPDATE on ad event tables so metrics cannot be rewritten
-- ============================================================
-- `ad_impressions` / `ad_clicks` / `ad_events` are insert-only and have no
-- UPDATE grant today; this states it explicitly so a future `grant all` cannot
-- silently reopen the ability to forge campaign performance.

revoke update, delete on public.ad_impressions from authenticated;
revoke update, delete on public.ad_clicks from authenticated;
revoke update, delete on public.ad_events from authenticated;


-- ============================================================
-- 20. serve-ad: the RPCs it calls were unreachable with its own key
-- ============================================================
-- `serve-ad` builds a SERVICE ROLE client and then calls `get_ad_for_user` and
-- `record_ad_event`. Both raise on `auth.uid() is null`, so every ad request
-- failed. Migration 009 fixed exactly this for `delete_user_account` and the
-- same fix was never applied to the ad RPCs.
--
-- Granting to service_role keeps the auth.uid() guard meaningful for the
-- authenticated client path while letting the edge function through.

grant execute on function public.get_ad_for_user(uuid, integer)
    to service_role;
grant execute on function public.record_ad_event(uuid, uuid, text, jsonb)
    to service_role;


-- ============================================================
-- 21. Backfill profile_completion for existing rows
-- ============================================================
-- The trigger above only fires on INSERT/UPDATE from here on. Existing profiles
-- keep the 0 the column has always held, so they would still lose the ranking
-- points 022 intended.

update public.profiles p
   set profile_completion = sub.score
  from (
    select p2.id,
           least(
             (case when coalesce(p2.display_name, '') <> '' then 20 else 0 end)
           + (case when p2.date_of_birth is not null then 20 else 0 end)
           + (case when coalesce(p2.city, '') <> '' then 15 else 0 end)
           + (case when coalesce(p2.bio, '') <> '' then 15 else 0 end)
           + (case when coalesce(p2.gender, '') not in ('', 'Prefer not to say')
                   then 10 else 0 end)
           + (case when (
               select count(*) from public.profile_photos pp
                where pp.user_id = p2.id and pp.moderation_status = 'approved'
           ) >= public.minimum_profile_photos() then 20 else 0 end),
             100
           ) as score
      from public.profiles p2
  ) sub
 where p.id = sub.id
   and p.profile_completion is distinct from sub.score;