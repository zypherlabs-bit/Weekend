import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

/**
 * Multilingual Message Translation Edge Function
 * Keeps original message intact while providing translation
 */
serve(async (req) => {
  const { text, targetLang = "English" } = await req.json();

  // In production, invokes Google Cloud Translation API or Gemini model securely
  const translated = `[${targetLang}] ${text}`;

  return new Response(
    JSON.stringify({
      original: text,
      targetLanguage: targetLang,
      translatedText: translated
    }),
    { headers: { "Content-Type": "application/json" } }
  );
});
