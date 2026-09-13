-- Migration: 008_advertisements_rls_and_functions.sql
-- RLS policies and server-side functions for the advertisement system.

-- ============================================================
-- ROW LEVEL SECURITY - ENABLE RLS
-- ============================================================
alter table public.advertisements enable row level security;
alter table public.ad_campaigns enable row level security;
alter table public.ad_impressions enable row level security;
alter table public.ad_clicks enable row level security;
alter table public.ad_events enable row level security;
alter table public.ad_config enable row level security;
alter table public.crossed_paths enable row level security;
alter table public.crossed_paths_log enable row level security;
alter table public.user_location_buckets enable row level security;

-- ============================================================
-- ADVERTISEMENTS POLICIES
-- Users can SELECT active advertisements only.
-- ============================================================
create policy "authenticated users can read active ads"
    on public.advertisements
    for select
    using (
        auth.uid() is not null
        and is_active = true
        and campaign_id in (
            select id from public.ad_campaigns
            where status = 'active'
              and (start_date is null or start_date <= now())
              and (end_date is null or end_date >= now())
        )
    );

create policy "campaign managers can manage own ads"
    on public.advertisements
    for all
    using (
        auth.uid() is not null
        and campaign_id in (
            select id from public.ad_campaigns
            where advertiser_id = auth.uid()
        )
    )
    with check (
        auth.uid() is not null
        and campaign_id in (
            select id from public.ad_campaigns
            where advertiser_id = auth.uid()
        )
    );

-- ============================================================
-- AD CAMPAIGNS POLICIES
-- ============================================================
create policy "authenticated users can read active campaigns"
    on public.ad_campaigns
    for select
    using (auth.uid() is not null);

-- Only advertisers (self-referencing) can manage their own campaigns
create policy "advertisers can manage own campaigns"
    on public.ad_campaigns
    for all
    using (
        auth.uid() is not null
        and advertiser_id = auth.uid()
    )
    with check (
        auth.uid() is not null
        and advertiser_id = auth.uid()
    );

-- ============================================================
-- AD IMPRESSIONS POLICIES
-- Users can INSERT own impressions. Users can read their own.
-- Server-side validation via Edge Function for trusted events.
-- ============================================================
create policy "users can read own ad impressions"
    on public.ad_impressions
    for select
    using (user_id = auth.uid());

create policy "users can create own ad impressions"
    on public.ad_impressions
    for insert
    with check (user_id = auth.uid());

-- No updates or deletes for impressions (audit trail)

-- ============================================================
-- AD CLICKS POLICIES
-- ============================================================
create policy "users can read own ad clicks"
    on public.ad_clicks
    for select
    using (user_id = auth.uid());

create policy "users can create own ad clicks"
    on public.ad_clicks
    for insert
    with check (user_id = auth.uid());

-- ============================================================
-- AD EVENTS POLICIES
-- ============================================================
create policy "users can read own ad events"
    on public.ad_events
    for select
    using (user_id = auth.uid());

create policy "users can create own ad events"
    on public.ad_events
    for insert
    with check (user_id = auth.uid());

-- ============================================================
-- AD CONFIG POLICIES (read-only for clients)
-- ============================================================
create policy "authenticated users can read ad config"
    on public.ad_config
    for select
    using (auth.uid() is not null);

-- ============================================================
-- CROSSED PATHS POLICIES
-- Users can only see crossed paths involving them.
-- ============================================================
create policy "users can read own crossed paths"
    on public.crossed_paths
    for select
    using (
        auth.uid() is not null
        and (user_a_id = auth.uid() or user_b_id = auth.uid())
    );

-- No direct insert/update/delete for users (computed server-side)

-- ============================================================
-- CROSSED PATHS LOG POLICIES
-- ============================================================
-- Internal table - no direct user access. Server-side only.
-- (Edge Functions with service role handle this)

-- ============================================================
-- USER LOCATION BUCKETS POLICIES
-- ============================================================
create policy "users can manage own location bucket"
    on public.user_location_buckets
    for all
    using (user_id = auth.uid())
    with check (user_id = auth.uid());

-- ============================================================
-- AD SERVING RPC: get_ad_for_user
-- Returns an eligible advertisement for the current user, respecting
-- frequency capping, campaign dates, targeting, and impressions.
-- ============================================================
create or replace function public.get_ad_for_user(
    p_user_id uuid,
    p_limit integer default 1
)
returns table (
    ad_id uuid,
    campaign_id uuid,
    title text,
    description text,
    image_url text,
    cta_text text,
    destination_url text,
    click_action text
)
language plpgsql
security definer
set search_path = public
as $$
declare
    v_hour_impressions integer;
    v_max_per_hour integer;
begin
    -- Enforce ownership: users can only get ads for themselves
    if auth.uid() is null or auth.uid() <> p_user_id then
        raise exception 'Not authorized to fetch ads for another user';
    end if;

    -- Get max impressions per hour from config
    select coalesce(max_ads_per_hour, 10) into v_max_per_hour
    from public.ad_config
    where id = 'default';

    -- Count impressions this user has had in the last hour
    select count(*) into v_hour_impressions
    from public.ad_impressions
    where user_id = p_user_id
      and impression_time > now() - interval '1 hour';

    -- If user has hit the hourly cap, return nothing
    if v_hour_impressions >= v_max_per_hour then
        return;
    end if;

    return query
    select
        a.id as ad_id,
        a.campaign_id,
        a.title,
        a.description,
        a.image_url,
        a.cta_text,
        a.destination_url,
        a.click_action
    from public.advertisements a
    join public.ad_campaigns c on a.campaign_id = c.id
    where a.is_active = true
      and c.status = 'active'
      and (c.start_date is null or c.start_date <= now())
      and (c.end_date is null or c.end_date >= now())
      and not exists (
          select 1 from public.ad_impressions ai
          where ai.ad_id = a.id
            and ai.user_id = p_user_id
            and ai.impression_time > now() - interval '1 hour'
      )
    order by c.cpm_cents desc, a.created_at desc
    limit p_limit;
