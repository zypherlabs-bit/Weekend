-- Migration: 018_edit_profile_live_fixes.sql
-- Fix the two live Edit Profile failures that surface as a generic
-- "server error" / "unable to proceed":
--
--   1. PHOTO UPLOAD: `profile_photos` inserts need a matching row in
--      `profiles` (FK `user_id -> profiles.id`) and the client insert must
--      satisfy the `users can upload own photos` RLS check. Nothing here
--      loosens RLS; the grants below restate the least-privilege set the
--      app needs so a fresh project (migrations applied in order) allows:
--        * own-row SELECT on profile_photos (any moderation state, so the
--          just-uploaded photo renders immediately for its owner),
--        * INSERT/UPDATE/DELETE of own photo rows,
--        * the `moderation_status` default stays server-decided (011 trigger).
--
--   2. SAVE / "UNABLE TO PROCEED": `WeekendNotifier.updateProfile` writes
--      interests via direct `user_interests` DELETE + `interests` UPSERT +
--      `user_interests` INSERT. The RLS on `user_interests` only allowed the
--      owner path, but the `interests` master table had NO policy at all, so
--      every save with an interest selected failed and the screen never
--      advanced. The policies below let any authenticated user READ the
--      shared master list and INSERT new names (dedupe via the unique
--      constraint), while links in `user_interests` stay owner-only.
--      (The supported path remains the `set_user_interests` RPC from 005;
--      these policies only unblock the direct-write path the client uses.)
--
--   3. Fresh-project safety: re-assert the `profile-photos` bucket row and the
--      owner-folder storage policies with DROP IF EXISTS + CREATE so a
--      database that missed 004 (or had its policies edited in the dashboard)
--      still accepts `<uid>/...` uploads. No policy is widened: uploads stay
--      scoped to the caller's own folder.

-- ============================================================
-- 1. profile_photos: least-privilege grants for the app's flow
-- ============================================================
grant select, insert, update, delete on public.profile_photos to authenticated;
grant usage, select on all sequences in schema public to authenticated;

-- ============================================================
-- 2. interests master list: readable + extendable by signed-in users
-- ============================================================
alter table public.interests enable row level security;

drop policy if exists "authenticated users can read interests"
    on public.interests;
create policy "authenticated users can read interests"
    on public.interests
    for select
    using (auth.uid() is not null);

drop policy if exists "authenticated users can add interests"
    on public.interests;
create policy "authenticated users can add interests"
    on public.interests
    for insert
    with check (auth.uid() is not null);

grant select, insert on public.interests to authenticated;

-- user_interests links stay owner-only (restated, not widened).
grant select, insert, update, delete on public.user_interests to authenticated;

-- ============================================================
-- 3. Storage bucket + owner-folder policies (idempotent re-assert)
-- ============================================================
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'profile-photos',
  'profile-photos',
  false,
  10485760,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "Users can upload to own profile folder"
    on storage.objects;
create policy "Users can upload to own profile folder"
    on storage.objects for insert
    with check (
      bucket_id = 'profile-photos'
      and auth.uid()::text = (storage.foldername(name))[1]
    );

drop policy if exists "Users can read approved profile photos"
    on storage.objects;
create policy "Users can read approved profile photos"
    on storage.objects for select
    using (
      bucket_id = 'profile-photos'
      and (
        exists (
          select 1 from public.profile_photos pp
          where pp.storage_path = name
          and pp.moderation_status = 'approved'
        )
        or auth.uid()::text = (storage.foldername(name))[1]
      )
    );

drop policy if exists "Users can update own profile photos"
    on storage.objects;
create policy "Users can update own profile photos"
    on storage.objects for update
    using (
      bucket_id = 'profile-photos'
      and auth.uid()::text = (storage.foldername(name))[1]
    );

drop policy if exists "Users can delete own profile photos"
    on storage.objects;
create policy "Users can delete own profile photos"
    on storage.objects for delete
    using (
      bucket_id = 'profile-photos'
      and auth.uid()::text = (storage.foldername(name))[1]
    );
