import {serve} from 'https://deno.land/std@0.224.0/http/server.ts';
import {createClient} from 'https://esm.sh/@supabase/supabase-js@2.45.6';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

async function authenticate(req: Request, supabase: ReturnType<typeof createClient>): Promise<string | null> {
  const authHeader = req.headers.get('Authorization');
  if (!authHeader?.startsWith('Bearer ')) return null;
  const token = authHeader.replace('Bearer ', '');
  const {data: {user}, error} = await supabase.auth.getUser(token);
  if (error || !user) return null;
  return user.id;
}

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', {headers: corsHeaders});
  }

  try {
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
    );

    const {userId, password, reason = 'user_request'} = await req.json();

    if (!userId) {
      return new Response(
        JSON.stringify({error: 'userId is required'}),
        {status: 400, headers: {...corsHeaders, 'Content-Type': 'application/json'}},
      );
    }

    // SECURITY: Verify the authenticated user is deleting their own account
    const authUserId = await authenticate(req, supabase);
    if (!authUserId || authUserId !== userId) {
      return new Response(
        JSON.stringify({error: 'Unauthorized: cannot delete another user\'s account'}),
        {status: 403, headers: {...corsHeaders, 'Content-Type': 'application/json'}},
      );
    }

    // Step 1: Call the secure database function to clean up all user data
    // (profiles, photos, matches, messages, blocks, reports, referrals, etc.)
    const {data: cleanupData, error: cleanupError } = await supabase.rpc(
      'delete_user_account',
      {p_user_id: userId, p_reason: reason},
    );

    if (cleanupError) {
      console.error('Failed to clean up user data:', cleanupError);
      return new Response(
        JSON.stringify({
          success: false,
          error: 'Failed to clean up user data',
          details: cleanupError.message,
        }),
        {status: 500, headers: {...corsHeaders, 'Content-Type': 'application/json'}},
      );
    }

    // Step 2: Delete the user from auth.users (requires service role)
    const { error: deleteAuthError } = await supabase.auth.admin.deleteUser(userId);

    if (deleteAuthError) {
      console.error('Failed to delete auth user:', deleteAuthError);
      return new Response(
        JSON.stringify({
          success: false,
          error: 'Failed to delete authentication account',
          details: deleteAuthError.message,
        }),
        {status: 500, headers: {...corsHeaders, 'Content-Type': 'application/json'}},
      );
    }

    // Step 3: Delete all files from profile-photos bucket for this user
    try {
      const { data: files, error: listError } = await supabase
        .storage
        .from('profile-photos')
        .list(userId + '/', {limit: 1000});

      if (!listError && files) {
        const filePaths = files.map(f => `${userId}/${f.name}`);
        if (filePaths.length > 0) {
          await supabase.storage.from('profile-photos').remove(filePaths);
        }
      }
    } catch (e) {
      console.warn('Could not delete storage files:', e);
    }

    // Step 4: Invalidate user sessions
    const { error: revokeError } = await supabase.auth.admin
      .signOutAllSessions(userId);

    if (revokeError) {
      console.warn('Failed to revoke sessions:', revokeError);
    }

    return new Response(
      JSON.stringify({
        success: true,
        userId,
        message: 'Account deleted successfully',
        cleanedUp: cleanupData,
      }),
      {status: 200, headers: {...corsHeaders, 'Content-Type': 'application/json'}},
    );
  } catch (error) {
    const err = error as Error;
    console.error('Account deletion error:', err);
    return new Response(
      JSON.stringify({
        success: false,
        error: 'Unexpected error during account deletion',
        details: err.message,
      }),
      {status: 500, headers: {...corsHeaders, 'Content-Type': 'application/json'}},
    );
  }
});
