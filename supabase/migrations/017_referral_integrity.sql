-- Migration: 017_referral_integrity.sql
-- Make the referral / QR-invite path actually work against LIVE Supabase.
--
-- Three separate breakages made the whole feature unreachable:
--
--   1. `profiles.referral_code` was never populated. `get_referral_stats`
--      (006) only *synthesised* a fallback code in its return value and never
--      wrote it anywhere, and `handle_new_user` (015) does not assign one. So
--      the code only ever existed in an RPC response the client discarded, and
--      the QR invite screen always hit its "No referral code available"
--      branch.
--
--   2. `QRInvitationService.validateInvitationServerSide` looked the code up in
--      `public.referrals`. That table holds one row per *referee*, so a code
--      that has never been redeemed has no row there and every freshly issued
--      invitation was rejected with "Referral code not found".
--
--   3. `QRInvitationService.recordReferral` calls the `record_referral` RPC,
--      which no migration ever created. Every scan ended in
--      "Failed to record referral".
--
-- Ownership model (unchanged and enforced):
--   * a referral code is a property of the *referrer's* profile row, and
--     `profiles` already has "profiles are visible to authenticated users" for
--     SELECT, so the lookup below exposes no more than the app already could
--     read;
--   * `record_referral` is SECURITY DEFINER and re-checks
--     `p_referee_id = auth.uid()`, so a client cannot credit a referral to
--     somebody else's account;
--   * the existing `referrals` CHECK (referrer_id <> referee_id) and the
--     UNIQUE (referrer_id, referee_id) constraint are relied upon rather than
--     replaced.

