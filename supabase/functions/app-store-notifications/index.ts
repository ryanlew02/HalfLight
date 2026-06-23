// app-store-notifications — Supabase Edge Function
//
// Receives App Store Server Notifications V2 from Apple and keeps
// `public.subscriptions` current for events that happen when the app isn't open:
// renewals, expirations, refunds, revocations, billing retries, etc.
//
// Apple calls this with no user JWT, so security comes entirely from verifying
// the signed payload against Apple's certificates (in `apple-verify.ts`). The
// dreamer is identified by the `appAccountToken` we attach at purchase time
// (set to the Supabase user id); if it's absent we fall back to the existing row
// keyed by Apple's original transaction id.
//
// Setup:
//   supabase functions deploy app-store-notifications --no-verify-jwt
//   Then set this function's URL as the Production + Sandbox notification URL in
//   App Store Connect → App → App Information → App Store Server Notifications (V2).

import {
  adminClient,
  upsertEntitlement,
  verifyNotification,
} from "../_shared/apple-verify.ts";

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), { status: 405 });
  }

  let signedPayload: string | undefined;
  try {
    ({ signedPayload } = await req.json());
  } catch {
    return new Response(JSON.stringify({ error: "Invalid JSON" }), { status: 400 });
  }
  if (!signedPayload) {
    return new Response(JSON.stringify({ error: "Missing signedPayload" }), { status: 400 });
  }

  try {
    const entitlement = await verifyNotification(signedPayload);
    // Test notifications (and any without a transaction) verify fine but carry
    // nothing to persist — acknowledge so Apple stops retrying.
    if (!entitlement) return new Response("ok", { status: 200 });

    const admin = adminClient();

    // Prefer the appAccountToken (our Supabase user id); otherwise locate the
    // dreamer by the original transaction id from a prior sync.
    let userId = entitlement.appAccountToken;
    if (!userId) {
      const { data } = await admin
        .from("subscriptions")
        .select("user_id")
        .eq("original_transaction_id", entitlement.originalTransactionId)
        .maybeSingle();
      userId = data?.user_id;
    }

    if (!userId) {
      // Nothing to attach this to yet; ack so Apple doesn't retry forever. The
      // app's own sync-subscription call will establish the mapping.
      console.warn("notification with no resolvable user:", entitlement.originalTransactionId);
      return new Response("ok", { status: 200 });
    }

    const error = await upsertEntitlement(admin, userId, entitlement);
    if (error) {
      console.error("notification upsert failed:", error);
      return new Response(JSON.stringify({ error: "Persist failed" }), { status: 500 });
    }
    return new Response("ok", { status: 200 });
  } catch (err) {
    console.error("app-store-notifications verify failed:", err);
    return new Response(JSON.stringify({ error: "Verification failed" }), { status: 400 });
  }
});
