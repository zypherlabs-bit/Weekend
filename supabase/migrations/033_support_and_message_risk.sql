-- ============================================================
-- 033 - Support tickets and explainable message risk
-- ============================================================
--
-- Features landed: Customer Support (in-app ticket workflow with real
-- persistence, status tracking and safety escalation) and Spam/Scam risk
-- indicators (EXPLAINABLE server-computed signals on the message row; the
-- message is still delivered, nobody is auto-banned - the recipient decides
-- what to do, supported by the existing report/block flows).
-- ============================================================

-- ============================================================
-- 1. SUPPORT TICKETS
-- ============================================================
create table if not exists public.support_tickets (
    id uuid primary key default uuid_generate_v4(),
    user_id uuid not null references public.profiles on delete set null,
    subject text not null check (length(btrim(subject)) between 1 and 120),
    category text not null
        check (category in ('account', 'safety', 'scam', 'bug', 'billing', 'other')),
    details text not null check (length(btrim(details)) between 1 and 4000),
    status text not null default 'open'
        check (status in ('open', 'in_progress', 'escalated', 'resolved')),
    priority text not null default 'normal'
        check (priority in ('low', 'normal', 'high')),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);
create index if not exists idx_support_tickets_user
    on public.support_tickets(user_id, created_at desc);
alter table public.support_tickets enable row level security;

drop policy if exists support_tickets_select_own on public.support_tickets;
create policy support_tickets_select_own on public.support_tickets
    for select to authenticated
    using (user_id = auth.uid());

drop policy if exists support_tickets_insert_own on public.support_tickets;
create policy support_tickets_insert_own on public.support_tickets
    for insert to authenticated
    with check (user_id = auth.uid());
-- No update/delete policies: ONLY trusted backend code (service role) may
-- change ticket state. Fake "resolved" flips from a client are impossible.

-- Set safety tickets to high priority (escalated status happens only on
-- explicit human action or admin). Rate limit: 5 tickets per 24 hours.
create or replace function public.validate_support_ticket()
returns trigger as $$
declare
    v_recent integer;
    v_me uuid := new.user_id;
begin
    new.subject := btrim(new.subject);
    new.details := btrim(new.details);

    if new.category in ('safety', 'scam') then
        new.priority := 'high';
    end if;

    if v_me is not null then
        select count(*) into v_recent
        from public.support_tickets t
        where t.user_id = v_me
          and t.created_at > now() - interval '24 hours';
        if v_recent >= 5 then
            raise exception 'Support ticket rate limit reached';
        end if;
    end if;

    return new;
end;
$$ language plpgsql
set search_path = public, pg_temp;

drop trigger if exists on_support_ticket_validate on public.support_tickets;
create trigger on_support_ticket_validate
    before insert on public.support_tickets
    for each row
    execute function public.validate_support_ticket();

-- In-app acknowledgement so the user has a REAL, persistent record of the
-- submission (never a fabricated success message in the UI).
create or replace function public.ack_support_ticket()
returns trigger as $$
begin
    insert into public.notifications (user_id, type, title, body, created_at)
    values (
        new.user_id,
        'support_ticket',
        case
            when new.priority = 'high'
            then 'Support ticket received - prioritised for safety review'
            else 'Support ticket received'
        end,
        'Your ticket "' || left(new.subject, 60) || '" has been logged. ' ||
            'Ticket ID: ' || left(new.id::text, 8) || '. ' ||
            'You can track its status in Settings > Support.',
        new.created_at
    );
    return new;
end;
$$ language plpgsql
set search_path = public, pg_temp;

drop trigger if exists on_support_ticket_ack on public.support_tickets;
create trigger on_support_ticket_ack
    after insert on public.support_tickets
    for each row
    execute function public.ack_support_ticket();

revoke all on public.support_tickets from anon, public;
grant select, insert on public.support_tickets to authenticated;

-- Notifications check constraint gains 'support_ticket' (additive).
alter table public.notifications drop constraint if exists notifications_type_check;
alter table public.notifications add constraint notifications_type_check
    check (type in ('new_match', 'new_message', 'new_like', 'referral_success',
                    'plan_invitation', 'safety_alert', 'verification_result',
                    'support_ticket'));

-- ============================================================
-- 2. EXPLAINABLE MESSAGE RISK SIGNALS
-- ============================================================
-- A deliverable message may carry 0..3 risk flags. Each flag is a specific,
-- explainable pattern used in known scam playbooks. Requirements honoured:
--   * The message STILL arrives (no auto-ban, no auto-hide, no shadow-drop).
--   * The participant sees exactly WHICH signals matched.
--   * User reports and blocks (already enforced server-side) remain the
--     enforcement path; this flag only informs.
alter table public.messages
    add column if not exists risk_flags text[] not null default '{}'::text[];
alter table public.messages
    add constraint messages_risk_flag_enum
    check (risk_flags <@ '{url_present,money_request,off_platform_contact}'::text[]);

create or replace function public.score_message_risk()
returns trigger as $$
declare
    v_text text := lower(coalesce(new.text, ''));
    v_flags text[] := '{}'::text[];
    v_normalized text;
begin
    if btrim(v_text) = '' then
        new.risk_flags := '{}'::text[];
        return new;
    end if;

    -- strip soft-hyphens/zero-widths to catch "t.e l e gram" style evasion
    v_normalized := regexp_replace(v_text, '[\u200B-\u200F\u2028-\u202F\u205F\u3000\-\s]', '', 'g');

    -- 1. URL present (any scheme or www.)
    if v_text ~ 'https?://|\bwww\.' then
        v_flags := v_flags || 'url_present';
    end if;

    -- 2. Money movement language (common scam funnel opener)
    if v_normalized ~ '(sendmoney|transferto|banktransfer|crypto|bitcoin|usdt|giftcard|itunesgift|westernunion|paym[e3]nt|upi|paytm|venmo|cashapp|zelle|recharge|earnmoney|forex)' then
        v_flags := v_flags || 'money_request';
    end if;

    -- 3. Off-platform redirect (reuses the standing social-media policy)
    if (public.detect_social_media_in_text(coalesce(new.text, ''))->>'detected')::boolean then
        v_flags := v_flags || 'off_platform_contact';
    end if;

    new.risk_flags := v_flags;
    return new;
end;
$$ language plpgsql
set search_path = public, pg_temp;

drop trigger if exists on_message_risk_score on public.messages;
create trigger on_message_risk_score
    before insert on public.messages
    for each row
    execute function public.score_message_risk();
