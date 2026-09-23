-- Migration: 010_realtime_and_notifications.sql
-- Completes the realtime + notifications + read-state loop.
--
-- Gaps found by live two-user verification:
--   1. conversation_members had no UPDATE policy -> users could never mark
--      chats as read (app writes conversation_members.last_read_at).
--   2. unread_count is a stored column nothing maintained.
--   3. No producer ever inserted notifications (match/message events were
--      invisible; inserts are intentionally denied to clients).
--   4. The client streams messages/conversations/notifications through
--      Supabase Realtime, but the tables were not in the
--      supabase_realtime publication, so no events were ever delivered.

-- ============================================================
-- 1. REALTIME PUBLICATION
-- ============================================================
do $$
begin
    if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
        create publication supabase_realtime;
    end if;
end $$;

do $$
declare
    t text;
begin
    foreach t in array array['messages', 'conversations', 'notifications'] loop
        if not exists (
            select 1 from pg_publication_tables
            where pubname = 'supabase_realtime'
              and schemaname = 'public'
              and tablename = t
        ) then
            execute format('alter publication supabase_realtime add table public.%I', t);
        end if;
    end loop;
end $$;

-- ============================================================
-- 2. CONVERSATION MEMBERS: members manage their own row
-- ============================================================
create policy "members can update own membership"
    on public.conversation_members
    for update
    using (user_id = auth.uid())
    with check (user_id = auth.uid());

-- ============================================================
-- 3. UNREAD COUNT MAINTENANCE (server-side, race-free)
-- ============================================================
create or replace function public.bump_unread_on_message()
returns trigger as $$
begin
    update public.conversation_members
    set unread_count = unread_count + 1
    where conversation_id = new.conversation_id
      and user_id <> new.sender_id;
    return new;
end;
$$ language plpgsql security definer
set search_path = public;

drop trigger if exists on_message_bump_unread on public.messages;
create trigger on_message_bump_unread
    after insert on public.messages
    for each row
    execute function public.bump_unread_on_message();

create or replace function public.reset_unread_on_read()
returns trigger as $$
begin
    if new.last_read_at is distinct from old.last_read_at then
        new.unread_count := 0;
    end if;
    return new;
end;
$$ language plpgsql
set search_path = public;

drop trigger if exists on_member_read_reset on public.conversation_members;
create trigger on_member_read_reset
    before update on public.conversation_members
    for each row
    execute function public.reset_unread_on_read();

-- ============================================================
-- 4. NOTIFICATION PRODUCERS
-- ============================================================
-- Mutual like -> "new match" notification for BOTH users. The match,
-- conversation, membership and referral crediting logic from 006 is kept
-- verbatim; only the notification inserts are added.
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

            -- Realtime + inbox: tell both users about the new match.
            insert into public.notifications (user_id, type, title, body, data)
            values
                (new.liker_id, 'new_match', 'It''s a match!',
                 'You have a new match. Say hi!',
                 jsonb_build_object('match_id', v_match_id, 'other_user', new.liked_id)),
                (new.liked_id, 'new_match', 'It''s a match!',
                 'You have a new match. Say hi!',
                 jsonb_build_object('match_id', v_match_id, 'other_user', new.liker_id));

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

drop trigger if exists on_like_created on public.likes;
create trigger on_like_created
    after insert on public.likes
    for each row
    execute function public.check_mutual_like();

-- New message -> "new message" notification for the other participant.
create or replace function public.notify_on_message()
returns trigger as $$
declare
    v_other uuid;
begin
    select cm.user_id into v_other
    from public.conversation_members cm
    where cm.conversation_id = new.conversation_id
      and cm.user_id <> new.sender_id
    limit 1;

    if v_other is not null then
        insert into public.notifications (user_id, type, title, body, data)
        values (
            v_other,
            'new_message',
            'New message',
            coalesce(left(new.text, 80), 'You have a new message'),
            jsonb_build_object(
                'conversation_id', new.conversation_id,
                'message_id', new.id,
                'sender', new.sender_id
            )
        );
    end if;
    return new;
end;
$$ language plpgsql security definer
set search_path = public;

drop trigger if exists on_message_notify on public.messages;
create trigger on_message_notify
    after insert on public.messages
    for each row
    execute function public.notify_on_message();