// analyze-dream — Supabase Edge Function
//
// Receives { title, entry, mood } from the app, asks Claude to categorize and
// interpret the dream, and returns structured { category, meaning, themes } JSON
// (themes = the 2–3 most central themes, used as the dreamer's profile themes).
// The Anthropic API key lives here (server-side), never in the app.
//
// One-time setup:
//   supabase secrets set ANTHROPIC_API_KEY=sk-ant-...
//   supabase functions deploy analyze-dream --no-verify-jwt
//
// (`--no-verify-jwt` lets the app call it with the project's publishable key.
//  Add auth / rate-limiting later if you open this up more widely.)

import Anthropic from "npm:@anthropic-ai/sdk";

// The model. claude-haiku-4-5 is the cheapest current Claude and is plenty for
// this task. For richer, more nuanced interpretations, switch to
// "claude-opus-4-8" (≈5x the cost per analysis) or "claude-sonnet-4-6".
const MODEL = "claude-haiku-4-5";

// Fixed category set keeps the UI consistent and filterable.
const CATEGORIES = [
  "Adventure",
  "Nightmare",
  "Symbolic",
  "Recurring",
  "Healing",
  "Relationships",
  "Anxiety",
  "Wish Fulfillment",
  "Spiritual",
  "Everyday",
];

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

  let body: { title?: string; entry?: string; mood?: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }

  const title = (body.title ?? "").trim();
  const entry = (body.entry ?? "").trim();
  const mood = (body.mood ?? "").trim();

  if (!entry) {
    return json({ error: "Missing dream text" }, 400);
  }

  try {
    const response = await client.messages.create({
      model: MODEL,
      max_tokens: 1024,
      system:
        "You are a thoughtful, grounded dream analyst. Given a dream, assign the " +
        "single best-fitting category and write a short interpretation of what it " +
        "may mean for the dreamer. Be specific to the dream's actual content; avoid " +
        "generic platitudes. Keep the meaning to 2–4 sentences and address the " +
        "dreamer directly as 'you'. Also identify the 2 to 3 most central themes of " +
        "the dream — each a short noun phrase of one or two words in Title Case " +
        "(e.g. 'Flight', 'Lost Identity', 'Family'), never in all-caps, naming a " +
        "recurring motif a dreamer would track over time.",
      messages: [
        {
          role: "user",
          content:
            `Title: ${title || "(untitled)"}\n` +
            `Mood: ${mood || "(unspecified)"}\n` +
            `Dream: ${entry}`,
        },
      ],
      // Structured outputs guarantee a parseable { category, meaning } shape.
      output_config: {
        format: {
          type: "json_schema",
          schema: {
            type: "object",
            properties: {
              category: { type: "string", enum: CATEGORIES },
              meaning: { type: "string" },
              themes: {
                type: "array",
                items: { type: "string" },
              },
            },
            required: ["category", "meaning", "themes"],
            additionalProperties: false,
          },
        },
      },
    });

    const textBlock = response.content.find((b) => b.type === "text") as
      | { text: string }
      | undefined;
    const parsed = JSON.parse(textBlock?.text ?? "{}") as {
      category?: string;
      meaning?: string;
      themes?: string[];
    };

    if (!parsed.category || !parsed.meaning) {
      return json({ error: "Empty analysis" }, 502);
    }

    const themes = (parsed.themes ?? [])
      .map((t) => t.trim())
      .filter((t) => t.length > 0)
      .slice(0, 3);

    return json(
      { category: parsed.category, meaning: parsed.meaning, themes },
      200,
    );
  } catch (err) {
    console.error("analyze-dream failed:", err);
    return json({ error: "Analysis failed" }, 502);
  }
});

function json(payload: unknown, status: number): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
