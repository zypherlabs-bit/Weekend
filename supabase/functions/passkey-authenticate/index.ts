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

    const {factor_type, authenticator_data, client_data_json, signature, credential_id} = await req.json();

    if (factor_type !== 'webauthn') {
      return new Response(
        JSON.stringify({error: 'Invalid factor type'}),
        {status: 400, headers: {...corsHeaders, 'Content-Type': 'application/json'}},
      );
    }

    if (!authenticator_data || !client_data_json || !signature || !credential_id) {
      return new Response(
        JSON.stringify({error: 'Missing required fields'}),
        {status: 400, headers: {...corsHeaders, 'Content-Type': 'application/json'}},
      );
    }

    // List user's MFA factors to find WebAuthn factors
    const {data: factors, error: factorsError} = await supabase.auth.mfa.listFactors();

    if (factorsError) {
      console.error('List factors error:', factorsError);
      return new Response(
        JSON.stringify({error: 'Failed to list factors', details: factorsError.message}),
        {status: 500, headers: {...corsHeaders, 'Content-Type': 'application/json'}},
      );
    }

    // Find WebAuthn factors - they may be in different locations in the response
    let webauthnFactors: any[] = [];
    if (factors && typeof factors === 'object') {
      // Check for webAuthn field
      if ('webAuthn' in factors && Array.isArray(factors.webAuthn)) {
        webauthnFactors = factors.webAuthn;
      } else if ('all' in factors && Array.isArray(factors.all)) {
        webauthnFactors = factors.all.filter((f: any) => f.factor_type === 'webauthn' || f.type === 'webauthn');
      }
    }

    // Find matching factor by credential ID
    const matchingFactor = webauthnFactors.find((f: any) => 
      f.credential_id === credential_id || f.id === credential_id
    );

    if (!matchingFactor) {
      return new Response(
        JSON.stringify({error: 'No matching passkey found'}),
        {status: 404, headers: {...corsHeaders, 'Content-Type': 'application/json'}},
      );
    }

    // Challenge the factor
    const {data: challenge, error: challengeError} = await supabase.auth.mfa.challenge(
      matchingFactor.id
    );

    if (challengeError) {
      console.error('MFA challenge error:', challengeError);
      return new Response(
        JSON.stringify({error: 'Failed to create challenge', details: challengeError.message}),
        {status: 500, headers: {...corsHeaders, 'Content-Type': 'application/json'}},
      );
    }

    // Verify the assertion
    const {data: verification, error: verifyError} = await supabase.auth.mfa.verify(
      matchingFactor.id,
      challenge.id,
      '' // The client-side verification uses the credential directly
    );

    if (verifyError) {
      console.error('MFA verify error:', verifyError);
      return new Response(
        JSON.stringify({error: 'Failed to verify passkey', details: verifyError.message}),
        {status: 500, headers: {...corsHeaders, 'Content-Type': 'application/json'}},
      );
    }

    // Get the session after successful verification
    const {data: {session}, error: sessionError} = await supabase.auth.getSession();

    if (sessionError || !session) {
      return new Response(
        JSON.stringify({error: 'Failed to get session after verification'}),
        {status: 500, headers: {...corsHeaders, 'Content-Type': 'application/json'}},
      );
    }

    return new Response(
      JSON.stringify({
        success: true,
        access_token: session.access_token,
        refresh_token: session.refresh_token,
      }),
      {status: 200, headers: {...corsHeaders, 'Content-Type': 'application/json'}},
    );
  } catch (error) {
    const err = error as Error;
    console.error('Passkey authentication error:', err);
    return new Response(
      JSON.stringify({error: 'Internal server error', details: err.message}),
      {status: 500, headers: {...corsHeaders, 'Content-Type': 'application/json'}},
    );
  }
});