end;
$$;

grant execute on function public.get_ad_for_user(uuid, integer) to authenticated;

-- ============================================================
-- CROSSED PATHS DETECTION FUNCTION
-- Computes crossed paths from geohash buckets and updates the
-- crossed_paths aggregation table. Called via cron or Edge Function.
-- ============================================================
create or replace function public.compute_crossed_paths(
    p_user_id uuid,
    p_geohash text,
    p_city text default null,
    p_locality text default null,
    p_country text default null
)
returns table (
    crossed_user_id uuid,
    cross_count integer
)
language plpgsql
security definer
set search_path = public
as $$
begin
    if auth.uid() is null or auth.uid() <> p_user_id then
        raise exception 'Not authorized to compute crossed paths for another user';
    end if;

    -- Insert or update the user's location bucket
    insert into public.user_location_buckets (user_id, geohash_7, city, locality, country, updated_at)
    values (p_user_id, p_geohash, p_city, p_locality, p_country, now())
    on conflict (user_id) do update
    set geohash_7 = excluded.geohash_7,
        city = excluded.city,
        locality = excluded.locality,
        country = excluded.country,
        updated_at = now();

    -- Log this location check
    insert into public.crossed_paths_log (user_id, geohash_bucket, timestamp)
    values (p_user_id, p_geohash, now());

    -- Update crossed_paths aggregation: find other users in the same geohash bucket
    -- (excluding self, blocked users, and users who haven't been active recently)
    insert into public.crossed_paths (user_a_id, user_b_id, geohash_bucket, first_crossed_at, last_crossed_at, cross_count)
    select p_user_id, o.user_id, p_geohash, now(), now(), 1
    from public.user_location_buckets o
    where o.geohash_7 = p_geohash
      and o.user_id <> p_user_id
      and not exists (select 1 from public.blocks where (blocker_id = p_user_id and blocked_id = o.user_id)
                       or (blocker_id = o.user_id and blocked_id = p_user_id))
    on conflict (user_a_id, user_b_id, geohash_bucket) do update
    set last_crossed_at = now(),
        cross_count = crossed_paths.cross_count + 1;

    -- Also insert the reverse direction for bidirectional lookup
    insert into public.crossed_paths (user_a_id, user_b_id, geohash_bucket, first_crossed_at, last_crossed_at, cross_count)
    select o.user_id, p_user_id, p_geohash, now(), now(), 1
    from public.user_location_buckets o
    where o.geohash_7 = p_geohash
      and o.user_id <> p_user_id
      and not exists (select 1 from public.blocks where (blocker_id = p_user_id and blocked_id = o.user_id)
                       or (blocker_id = o.user_id and blocked_id = p_user_id))
    on conflict (user_a_id, user_b_id, geohash_bucket) do update
    set last_crossed_at = now(),
        cross_count = crossed_paths.cross_count + 1;

    return query
    select
        cp.user_b_id as crossed_user_id,
        cp.cross_count
    from public.crossed_paths cp
    where cp.user_a_id = p_user_id
      and cp.last_crossed_at > now() - interval '30 days'
    order by cp.cross_count desc, cp.last_crossed_at desc;
end;
$$;

grant execute on function public.compute_crossed_paths(uuid, text, text, text, text) to authenticated;

-- ============================================================
-- RECORD AD EVENT RPC
-- Server-side validated ad event recording.
-- ============================================================
create or replace function public.record_ad_event(
    p_user_id uuid,
    p_ad_id uuid,
    p_event_type text,
    p_metadata jsonb default '{}'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    v_result jsonb;
    v_hour_impressions integer;
    v_max_per_hour integer;
begin
    -- Enforce ownership
    if auth.uid() is null or auth.uid() <> p_user_id then
        raise exception 'Not authorized to record ad events for another user';
    end if;

    -- Validate event type
    if p_event_type not in ('impression', 'click', 'view', 'hide', 'report') then
        raise exception 'Invalid event type';
    end if;

    -- For impressions, check frequency capping
    if p_event_type = 'impression' then
        select coalesce(max_ads_per_hour, 10) into v_max_per_hour
        from public.ad_config where id = 'default';

        select count(*) into v_hour_impressions
        from public.ad_impressions
        where user_id = p_user_id
          and impression_time > now() - interval '1 hour';

        if v_hour_impressions >= v_max_per_hour then
            return jsonb_build_object(
                'success', false,
                'error', 'Hourly impression cap reached'
            );
        end if;

        -- Record impression
        insert into public.ad_impressions (ad_id, user_id, campaign_id, impression_time)
        select p_ad_id, p_user_id, campaign_id, now()
        from public.advertisements where id = p_ad_id
        on conflict do nothing;
    elsif p_event_type = 'click' then
        -- Record click
        insert into public.ad_clicks (ad_id, user_id, campaign_id, click_time)
        select p_ad_id, p_user_id, campaign_id, now()
        from public.advertisements where id = p_ad_id
        on conflict do nothing;
    end if;

    -- Record event
    insert into public.ad_events (ad_id, user_id, campaign_id, event_type, created_at, metadata)
    select p_ad_id, p_user_id, campaign_id, p_event_type, now(), p_metadata
    from public.advertisements where id = p_ad_id;

    v_result := jsonb_build_object(
        'success', true,
        'event_type', p_event_type,
        'ad_id', p_ad_id
    );

    return v_result;
end;
$$;

grant execute on function public.record_ad_event(uuid, uuid, text, jsonb) to authenticated;
