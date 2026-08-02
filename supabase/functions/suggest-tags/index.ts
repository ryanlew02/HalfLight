// suggest-tags — Supabase Edge Function
//
// Receives { title, entry, mood } and returns { tags: string[] } — a few short
// theme/symbol tags drawn from the dream description. Used by the "Auto-tag"
// button in the new-dream form. The Anthropic key lives here, server-side.
//
// One-time setup (key is shared with analyze-dream if already set):
//   supabase secrets set ANTHROPIC_API_KEY=sk-ant-...
//   supabase functions deploy suggest-tags --no-verify-jwt

import Anthropic from "npm:@anthropic-ai/sdk";
import { guardAIRequest, MAX_ENTRY_CHARS, MAX_FIELD_CHARS } from "../_shared/ai-guard.ts";

// Cheapest current Claude; plenty for short tag extraction. Bump to
// "claude-opus-4-8" or "claude-sonnet-4-6" for richer tags.
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

  // Truncate rather than reject: the credit is already spent by the guard above,
  // and a clipped dream still tags fine.
  const title = (body.title ?? "").trim().slice(0, MAX_FIELD_CHARS);
  const entry = (body.entry ?? "").trim().slice(0, MAX_ENTRY_CHARS);
  const mood = (body.mood ?? "").trim().slice(0, MAX_FIELD_CHARS);

  if (!entry) {
    return json({ error: "Missing dream text" }, 400);
  }

  try {
    const response = await client.messages.create({
      model: MODEL,
      max_tokens: 256,
      system:
        "You label dreams with short, searchable tags drawn from the dream's " +
        "content. Return 3 to 6 tags. Each tag is one or two lowercase words " +
        "naming a concrete theme, symbol, place, person, or emotion that actually " +
        "appears in the dream (e.g. 'ocean', 'flight', 'being chased', 'family'). " +
        "No punctuation, no hashtags, no duplicates.",
      messages: [
        {
          role: "user",
          content:
            `Title: ${title || "(untitled)"}\n` +
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
              tags: { type: "array", items: { type: "string" } },
            },
            required: ["tags"],
            additionalProperties: false,
          },
        },
      },
    });

    const textBlock = response.content.find((b) => b.type === "text") as
      | { text: string }
      | undefined;
    const parsed = JSON.parse(textBlock?.text ?? "{}") as { tags?: string[] };

    const tags = (parsed.tags ?? [])
      .map((t) => t.trim())
      .filter((t) => t.length > 0)
      .slice(0, 6);

    return json({ tags }, 200);
  } catch (err) {
    console.error("suggest-tags failed:", err);
    return json({ error: "Tag generation failed" }, 502);
  }
});

function json(payload: unknown, status: number): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
