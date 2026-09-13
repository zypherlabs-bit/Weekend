-- ============================================================
-- RLS Test Script for Advertisement Tables
-- Run this after applying migrations 007 and 008
-- Usage: psql $DATABASE_URL -f supabase/test/rls_test.sql
-- ============================================================

\echo '=== Testing Ad Table RLS Policies ==='

-- Test: Unauthenticated/anon users cannot access ad tables
\echo 'Test 1: Anon user cannot read ad_campaigns'
SELECT assert_false(
  EXISTS (
    SELECT 1 FROM ad_campaigns
    LIMIT 1
  ),
  'anon should not be able to read ad_campaigns'
);

\echo 'Test 2: Anon user cannot insert into ad_events'
INSERT INTO ad_events (user_id, ad_id, event_type)
VALUES ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000000000', 'impression')
ON CONFLICT DO NOTHING;

-- Verify no row was inserted
SELECT assert_false(
  EXISTS (
    SELECT 1 FROM ad_events
    WHERE user_id = '00000000-0000-0000-0000-000000000000'
  ),
  'anon should not be able to insert into ad_events'
);

-- Test: Authenticated user can only see their own ad events
\echo 'Test 3: Authenticated user can read their own ad_events'
-- This requires setting up an auth context first
-- In practice, this is tested via the Edge Function with a valid JWT

-- Test: get_ad_for_user RPC returns only active campaigns
\echo 'Test 4: get_ad_for_user returns active campaigns only'
-- SELECT * FROM get_ad_for_user('<user_id>')
-- Verify all returned ads have is_active = true in ad_campaigns

-- Test: record_ad_event enforces event type validation
\echo 'Test 5: record_ad_event validates event type'
-- SELECT record_ad_event('<user_id>', '<ad_id>', 'invalid_type')
-- Should return an error or no-op for invalid event types

-- Test: Crossed paths only visible to the involved user
\echo 'Test 6: User A cannot see User B crossed paths'
-- SELECT * FROM crossed_paths WHERE user_a_id = '<other_user_id>'
-- Should return empty

-- Test: User location buckets are not publicly readable
\echo 'Test 7: Anon cannot read user_location_buckets'
SELECT assert_false(
  EXISTS (
    SELECT 1 FROM user_location_buckets
    LIMIT 1
  ),
  'anon should not be able to read user_location_buckets'
);

-- Test: Service role can access all tables (for admin functions)
\echo 'Test 8: Service role can read ad_campaigns'
-- With service role JWT:
-- SELECT 1 FROM ad_campaigns LIMIT 1; -- Should succeed

-- Cleanup
ROLLBACK;

\echo '=== RLS Tests Complete ==='
