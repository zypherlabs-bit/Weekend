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

    const authUserId = await authenticate(req, supabase);
    if (!authUserId) {
      return new Response(
        JSON.stringify({error: 'Unauthorized'}),
        {status: 401, headers: {...corsHeaders, 'Content-Type': 'application/json'}},
      );
    }

    const {factor_type, attestation, client_data_json, email, data} = await req.json();

    if (factor_type !== 'webauthn') {
      return new Response(
        JSON.stringify({error: 'Invalid factor type'}),
        {status: 400, headers: {...corsHeaders, 'Content-Type': 'application/json'}},
      );
    }

    if (!attestation || !client_data_json || !email) {
      return new Response(
        JSON.stringify({error: 'Missing required fields: attestation, client_data_json, email'}),
        {status: 400, headers: {...corsHeaders, 'Content-Type': 'application/json'}},
      );
    }

    // Verify the email matches the authenticated user
    const {data: userData, error: userError} = await supabase.auth.admin.getUserById(authUserId);
    if (userError || !userData?.user || userData.user.email !== email) {
      return new Response(
        JSON.stringify({error: 'Email does not match authenticated user'}),
        {status: 403, headers: {...corsHeaders, 'Content-Type': 'application/json'}},
      );
    }

    // Create MFA factor for WebAuthn
    const {data: factor, error: factorError} = await supabase.auth.mfa.enroll(
      authUserId,
      {
        factorType: 'webauthn',
        issuer: 'Weekend',
        friendlyName: email,
      }
    );

    if (factorError) {
      console.error('MFA enroll error:', factorError);
      return new Response(
        JSON.stringify({error: 'Failed to enroll passkey factor', details: factorError.message}),
        {status: 500, headers: {...corsHeaders, 'Content-Type': 'application/json'}},
      );
    }

    // Verify the attestation by challenging the factor
    const {data: challenge, error: challengeError} = await supabase.auth.mfa.challenge(
      authUserId,
      {factorId: factor.id}
    );

    if (challengeError) {
      console.error('MFA challenge error:', challengeError);
      return new Response(
        JSON.stringify({error: 'Failed to create challenge', details: challengeError.message}),
        {status: 500, headers: {...corsHeaders, 'Content-Type': 'application/json'}},
      );
    }

    // The client will verify the challenge with the attestation
    // For now, we return the factor ID and challenge ID for client-side verification
    // In a full implementation, this would verify the attestation via Supabase's WebAuthn flow

    return new Response(
      JSON.stringify({
        success: true,
        factorId: factor.id,
        challengeId: challenge.id,
      }),
      {status: 200, headers: {...corsHeaders, 'Content-Type': 'application/json'}},
    );
  } catch (error) {
    const err = error as Error;
    console.error('Passkey registration error:', err);
    return new Response(
      JSON.stringify({error: 'Internal server error', details: err.message}),
      {status: 500, headers: {...corsHeaders, 'Content-Type': 'application/json'}},
    );
  }
});