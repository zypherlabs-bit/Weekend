-- Migration: 004_storage_policies.sql
-- Storage bucket policies for profile photos

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'profile-photos',
  'profile-photos',
  false,
  10485760,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict do nothing;

-- Allow users to upload files to their own folder
create policy "Users can upload to own profile folder"
  on storage.objects for insert
  with check (
    bucket_id = 'profile-photos'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

-- Allow users to read approved photos (public thumbnails are served via CDN)
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

-- Allow users to update their own photos
create policy "Users can update own profile photos"
  on storage.objects for update
  using (
    bucket_id = 'profile-photos'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

-- Allow users to delete their own photos
create policy "Users can delete own profile photos"
  on storage.objects for delete
  using (
    bucket_id = 'profile-photos'
    and auth.uid()::text = (storage.foldername(name))[1]
  );
