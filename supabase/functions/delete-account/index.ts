// delete-account — Supabase Edge Function
//
// Permanently deletes the calling user's account. Verifies the user's JWT, then
// deletes the auth user with the service role; their `profiles`, `dreams`, and
// `ai_usage` rows cascade away via on-delete-cascade foreign keys. Required for
// App Store Guideline 5.1.1(v) (in-app account deletion).
//
// Deploy: supabase functions deploy delete-account --no-verify-jwt
// (The function verifies the user JWT itself, so it isn't actually open.)

import { createClient } from "npm:@supabase/supabase-js@2";

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

  const { error: deleteError } = await admin.auth.admin.deleteUser(user.id);
  if (deleteError) {
    console.error("delete-account failed:", deleteError);
    return json({ error: "Couldn't delete your account. Please try again." }, 502);
  }

  return json({ ok: true }, 200);
});

function json(payload: unknown, status: number): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
