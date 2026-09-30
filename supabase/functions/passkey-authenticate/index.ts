// ============================================================
// RETIRED - do not re-enable.
//
// This endpoint is hard-disabled and will stay that way until the
// whole file is deleted from the deployed project.
//
// WHY
// ---
// 1. It never called `authenticate()`. Every other function in
//    `supabase/functions/` does, and they all build a service-role client
//    and then explicitly bind it to the caller via `authenticate()`. This one
//    skipped that step, so it was an endpoint whose entire job was to reach
//    `auth.mfa.verify()` and return `access_token` / `refresh_token`
//    (old lines 117-123) to any unauthenticated caller that reached it.
//
// 2. Even so, it could never have worked. `auth.mfa.listFactors()`,
//    `auth.mfa.challenge()`, `auth.mfa.verify()` and `auth.getSession()`
//    resolve against the SERVICE-ROLE client's own session, and a service-role
//    client has no user session. So in practice it failed at `listFactors`
//    and returned "No matching passkey found". It was simultaneously
//    unreachable-as-designed and, on the failure paths, an unauthenticated
//    endpoint that leaked internal `verifyError.message` text.
//
// 3. Nothing in `lib/` calls it. Weekend registers and signs in with
//    passkeys through Supabase's NATIVE WebAuthn API
//    (`client.auth.passkey.*`, via `lib/services/passkey_service.dart` +
//    `lib/repositories/auth_repository.dart`), which keeps the ceremony inside
//    GoTrue and needs no custom endpoint at all. `passkey-register` is the
//    same story: it called `auth.mfa.enroll(authUserId, ...)` on a service-role
//    client, which is the wrong API surface (service-role MFA lives under
//    `auth.admin.mfa.*`) and also has no caller.
//
// WHAT TO DO INSTEAD
// -------------------
// Nothing. Passkeys already work through the native path. When you are ready,
// delete both `passkey-authenticate` and `passkey-register` from the deployed
// project with `supabase functions delete`, then remove these files from the
// repository. Keeping a hard 410 rather than silently deleting the file is
// deliberate: deploying this replaces whatever is currently live, whereas
// deleting the file from the repository would leave an unknown version of it
// still running in production.
// ============================================================

import {serve} from 'https://deno.land/std@0.224.0/http/server.ts';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

serve(() => {
  // 410 Gone, not 404: the caller knows this endpoint existed, and the body
  // says what to use instead. No detail about the previous implementation is
  // returned.
  return new Response(
    JSON.stringify({
      error: 'This endpoint has been retired.',
      use: 'client.auth.passkey.register() / client.auth.passkey.authenticate()',
    }),
    {status: 410, headers: {...corsHeaders, 'Content-Type': 'application/json'}},
  );
});