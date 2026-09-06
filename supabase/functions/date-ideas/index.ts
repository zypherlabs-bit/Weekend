import {serve} from 'https://deno.land/std@0.224.0/http/server.ts';
import {createClient} from 'https://esm.sh/@supabase/supabase-js@2.45.6';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

interface DateIdea {
  title: string;
  venueType: string;
  description: string;
  estimatedBudget: string;
  conversationTip: string;
}

const fallbackIdeas: DateIdea[] = [
  {
    title: 'Specialty Coffee Crawl & Gallery Walk',
    venueType: 'Cafe + Contemporary Art',
    description: 'Meet at a cozy independent roaster for artisan pour-overs, then take a stroll through the local art gallery.',
    estimatedBudget: '₹₹ (Moderate)',
    conversationTip: 'Ask them about the last piece of art or music that gave them chills.',
  },
  {
    title: 'Sunset Hilltop Tekdi & Chai',
    venueType: 'Outdoor Nature',
    description: 'A gentle golden-hour walk up the tekdi with panoramic city views, concluding with authentic clay-cup kulhad chai.',
    estimatedBudget: '₹ (Casual)',
    conversationTip: 'Talk about dream travel destinations and funniest weekend misadventures.',
  },
  {
    title: 'Pottery Workshop or Board Game Cafe',
    venueType: 'Interactive & Playful',
    description: 'Skip awkward small talk and make something with your hands or team up in a cooperative strategy game.',
    estimatedBudget: '₹₹ (Moderate)',
    conversationTip: 'Find out how competitive they get during board games!',
  },
  {
    title: 'Rooftop Tapas & Live Jazz',
    venueType: 'Evening Romance',
    description: 'Ambient string lights, acoustic music, and shared small plates under the open night sky.',
    estimatedBudget: '₹₹₹ (Premium)',
    conversationTip: 'Discuss what they would do if they took a year off from work tomorrow.',
  },
];

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
        JSON.stringify({ideas: fallbackIdeas, source: 'fallback'}),
        {status: 200, headers: {...corsHeaders, 'Content-Type': 'application/json'}},
      );
    }

    const apiKey = Deno.env.get('GEMINI_API_KEY');
    const {
      userInterests = [],
      partnerInterests = [],
      city = 'Pune',
    } = await req.json();

    if (!apiKey) {
      return new Response(
        JSON.stringify({ideas: fallbackIdeas, source: 'fallback'}),
        {status: 200, headers: {...corsHeaders, 'Content-Type': 'application/json'}},
      );
    }

    const userInt = userInterests as string[];
    const partnerInt = partnerInterests as string[];
    const allInterests = [...new Set([...userInt, ...partnerInt])];

    const prompt = `Act as the 'Weekend' App Smart Date Planner.
City: ${city}
Shared Interests: ${allInterests.join(', ')}
Generate 3 creative, real-world date suggestions suitable for young adults.
Return ONLY valid JSON array of objects with keys:
"title", "venueType", "description", "estimatedBudget", "conversationTip".`;

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
      console.error('Gemini date-ideas error:', errText);
      return new Response(
        JSON.stringify({ideas: fallbackIdeas, source: 'fallback'}),
        {status: 200, headers: {...corsHeaders, 'Content-Type': 'application/json'}},
      );
    }

    const data = await response.json();
    let rawContent = data.candidates?.[0]?.content?.parts?.[0]?.text || '';

    if (rawContent.includes('```json')) {
      const start = rawContent.indexOf('```json') + 7;
      const end = rawContent.indexOf('```', start);
      rawContent = (end > start ? rawContent.substring(start, end) : rawContent.substring(start)).trim();
    } else if (rawContent.includes('```')) {
      const start = rawContent.indexOf('```') + 3;
      const end = rawContent.indexOf('```', start);
      rawContent = (end > start ? rawContent.substring(start, end) : rawContent.substring(start)).trim();
    }

    const parsed = JSON.parse(rawContent) as DateIdea[];

    if (parsed.length === 0) {
      return new Response(
        JSON.stringify({ideas: fallbackIdeas, source: 'fallback'}),
        {status: 200, headers: {...corsHeaders, 'Content-Type': 'application/json'}},
      );
    }

    return new Response(
      JSON.stringify({ideas: parsed, source: 'gemini'}),
      {status: 200, headers: {...corsHeaders, 'Content-Type': 'application/json'}},
    );
  } catch (error) {
    const err = error as Error;
    console.error('Date ideas generation error:', err);
    return new Response(
      JSON.stringify({ideas: fallbackIdeas, source: 'fallback'}),
      {status: 200, headers: {...corsHeaders, 'Content-Type': 'application/json'}},
    );
  }
});
