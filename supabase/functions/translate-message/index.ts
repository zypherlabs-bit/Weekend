import {serve} from 'https://deno.land/std@0.224.0/http/server.ts';
import {createClient} from 'https://esm.sh/@supabase/supabase-js@2.45.6';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

async function authenticate(req: Request): Promise<string | null> {
  const authHeader = req.headers.get('Authorization');
  if (!authHeader?.startsWith('Bearer ')) return null;
  const token = authHeader.replace('Bearer ', '');
  const supabase = createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
  );
  const {data: {user}, error} = await supabase.auth.getUser(token);
  if (error || !user) return null;
  return user.id;
}

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', {headers: corsHeaders});
  }

  try {
    // Authenticate the caller
    const authUserId = await authenticate(req);
    if (!authUserId) {
      return new Response(
        JSON.stringify({error: 'Unauthorized'}),
        {status: 401, headers: {...corsHeaders, 'Content-Type': 'application/json'}},
      );
    }

    const apiKey = Deno.env.get('GEMINI_API_KEY');
    if (!apiKey) {
      return new Response(
        JSON.stringify({error: 'Gemini API key not configured'}),
        {status: 500, headers: {...corsHeaders, 'Content-Type': 'application/json'}},
      );
    }

    const {text, targetLanguage = 'English'} = await req.json();

    if (!text) {
      return new Response(
        JSON.stringify({error: 'text is required'}),
        {status: 400, headers: {...corsHeaders, 'Content-Type': 'application/json'}},
      );
    }

    const prompt = `Translate the following chat message accurately to ${targetLanguage}. Output ONLY the translated text without extra comments:\n\n${text}`;

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
      console.error('Gemini translation error:', errText);
      return new Response(
        JSON.stringify({translatedText: `[Translated to ${targetLanguage}]: ${text}`}),
        {status: 200, headers: {...corsHeaders, 'Content-Type': 'application/json'}},
      );
    }

    const data = await response.json();
    const translated = data.candidates?.[0]?.content?.parts?.[0]?.text || '';

    return new Response(
      JSON.stringify({
        translatedText: translated.trim().replace(/^["']|["']$/g, ''),
        source: 'gemini',
      }),
      {status: 200, headers: {...corsHeaders, 'Content-Type': 'application/json'}},
    );
  } catch (error) {
    const err = error as Error;
    console.error('Translation error:', err);
    const {text = ''} = await req.clone().json().catch(() => ({}));
    return new Response(
      JSON.stringify({translatedText: `[Translated]: ${text}`, source: 'fallback'}),
      {status: 200, headers: {...corsHeaders, 'Content-Type': 'application/json'}},
    );
  }
});
