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

    const {messageId, targetLanguage = 'English'} = await req.json();

    if (!messageId) {
      return new Response(
        JSON.stringify({error: 'messageId is required'}),
        {status: 400, headers: {...corsHeaders, 'Content-Type': 'application/json'}},
      );
    }

    // Fetch the message text from the database using the service role.
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
    );

    const { data: messageData, error: fetchError } = await supabase
      .from('messages')
      .select('text')
      .eq('id', messageId)
      .single();

    if (fetchError || !messageData) {
      console.error('Failed to fetch message:', fetchError?.message);
      return new Response(
        JSON.stringify({error: 'Message not found'}),
        {status: 404, headers: {...corsHeaders, 'Content-Type': 'application/json'}},
      );
    }

    const text = messageData.text;
    if (!text) {
      return new Response(
        JSON.stringify({error: 'Message has no text'}),
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

    const cleanText = translated.trim().replace(/^["']|["']$/g, '');

    // Persist the translation so it streams to all participants via Realtime.
    await supabase
      .from('messages')
      .update({
        translated_text: cleanText,
        is_translated: true,
      })
      .eq('id', messageId);

    return new Response(
      JSON.stringify({
        translatedText: cleanText,
        source: 'gemini',
      }),
      {status: 200, headers: {...corsHeaders, 'Content-Type': 'application/json'}},
    );
  } catch (error) {
    const err = error as Error;
    console.error('Translation error:', err);
    const body = await req.clone().json().catch(() => ({}));
    const {messageId: fallbackId, text: fallbackText = ''} = body as {messageId?: string; text?: string};
    const fallbackResult = fallbackText || `[Translation unavailable]`;
    return new Response(
      JSON.stringify({translatedText: fallbackResult, source: 'fallback', messageId: fallbackId}),
      {status: 200, headers: {...corsHeaders, 'Content-Type': 'application/json'}},
    );
  }
});
