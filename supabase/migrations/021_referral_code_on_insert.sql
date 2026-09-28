-- Migration: 021_referral_code_on_insert.sql
-- Guarantee that EVERY profiles row owns a referral code, including rows the
-- client inserts.
--
-- Why this exists
-- ---------------
-- Migration 017 established the invariant "every profile owns a stable,
-- unique referral code", and `handle_new_user` assigns one on
-- `auth.users` INSERT. But referral_code is NOT set by a trigger on
-- `public.profiles`, so any INSERT that does not come from that trigger
-- creates a row with a NULL code.
--
-- The Edit Profile recovery path introduced in this branch is exactly such
-- an INSERT. `saveProfileWithRecovery` (lib/repositories/profile_repository.dart)
-- re-creates a missing row with
--     INSERT INTO public.profiles (id, ...) VALUES (authId, ...)
-- and `buildProfilePayload` carries no referral_code. Because the auth
-- trigger does not fire on a direct profiles INSERT, the recovered row is
-- left with referral_code = NULL.
--
-- Independently verified on the live project (2026-09-28): after deleting a
-- profile row server-side and saving from the app, the row came back with
-- referral_code = NULL (it had been WKND-8C352EC95D). 1 of 9 profiles rows
-- carried a NULL code, and it was precisely the recovered one.
--
-- User-visible impact of a NULL code:
--   * Profile screen renders an empty "Referral Code" field, and its Copy
--     button silently does nothing (profile_screen.dart returns early on an
--     empty code);
--   * QRInviteScreen reports "No referral code available";
--   * invitations already shared under the old code stop resolving.
--
-- Fix: enforce the invariant at the table, not at each caller. A BEFORE
-- INSERT trigger fills a missing code using the same deterministic scheme as
-- 017 ('WKND-' || first 10 hex chars of the uuid), so the value is stable
-- and identical to what signup would have produced for that id.
--
-- Safety properties (deliberate):
--   * Idempotent: CREATE OR REPLACE + DROP TRIGGER IF EXISTS, and a
--     re-runnable backfill. Existing non-NULL codes are never overwritten, so
--     a code already shared in a QR invitation never changes.
--   * The code is derived from the row's OWN id, so a client cannot file a
--     code under another user.
--   * The trigger only ever fills a NULL/empty value; it never rewrites a
--     client-supplied code, and it never mutates any other column.
--   * RLS is untouched.

-- ============================================================
-- 1. Backfill any code-less rows that already exist
-- ============================================================
-- Reuses the 017 generator, which is itself idempotent and preserves any
-- code that is already present. It UPDATEs, so it cannot run inside a
-- BEFORE INSERT trigger; the trigger below therefore computes the value
-- itself. (Run as SELECT perform(...) per row: the Management API's query
-- endpoint rejects a bare UPDATE with no RETURNING clause.)

do $$
declare
    r record;
begin
    for r in
        select id from public.profiles
        where referral_code is null or referral_code = ''
    loop
        perform public.generate_referral_code(r.id);
    end loop;
end;
$$;

-- ============================================================
-- 2. Assign a code to any future profiles INSERT
-- ============================================================
create or replace function public.assign_referral_code_on_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    v_code text;
    v_try int := 0;
begin
    -- An explicitly supplied code always wins: never disturb a code that has
    -- already been shared with somebody.
    if new.referral_code is not null and new.referral_code <> '' then
        return new;
    end if;

    -- Deterministic and stable for a given id, so a retry produces the same
    -- code. Bounded retries guard the UNIQUE index on referral_code.
    loop
        v_code := 'WKND-' || upper(substr(replace(new.id::text, '-', ''), 1, 10));
        v_try := v_try + 1;

        exit when not exists (
            select 1 from public.profiles p where p.referral_code = v_code
        );
        exit when v_try > 20; -- unreachable in practice: 10 hex chars
    end loop;

    new.referral_code := v_code;
    return new;
end;
$$;

drop trigger if exists on_profile_referral_code on public.profiles;
create trigger on_profile_referral_code
    before insert on public.profiles
    for each row
    execute function public.assign_referral_code_on_insert();
