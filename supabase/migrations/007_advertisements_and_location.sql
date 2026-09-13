-- Migration: 007_advertisements_and_location.sql
-- Advertisement system, crossed-paths tracking, geohash buckets, and discovery config.

-- ============================================================
-- GEOHASH / LOCATION PRIVACY EXTENSION
-- ============================================================
create extension if not exists "uuid-ossp";

-- ============================================================
-- ADVERTISEMENT CAMPAIGNS TABLE
-- ============================================================
create table public.ad_campaigns (
    id uuid primary key default uuid_generate_v4(),
    name text not null,
    advertiser_id uuid,
    target_country text,
    target_city text,
    target_geohash text,
    start_date timestamptz,
    end_date timestamptz,
    budget_cents integer default 0,
    spent_cents integer default 0,
    max_impressions integer default 0,
    status text check (status in ('active', 'paused', 'completed', 'draft')) default 'draft',
    frequency_capping integer default 3,
    cpm_cents integer default 10,
    created_at timestamptz default now(),
    updated_at timestamptz default now()
);

-- ============================================================
-- ADVERTISEMENTS TABLE
-- ============================================================
create table public.advertisements (
    id uuid primary key default uuid_generate_v4(),
    campaign_id uuid references public.ad_campaigns(id) on delete cascade,
    title text not null,
    description text,
    image_url text not null,
    image_width integer,
    image_height integer,
    cta_text text default 'Learn More',
    destination_url text not null,
    click_action text check (click_action in ('external_url', 'deep_link', 'internal_page')) default 'external_url',
    is_active boolean default true,
    created_at timestamptz default now(),
    updated_at timestamptz default now()
);

-- ============================================================
-- AD IMPRESSIONS TABLE
-- ============================================================
create table public.ad_impressions (
    id uuid primary key default uuid_generate_v4(),
    ad_id uuid references public.advertisements(id) on delete cascade,
    user_id uuid references public.profiles(id) on delete cascade,
    campaign_id uuid references public.ad_campaigns(id) on delete cascade,
    impression_time timestamptz default now(),
    unique (ad_id, user_id, date_trunc('hour', impression_time))
);

-- ============================================================
-- AD CLICKS TABLE
-- ============================================================
create table public.ad_clicks (
    id uuid primary key default uuid_generate_v4(),
    ad_id uuid references public.advertisements(id) on delete cascade,
    user_id uuid references public.profiles(id) on delete cascade,
    campaign_id uuid references public.ad_campaigns(id) on delete cascade,
    click_time timestamptz default now()
);

-- ============================================================
-- AD EVENTS TABLE (general events log)
-- ============================================================
create table public.ad_events (
    id uuid primary key default uuid_generate_v4(),
    ad_id uuid references public.advertisements(id) on delete cascade,
    user_id uuid references public.profiles(id) on delete cascade,
    campaign_id uuid references public.ad_campaigns(id) on delete cascade,
    event_type text check (event_type in ('impression', 'click', 'view', 'hide', 'report')),
    created_at timestamptz default now(),
    metadata jsonb
);

-- ============================================================
-- AD CONFIG TABLE (server-side frequency settings)
-- ============================================================
create table public.ad_config (
    id text primary key,
    ad_interval_seconds integer default 120 check (ad_interval_seconds >= 10),
    max_ads_per_hour integer default 10,
    ad_placeholder_text text default 'Sponsored',
    is_advertising_enabled boolean default true,
    updated_at timestamptz default now()
);

insert into public.ad_config (id, ad_interval_seconds, max_ads_per_hour)
values ('default', 120, 10)
on conflict (id) do nothing;

