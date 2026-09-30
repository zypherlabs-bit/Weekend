// ============================================================
// RETIRED - do not re-enable. See passkey-authenticate/index.ts
// for the full reasoning; the summary is:
//
//   * It called `auth.mfa.enroll(authUserId, ...)` on a SERVICE-ROLE client.
//     `auth.mfa.*` resolves against the calling client's own session, and a
//     service-role client has none. The service-role MFA surface is
//     `auth.admin.mfa.*`. So this call could not succeed as written.
//   * Even if it had, the response handed the client a `factorId` and
//     `challengeId` and then said, in its own comment, "The client will
//     verify the challenge with the attestation ... In a full implementation,
//     this would verify the attestation via Supabase's WebAuthn flow". No such
//     client verification exists, so a successful response here would have left
//     an enrolled but unverified factor.
//   * Nothing in `lib/` calls it. Weekend uses Supabase's native WebAuthn API
//     (`client.auth.passkey.register()`), which performs the whole ceremony
//     correctly inside GoTrue.
//
// This is a hard 410 rather than a deleted file so that deploying it actually
// replaces whatever is currently live. Delete the file from the repository
// once `supabase functions delete passkey-register` has been run.
// ============================================================

import {serve} from 'https://deno.land/std@0.224.0/http/server.ts';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

serve(() => {
  return new Response(
    JSON.stringify({
      error: 'This endpoint has been retired.',
      use: 'client.auth.passkey.register()',
    }),
    {status: 410, headers: {...corsHeaders, 'Content-Type': 'application/json'}},
  );
});