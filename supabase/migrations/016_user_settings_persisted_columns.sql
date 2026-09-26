-- Migration: 016_user_settings_persisted_columns.sql
-- Persist the settings the app already claims to save.
--
-- Root cause this fixes
-- ---------------------
-- `WeekendNotifier.updateProfile` finishes with
--
--     client.from('user_settings')
--          .upsert({'user_id': ..., 'weekend_availability': ...});
--
-- but `user_settings` (migration 001) has no `weekend_availability` column and
-- no later migration added one. PostgREST therefore answered every Edit Profile
-- save with `42703 column "weekend_availability" of relation "user_settings"
-- does not exist`.
--
-- Because that upsert ran *after* the `profiles` UPDATE and inside the same
-- try/catch that rethrows, the screen showed "Failed to save your profile" and
-- never advanced even though the name and city had been written correctly.
-- That is exactly the reported "Edit Profile does nothing" symptom.
--
-- The same gap made these UI toggles pure in-memory state that reported
-- "Settings saved" while persisting nothing across a restart:
--   * Location Settings  - location discovery, nearby discovery, show
--                          distance, travel mode, crossed paths
--   * Safety Center      - read receipts
--
-- All of them are ordinary user-owned preference flags, so they live on the
-- existing per-user `user_settings` row (unique on user_id) with the same RLS
-- model as the rest of that table: "users can manage own settings" already
-- restricts every statement to auth.uid() = user_id.
--
-- No RLS is loosened and no policy is weakened by this migration.

-- ============================================================
-- 1. Columns the client already writes
-- ============================================================
alter table public.user_settings
    add column if not exists weekend_availability jsonb not null default '{}'::jsonb;

-- Location Settings screen toggles (previously memory-only).
alter table public.user_settings
    add column if not exists location_discovery_enabled boolean not null default true;

alter table public.user_settings
    add column if not exists nearby_discovery_enabled boolean not null default true;

alter table public.user_settings
    add column if not exists show_distance_enabled boolean not null default true;

alter table public.user_settings
    add column if not exists travel_mode_enabled boolean not null default false;

alter table public.user_settings
    add column if not exists crossed_paths_enabled boolean not null default true;

-- Safety Center toggle.
alter table public.user_settings
    add column if not exists read_receipts_enabled boolean not null default true;

-- ============================================================
-- 2. Backfill: existing rows pick up the defaults above automatically
--    (add column ... default ... is a constant default, so no rewrite
--    statement is required).
-- ============================================================

-- ============================================================
-- 3. Grants
-- ============================================================
-- user_settings was never column-restricted, so `authenticated` keeps its
-- existing table-level privileges. These are re-stated so the intent is
-- explicit and survives a future column-level grant pass.
grant select, update on public.user_settings to authenticated;

-- ============================================================
-- 4. Safety: the JSON shape the client writes
-- ============================================================
-- `weekend_availability` is {"Saturday": true, "Sunday": false}. Restrict the
-- stored object to that shape so a malformed payload cannot reach the app and
-- break the Availability chips.
alter table public.user_settings
    drop constraint if exists user_settings_weekend_availability_shape;

alter table public.user_settings
    add constraint user_settings_weekend_availability_shape
    check (
        weekend_availability is null
        or (
            jsonb_typeof(weekend_availability) = 'object'
            and weekend_availability <@ '{"Saturday": true, "Sunday": true}'::jsonb
        )
    );
