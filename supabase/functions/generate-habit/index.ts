// Setup type definitions for built-in Supabase Runtime APIs
import "@supabase/functions-js/edge-runtime.d.ts";

const OPENAI_MODEL = "gpt-4o-mini";
const OPENAI_TIMEOUT_MS = 15_000;
const MAX_GOAL_LENGTH = 500;

// Must stay in sync with habitIconOptions in
// lib/features/home/domain/habit_icons.dart
const ICON_IDS = [
  "water",
  "book",
  "walk",
  "fitness",
  "sleep",
  "mindfulness",
] as const;

type IconId = (typeof ICON_IDS)[number];

const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

interface HabitSuggestionPayload {
  title: string;
  reason: string;
  scheduledTime: string;
  iconId: IconId;
}

function jsonResponse(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

function errorResponse(
  status: number,
  code: string,
  message: string,
): Response {
  return jsonResponse({ error: { code, message } }, status);
}

function isValidScheduledTime(value: unknown): value is string {
  return typeof value === "string" && /^([01]\d|2[0-3]):[0-5]\d$/.test(value);
}

function isValidIconId(value: unknown): value is IconId {
  return (
    typeof value === "string" && (ICON_IDS as readonly string[]).includes(value)
  );
}

function parseSuggestion(raw: unknown): HabitSuggestionPayload | null {
  if (typeof raw !== "object" || raw === null) return null;
  const candidate = raw as Record<string, unknown>;
  const { title, reason, scheduledTime, iconId } = candidate;

  if (typeof title !== "string" || title.trim().length === 0) return null;
  if (typeof reason !== "string" || reason.trim().length === 0) return null;
  if (!isValidScheduledTime(scheduledTime)) return null;
  if (!isValidIconId(iconId)) return null;

  return {
    title: title.trim(),
    reason: reason.trim(),
    scheduledTime,
    iconId,
  };
}

function extractOutputText(payload: unknown): string | null {
  if (typeof payload !== "object" || payload === null) return null;
  const output = (payload as Record<string, unknown>).output;
  if (!Array.isArray(output)) return null;

  for (const item of output) {
    if (typeof item !== "object" || item === null) continue;
    const itemRecord = item as Record<string, unknown>;
    if (itemRecord.type !== "message") continue;

    const content = itemRecord.content;
    if (!Array.isArray(content)) continue;

    for (const part of content) {
      if (typeof part !== "object" || part === null) continue;
      const partRecord = part as Record<string, unknown>;
      if (
        partRecord.type === "output_text" &&
        typeof partRecord.text === "string"
      ) {
        return partRecord.text;
      }
    }
  }

  return null;
}

async function callOpenAi(goal: string, apiKey: string): Promise<unknown> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), OPENAI_TIMEOUT_MS);

  try {
    const response = await fetch("https://api.openai.com/v1/responses", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: OPENAI_MODEL,
        input: [
          {
            role: "system",
            content:
              "You are a habit-coaching assistant. Suggest exactly one " +
              "small, concrete daily habit that helps the user reach their " +
              "stated goal. Reply only with the requested structured fields.",
          },
          {
            role: "user",
            content: goal,
          },
        ],
        text: {
          format: {
            type: "json_schema",
            name: "habit_suggestion",
            strict: true,
            schema: {
              type: "object",
              properties: {
                title: { type: "string" },
                reason: { type: "string" },
                scheduledTime: {
                  type: "string",
                  description: "24-hour time of day in HH:mm format",
                },
                iconId: { type: "string", enum: ICON_IDS },
              },
              required: ["title", "reason", "scheduledTime", "iconId"],
              additionalProperties: false,
            },
          },
        },
      }),
      signal: controller.signal,
    });

    if (!response.ok) {
      throw new Error(`OpenAI request failed with status ${response.status}`);
    }

    return await response.json();
  } finally {
    clearTimeout(timeout);
  }
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }

  if (req.method !== "POST") {
    return errorResponse(405, "method_not_allowed", "Only POST is supported.");
  }

  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return errorResponse(
      400,
      "invalid_json",
      "Request body must be valid JSON.",
    );
  }

  if (typeof body !== "object" || body === null) {
    return errorResponse(
      400,
      "invalid_request",
      "Request body must be a JSON object.",
    );
  }

  const goal = (body as Record<string, unknown>).goal;
  if (typeof goal !== "string") {
    return errorResponse(400, "invalid_goal", "goal must be a string.");
  }

  const trimmedGoal = goal.trim();
  if (trimmedGoal.length === 0) {
    return errorResponse(400, "invalid_goal", "goal must not be empty.");
  }

  if (trimmedGoal.length > MAX_GOAL_LENGTH) {
    return errorResponse(
      400,
      "invalid_goal",
      `goal must be ${MAX_GOAL_LENGTH} characters or fewer.`,
    );
  }

  const apiKey = Deno.env.get("OPENAI_API_KEY");
  if (!apiKey) {
    console.error("OPENAI_API_KEY is not configured.");
    return errorResponse(
      500,
      "configuration_error",
      "The service is not configured correctly.",
    );
  }

  let openAiPayload: unknown;
  try {
    openAiPayload = await callOpenAi(trimmedGoal, apiKey);
  } catch (error) {
    if (error instanceof DOMException && error.name === "AbortError") {
      console.error("OpenAI request timed out.");
      return errorResponse(
        504,
        "upstream_timeout",
        "The request took too long. Please try again.",
      );
    }
    console.error(
      "OpenAI request failed:",
      error instanceof Error ? error.message : "unknown error",
    );
    return errorResponse(
      502,
      "upstream_error",
      "Could not generate a suggestion right now.",
    );
  }

  const outputText = extractOutputText(openAiPayload);
  if (outputText === null) {
    console.error("OpenAI response did not contain output text.");
    return errorResponse(
      502,
      "upstream_error",
      "Could not generate a suggestion right now.",
    );
  }

  let parsedJson: unknown;
  try {
    parsedJson = JSON.parse(outputText);
  } catch {
    console.error("OpenAI output text was not valid JSON.");
    return errorResponse(
      502,
      "invalid_model_output",
      "Could not generate a suggestion right now.",
    );
  }

  const suggestion = parseSuggestion(parsedJson);
  if (suggestion === null) {
    console.error("OpenAI output did not match the expected suggestion shape.");
    return errorResponse(
      502,
      "invalid_model_output",
      "Could not generate a suggestion right now.",
    );
  }

  return jsonResponse(suggestion, 200);
});

/* To invoke locally:

  1. Run `supabase start` (see: https://supabase.com/docs/reference/cli/supabase-start)
  2. Make an HTTP request:

  curl -i --location --request POST 'http://127.0.0.1:54321/functions/v1/generate-habit' \
    --header 'Content-Type: application/json' \
    --data '{"goal":"I want to read more"}'

*/
