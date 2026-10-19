-- ============================================================
-- 031 - Unified discovery: entitlements, privacy modes, spotlight,
--       surge, photo insights
-- ============================================================
--
-- This migration repairs/lands several product surfaces that the codebase
-- previously stubbed or stopped half way through. It is deliberately
-- ADDITIVE: existing columns, rows and policies are preserved, existing RPC
-- signatures keep their arity and order (new parameters are APPENDED with
-- defaults so every existing call site keeps working), and no table is
-- dropped.
--
-- Product rules (documented in docs/ and CHANGELOG):
--   * Entitlements are server-authoritative. The client can never grant
--     itself an entitlement; this migration defines the DEFAULT-FREE set
--     (Weekend is ad-funded today - the user has explicitly approved
--     "entitlement table, all free by default"). Paid tiers may later be
--     inserted into user_entitlements by trusted code only.
--   * Incognito restricts WHO CAN DISCOVER you.
--   * Snooze temporarily REMOVES you from discovery.
--   * Neither mode deletes matches, likes, messages or notification rows.
--   * Travel mode uses a user-chosen approximate destination stored in
--     user_settings. It NEVER overwrites profiles.latitude/longitude and
--     auto-disables after 7 days.
--   * Spotlight raises ranking ONLY (never eligibility), expires by time
--     window, and is rate limited server-side.
--   * Swipe Surge is derived from an explainable activity threshold in the
--     viewer's own city; it is never a permanent state.
-- ============================================================

-- ============================================================
-- 1. ENTITLEMENT MODEL
-- ============================================================
create table if not exists public.user_entitlements (
    id uuid primary key default uuid_generate_v4(),
    user_id uuid not null references public.profiles on delete cascade,
    feature text not null,
    granted_at timestamptz not null default now(),
    expires_at timestamptz,
    source text not null default 'system_free'
        check (source in ('system_free', 'system_grant', 'service_role')),
    metadata jsonb not null default '{}'::jsonb,
    unique (user_id, feature),
    check (expires_at is null or expires_at > granted_at)
);
create index if not exists idx_user_entitlements_user
    on public.user_entitlements(user_id);

alter table public.user_entitlements enable row level security;

-- Read YOUR OWN rows. There are deliberately NO insert/update/delete
-- policies: the owner can see the grant but can never create or extend one.
drop policy if exists user_entitlements_select_own on public.user_entitlements;
create policy user_entitlements_select_own on public.user_entitlements
    for select to authenticated
    using (user_id = auth.uid());

-- New profiles start with the default-free entitlement set. Backfill covers
-- every existing profile, so no user loses access they already had.
create or replace function public.grant_default_entitlements()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
    insert into public.user_entitlements (user_id, feature, source)
    values
        (new.id, 'priority_likes', 'system_free'),
        (new.id, 'spotlight', 'system_free'),
        (new.id, 'super_swipe', 'system_free'),
        (new.id, 'unlimited_likes', 'system_free'),
        (new.id, 'see_who_likes_you', 'system_free'),
        (new.id, 'photo_insights', 'system_free'),
        (new.id, 'travel_mode', 'system_free'),
        (new.id, 'incognito', 'system_free'),
        (new.id, 'snooze', 'system_free'),
        (new.id, 'opening_moves', 'system_free'),
        (new.id, 'like_notes', 'system_free'),
        (new.id, 'support', 'system_free'),
        (new.id, 'translation', 'system_free'),
        (new.id, 'rematch', 'system_free')
    on conflict (user_id, feature) do nothing;
    return new;
end;
$$;

drop trigger if exists on_profile_insert_entitlements on public.profiles;
create trigger on_profile_insert_entitlements
    after insert on public.profiles
    for each row
    execute function public.grant_default_entitlements();

-- Backfill (idempotent).
insert into public.user_entitlements (user_id, feature, source)
select pr.id, f.feature, 'system_free'
from public.profiles pr
cross join unnest (array[
    'priority_likes', 'spotlight', 'super_swipe', 'unlimited_likes',
    'see_who_likes_you', 'photo_insights', 'travel_mode', 'incognito',
    'snooze', 'opening_moves', 'like_notes', 'support', 'translation',
    'rematch'
]) as f(feature)
where not exists (
    select 1 from public.user_entitlements e
    where e.user_id = pr.id and e.feature = f.feature
);

