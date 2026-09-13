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
  const {data: {user}, error } = await supabase.auth.getUser(token);
  if (error || !user) return null;
  return user.id;
}

async function validateAdUrl(url: string): Promise<boolean> {
  try {
    const u = new URL(url);
    const allowedSchemes = ['https:', 'http:'];
    const allowedHosts = [
      'weekend.app', 'localhost', '127.0.0.1',
      'play.google.com', 'apps.apple.com',
      'github.com', 'wikipedia.org',
    ];
    if (!allowedSchemes.includes(u.protocol)) return false;
    if (!allowedHosts.some(h => u.hostname === h || u.hostname.endsWith('.' + h))) return false;
    return true;
  } catch {
    return false;
  }
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

    const authUserId = await authenticate(req, supabase);
    if (!authUserId) {
      return new Response(
        JSON.stringify({error: 'Unauthorized'}),
        {status: 401, headers: {...corsHeaders, 'Content-Type': 'application/json'}},
      );
    }

    const { action = 'fetch', userId, adId, eventData } = await req.json();

    // Enforce ownership for ad events
    if (userId && userId !== authUserId) {
      return new Response(
        JSON.stringify({error: 'Unauthorized: cannot act on another user\'s ads'}),
        {status: 403, headers: {...corsHeaders, 'Content-Type': 'application/json'}},
      );
    }

    const targetUserId = userId || authUserId;

    switch (action) {
      case 'fetch':
        return await handleFetchAd(supabase, targetUserId);

      case 'record_impression':
      case 'record_click':
      case 'record_report':
      case 'record_hide': {
        const eventType = action.replace('record_', '');
        return await handleRecordEvent(supabase, targetUserId, adId, eventType, eventData);
      }

      default:
        return new Response(
          JSON.stringify({error: 'Unknown action'}),
          {status: 400, headers: {...corsHeaders, 'Content-Type': 'application/json'}},
        );
    }
  } catch (error) {
    const err = error as Error;
    console.error('Ad function error:', err);
    return new Response(
      JSON.stringify({error: 'Internal server error', details: err.message}),
      {status: 500, headers: {...corsHeaders, 'Content-Type': 'application/json'}},
    );
  }
});

async function handleFetchAd(supabase: ReturnType<typeof createClient>, userId: string): Promise<Response> {
  const { data: ads, error } = await supabase.rpc('get_ad_for_user', {
    p_user_id: userId,
    p_limit: 1,
  });

  if (error) {
    console.error('Ad fetch RPC error:', error);
    return new Response(
      JSON.stringify({ads: [], source: 'error', error: error.message}),
      {status: 200, headers: {...corsHeaders, 'Content-Type': 'application/json'}},
    );
  }

  const adsList = (ads || []) as Array<{
    ad_id: string;
    campaign_id: string;
    title: string;
    description: string;
    image_url: string;
    cta_text: string;
    destination_url: string;
    click_action: string;
  }>;

  // Validate ad destinations server-side
  const validatedAds: typeof adsList = [];
  for (const ad of adsList) {
    if (await validateAdUrl(ad.destination_url)) {
      validatedAds.push(ad);
    } else {
      console.warn('Skipping ad with invalid destination URL:', ad.ad_id);
    }
  }

  // Fetch ad config
  const { data: config } = await supabase
    .from('ad_config')
    .select('ad_interval_seconds, ad_placeholder_text')
    .eq('id', 'default')
    .maybeSingle();

  return new Response(
    JSON.stringify({
      ads: validatedAds,
      adConfig: config || {ad_interval_seconds: 120, ad_placeholder_text: 'Sponsored'},
      source: 'supabase',
    }),
    {status: 200, headers: {...corsHeaders, 'Content-Type': 'application/json'}},
  );
}

async function handleRecordEvent(
  supabase: ReturnType<typeof createClient>,
  userId: string,
  adId: string,
  eventType: string,
  eventData: Record<string, unknown> | undefined,
): Promise<Response> {
  if (!adId) {
    return new Response(
      JSON.stringify({error: 'adId is required'}),
      {status: 400, headers: {...corsHeaders, 'Content-Type': 'application/json'}},
    );
  }

  const { data, error } = await supabase.rpc('record_ad_event', {
    p_user_id: userId,
    p_ad_id: adId,
    p_event_type: eventType,
    p_metadata: JSON.stringify(eventData || {}),
  });

  if (error) {
    console.error('Ad event recording error:', error);
    return new Response(
      JSON.stringify({success: false, error: error.message}),
      {status: 200, headers: {...corsHeaders, 'Content-Type': 'application/json'}},
    );
  }

  return new Response(
    JSON.stringify({success: true, result: data}),
    {status: 200, headers: {...corsHeaders, 'Content-Type': 'application/json'}},
  );
}
