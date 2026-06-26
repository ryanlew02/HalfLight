// push-notify — Supabase Edge Function (run on a cron, ~every 15 minutes)
//
// Delivers APNs pushes for like/comment activity that hasn't been pushed yet
// (notifications.push_sent_at is null), throttled per user:
//   • One push per user per run.
//   • At most PUSH_MAX_PER_HOUR pushes/hour (counted from notification_pushes).
//   • 1 new item        → a detailed push ("Alice liked your dream").
//   • 2+ new items      → a summary push  ("You have 36 new likes").
//   • Over the cap      → left unpushed; collapses into a bigger summary later.
//
// Setup:
//   supabase secrets set APNS_KEY_ID=... APNS_TEAM_ID=... APNS_BUNDLE_ID=... \
//                        APNS_ENV=sandbox CRON_SECRET=... \
//                        APNS_PRIVATE_KEY="$(cat AuthKey_XXXX.p8)"
//   supabase functions deploy push-notify --no-verify-jwt
//   Then schedule it (Supabase Dashboard → Edge Functions → Schedules, or pg_cron):
//     */15 * * * *  POST <function-url>  with header  x-cron-secret: <CRON_SECRET>
//
// SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY are injected automatically.

import { createClient } from "npm:@supabase/supabase-js@2";
import { apnsConfigured, sendPush } from "../_shared/apns.ts";

const MAX_PER_HOUR = parseInt(Deno.env.get("PUSH_MAX_PER_HOUR") ?? "4", 10);
const CRON_SECRET = Deno.env.get("CRON_SECRET") ?? "";

interface NotificationRow {
  id: string;
  recipient_id: string;
  type: "like" | "comment";
  actor_name: string;
  post_title: string;
}

function admin() {
  return createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false } },
  );
}

/** Compose the push copy for a user's batch of new activity. */
function composeBody(items: NotificationRow[]): string {
  if (items.length === 1) {
    const n = items[0];
    const who = n.actor_name?.trim() || "Someone";
    const verb = n.type === "like" ? "liked" : "commented on";
    const title = n.post_title?.trim() ? `“${n.post_title.trim()}”` : "your dream";
    return `${who} ${verb} ${title}`;
  }
  const likes = items.filter((i) => i.type === "like").length;
  const comments = items.length - likes;
  const parts: string[] = [];
  if (likes > 0) parts.push(`${likes} new ${likes === 1 ? "like" : "likes"}`);
  if (comments > 0) parts.push(`${comments} new ${comments === 1 ? "comment" : "comments"}`);
  return `You have ${parts.join(" and ")}`;
}

Deno.serve(async (req) => {
  // Cron-only: require the shared secret so the endpoint isn't openly invokable.
  if (CRON_SECRET && req.headers.get("x-cron-secret") !== CRON_SECRET) {
    return json({ error: "Unauthorized" }, 401);
  }
  if (!apnsConfigured()) {
    return json({ skipped: "APNs not configured (set APNS_* secrets)" }, 200);
  }

  const db = admin();
  const sinceHour = new Date(Date.now() - 60 * 60 * 1000).toISOString();

  // All un-pushed activity, oldest first so summaries read chronologically.
  const { data: pending, error } = await db
    .from("notifications")
    .select("id, recipient_id, type, actor_name, post_title")
    .is("push_sent_at", null)
    .order("created_at", { ascending: true })
    .limit(5000);
  if (error) return json({ error: error.message }, 500);

  // Group pending activity by recipient.
  const byUser = new Map<string, NotificationRow[]>();
  for (const row of (pending ?? []) as NotificationRow[]) {
    (byUser.get(row.recipient_id) ?? byUser.set(row.recipient_id, []).get(row.recipient_id)!).push(row);
  }

  let sent = 0, skippedCap = 0, skippedNoDevice = 0;

  for (const [userId, items] of byUser) {
    // Per-user hourly cap.
    const { count } = await db
      .from("notification_pushes")
      .select("id", { count: "exact", head: true })
      .eq("recipient_id", userId)
      .gte("sent_at", sinceHour);
    if ((count ?? 0) >= MAX_PER_HOUR) { skippedCap++; continue; }

    // Where to send.
    const { data: tokens } = await db
      .from("device_tokens")
      .select("token")
      .eq("user_id", userId);
    if (!tokens || tokens.length === 0) { skippedNoDevice++; continue; }

    // Badge = the user's total unread (so the app icon reflects the inbox).
    const { count: unread } = await db
      .from("notifications")
      .select("id", { count: "exact", head: true })
      .eq("recipient_id", userId)
      .is("read_at", null);

    const body = composeBody(items);
    let delivered = false;

    for (const { token } of tokens) {
      const result = await sendPush(token, { title: "HalfLight", body, badge: unread ?? undefined });
      if (result.ok) delivered = true;
      else if (result.unregistered) {
        await db.from("device_tokens").delete().eq("token", token);
      }
    }

    if (!delivered) { skippedNoDevice++; continue; }

    // Mark this batch pushed and log the send (for the hourly cap).
    const ids = items.map((i) => i.id);
    await db.from("notifications").update({ push_sent_at: new Date().toISOString() }).in("id", ids);
    await db.from("notification_pushes").insert({ recipient_id: userId, body });
    sent++;
  }

  return json({ users: byUser.size, sent, skippedCap, skippedNoDevice }, 200);
});

function json(payload: unknown, status: number): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "content-type": "application/json" },
  });
}
