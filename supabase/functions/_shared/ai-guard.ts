// ai-guard — shared gate for the AI edge functions.
//
// Verifies the caller's Supabase JWT (so only signed-in dreamers can call the AI
// functions) and consumes one of their daily AI credits. Each dreamer gets
// DAILY_LIMIT successful AI requests per day; further requests get a 429 until
// midnight (server time). SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY are injected
// into every Supabase Edge Function automatically.

import { createClient } from "npm:@supabase/supabase-js@2";

/// Daily per-user AI request allowance.
const DAILY_LIMIT = 8;

export interface Guarded {
  ok: boolean;
  userId?: string;
  /// The response to return as-is when `ok` is false (401 / 429 / 500).
  response?: Response;
}

export async function guardAIRequest(
  req: Request,
  corsHeaders: Record<string, string>,
): Promise<Guarded> {
  const deny = (status: number, message: string): Guarded => ({
    ok: false,
    response: new Response(JSON.stringify({ error: message }), {
      status,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    }),
  });

  const jwt = (req.headers.get("Authorization") ?? "")
    .replace(/^Bearer\s+/i, "")
    .trim();
  if (!jwt) return deny(401, "Sign in to use AI features.");

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );

  // Verify the token belongs to a real user (the publishable key alone won't).
  const { data: { user }, error } = await admin.auth.getUser(jwt);
  if (error || !user) {
    return deny(401, "Your session has expired. Please sign in again.");
  }

  // Atomically consume one of today's credits.
  const { data: allowed, error: limitError } = await admin.rpc("consume_ai_credit", {
    p_user_id: user.id,
    p_daily_limit: DAILY_LIMIT,
  });
  if (limitError) {
    console.error("consume_ai_credit failed:", limitError);
    return deny(500, "Couldn't check your AI usage. Please try again.");
  }
  if (allowed === false) {
    return deny(
      429,
      `You've used all ${DAILY_LIMIT} of today's AI requests. Check back tomorrow.`,
    );
  }

  return { ok: true, userId: user.id };
}
