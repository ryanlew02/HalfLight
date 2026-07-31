// delete-account — Supabase Edge Function
//
// Permanently deletes the calling user's account. Verifies the user's JWT, then
// deletes the auth user with the service role; their `profiles`, `dreams`, and
// `ai_usage` rows cascade away via on-delete-cascade foreign keys. Required for
// App Store Guideline 5.1.1(v) (in-app account deletion).
//
// For accounts created with Sign in with Apple, that same guideline also requires
// revoking the Apple grant — deleting our user row leaves HalfLight listed under
// the dreamer's Apple ID indefinitely. The refresh token needed to do that is
// captured at sign-in by the `apple-link` function.
//
// Deploy: supabase functions deploy delete-account --no-verify-jwt
// (The function verifies the user JWT itself, so it isn't actually open.)

import { createClient } from "npm:@supabase/supabase-js@2";
import { appleOAuthConfigured, revokeRefreshToken } from "../_shared/apple-oauth.ts";

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

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );

  const { data: { user }, error } = await admin.auth.getUser(jwt);
  if (error || !user) {
    return json({ error: "Your session has expired. Please sign in again." }, 401);
  }

  // Sign in with Apple: sever the grant at Apple before the account goes away.
  // Guideline 5.1.1(v) requires this — deleting the Supabase user alone leaves
  // HalfLight listed under the dreamer's Apple ID forever. Must happen first,
  // because the stored token cascades away with the user row.
  await revokeAppleGrant(admin, user.id);

  const { error: deleteError } = await admin.auth.admin.deleteUser(user.id);
  if (deleteError) {
    console.error("delete-account failed:", deleteError);
    return json({ error: "Couldn't delete your account. Please try again." }, 502);
  }

  return json({ ok: true }, 200);
});

/// Best-effort revocation of the user's Sign in with Apple grant.
///
/// Deliberately never throws. Deletion is the dreamer's right and the thing they
/// asked for; if Apple is unreachable we still delete the account rather than
/// trapping them in it. Failures are logged loudly so a systematic breakage
/// (expired .p8, wrong client_id) is visible in the function logs.
async function revokeAppleGrant(
  admin: ReturnType<typeof createClient>,
  userId: string,
): Promise<void> {
  try {
    const { data, error } = await admin
      .from("apple_refresh_tokens")
      .select("refresh_token")
      .eq("user_id", userId)
      .maybeSingle();

    if (error) {
      console.error("delete-account: token lookup failed:", error);
      return;
    }
    // Email/password accounts, and Apple users who signed in before apple-link
    // shipped, have nothing to revoke.
    if (!data?.refresh_token) return;

    if (!appleOAuthConfigured()) {
      console.error("delete-account: stored Apple token but SIWA secrets unset — grant NOT revoked");
      return;
    }

    const result = await revokeRefreshToken(data.refresh_token);
    if (!result.ok) {
      console.error("delete-account: Apple revoke failed:", result.error);
    }
  } catch (err) {
    console.error("delete-account: Apple revoke threw:", err);
  }
}

function json(payload: unknown, status: number): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
