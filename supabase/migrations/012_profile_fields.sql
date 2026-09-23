-- Migration: 012_profile_fields.sql
-- Add profile display fields the client data layer reads and edits.
--
-- Live verification: ProfileRepository.fetchUserProfile selects
-- occupation/education/favorite_music/ideal_weekend, but no migration ever
-- created those columns, so every profile fetch failed with
-- "column profiles.occupation does not exist" and the Profile screen had
-- no data. Edit Profile writes the music/weekend fields as well.

alter table public.profiles
    add column if not exists occupation text not null default '',
    add column if not exists education text not null default '',
    add column if not exists favorite_music text not null default '',
    add column if not exists ideal_weekend text not null default '';

-- Extend the 006 least-privilege grants with the new columns (column-level
-- grants are additive). Everything not listed here stays backend-only.
grant select (occupation, education, favorite_music, ideal_weekend)
    on public.profiles to authenticated;
grant update (occupation, education, favorite_music, ideal_weekend)
    on public.profiles to authenticated;