// moderate-reports — Supabase Edge Function
//
// Daily AI triage of the dream-feed report queue. For each piece of content
// with pending reports, Claude decides:
//   keep     → easy, content is fine     → status closed, resolution kept
//   hide     → easy, clear violation     → hidden + status closed, resolution hidden
//   escalate → a human should review it  → status escalated (dashboard "Issue")
// ai_reason stores the one-line rationale shown in the dashboard.
//
// Invoked by pg_cron once a day (not by users), guarded by a shared secret.
// The Anthropic API key lives server-side, never in the app.
//
// One-time setup:
//   supabase secrets set ANTHROPIC_API_KEY=sk-ant-...
//   supabase secrets set MODERATION_CRON_SECRET=<a long random string>
//   supabase functions deploy moderate-reports --no-verify-jwt
//
// Then schedule it (Supabase SQL editor, needs pg_cron + pg_net):
//   select cron.schedule(
//     'moderate-reports-daily',
//     '0 9 * * *',                          -- 09:00 UTC every day
//     $$ select net.http_post(
//          url     := 'https://<PROJECT-REF>.functions.supabase.co/moderate-reports',
//          headers := jsonb_build_object(
//            'Content-Type', 'application/json',
//            'x-cron-secret', '<MODERATION_CRON_SECRET>'
//          )
//        ); $$
//   );

import Anthropic from "npm:@anthropic-ai/sdk";
import { createClient } from "npm:@supabase/supabase-js@2";

// Haiku is the cheapest current Claude and is plenty for this short
// classify-and-escalate task. Bump to "claude-opus-4-8" for sharper judgment on
// borderline cases (≈5x the cost) — but note Opus also wants adaptive thinking
// + output_config.effort, which error on Haiku, so re-add them if you switch.
const MODEL = "claude-haiku-4-5";

const GUIDELINES =
  "HalfLight is a gentle dream-journaling community. Decide whether reported " +
  "content breaks the rules. Clear violations: harassment or hate, sexual " +
  "content involving minors, credible threats or encouragement of self-harm, " +
  "spam or scams, or graphic sexual content. A dream that is merely strange, " +
  "dark, sad, frightening, or unsettling is NOT a violation — dreams are " +
  "allowed to be weird. For each report choose:\n" +
  '- "keep": clearly fine, no violation (an easy call).\n' +
  '- "hide": clearly violates the rules and should be removed (an easy call).\n' +
  '- "escalate": genuinely ambiguous, borderline, context-dependent, or ' +
  "anything a careful human moderator would want to look at. When in doubt, " +
  "escalate.\n" +
  "Give a short one-sentence reason a moderator can skim.";

const anthropic = new Anthropic({ apiKey: Deno.env.get("ANTHROPIC_API_KEY") });

// Service-role client (auto-injected env vars in edge functions) bypasses RLS.
const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

Deno.serve(async (req) => {
  if (
    req.headers.get("x-cron-secret") !==
    Deno.env.get("MODERATION_CRON_SECRET")
  ) {
    return json({ error: "forbidden" }, 403);
  }

  // Pull pending reports with the content they target.
  const { data: reports, error } = await supabase
    .from("feed_reports")
    .select(
      `id, reason, post_id, comment_id,
       feed_posts ( id, title, dream_description ),
       feed_comments ( id, text )`,
    )
    .eq("status", "pending")
    .limit(500);
  if (error) return json({ error: error.message }, 500);

  // Group by content so duplicate reports get one decision.
  type G = {
    postId: string | null;
    commentId: string | null;
    text: string;
    reasons: string[];
  };
  const groups = new Map<string, G>();
  for (const r of reports ?? []) {
    const key = r.post_id ?? r.comment_id;
    if (!key) continue;
    const g = groups.get(key);
    if (g) {
      if (!g.reasons.includes(r.reason)) g.reasons.push(r.reason);
      continue;
    }
    const text = r.post_id
      ? `Dream titled "${r.feed_posts?.title ?? ""}": ${r.feed_posts?.dream_description ?? ""}`
      : `Comment: ${r.feed_comments?.text ?? ""}`;
    groups.set(key, {
      postId: r.post_id,
      commentId: r.comment_id,
      text,
      reasons: [r.reason],
    });
  }

  let kept = 0;
  let hidden = 0;
  let escalated = 0;

  for (const g of groups.values()) {
    // Default to escalate, so a triage failure still lands in front of a human.
    let decision = "escalate";
    let reason = "Couldn’t auto-triage — flagged for review.";

    try {
      const resp = await anthropic.messages.create({
        model: MODEL,
        max_tokens: 512,
        system: GUIDELINES,
        messages: [
          {
            role: "user",
            content: `Reported for: ${g.reasons.join(", ")}\n\n${g.text}`,
          },
        ],
        output_config: {
          format: {
            type: "json_schema",
            schema: {
              type: "object",
              properties: {
                decision: { type: "string", enum: ["keep", "hide", "escalate"] },
                reason: { type: "string" },
              },
              required: ["decision", "reason"],
              additionalProperties: false,
            },
          },
        },
      });
      const text =
        resp.content.find((b) => b.type === "text")?.text ?? "{}";
      const parsed = JSON.parse(text) as { decision?: string; reason?: string };
      if (parsed.decision) decision = parsed.decision;
      if (parsed.reason) reason = parsed.reason;
    } catch (err) {
      console.error("triage failed:", err);
      // keep the escalate default
    }

    const column = g.postId ? "post_id" : "comment_id";
    const value = g.postId ?? g.commentId;
    const now = new Date().toISOString();

    if (decision === "hide") {
      const table = g.postId ? "feed_posts" : "feed_comments";
      await supabase.from(table).update({ hidden: true }).eq("id", value);
      await supabase
        .from("feed_reports")
        .update({ status: "closed", resolution: "hidden", ai_reason: reason, reviewed_at: now })
        .eq(column, value!)
        .eq("status", "pending");
      hidden++;
    } else if (decision === "keep") {
      await supabase
        .from("feed_reports")
        .update({ status: "closed", resolution: "kept", ai_reason: reason, reviewed_at: now })
        .eq(column, value!)
        .eq("status", "pending");
      kept++;
    } else {
      await supabase
        .from("feed_reports")
        .update({ status: "escalated", ai_reason: reason, reviewed_at: now })
        .eq(column, value!)
        .eq("status", "pending");
      escalated++;
    }
  }

  return json({ groups: groups.size, kept, hidden, escalated });
});

function json(payload: unknown, status = 200): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
