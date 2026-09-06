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
    const apiKey = Deno.env.get('GEMINI_API_KEY');
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
    );

    // Authenticate the caller (icebreaker is a trusted-user feature)
    const authUserId = await authenticate(req, supabase);
    if (!authUserId) {
      return new Response(
        JSON.stringify({error: 'Unauthorized'}),
        {status: 401, headers: {...corsHeaders, 'Content-Type': 'application/json'}},
      );
    }

    if (!apiKey) {
      return new Response(
        JSON.stringify({error: 'Gemini API key not configured'}),
        {status: 500, headers: {...corsHeaders, 'Content-Type': 'application/json'}},
      );
    }

    const {userName, matchName, sharedInterests = [], favoritePlace = 'cafe'} = await req.json();

    if (!userName || !matchName) {
      return new Response(
        JSON.stringify({error: 'userName and matchName are required'}),
        {status: 400, headers: {...corsHeaders, 'Content-Type': 'application/json'}},
      );
    }

    const interests = sharedInterests as string[];
    if (interests.length === 0) {
      return new Response(
        JSON.stringify({
          text: `Ask ${matchName} about their ideal weekend adventure or their go-to coffee spot!`,
          source: 'fallback',
        }),
        {status: 200, headers: {...corsHeaders, 'Content-Type': 'application/json'}},
      );
    }

    const prompt = `Generate ONE short, friendly, fun, natural conversation starter (max 2 sentences) for a dating/social app called Weekend.
User 1: ${userName}
User 2: ${matchName}
Shared Interests: ${interests.join(', ')}
Favorite Place: ${favoritePlace}
Make it specific and engaging without being cheesy.`;

    const response = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=${apiKey}`,
      {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({
          contents: [{parts: [{text: prompt}]}],
        }),
      },
    );

    if (!response.ok) {
      const errText = await response.text();
      console.error('Gemini API error:', errText);
      const fallbackText = `You both love ${interests[0] || 'making weekend plans'}! Ask ${matchName} what got them into it or their favorite spot for it.`;
      return new Response(
        JSON.stringify({text: fallbackText, source: 'fallback'}),
        {status: 200, headers: {...corsHeaders, 'Content-Type': 'application/json'}},
      );
    }

    const data = await response.json();
    const text = data.candidates?.[0]?.content?.parts?.[0]?.text || '';

    if (!text) {
      const fallbackText = `You both love ${interests[0] || 'hanging out'}! Ask ${matchName} about their favorite weekend spot.`;
      return new Response(
        JSON.stringify({text: fallbackText, source: 'fallback'}),
        {status: 200, headers: {...corsHeaders, 'Content-Type': 'application/json'}},
      );
    }

    return new Response(
      JSON.stringify({text: text.trim().replace(/^["']|["']$/g, ''), source: 'gemini'}),
      {status: 200, headers: {...corsHeaders, 'Content-Type': 'application/json'}},
    );
  } catch (error) {
    const err = error as Error;
    console.error('Icebreaker generation error:', err);
    return new Response(
      JSON.stringify({text: 'Ask them about their favorite weekend adventure!', source: 'fallback'}),
      {status: 200, headers: {...corsHeaders, 'Content-Type': 'application/json'}},
    );
  }
});
