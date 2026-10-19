-- 036 — Harden EXECUTE grants on internal helper functions (finding F2)
--
-- Every function in this file was reachable with the public anon key, and four
-- of them were also reachable by any signed-in user. None of them is a client
-- entry point:
--
--   * get_user_interests       — IS a client RPC (lib/repositories/
--                                discovery_repository.dart), so `authenticated`
--                                keeps EXECUTE and only anon/PUBLIC lose it.
--   * approved_photo_count     — called from search_profiles (023).
--   * has_feature_entitlement  — called from activate_spotlight,
--                                set_privacy_mode, set_travel_location (031)
--                                and record_like (032).
--   * mfa_recovery_code_hash   — called from consume_mfa_recovery_code (025).
--   * tmp_probe_dollar         — debris from an earlier probe; nothing calls it.
--
-- The four internal helpers are only ever called from SECURITY DEFINER
-- functions, which execute as the owner (`postgres`), so revoking EXECUTE from
-- anon/PUBLIC/authenticated does not affect any legitimate call path: the owner
-- keeps its own grant and the inner call never runs as the caller.
--
-- mfa_recovery_code_hash is the one that matters most. It is a hashing oracle:
-- `select public.mfa_recovery_code_hash('<any uid>', '<guess>')` let anyone
-- holding the public anon key (or any signed-in account) test recovery-code
-- guesses against an arbitrary user without ever touching that user's session.
-- The account it protects belongs to the person it is being attacked; the
-- exposure was live and is confirmed in the audit document.
--
-- This migration changes no behaviour a client can observe: the client calls
-- get_user_interests, mfa_recovery_code_count and consume_mfa_recovery_code,
-- and all three keep working.

-- 1. Client RPC: drop anon/PUBLIC, keep authenticated.
revoke all on function public.get_user_interests(uuid) from public, anon;

-- 2. Internal helpers: keep only the owner and service_role.
revoke all on function public.approved_photo_count(uuid)
    from public, anon, authenticated;

revoke all on function public.has_feature_entitlement(uuid, text)
    from public, anon, authenticated;

revoke all on function public.mfa_recovery_code_hash(uuid, text)
    from public, anon, authenticated;

-- 3. Debris from an earlier live probe. Nothing references it (verified against
--    the live catalog before writing this migration).
drop function if exists public.tmp_probe_dollar();

-- Re-affirm the grant the client actually needs, so this migration is the last
-- word on it regardless of how the earlier grants drifted.
grant execute on function public.get_user_interests(uuid) to authenticated;
grant execute on function public.get_user_interests(uuid) to service_role;
