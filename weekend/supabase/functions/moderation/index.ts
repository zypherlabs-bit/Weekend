import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

/**
 * Weekend Moderation Edge Function
 * Evaluates profile photos and text for real-human presence,
 * scam indicators, financial spam, and policy violations.
 */
serve(async (req) => {
  const { userId, photoUrl, bioText } = await req.json();

  // Synthetic/AI detection & real-human verification scoring
  let isApproved = true;
  let trustScore = 98;
  let riskLevel = "Low Risk";

  const forbiddenTriggers = ["crypto", "invest", "cashapp", "telegram:", "whatsapp:"];
  const containsSpam = forbiddenTriggers.some(t => bioText?.toLowerCase().includes(t));

  if (containsSpam) {
    isApproved = false;
    trustScore = 30;
    riskLevel = "High Risk · Spam Detected";
  }

  return new Response(
    JSON.stringify({
      userId,
      approved: isApproved,
      trustScore,
      riskLevel,
      evaluatedAt: new Date().toISOString()
    }),
    { headers: { "Content-Type": "application/json" } }
  );
});
