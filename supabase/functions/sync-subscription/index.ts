// sync-subscription — Supabase Edge Function
//
// The app posts the signed JWS of its current App Store transaction here right
// after a purchase or restore. We verify the caller's Supabase JWT, verify the
// transaction against Apple's certificates, and record the entitlement in
// `public.subscriptions` so the AI functions can gate Claude calls on it.
//
// This gives the server an entitlement immediately, rather than waiting for
// Apple's Server Notification (which `app-store-notifications` handles for
// renewals / expirations / refunds that happen later, when the app isn't open).
//
// Setup:
//   supabase functions deploy sync-subscription --no-verify-jwt
//   (the function verifies the user JWT itself; secrets in `apple-verify.ts`.)

import { createClient } from "npm:@supabase/supabase-js@2";
import {
  adminClient,
  upsertEntitlement,
  verifyTransactionJWS,
} from "../_shared/apple-verify.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  // Authenticate the dreamer by their Supabase JWT.
  const jwt = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "").trim();
  if (!jwt) return json({ error: "Sign in required." }, 401);

  const auth = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );
  const { data: { user }, error: userError } = await auth.auth.getUser(jwt);
  if (userError || !user) return json({ error: "Invalid session." }, 401);

  let body: { jws?: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }
  if (!body.jws) return json({ error: "Missing transaction" }, 400);

  try {
    const entitlement = await verifyTransactionJWS(body.jws);
    const error = await upsertEntitlement(adminClient(), user.id, entitlement);
    if (error) {
      console.error("upsert subscription failed:", error);
      return json({ error: "Couldn't save subscription." }, 500);
    }
    return json({ status: entitlement.status, expiresAt: entitlement.expiresMs }, 200);
  } catch (err) {
    // Keep the full reason in the server logs, but don't leak internals to the app.
    console.error("sync-subscription verify failed:", err);
    return json({ error: "Could not verify the purchase." }, 400);
  }
});

function json(payload: unknown, status: number): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