-- ============================================================
-- 1. Every profile owns a stable, unique referral code
-- ============================================================
create or replace function public.generate_referral_code(p_user_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
    v_code text;
    v_try int := 0;
begin
    -- Reuse the existing code when there is one, so a code already shared in a
    -- QR invitation never changes.
    select p.referral_code into v_code
    from public.profiles p
    where p.id = p_user_id;

    if v_code is not null and v_code <> '' then
        return v_code;
    end if;

    loop
        v_code := 'WKND-' || upper(substr(replace(p_user_id::text, '-', ''), 1, 10));
        v_try := v_try + 1;

        exit when not exists (
            select 1 from public.profiles p where p.referral_code = v_code
        );
        exit when v_try > 20; -- 160 bits of entropy; unreachable in practice
    end loop;

    update public.profiles
       set referral_code = v_code
     where id = p_user_id;

    return v_code;
end;
$$;

-- Backfill: any profile that still has no code gets one now. The function is
-- idempotent, so re-running is harmless.
do $$
declare
    r record;
begin
    for r in select id from public.profiles where referral_code is null loop
        perform public.generate_referral_code(r.id);
    end loop;
end;
$$;

-- ============================================================
-- 2. Assign a code at signup time
-- ============================================================
-- Reuses the 015 trigger body and adds the referral code, so a brand new user
-- can generate an invite immediately without a round trip.
create or replace function public.handle_new_user()
returns trigger as $$
begin
    insert into public.profiles (
        id,
        display_name,
        date_of_birth,
        gender,
        relationship_intent,
        referral_code,
        created_at,
        updated_at,
        last_active_at
    ) values (
        new.id,
        new.raw_user_meta_data->>'full_name',
        nullif(new.raw_user_meta_data->>'date_of_birth', '')::date,
        nullif(new.raw_user_meta_data->>'gender', ''),
        nullif(new.raw_user_meta_data->>'relationship_intent', ''),
        'WKND-' || upper(substr(replace(new.id::text, '-', ''), 1, 10)),
        now(),
        now(),
        now()
    );

    insert into public.user_settings (user_id) values (new.id);
    insert into public.preferences (user_id) values (new.id);

    return new;
end;
$$ language plpgsql security definer;

-- ============================================================
-- 3. get_referral_stats persists the code it returns
-- ============================================================
-- 006 read the code from `referrals`, then from `profiles`, and still could
-- return NULL. It now mints and stores one so the client, the QR invite screen
-- and the server-side validator all agree on the same value.
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

    v_code := public.generate_referral_code(p_user_id);

    return query
    select
        v_code as referral_code,
        count(*)::integer as invited_count,
        count(*) filter (where r.status = 'successful')::integer as verified_count,
        case
            when count(*) filter (where r.status = 'successful') >= 10 then 'Elite Pioneer'
            when count(*) filter (where r.status = 'successful') >= 5 then 'Silver Ambassador'
            when count(*) filter (where r.status = 'successful') >= 1 then 'Bronze Contributor'
            else 'New Pioneer'
        end as badge_title,
        case
            when count(*) filter (where r.status = 'successful') >= 10 then 'Gold Ambassador'
            when count(*) filter (where r.status = 'successful') >= 5 then 'Silver Ambassador'
            when count(*) filter (where r.status = 'successful') >= 1 then 'Bronze Contributor'
            else 'New Pioneer'
        end as achievement_tier,
        'https://weekend.app/invite/' || coalesce(v_code, '') as link_url
    from public.referrals r
    where r.referrer_id = p_user_id;
end;
$$;

revoke execute on function public.get_referral_stats(uuid)
    from anon, public;
grant execute on function public.get_referral_stats(uuid) to authenticated;

revoke execute on function public.generate_referral_code(uuid)
    from anon, public;
grant execute on function public.generate_referral_code(uuid) to authenticated;

-- ============================================================
-- 4. record_referral - the RPC the client actually calls
-- ============================================================
-- SECURITY DEFINER because RLS on `referrals` only allows a user to see their
-- own rows as referee; the insert attributes the row to somebody else (the
-- inviter), which the policy correctly forbids. The function is the narrow,
-- audited place where that write is allowed to happen.
create or replace function public.record_referral(
    p_referral_code text,
    p_referee_id uuid,
    p_inviter_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
    v_actual_inviter uuid;
begin
    -- The referee must be the caller. Without this, any authenticated user
    -- could credit a referral to an arbitrary account.
    if p_referee_id is distinct from auth.uid() then
        raise exception 'referral referee must be the authenticated user'
            using errcode = '42501';
    end if;

    if p_referee_id = p_inviter_id then
        -- Defence in depth behind the table CHECK.
        raise exception 'self-referrals are not allowed'
            using errcode = '23514';
    end if;

    if p_referral_code is null or btrim(p_referral_code) = '' then
        return false;
    end if;

    -- Resolve the inviter from the referral code itself. Never trust a
    -- client-supplied inviter id: that would let a caller attach a code to
    -- somebody else's account.
    select p.id into v_actual_inviter
    from public.profiles p
    where p.referral_code = btrim(p_referral_code);

    if v_actual_inviter is null then
        return false;
    end if;

    -- A client may pass the inviter id, but it must agree with the code.
    if p_inviter_id is not null and p_inviter_id <> v_actual_inviter then
        return false;
    end if;

    insert into public.referrals (referrer_id, referee_id, referral_code, status)
    values (v_actual_inviter, p_referee_id, btrim(p_referral_code), 'pending')
    on conflict (referrer_id, referee_id) do nothing;

    return true;
exception
    when unique_violation then
        -- Already recorded: the referral stands, the scan is simply a repeat.
        return true;
end;
$$;

revoke execute on function public.record_referral(text, uuid, uuid)
    from anon, public;
grant execute on function public.record_referral(text, uuid, uuid) to authenticated;

-- ============================================================
-- 5. A referral code lookup helper for the QR validator
-- ============================================================
-- `validateInvitationServerSide` must confirm the code is real and unused.
-- `referrals` only holds redeemed codes, so the authoritative source is
-- `profiles.referral_code`. Returns NULL when the code is unknown.
create or replace function public.lookup_referral_inviter(
    p_referral_code text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
    v_inviter uuid;
begin
    if p_referral_code is null or btrim(p_referral_code) = '' then
        return null;
    end if;

    select p.id into v_inviter
    from public.profiles p
    where p.referral_code = btrim(p_referral_code)
    limit 1;

    return v_inviter;
end;
$$;

revoke execute on function public.lookup_referral_inviter(text)
    from anon, public;
grant execute on function public.lookup_referral_inviter(text) to authenticated;