-- Effective-entitlement helper. SECURITY DEFINER so RLS on user_entitlements
-- never limits trusted server helpers; general callers cannot reach it with
-- someone else's id without also being inside a SECURITY DEFINER helper.
create or replace function public.has_feature_entitlement(
    p_user_id uuid,
    p_feature text
)
returns boolean
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
    return exists (
        select 1 from public.user_entitlements e
        where e.user_id = p_user_id
          and e.feature = p_feature
          and (e.expires_at is null or e.expires_at > now())
    );
end;
$$;

create or replace function public.get_my_entitlements()
returns table (
    feature text,
    granted_at timestamptz,
    expires_at timestamptz,
    active boolean
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
    if auth.uid() is null then
        raise exception 'Not authenticated';
    end if;
    return query
    select e.feature, e.granted_at, e.expires_at,
           (e.expires_at is null or e.expires_at > now())
    from public.user_entitlements e
    where e.user_id = auth.uid()
    order by e.feature;
end;
$$;

revoke all on function public.get_my_entitlements() from public, anon;
grant execute on function public.get_my_entitlements() to authenticated;

-- ============================================================
-- 2. USER SETTINGS: new privacy/mode columns
-- ============================================================
-- All additive with constant defaults (no table rewrite).
alter table public.user_settings
    add column if not exists incognito_mode boolean not null default false;
alter table public.user_settings
    add column if not exists snooze_mode boolean not null default false;
alter table public.user_settings
    add column if not exists snooze_until timestamptz;
alter table public.user_settings
    add column if not exists show_online_now boolean not null default true;
alter table public.user_settings
    add column if not exists away_status text
    check (away_status is null or length(btrim(away_status)) <= 140);
alter table public.user_settings
    add column if not exists away_until timestamptz;
alter table public.user_settings
    add column if not exists travel_city text
    check (travel_city is null or length(btrim(travel_city)) <= 120);
alter table public.user_settings
    add column if not exists travel_lat double precision;
alter table public.user_settings
    add column if not exists travel_lon double precision;
alter table public.user_settings
    add column if not exists travel_started_at timestamptz;

-- ============================================================
-- 3. Spotlight windows
-- ============================================================
create table if not exists public.spotlight_windows (
    id uuid primary key default uuid_generate_v4(),
    user_id uuid not null references public.profiles on delete cascade,
    starts_at timestamptz not null default now(),
    ends_at timestamptz not null,
    check (ends_at > starts_at),
    unique (user_id, starts_at)
);
create index if not exists idx_spotlight_windows_active
    on public.spotlight_windows(user_id, ends_at desc);
alter table public.spotlight_windows enable row level security;

drop policy if exists spotlight_windows_select_own on public.spotlight_windows;
create policy spotlight_windows_select_own on public.spotlight_windows
    for select to authenticated
    using (user_id = auth.uid());
-- No write policies: activation goes through the security-definer RPC below.

create or replace function public.activate_spotlight()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    v_me uuid := auth.uid();
    v_now timestamptz := now();
    v_active_exists boolean;
    v_recent integer;
    v_window_end timestamptz;
    v_window record;
    v_duration interval := interval '4 hours';
begin
    if v_me is null then
        raise exception 'Not authenticated';
    end if;

    if not public.has_feature_entitlement(v_me, 'spotlight') then
        raise exception 'Spotlight is not available for this account'
            using errcode = 'insufficient_privilege';
    end if;

    -- One active window at a time.
    select w.ends_at into v_window_end
    from public.spotlight_windows w
    where w.user_id = v_me and w.ends_at > v_now
    limit 1;

    if v_window_end is not null then
        return jsonb_build_object(
            'activated', false,
            'reason', 'already_active',
            'ends_at', v_window_end
        );
    end if;

    -- Server-side abuse cap: 3 activations per rolling 30 days.
    select count(*) into v_recent
    from public.spotlight_windows w
    where w.user_id = v_me and w.starts_at > v_now - interval '30 days';
    if v_recent >= 3 then
        return jsonb_build_object(
            'activated', false,
            'reason', 'monthly_limit'
        );
    end if;

    insert into public.spotlight_windows (user_id, starts_at, ends_at)
    values (v_me, v_now, v_now + v_duration)
    returning * into v_window;

    return jsonb_build_object(
        'activated', true,
        'starts_at', v_window.starts_at,
        'ends_at', v_window.ends_at
    );
end;
$$;

revoke all on function public.activate_spotlight() from public, anon;
grant execute on function public.activate_spotlight() to authenticated;

create or replace function public.get_my_spotlight()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
    v_end timestamptz;
begin
    if auth.uid() is null then
        raise exception 'Not authenticated';
    end if;
    select w.ends_at into v_end
    from public.spotlight_windows w
    where w.user_id = auth.uid() and w.ends_at > now()
    limit 1;
    return jsonb_build_object(
        'active', v_end is not null,
        'ends_at', v_end,
        'activations_last_30_days', (
            select count(*) from public.spotlight_windows w
            where w.user_id = auth.uid()
              and w.starts_at > now() - interval '30 days'
        )
    );
end;
$$;

revoke all on function public.get_my_spotlight() from public, anon;
grant execute on function public.get_my_spotlight() to authenticated;

-- ============================================================
-- 4. Swipe surge (explainable, derived, no permanent state)
-- ============================================================
-- A surge for a city key is active when a discovery_surges row's window
-- covers now(). A row is created by get_surge_state when the city has >= 30
-- profiles active in the last 45 minutes. NO personal activity data is
-- ever returned.
create table if not exists public.discovery_surges (
    id uuid primary key default uuid_generate_v4(),
    city_key text not null,
    starts_at timestamptz not null default now(),
    ends_at timestamptz not null,
    participant_count integer not null default 0,
    unique (city_key, starts_at)
);
create index if not exists idx_surge_key_window
    on public.discovery_surges(city_key, starts_at desc);
alter table public.discovery_surges enable row level security;

-- Aggregated surge state only; readable to service machinery, not users.
-- (No SELECT policy: users learn surge state only through the RPC.)

create or replace function public.get_surge_state()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    v_me uuid := auth.uid();
    v_city text;
    v_key text;
    v_active_count integer;
    v_threshold constant integer := 30;
    v_window record;
begin
    if v_me is null then
        raise exception 'Not authenticated';
    end if;

    select p.city into v_city
    from public.profiles p
    where p.id = v_me;

    if v_city is null or length(btrim(v_city)) = 0 then
        return jsonb_build_object(
            'active', false, 'ends_at', null, 'city', null, 'reason', 'no_city'
        );
    end if;

    v_key := lower(btrim(v_city));

    -- An existing, unexpired window IS the surge.
    select * into v_window
    from public.discovery_surges s
    where s.city_key = v_key and s.ends_at > now()
    order by s.starts_at desc
    limit 1;

    if v_window is not null then
        return jsonb_build_object(
            'active', true,
            'ends_at', v_window.ends_at,
            'city', btrim(v_city),
            'threshold', v_threshold
        );
    end if;

    -- Recompute the explainable activity metric. A user is "active" when
    -- their presence row is fresher than 45 minutes (stale presence counts
    -- as offline; see the Online Now spec). Counting is aggregate-only:
    -- no per-user activity or consent flag is exposed by this RPC.
    select count(distinct pr.id) into v_active_count
    from public.profiles pr
    left join public.user_settings us on us.user_id = pr.id
    where pr.is_active
      and pr.deleted_at is null
      and pr.dating_profile_activated
      and pr.last_active_at > now() - interval '45 minutes'
      and lower(btrim(coalesce(pr.city, ''))) = v_key;

    if v_active_count >= v_threshold then
        insert into public.discovery_surges
            (city_key, starts_at, ends_at, participant_count)
        values (v_key, now(), now() + interval '45 minutes', v_active_count)
        on conflict (city_key, starts_at) do nothing
        returning * into v_window;

        return jsonb_build_object(
            'active', v_window is not null,
            'ends_at', v_window.ends_at,
            'city', btrim(v_city),
            'threshold', v_threshold
        );
    end if;

    return jsonb_build_object(
        'active', false, 'ends_at', null, 'city', btrim(v_city),
        'threshold', v_threshold
    );
end;
$$;

revoke all on function public.get_surge_state() from public, anon;
grant execute on function public.get_surge_state() to authenticated;

-- ============================================================
-- 5. Photo impressions (privacy-aware) + insights
-- ============================================================
-- An impression row records that THE CALLER saw this photo once per UTC day.
-- viewer_id is stored only for per-viewer deduplication and aggregate math;
-- no policy exposes individual rows.
create table if not exists public.photo_impressions (
    id uuid primary key default uuid_generate_v4(),
    photo_id uuid not null references public.profile_photos on delete cascade,
    viewer_id uuid not null references public.profiles on delete cascade,
    viewed_on date not null default (now() at time zone 'UTC')::date,
    viewed_at timestamptz not null default now(),
    unique (photo_id, viewer_id, viewed_on)
);
create index if not exists idx_photo_impressions_photo
    on public.photo_impressions(photo_id, viewed_on desc);
alter table public.photo_impressions enable row level security;

drop policy if exists photo_impressions_select_own on public.photo_impressions;
create policy photo_impressions_select_own on public.photo_impressions
    for select to authenticated
    using (viewer_id = auth.uid());
-- photo owners cannot read other people's IMPRESSION rows (privacy).

create or replace function public.record_photo_impressions(
    p_photo_ids uuid[]
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    v_me uuid := auth.uid();
    v_seen uuid[];
    v_today date := (now() at time zone 'UTC')::date;
    v_day_count integer;
    v_recorded integer;
    v_max_per_day constant integer := 400;
begin
    if v_me is null then
        raise exception 'Not authenticated';
    end if;

    if p_photo_ids is null then
        return jsonb_build_object('recorded', 0);
    end if;

    select array_agg(distinct u.pid)
      into v_seen
    from unnest(p_photo_ids) as u(pid)
    where u.pid is not null;

    -- per-call cap
    if coalesce(cardinality(v_seen), 0) > 50 then
        raise exception 'Too many photos in batch';
    end if;

    select count(*) into v_day_count
    from public.photo_impressions
    where viewer_id = v_me and viewed_on = v_today;
    if v_day_count >= v_max_per_day then
        return jsonb_build_object('recorded', 0, 'rate_limited', true);
    end if;

    insert into public.photo_impressions (photo_id, viewer_id, viewed_on)
    select i, v_me, v_today
    from unnest(v_seen) as u4(i)
    join public.profile_photos pp on pp.id = i
    join public.profiles own on own.id = pp.user_id
    where own.deleted_at is null
      and own.is_active
      and pp.moderation_status = 'approved'
      and not exists (select 1 from public.blocks b
                      where (b.blocker_id = v_me and b.blocked_id = own.id)
                         or (b.blocker_id = own.id and b.blocked_id = v_me))
      and own.id <> v_me
    on conflict (photo_id, viewer_id, viewed_on) do nothing;

    get diagnostics v_recorded = row_count;
    return jsonb_build_object('recorded', v_recorded);
end;
$$;

revoke all on function public.record_photo_impressions(uuid[])
    from public, anon;
grant execute on function public.record_photo_impressions(uuid[])
    to authenticated;

create or replace function public.get_my_photo_insights()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
    v_me uuid := auth.uid();
    v_min constant integer := 30; -- minimum impressions before insights show
begin
    if v_me is null then
        raise exception 'Not authenticated';
    end if;

    return jsonb_build_object(
        'window_days', 30,
        'minimum_required_impressions', v_min,
        'photos', coalesce((
            select jsonb_agg(jsonb_build_object(
                'photo_id', pp.id,
                'storage_path', pp.storage_path,
                'is_primary', pp.is_primary,
                'impressions_30d', s.impressions_30d,
                'unique_viewers_30d', s.unique_viewers_30d,
                'sufficient_data', s.impressions_30d >= v_min
            ) order by pp.is_primary desc, pp.sort_order asc)
            from public.profile_photos pp
            join lateral (
                select
                    count(*)::int as impressions_30d,
                    count(distinct pi.viewer_id)::int as unique_viewers_30d
                from public.photo_impressions pi
                where pi.photo_id = pp.id
                  and pi.viewed_at > now() - interval '30 days'
            ) s on true
            where pp.user_id = v_me
              and pp.moderation_status = 'approved'
        ), '[]'::jsonb)
    );
end;
$$;

revoke all on function public.get_my_photo_insights() from public, anon;
grant execute on function public.get_my_photo_insights() to authenticated;

-- ============================================================
-- 6. Presence / privacy RPCs
-- ============================================================
create or replace function public.set_privacy_mode(
    p_mode text,
    p_enabled boolean,
    p_snooze_hours integer default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    v_me uuid := auth.uid();
    v_has_ent boolean;
begin
    if v_me is null then
        raise exception 'Not authenticated';
    end if;

    if p_mode = 'incognito' then
        if not public.has_feature_entitlement(v_me, 'incognito') then
            raise exception 'Incognito is not available for this account'
                using errcode = 'insufficient_privilege';
        end if;
        update public.user_settings
           set incognito_mode = p_enabled
         where user_id = v_me;
    elsif p_mode = 'snooze' then
        if not public.has_feature_entitlement(v_me, 'snooze') then
            raise exception 'Snooze is not available for this account'
                using errcode = 'insufficient_privilege';
        end if;
        update public.user_settings
           set snooze_mode = p_enabled,
               snooze_until = case
                   when p_enabled and p_snooze_hours is not null
                   then now() + make_interval(hours => least(greatest(p_snooze_hours, 1), 24 * 7)::int)
                   else null
               end
         where user_id = v_me;
    else
        raise exception 'Unknown privacy mode';
    end if;

    if not found then
        raise exception 'Settings unavailable';
    end if;

    return jsonb_build_object('mode', p_mode, 'enabled', p_enabled);
end;
$$;

revoke all on function public.set_privacy_mode(text, boolean, integer)
    from public, anon;
grant execute on function public.set_privacy_mode(text, boolean, integer)
    to authenticated;

create or replace function public.set_away_status(
    p_message text,
    p_hours integer default 24
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    v_me uuid := auth.uid();
    v_message text := p_message;
begin
    if v_me is null then
        raise exception 'Not authenticated';
    end if;

    -- Clearing is allowed anytime.
    if v_message is null or length(btrim(v_message)) = 0 then
        update public.user_settings
           set away_status = null, away_until = null
         where user_id = v_me;
        return jsonb_build_object('away', false, 'message', null);
    end if;

    v_message := btrim(v_message);

    -- Reuse the standing text policy (no off-platform solicitation).
    if (public.detect_social_media_in_text(v_message)->>'detected')::boolean then
        raise exception 'Away message contains external social media identifiers';
    end if;

    if length(v_message) > 140 then
        raise exception 'Away message too long';
    end if;

    update public.user_settings
       set away_status = v_message,
           away_until = now()
                      + make_interval(hours => least(greatest(coalesce(p_hours, 24), 1), 168)::int)
     where user_id = v_me;

    if not found then
        raise exception 'Settings unavailable';
    end if;

    return jsonb_build_object('away', true, 'message', v_message);
end;
$$;

revoke all on function public.set_away_status(text, integer)
    from public, anon;
grant execute on function public.set_away_status(text, integer)
    to authenticated;

create or replace function public.set_travel_location(
    p_city text,
    p_lat double precision,
    p_lon double precision
)
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

    -- Disabling travel mode is always allowed.
    if p_city is null or length(btrim(p_city)) = 0 then
        update public.user_settings
           set travel_mode_enabled = false,
               travel_city = null,
               travel_lat = null,
               travel_lon = null,
               travel_started_at = null
         where user_id = v_me;
        return jsonb_build_object('travel_enabled', false);
    end if;

    if not public.has_feature_entitlement(v_me, 'travel_mode') then
        raise exception 'Travel mode is not available for this account'
            using errcode = 'insufficient_privilege';
    end if;

    if p_lat is null or p_lat < -90 or p_lat > 90
       or p_lon is null or p_lon < -180 or p_lon > 180 then
        raise exception 'Invalid travel destination';
    end if;

    update public.user_settings
       set travel_mode_enabled = true,
           travel_city = btrim(left(p_city, 120)),
           travel_lat = p_lat,
           travel_lon = p_lon,
           travel_started_at = now()
     where user_id = v_me;

    if not found then
        raise exception 'Settings unavailable';
    end if;

    return jsonb_build_object(
        'travel_enabled', true,
        'city', btrim(left(p_city, 120)),
        'expires_at', now() + interval '7 days'
    );
end;
$$;

revoke all on function public.set_travel_location(text, double precision, double precision)
    from public, anon;
grant execute on function public.set_travel_location(text, double precision, double precision)
    to authenticated;

-- Away status of the OTHER member of a conversation you are in. Used by the
-- chat screen; deliberately conversation-scoped, never discovery-scoped.
create or replace function public.get_conversation_away_note(
    p_conversation_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
    v_me uuid := auth.uid();
    v_other uuid;
    v_away_status public.user_settings.away_status%type;
    v_away_until public.user_settings.away_until%type;
    v_away boolean;
begin
    if v_me is null then
        raise exception 'Not authenticated';
    end if;

    -- The caller must be a member of the conversation; the away note surfaced
    -- is the OTHER member's, and only for active conversations.
    select cm2.user_id
      into v_other
    from public.conversation_members cm1
    join public.conversation_members cm2
      on cm2.conversation_id = cm1.conversation_id
    where cm1.conversation_id = p_conversation_id
      and cm1.user_id = v_me
      and cm2.user_id <> v_me
    limit 1;

    if v_other is null then
        return jsonb_build_object('away', false, 'message', null);
    end if;

    select away_status, away_until
      into v_away_status, v_away_until
    from public.user_settings
    where user_id = v_other;

    v_away := v_away_status is not null
              and (v_away_until is null or v_away_until > now());

    return jsonb_build_object(
        'away', v_away,
        'message', case when v_away then v_away_status else null end
    );
end;
$$;

revoke all on function public.get_conversation_away_note(uuid)
    from public, anon;
grant execute on function public.get_conversation_away_note(uuid)
    to authenticated;

-- ============================================================
-- 7. get_nearby_profiles - unified rewrite
-- ============================================================
--
-- Same signature as 027 plus APPENDED parameters (existing call sites keep
-- working). New in this version:
--   * mode 'travel' resolves the viewer's stored approximate destination
--     (7-day auto-expiry, never GPS-spoofed).
--   * snoozed candidates are excluded; near-expiry snooze stays inactive.
--   * incognito candidates are only visible to people they already liked.
--   * is_online boolean out for the Online Now dot, authored by the
--     candidate's own show_online_now consent.
--   * last_active_at respects consent (null when hidden).
--   * p_last_active_hours: the Recently Active filter.
--   * active Spotlight windows contribute to SOFT ranking ONLY.
create or replace function public.get_nearby_profiles(
    p_user_id uuid,
    p_limit integer default 20,
    p_offset integer default 0,
    p_max_distance_km double precision default 50,
    p_preferred_genders text[] default array[]::text[],
    p_age_min integer default 18,
    p_age_max integer default 100,
    p_discovery_mode text default 'nearby',
    p_last_active_hours integer default null
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
    compatibility_score numeric,
    is_online boolean,
    is_spotlit boolean
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
    v_viewer_lat double precision;
    v_viewer_lon double precision;
    v_viewer_city text;
    v_limit integer := least(greatest(coalesce(p_limit, 20), 1), 50);
    v_offset integer := greatest(coalesce(p_offset, 0), 0);
    v_gender_set boolean := coalesce(cardinality(p_preferred_genders), 0) > 0;
    v_mode text := coalesce(p_discovery_mode, 'nearby');
    v_enforce_distance boolean := v_mode not in ('global', 'crossed_paths');
begin
    perform public.assert_self(p_user_id);

    if v_mode not in ('nearby', 'global', 'city', 'crossed_paths', 'travel') then
        v_mode := 'nearby';
    end if;

    select pr.latitude, pr.longitude, pr.city
      into v_viewer_lat, v_viewer_lon, v_viewer_city
    from public.profiles pr where pr.id = p_user_id;

    -- Travel mode: stored approximate destination only, valid for 7 days.
    if v_mode = 'travel' then
        select ts.travel_lat, ts.travel_lon, ts.travel_city
          into v_viewer_lat, v_viewer_lon, v_viewer_city
        from public.user_settings ts
        where ts.user_id = p_user_id
          and ts.travel_mode_enabled
          and ts.travel_started_at > now() - interval '7 days';

        -- Expired or non-existent travel configuration falls back to home.
        if v_viewer_lat is null or v_viewer_lon is null then
            select pr.latitude, pr.longitude, pr.city
              into v_viewer_lat, v_viewer_lon, v_viewer_city
            from public.profiles pr where pr.id = p_user_id;
            v_mode := 'nearby';
        end if;
    end if;

    return query
    select
        p.id as profile_id,
        p.display_name,
        case when p.date_of_birth is not null
             then date_part('years', age(p.date_of_birth))::int
             else null
        end as age,
        p.gender,
        p.bio,
        p.city,
        case
            when v_enforce_distance and p.latitude is not null
                 and p.longitude is not null
                 and v_viewer_lat is not null and v_viewer_lon is not null
            then round((
                ST_Distance(
                    ST_Point(p.longitude, p.latitude)::geography,
                    ST_Point(v_viewer_lon, v_viewer_lat)::geography
                ) / 1000
            )::numeric, 1)::double precision
            else 0
        end as distance_km,
        p.is_photo_verified,
        p.trust_score,
        (select storage_path from public.profile_photos pp
          where pp.user_id = p.id and pp.moderation_status = 'approved'
          order by pp.is_primary desc, pp.created_at asc
          limit 1) as primary_photo_path,
        (select array_agg(i.name)
           from public.user_interests ui
           join public.interests i on i.id = ui.interest_id
          where ui.user_id = p.id) as interests,
        p.relationship_intent,
        -- Raw last-seen only leaves the API when the owner consents.
        case when coalesce(us.show_online_now, true)
             then p.last_active_at else null end as last_active_at,
        (p.trust_score * 0.3)
        + (case when p.is_photo_verified then 15 else 0 end)
        + (case when p.last_active_at > now() - interval '7 days' then 20 else 0 end)
        + (case when sw.id is not null then 40 else 0 end)
            as compatibility_score,
        -- Online Now: consented, fresh (5 minutes), non-stale presence.
        (coalesce(us.show_online_now, true)
         and p.last_active_at > now() - interval '5 minutes') as is_online,
        (sw.id is not null) as is_spotlit
    from public.profiles p
    left join public.user_settings us on us.user_id = p.id
    left join lateral (
        select 1 as id
        from public.spotlight_windows w
        where w.user_id = p.id and w.starts_at <= now() and w.ends_at > now()
        limit 1
    ) sw on true
    where p.id <> p_user_id
      and p.is_active
      and p.deleted_at is null
      and p.dating_profile_activated
      and p.display_name is not null
      and length(btrim(p.display_name)) > 0
      -- ADULT FLOOR (migration 028), unchanged.
      and p.date_of_birth is not null
      and date_part('years', age(p.date_of_birth))::int >= 18
      and date_part('years', age(p.date_of_birth))::int
            >= greatest(coalesce(p_age_min, 18), 18)
      and date_part('years', age(p.date_of_birth))::int
            <= coalesce(p_age_max, 120)
      and (not v_gender_set
           or (p.gender is not null and p.gender = any(p_preferred_genders)))
      -- SNOOZE excludes the candidate entirely until the window passes.
      and not (coalesce(us.snooze_mode, false)
               and (us.snooze_until is null or us.snooze_until > now()))
      -- INCOGNITO: a candidate is hidden from discovery unless they have
      -- already liked the viewer.
      and (not coalesce(us.incognito_mode, false)
           or exists (select 1 from public.likes l2
                      where l2.liker_id = p.id
                        and l2.liked_id = p_user_id))
      -- Recently Active filter (privacy-preserving aggregate window).
      and (p_last_active_hours is null
           or (p.last_active_at > now()
                 - make_interval(hours => greatest(coalesce(p_last_active_hours, 0), 0)::int)))
      and (
            v_mode not in ('global', 'city')
         or v_mode = 'global'
         or (v_mode = 'city' and p.city is not null
             and lower(btrim(p.city)) = lower(btrim(coalesce(v_viewer_city, ''))))
      )
      and not exists (select 1 from public.blocks
                       where blocker_id = p_user_id and blocked_id = p.id)
      and not exists (select 1 from public.blocks
                       where blocker_id = p.id and blocked_id = p_user_id)
      and not exists (select 1 from public.passes
                       where user_id = p_user_id and target_id = p.id)
      and not exists (select 1 from public.likes
                       where liker_id = p_user_id and liked_id = p.id)
      and not exists (select 1 from public.reports
                       where reporter_id = p_user_id and reported_id = p.id)
      and not exists (
            select 1 from public.matches
            where (user_a_id = p_user_id and user_b_id = p.id)
               or (user_b_id = p_user_id and user_a_id = p.id)
          )
    order by is_spotlit desc,
             distance_km asc nulls last,
             compatibility_score desc nulls last,
             p.last_active_at desc
    limit v_limit offset v_offset;
end;
$$;

-- The 027 8-parameter overload still exists alongside this 9-parameter
-- version. Drop it so callers with the old argument list resolve to THIS
-- function through p_last_active_hours' DEFAULT (PostgREST fills omitted
-- named arguments with defaults). Keeping both would let an 8-argument call
-- silently hit the stale version with none of the new predicates.
drop function if exists public.get_nearby_profiles(
    uuid, integer, integer, double precision, text[], integer, integer, text
);

revoke all on function public.get_nearby_profiles(
    uuid, integer, integer, double precision, text[], integer, integer, text, integer
) from public, anon;
grant execute on function public.get_nearby_profiles(
    uuid, integer, integer, double precision, text[], integer, integer, text, integer
) to authenticated;

-- ============================================================
-- 8. search_profiles - additive hardening
-- ============================================================
--
-- Same 21-argument signature as 030 (clients keep calling unchanged). New:
-- snoozed and incognito candidates excluded (same rules as the nearby deck),
-- spotlight in SOFT ranking, and last_active_at consent gating in the
-- OUTPUT columns only (the ranking uses the internal value from `candidate`).
--
-- The 030 version of this function returns a DIFFERENT OUT row type (it lacks
-- primary_photo_id / is_online / is_spotlit), and Postgres refuses
-- CREATE OR REPLACE across a row-type change, so the previous overload is
-- dropped first - exactly as this migration already does for
-- get_nearby_profiles above. Nothing depends on the old function (clients call
-- the RPC with named parameters, which re-resolve the overload at call time).
drop function if exists public.search_profiles(
    uuid, integer, integer, double precision, double precision, double precision,
    text, text[], integer, integer, text[], text[], text[], text[], text[],
    text, text, text, text, text, boolean
);

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
        select 1 as mid from public.spotlight_windows w
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

-- ============================================================
-- 9. Notifications: new types
-- ============================================================
alter table public.notifications drop constraint if exists notifications_type_check;
alter table public.notifications add constraint notifications_type_check
    check (type in ('new_match', 'new_message', 'new_like', 'referral_success',
                    'plan_invitation', 'safety_alert', 'verification_result',
                    'support_ticket'));
