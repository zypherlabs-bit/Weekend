// get-photo-urls - signs short-lived URLs for profile photos.
//
// The profile-photos bucket is PRIVATE. Signed URLs are only produced for:
//   * photos with moderation_status = 'approved' (public profile photos), or
//   * the caller's own photos in any state
// Everything else is silently skipped. The caller's JWT is verified against
// Supabase Auth before any work happens.
import {serve} from 'https://deno.land/std@0.224.0/http/server.ts';
import {createClient} from 'https://esm.sh/@supabase/supabase-js@2.45.6';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const MAX_PATHS = 50;
const SIGNED_URL_TTL_SECONDS = 3600;

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', {headers: corsHeaders});
  }
  if (req.method !== 'POST') {
    return new Response(JSON.stringify({error: 'POST required'}), {
      status: 405,
      headers: {...corsHeaders, 'Content-Type': 'application/json'},
    });
  }

  try {
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
    );

    // Verify the caller's JWT.
    const authHeader = req.headers.get('Authorization') ?? '';
    if (!authHeader.startsWith('Bearer ')) {
      return new Response(JSON.stringify({error: 'Unauthorized'}), {
        status: 401,
        headers: {...corsHeaders, 'Content-Type': 'application/json'},
      });
    }
    const token = authHeader.replace('Bearer ', '');
    const {data: {user}, error: userError} = await supabase.auth.getUser(token);
    if (userError || !user) {
      return new Response(JSON.stringify({error: 'Unauthorized'}), {
        status: 401,
        headers: {...corsHeaders, 'Content-Type': 'application/json'},
      });
    }

    const {paths} = await req.json();
    if (!Array.isArray(paths) || paths.length === 0) {
      return new Response(JSON.stringify({urls: {}}), {
        headers: {...corsHeaders, 'Content-Type': 'application/json'},
      });
    }
    if (paths.length > MAX_PATHS) {
      return new Response(JSON.stringify({error: `At most ${MAX_PATHS} paths per request`}), {
        status: 400,
        headers: {...corsHeaders, 'Content-Type': 'application/json'},
      });
    }

    // Authorization: only approved photos or the caller's own photos.
    const {data: rows, error: dbError} = await supabase
      .from('profile_photos')
      .select('storage_path, user_id, moderation_status')
      .in('storage_path', paths);

    const allowed = new Map<string, boolean>();
    for (const row of rows ?? []) {
      if (!row.storage_path) continue;
      allowed.set(
        row.storage_path,
        row.moderation_status === 'approved' || row.user_id === user.id,
      );
    }

    const urls: Record<string, string> = {};
    for (const p of paths) {
      if (typeof p !== 'string' || !allowed.get(p)) continue;
      const {data, error} = await supabase.storage
        .from('profile-photos')
        .createSignedUrl(p, SIGNED_URL_TTL_SECONDS);
      if (!error && data?.signedUrl) {
        urls[p] = data.signedUrl;
      }
    }

    return new Response(JSON.stringify({urls}), {
      headers: {...corsHeaders, 'Content-Type': 'application/json'},
    });
  } catch (e) {
    return new Response(JSON.stringify({error: 'Internal error'}), {
      status: 500,
      headers: {...corsHeaders, 'Content-Type': 'application/json'},
    });
  }
});