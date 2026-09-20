-- Migration: 009_account_deletion_service_role.sql
-- Make server-side account deletion actually executable end-to-end.
--
-- Defect found while planning the live 2FA/deletion verification:
--   The `account-deletion` Edge Function calls this RPC with the
--   service-role key. Two stacked failures made every deletion fail:
--     1. 006 revoked EXECUTE from PUBLIC and only re-granted to
--        `authenticated`, so the service role had no permission to run
--        the function at all (PostgREST: permission denied).
--     2. `assert_self` raises whenever `auth.uid()` is null — which is
--        always the case for a service-role call (no user JWT sub claim).
--
--   The Edge Function already authenticates the caller's JWT and rejects
--   cross-account deletions (`authenticate()` + the
--   `authUserId !== userId` guard in index.ts), so permitting the service
--   role here does not weaken user-facing ownership enforcement: direct
--   authenticated callers are still bound by `assert_self`.
--
-- Contract after this migration:
--   * service_role may execute `delete_user_account` (Edge Function path)
--   * authenticated users may execute it only for their own id
--   * anon/public remain revoked (006 unchanged)

create or replace function public.delete_user_account(
    p_user_id uuid,
    p_reason text default 'user_request'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    v_result jsonb;
begin
    -- Ownership guard. The service role is a trusted backend caller (same
    -- pattern as `protect_profile_columns` in 005); the Edge Function has
    -- already verified the requester's JWT and self-ownership.
    if auth.role() <> 'service_role' then
        perform public.assert_self(p_user_id);
    end if;

    insert into public.moderation_events (user_id, action, reason, performed_by, created_at)
    values (p_user_id, 'delete', p_reason, p_user_id, now());

    delete from public.referrals where referrer_id = p_user_id;
    delete from public.referrals where referee_id = p_user_id;
    delete from public.verification_requests where user_id = p_user_id;
    delete from public.plans where creator_id = p_user_id;

    -- The profile, photos, matches, messages, blocks, reports, etc. are
    -- cascade-deleted via foreign key constraints (see 001_initial_schema).

    v_result := jsonb_build_object(
        'success', true,
        'user_id', p_user_id,
        'reason', p_reason,
        'deleted_at', now()
    );

    return v_result;
end;
$$;

-- 006 removed the default PUBLIC execute grant; the service role needs an
-- explicit grant for the Edge Function path. anon/public stay revoked.
grant execute on function public.delete_user_account(uuid, text) to service_role;
