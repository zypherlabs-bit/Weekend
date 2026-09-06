import {serve} from 'https://deno.land/std@0.224.0/http/server.ts';
import {createClient} from 'https://esm.sh/@supabase/supabase-js@2.45.6';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

const SUSPICIOUS_PATTERNS = [
  /screenshot/i, /screen\s*shot/i, /ai\s*generated/i, /deepfake/i,
  /meme/i, /cartoon/i, /anime/i, /illustration/i, /drawing/i,
  /art\b/i, /god/i, /deity/i, /religious/i, /logo\b/i, /brand/i, /filter/i,
];

/**
 * Verifies the caller's JWT and ensures the authenticated user matches
 * the requested userId. Returns the user ID or null if unauthenticated.
 */
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

    const {userId, photoUrl, storagePath} = await req.json();

    if (!userId || !photoUrl) {
      return new Response(
        JSON.stringify({error: 'userId and photoUrl are required'}),
        {status: 400, headers: {...corsHeaders, 'Content-Type': 'application/json'}},
      );
    }

    // SECURITY: Verify the authenticated user is requesting verification for themselves
    const authUserId = await authenticate(req, supabase);
    if (!authUserId || authUserId !== userId) {
      return new Response(
        JSON.stringify({error: 'Unauthorized: cannot verify another user\'s photo'}),
        {status: 403, headers: {...corsHeaders, 'Content-Type': 'application/json'}},
      );
    }

    // Download the image from Supabase Storage
    const apiKey = Deno.env.get('GEMINI_API_KEY');
    if (!apiKey) {
      return new Response(
        JSON.stringify({error: 'Gemini API key not configured'}),
        {status: 500, headers: {...corsHeaders, 'Content-Type': 'application/json'}},
      );
    }

    // Try to download the image from storage
    let imageBytes: Uint8Array | null = null;
    try {
      const {data: imageData, error: downloadError } = await supabase.storage
        .from('profile-photos')
        .download(storagePath || '');

      if (downloadError) {
        console.error('Storage download error:', downloadError);
      } else if (imageData) {
        imageBytes = new Uint8Array(await imageData.arrayBuffer());
      }
    } catch (e) {
      console.warn('Could not download image from storage, falling back to URL:', e);
    }

    // If we can't download from storage, try fetching via signed URL
    let processedImageUrl: string = photoUrl;
    if (!imageBytes) {
      try {
        const {data: signedUrl, error: urlError } = await supabase.storage
          .from('profile-photos')
          .createSignedUrl(storagePath || '', 3600);

        if (!urlError && signedUrl) {
          processedImageUrl = signedUrl.publicUrl || signedUrl;
          const imageResp = await fetch(processedImageUrl);
          if (imageResp.ok) {
            imageBytes = new Uint8Array(await imageResp.arrayBuffer());
          }
        }
      } catch (e) {
        console.warn('Could not fetch image:', e);
      }
    }

    // Build multimodal prompt for Gemini Vision
    const imageBase64 = imageBytes
      ? Buffer.from(imageBytes).toString('base64')
      : null;

    let geminiResponse;
    let detectionSignals: Record<string, unknown> = {};

    if (imageBase64) {
      const prompt = `Analyze this image as part of a dating app photo verification system.
      Determine if this is a real human selfie/photo.
      Detect: human presence, face, non-human images, cartoons, illustrations, logos,
      places/landscapes, religious artwork, deity/god images, screenshots, AI-generated images,
      synthetic portraits, and inappropriate content.
      Return JSON with:
      - is_human_face (boolean)
      - confidence (0-100)
      - detects: array of what was detected (human, face, cartoon, screenshot, ai_generated, etc.)
      - suspicion_reasons: array of strings if suspicious, empty if clean
      - risk_level: "low", "medium", "high"`;

      const response = await fetch(
        `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=${apiKey}`,
        {
          method: 'POST',
          headers: {'Content-Type': 'application/json'},
          body: JSON.stringify({
            contents: [{
              parts: [
                {text: prompt},
                {
                  inlineData: {
                    mimeType: 'image/jpeg',
                    data: imageBase64,
                  },
                },
              ],
            }],
          }),
        },
      );

      if (response.ok) {
        const data = await response.json();
        const text = data.candidates?.[0]?.content?.parts?.[0]?.text || '';
        try {
          geminiResponse = JSON.parse(text);
          detectionSignals = {
            gemini_analysis: geminiResponse,
            has_image_bytes: true,
            image_size_bytes: imageBytes.length,
          };
        } catch {
          detectionSignals = {
            raw_text: text,
            has_image_bytes: true,
            image_size_bytes: imageBytes.length,
          };
        }
      }
    }

    // Secondary signal: check filename/URL for suspicious patterns
    const suspiciousMatches = SUSPICIOUS_PATTERNS.filter(p =>
      p.test(photoUrl) || p.test(storagePath || '')
    );
    detectionSignals.filename_suspicious_patterns = suspiciousMatches;

    // Determine result
    const geminiAnalysis = (detectionSignals.gemini_analysis ||
      (detectionSignals as Record<string, unknown>).raw_text) as Record<string, unknown> | undefined;

    let isHumanFace = false;
    let confidence = 50;
    let riskLevel = 'low';
    const suspicionReasons: string[] = [];

    if (geminiAnalysis && typeof geminiAnalysis === 'object') {
      isHumanFace = (geminiAnalysis['is_human_face'] as boolean) ?? false;
      confidence = (geminiAnalysis['confidence'] as number) ?? 50;
      riskLevel = (geminiAnalysis['risk_level'] as string) ?? 'low';
      suspicionReasons.push(...((geminiAnalysis['suspicion_reasons'] as string[]) ?? []));
    }

    if (suspiciousMatches.length > 0) {
      riskLevel = riskLevel === 'high' ? 'high' : 'medium';
      for (const m of suspiciousMatches) {
        suspicionReasons.push(`Filename matches suspicious pattern: ${m}`);
      }
    }

    // Determine verification status based on risk signals
    let status: string;
    if (riskLevel === 'high') {
      status = 'rejected';
    } else if (riskLevel === 'medium') {
      status = 'pending';
    } else if (isHumanFace && confidence >= 70) {
      status = 'approved';
    } else if (isHumanFace && confidence < 70) {
      status = 'pending';
    } else if (!isHumanFace) {
      status = 'rejected';
    } else {
      status = 'pending';
    }

    // Save verification request to database
    const { error: upsertError } = await supabase
      .from('verification_requests')
      .insert({
        user_id: userId,
        photo_id: null,
        status: 'pending',
        confidence_score: confidence,
        detection_signals: detectionSignals,
      })
      .single();

    if (upsertError) {
      console.error('Failed to save verification request:', upsertError);
    }

    // Update profile verification status
    if (status === 'approved') {
      await supabase
        .from('profiles')
        .update({
          verification_status: 'verified',
          trust_score: confidence,
        })
        .eq('id', userId);
    } else if (status === 'rejected') {
      await supabase
        .from('profiles')
        .update({
          verification_status: 'rejected',
          trust_score: 0,
        })
        .eq('id', userId);
    }

    return new Response(
      JSON.stringify({
        status,
        confidence,
        isHumanFace,
        riskLevel,
        suspicionReasons,
        detectionSignals,
      }),
      {status: 200, headers: {...corsHeaders, 'Content-Type': 'application/json'}},
    );
  } catch (error) {
    const err = error as Error;
    console.error('Photo verification error:', err);
    return new Response(
      JSON.stringify({
        error: 'Verification service error',
        details: err.message,
        status: 'pending',
        confidence: 50,
      }),
      {status: 500, headers: {...corsHeaders, 'Content-Type': 'application/json'}},
    );
  }
});
