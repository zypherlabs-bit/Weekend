-- Migration: 005_security_hardening.sql
-- Hardening pass: protect admin-controlled columns, add columns required by
-- the client data layer, and add interest helper functions.

-- ============================================================
-- ADD MISSING COLUMNS
-- ============================================================
-- profiles.is_photo_verified: denormalized flag read by discovery/match RPCs.
alter table public.profiles
    add column if not exists is_photo_verified boolean not null default false;

-- profiles.referral_code: unique public code used for the referral program.
alter table public.profiles
    add column if not exists referral_code text;

create unique index if not exists idx_profiles_referral_code
    on public.profiles(referral_code)
    where referral_code is not null;

-- Keep the denormalized verification flag in sync with verification_status.
create or replace function public.sync_photo_verified()
returns trigger as $$
begin
    new.is_photo_verified := (new.verification_status = 'verified');
    return new;
end;
$$ language plpgsql;

drop trigger if exists on_verification_change on public.profiles;
create trigger on_verification_change
    before update of verification_status on public.profiles
    for each row
    execute function public.sync_photo_verified();

-- ============================================================
-- PROTECT ADMIN/MODERATION-CONTROLLED COLUMNS
-- Clients must never be able to write verification status, trust score,
-- or profile completion. Only the service role (Edge Functions / backend
-- pipelines) may change them.
-- ============================================================
create or replace function public.protect_profile_columns()
returns trigger as $$
begin
    -- Service role (trusted backend) is always allowed.
    if auth.role() = 'service_role' or auth.uid() is null then
        return new;
    end if;

    if new.verification_status is distinct from old.verification_status
       or new.trust_score is distinct from old.trust_score
       or new.profile_completion is distinct from old.profile_completion then
        raise exception 'verification_status, trust_score and profile_completion can only be modified by the backend';
    end if;

    return new;
end;
$$ language plpgsql security definer;

drop trigger if exists on_profile_column_protection on public.profiles;
create trigger on_profile_column_protection
    before update on public.profiles
    for each row
    execute function public.protect_profile_columns();

-- ============================================================
-- INTERESTS HELPER FUNCTIONS
-- ============================================================
create or replace function public.get_user_interests(
    p_user_id uuid
)
returns table (
    name text
)
language sql
stable
as $$
    select i.name
    from public.user_interests ui
    join public.interests i on ui.interest_id = i.id
    where ui.user_id = p_user_id;
$$;

create or replace function public.set_user_interests(
    p_user_id uuid,
    p_interests text[]
)
returns void
language plpgsql
security definer
as $$
begin
    -- Ensure the caller is only modifying their own interests.
    if auth.uid() is null or auth.uid() <> p_user_id then
        raise exception 'Not allowed to modify interests of another user';
    end if;

    delete from public.user_interests where user_id = p_user_id;

    insert into public.interests (name)
    select unnest(p_interests)
    on conflict (name) do nothing;

    insert into public.user_interests (user_id, interest_id)
    select p_user_id, i.id
    from public.interests i
    where i.name = any(p_interests)
    on conflict do nothing;
end;
$$;

grant execute on function public.get_user_interests(uuid) to authenticated;
grant execute on function public.set_user_interests(uuid, text[]) to authenticated;