-- ============================================================
-- CROSSED PATHS TABLE (enhanced for privacy-safe co-location)
-- ============================================================
-- Store geohash buckets (not exact coordinates) for privacy-safe crossed paths.
-- A geohash bucket is an area of approximately 5km x 5km.
create table public.crossed_paths (
    id uuid primary key default uuid_generate_v4(),
    user_a_id uuid references public.profiles(id) on delete cascade,
    user_b_id uuid references public.profiles(id) on delete cascade,
    geohash_bucket text not null,
    first_crossed_at timestamptz default now(),
    last_crossed_at timestamptz default now(),
    cross_count integer default 1,
    created_at timestamptz default now(),
    unique (user_a_id, user_b_id, geohash_bucket)
);

-- ============================================================
-- CROSSED PATHS LOG (append-only, for aggregation only
-- ============================================================
create table public.crossed_paths_log (
    id uuid primary key default uuid_generate_v4(),
    user_id uuid references public.profiles(id) on delete cascade,
    geohash_bucket text not null,
    timestamp timestamptz default now()
);

create index idx_crossed_paths_log_user_time on public.crossed_paths_log(user_id, timestamp desc);
create index idx_crossed_paths_log_bucket on public.crossed_paths_log(geohash_bucket, timestamp desc);

-- ============================================================
-- USER LOCATION BUCKETS (privacy-safe geohash storage)
-- ============================================================
-- Instead of storing exact lat/lon for crossed-paths, we store
-- a geohash bucket. The profiles table still has raw latitude/longitude
-- for distance queries, but crossed paths is computed from buckets.
create table public.user_location_buckets (
    id uuid primary key default uuid_generate_v4(),
    user_id uuid unique references public.profiles(id) on delete cascade,
    geohash_7 text not null,
    city text,
    locality text,
    country text,
    updated_at timestamptz default now()
);

create index idx_user_location_buckets_geohash on public.user_location_buckets(geohash_7);
create index idx_user_location_buckets_city on public.user_location_buckets(city);

-- ============================================================
-- INDEXES
-- ============================================================

-- Ad campaigns indexes
create index if not exists idx_ad_campaigns_active on public.ad_campaigns(status) where status = 'active';
create index if not exists idx_ad_campaigns_date on public.ad_campaigns(start_date, end_date);

-- Advertisements indexes
create index if not exists idx_advertisements_campaign on public.advertisements(campaign_id);
create index if not exists idx_advertisements_active on public.advertisements(is_active) where is_active = true;

-- Ad impressions indexes
create index if not exists idx_ad_impressions_user_time on public.ad_impressions(user_id, impression_time desc);
create index if not exists idx_ad_impressions_ad_time on public.ad_impressions(ad_id, impression_time desc);
create index if not exists idx_ad_impressions_hour on public.ad_impressions(date_trunc('hour', impression_time));

-- Ad clicks indexes
create index if not exists idx_ad_clicks_user_time on public.ad_clicks(user_id, click_time desc);

-- Ad events indexes
create index if not exists idx_ad_events_time on public.ad_events(created_at desc);
create index if not exists idx_ad_events_user on public.ad_events(user_id, created_at desc);

-- Crossed paths indexes
create index if not exists idx_crossed_paths_user_a on public.crossed_paths(user_a_id);
create index if not exists idx_crossed_paths_user_b on public.crossed_paths(user_b_id);
create index if not exists idx_crossed_paths_bucket on public.crossed_paths(geohash_bucket);
create index if not exists idx_crossed_paths_last_crossed on public.crossed_paths(last_crossed_at desc);

-- Update trigger for timestamps
create or replace function public.update_ad_updated_at()
returns trigger as $$
begin
    new.updated_at = now();
    return new;
end;
$$ language plpgsql;

create trigger ad_campaigns_updated_at_trigger
    before update on public.ad_campaigns
    for each row
    execute function public.update_ad_updated_at();

create trigger advertisements_updated_at_trigger
    before update on public.advertisements
    for each row
    execute function public.update_ad_updated_at();

create trigger ad_config_updated_at_trigger
    before update on public.ad_config
    for each row
    execute function public.update_ad_updated_at();
