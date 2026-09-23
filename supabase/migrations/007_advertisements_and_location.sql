-- Migration: 007_advertisements_and_location.sql
-- Advertisement system, crossed-paths tracking, geohash buckets, and discovery config.

-- ============================================================
-- GEOHASH / LOCATION PRIVACY EXTENSION
-- ============================================================
create extension if not exists "uuid-ossp";

-- ============================================================
-- ADVERTISEMENT CAMPAIGNS TABLE
-- ============================================================
create table if not exists public.ad_campaigns (
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
create table if not exists public.advertisements (
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
-- NOTE: the original `unique (ad_id, user_id, date_trunc('hour', ...))`
-- table constraint was invalid Postgres (expressions are not allowed in
-- UNIQUE constraints, and date_trunc on timestamptz is not IMMUTABLE).
-- Per-user hourly dedupe is enforced in record_ad_event with an anti-join.
create table if not exists public.ad_impressions (
    id uuid primary key default uuid_generate_v4(),
    ad_id uuid references public.advertisements(id) on delete cascade,
    user_id uuid references public.profiles(id) on delete cascade,
    campaign_id uuid references public.ad_campaigns(id) on delete cascade,
    impression_time timestamptz default now()
);

-- ============================================================
-- AD CLICKS TABLE
-- ============================================================
create table if not exists public.ad_clicks (
    id uuid primary key default uuid_generate_v4(),
    ad_id uuid references public.advertisements(id) on delete cascade,
    user_id uuid references public.profiles(id) on delete cascade,
    campaign_id uuid references public.ad_campaigns(id) on delete cascade,
    click_time timestamptz default now()
);

-- ============================================================
-- AD EVENTS TABLE (general events log)
-- ============================================================
create table if not exists public.ad_events (
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
create table if not exists public.ad_config (
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
-- CROSSED PATHS (upgrade the table created in 001 for privacy-safe
-- co-location) - geohash bucket is an area of approximately 5km x 5km.
-- ============================================================
-- 001 created crossed_paths without the geohash bucket; extend it instead
-- of creating a duplicate table.
alter table public.crossed_paths add column if not exists geohash_bucket text;

-- Widen the uniqueness from (user_a_id, user_b_id) to include the bucket.
do $$
begin
    if not exists (
        select 1 from pg_constraint
        where conname = 'crossed_paths_user_bucket_key'
    ) then
        alter table public.crossed_paths
            drop constraint if exists crossed_paths_user_a_id_user_b_id_key;
        alter table public.crossed_paths
            add constraint crossed_paths_user_bucket_key
            unique (user_a_id, user_b_id, geohash_bucket);
    end if;
end $$;

-- ============================================================
-- CROSSED PATHS LOG (append-only, for aggregation only
-- ============================================================
create table if not exists public.crossed_paths_log (
    id uuid primary key default uuid_generate_v4(),
    user_id uuid references public.profiles(id) on delete cascade,
    geohash_bucket text not null,
    timestamp timestamptz default now()
);

create index if not exists idx_crossed_paths_log_user_time on public.crossed_paths_log(user_id, timestamp desc);
create index if not exists idx_crossed_paths_log_bucket on public.crossed_paths_log(geohash_bucket, timestamp desc);

-- ============================================================
-- USER LOCATION BUCKETS (privacy-safe geohash storage)
-- ============================================================
-- Instead of storing exact lat/lon for crossed-paths, we store
-- a geohash bucket. The profiles table still has raw latitude/longitude
-- for distance queries, but crossed paths is computed from buckets.
create table if not exists public.user_location_buckets (
    id uuid primary key default uuid_generate_v4(),
    user_id uuid unique references public.profiles(id) on delete cascade,
    geohash_7 text not null,
    city text,
    locality text,
    country text,
    updated_at timestamptz default now()
);

create index if not exists idx_user_location_buckets_geohash on public.user_location_buckets(geohash_7);
create index if not exists idx_user_location_buckets_city on public.user_location_buckets(city);

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

-- Update trigger for timestamps (drop-guarded for idempotent re-runs)
create or replace function public.update_ad_updated_at()
returns trigger as $$
begin
    new.updated_at = now();
    return new;
end;
$$ language plpgsql;

drop trigger if exists ad_campaigns_updated_at_trigger on public.ad_campaigns;
create trigger ad_campaigns_updated_at_trigger
    before update on public.ad_campaigns
    for each row
    execute function public.update_ad_updated_at();

drop trigger if exists advertisements_updated_at_trigger on public.advertisements;
create trigger advertisements_updated_at_trigger
    before update on public.advertisements
    for each row
    execute function public.update_ad_updated_at();

drop trigger if exists ad_config_updated_at_trigger on public.ad_config;
create trigger ad_config_updated_at_trigger
    before update on public.ad_config
    for each row
    execute function public.update_ad_updated_at();
