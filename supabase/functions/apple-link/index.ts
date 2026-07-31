// apple-link — Supabase Edge Function
//
// Called by the app right after a successful Sign in with Apple, with the
// one-time `authorizationCode` from the Apple credential. Exchanges it with
// Apple for a refresh token and stores that against the user, so
// `delete-account` can revoke the grant later — required by App Store Review
// Guideline 5.1.1(v).
//
// The authorizationCode is single-use and expires in ~5 minutes, so this has to
// run at sign-in; there is no way to obtain a refresh token afterwards. A user
// who signed in before this shipped simply has no stored token, and deletion
// falls back to deleting the account without a revoke (see delete-account).
//
// Failure here is deliberately NOT fatal to sign-in: the dreamer is already
// authenticated by the time we're called, and blocking them from using the app
// because Apple's token endpoint hiccuped would be worse than the missing token.
//
// Setup:
//   supabase secrets set APPLE_SIWA_KEY_ID=... APPLE_TEAM_ID=... \
//     APPLE_SIWA_CLIENT_ID=LanternHours.HalfLight \
//     APPLE_SIWA_PRIVATE_KEY="$(cat AuthKey_XXXXXXXXXX.p8)"
//   supabase functions deploy apple-link --no-verify-jwt
// (`--no-verify-jwt` lets the request reach our code; we verify the user JWT
//  ourselves below, so it isn't open.)

import { createClient } from "npm:@supabase/supabase-js@2";
import { exchangeCode, appleOAuthConfigured } from "../_shared/apple-oauth.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  const jwt = (req.headers.get("Authorization") ?? "")
    .replace(/^Bearer\s+/i, "")
    .trim();
  if (!jwt) return json({ error: "Not signed in." }, 401);

  let body: { authorizationCode?: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }
  const code = (body.authorizationCode ?? "").trim();
  if (!code) return json({ error: "Missing authorizationCode" }, 400);

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );

  // Verify the caller before anything else, so an unauthenticated request can't
  // probe whether Sign in with Apple is configured.
  const { data: { user }, error } = await admin.auth.getUser(jwt);
  if (error || !user) {
    return json({ error: "Your session has expired. Please sign in again." }, 401);
  }

  if (!appleOAuthConfigured()) {
    console.error("apple-link: Sign in with Apple secrets are not set");
    return json({ error: "Apple sign-in is not configured." }, 500);
  }

  const exchange = await exchangeCode(code);
  if (!exchange.ok || !exchange.refreshToken) {
    console.error("apple-link: code exchange failed:", exchange.error);
    return json({ error: "Couldn't link your Apple account." }, 502);
  }

  const { error: writeError } = await admin
    .from("apple_refresh_tokens")
    .upsert({
      user_id: user.id,
      refresh_token: exchange.refreshToken,
      updated_at: new Date().toISOString(),
    }, { onConflict: "user_id" });

  if (writeError) {
    console.error("apple-link: could not store refresh token:", writeError);
    return json({ error: "Couldn't link your Apple account." }, 500);
  }

  return json({ ok: true }, 200);
});

function json(payload: unknown, status: number): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
