// suggest-title — Supabase Edge Function
//
// Receives { title, entry, mood } and returns { title: string } — a short,
// evocative title drawn from the dream description. Used by the "Generate
// title" button in the new-dream form. The Anthropic key lives here, server-side.
//
// One-time setup (key is shared with analyze-dream / suggest-tags if already set):
//   supabase secrets set ANTHROPIC_API_KEY=sk-ant-...
//   supabase functions deploy suggest-title --no-verify-jwt

import Anthropic from "npm:@anthropic-ai/sdk";
import { guardAIRequest } from "../_shared/ai-guard.ts";

// Cheapest current Claude; plenty for a short title. Bump to
// "claude-opus-4-8" or "claude-sonnet-4-6" for richer titles.
const MODEL = "claude-haiku-4-5";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const client = new Anthropic({ apiKey: Deno.env.get("ANTHROPIC_API_KEY") });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  const guard = await guardAIRequest(req, corsHeaders);
  if (!guard.ok) return guard.response!;

  let body: { title?: string; entry?: string; mood?: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }

  const entry = (body.entry ?? "").trim();
  const mood = (body.mood ?? "").trim();

  if (!entry) {
    return json({ error: "Missing dream text" }, 400);
  }

  try {
    const response = await client.messages.create({
      model: MODEL,
      max_tokens: 64,
      system:
        "You name dreams with a short, evocative title drawn from the dream's " +
        "content. Return a single title of 2 to 5 words that captures the most " +
        "striking image, feeling, or moment in the dream. Title Case, no quotes, " +
        "no trailing punctuation, no emoji.",
      messages: [
        {
          role: "user",
          content:
            `Mood: ${mood || "(unspecified)"}\n` +
            `Dream: ${entry}`,
        },
      ],
      output_config: {
        format: {
          type: "json_schema",
          schema: {
            type: "object",
            properties: {
              title: { type: "string" },
            },
            required: ["title"],
            additionalProperties: false,
          },
        },
      },
    });

    const textBlock = response.content.find((b) => b.type === "text") as
      | { text: string }
      | undefined;
    const parsed = JSON.parse(textBlock?.text ?? "{}") as { title?: string };

    const title = (parsed.title ?? "").trim();
    if (!title) {
      return json({ error: "Title generation failed" }, 502);
    }

    return json({ title }, 200);
  } catch (err) {
    console.error("suggest-title failed:", err);
    return json({ error: "Title generation failed" }, 502);
  }
});

function json(payload: unknown, status: number): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
