// Setup type definitions for built-in Supabase Runtime APIs
import "@supabase/functions-js/edge-runtime.d.ts";
import {
  isDeveloperBypass,
  parseUserIdFromJwt,
} from "../_shared/quota_bypass.ts";

const OPENAI_MODEL = "gpt-4o-mini";
const OPENAI_TIMEOUT_MS = 15_000;
const DAILY_QUOTA_LIMIT = 10;
const MAX_GOAL_LENGTH = 500;

const SYSTEM_PROMPT = `You are a habit-coaching assistant. Suggest exactly one small, concrete habit that directly supports the user's stated goal. Reply only with the requested structured fields.

Goal-preservation rules:
- Preserve explicit numbers, quantities, durations, frequencies, and times of day exactly as the user stated them. Never silently replace the user's measurable target with a different quantity.
- The title must clearly relate to the original goal. If the user names a quantity or duration, the title must reflect it or identify the habit as a first step toward that specific target.
- If one app reminder cannot represent the whole goal (for example, a daily total meant to be spread across the day), generate a concrete first-step habit and state in the reason that it is the starting point for the user's stated target. Do not invent a replacement target.
- Keep suggestions practical and measurable.
- Do not make medical claims. Do not state that any quantity is universally safe, optimal, or medically recommended.

Weekday scheduling rules:
- Map explicit weekday names to ISO integers: 1=Monday, 2=Tuesday, 3=Wednesday, 4=Thursday, 5=Friday, 6=Saturday, 7=Sunday.
- "weekdays" means [1,2,3,4,5]. "weekends" means [6,7]. "daily", "every day", or no specific days means [1,2,3,4,5,6,7] with requiredDaysPerWeek=null.
- Do not invent specific weekdays the user did not mention.
- When the user states only a frequency count ("twice a week", "3 times a week") WITHOUT naming specific days: set requiredDaysPerWeek to the count and set weekdays to null. Do NOT guess which days.
- When the user names explicit days, set weekdays to those days and requiredDaysPerWeek to null.
- When the user states a count AND names explicit days: if the count matches the number of named days, set weekdays and requiredDaysPerWeek=null. If there is a mismatch, set both weekdays (partial list) and requiredDaysPerWeek to the stated count.

Examples (style only — do not reuse these numbers or phrases in your actual output):

User: drink 3 liters of water per day
Output: {"title":"Morning glass","reason":"...","scheduledTime":"07:30","iconId":"water","weekdays":[1,2,3,4,5,6,7],"requiredDaysPerWeek":null}

User: work out Monday Wednesday Friday
Output: {"title":"Strength workout","reason":"...","scheduledTime":"07:00","iconId":"fitness","weekdays":[1,3,5],"requiredDaysPerWeek":null}

User: go to the gym twice a week
Output: {"title":"Gym session","reason":"...","scheduledTime":"07:00","iconId":"fitness","weekdays":null,"requiredDaysPerWeek":2}

User: read on weekdays
Output: {"title":"Read for 20 minutes","reason":"...","scheduledTime":"20:00","iconId":"book","weekdays":[1,2,3,4,5],"requiredDaysPerWeek":null}

User: go for a walk every weekend
Output: {"title":"Weekend walk","reason":"...","scheduledTime":"09:00","iconId":"walk","weekdays":[6,7],"requiredDaysPerWeek":null}`;

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
  weekdays: number[] | null;
  requiredDaysPerWeek: number | null;
}

interface QuotaResult {
  allowed: boolean;
  used: number;
  limit: number;
  resetsAt: string;
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
  metadata?: Record<string, unknown>,
): Response {
  return jsonResponse({ error: { code, message, ...metadata } }, status);
}

function isValidScheduledTime(value: unknown): value is string {
  return typeof value === "string" && /^([01]\d|2[0-3]):[0-5]\d$/.test(value);
}

function isValidIconId(value: unknown): value is IconId {
  return (
    typeof value === "string" && (ICON_IDS as readonly string[]).includes(value)
  );
}

function normalizeWeekdays(raw: unknown): number[] {
  if (!Array.isArray(raw)) return [1, 2, 3, 4, 5, 6, 7];
  const valid = [
    ...new Set(
      raw.filter((d): d is number => Number.isInteger(d) && d >= 1 && d <= 7),
    ),
  ].sort((a, b) => a - b);
  return valid.length > 0 ? valid : [1, 2, 3, 4, 5, 6, 7];
}

function parseRequiredDays(raw: unknown): number | null {
  if (typeof raw !== "number" || !Number.isInteger(raw)) return null;
  return raw >= 1 && raw <= 7 ? raw : null;
}

function parseSuggestion(raw: unknown): HabitSuggestionPayload | null {
  if (typeof raw !== "object" || raw === null) return null;
  const candidate = raw as Record<string, unknown>;
  const { title, reason, scheduledTime, iconId } = candidate;

  if (typeof title !== "string" || title.trim().length === 0) return null;
  if (typeof reason !== "string" || reason.trim().length === 0) return null;
  if (!isValidScheduledTime(scheduledTime)) return null;
  if (!isValidIconId(iconId)) return null;

  const normalizedWeekdays = candidate.weekdays === null
    ? null
    : normalizeWeekdays(candidate.weekdays);

  return {
    title: title.trim(),
    reason: reason.trim(),
    scheduledTime,
    iconId,
    weekdays: normalizedWeekdays,
    requiredDaysPerWeek: parseRequiredDays(candidate.requiredDaysPerWeek),
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
          { role: "system", content: SYSTEM_PROMPT },
          { role: "user", content: goal },
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
                weekdays: {
                  anyOf: [
                    {
                      type: "array",
                      items: { type: "integer" },
                      description:
                        "ISO weekday integers 1=Mon…7=Sun. Null when only a frequency count was provided.",
                    },
                    { type: "null" },
                  ],
                },
                requiredDaysPerWeek: {
                  anyOf: [
                    {
                      type: "integer",
                      description:
                        "How many days per week the user requested, when no specific days were named.",
                    },
                    { type: "null" },
                  ],
                },
              },
              required: [
                "title",
                "reason",
                "scheduledTime",
                "iconId",
                "weekdays",
                "requiredDaysPerWeek",
              ],
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

function parseQuotaResult(raw: unknown): QuotaResult | null {
  if (!Array.isArray(raw) || raw.length !== 1) return null;
  const candidate = raw[0];
  if (typeof candidate !== "object" || candidate === null) return null;

  const record = candidate as Record<string, unknown>;
  const allowed = record.allowed;
  const used = record.used;
  const limit = record.limit;
  const resetsAt = record.resets_at;

  if (typeof allowed !== "boolean") return null;
  if (!Number.isInteger(used) || typeof used !== "number") return null;
  if (!Number.isInteger(limit) || typeof limit !== "number") return null;
  if (typeof resetsAt !== "string" || resetsAt.length === 0) return null;

  return { allowed, used, limit, resetsAt };
}

async function consumeQuota(req: Request): Promise<QuotaResult> {
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY") ??
    Deno.env.get("SUPABASE_PUBLISHABLE_KEY");
  const authorization = req.headers.get("Authorization");

  if (!supabaseUrl || !supabaseAnonKey) {
    throw new Error("Supabase environment is not configured.");
  }
  if (!authorization) {
    throw new Error("Authorization header is missing.");
  }

  const response = await fetch(
    `${supabaseUrl}/rest/v1/rpc/consume_ai_quota`,
    {
      method: "POST",
      headers: {
        "Authorization": authorization,
        "apikey": supabaseAnonKey,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        target_function_name: "generate-habit",
        daily_limit: DAILY_QUOTA_LIMIT,
      }),
    },
  );

  if (!response.ok) {
    throw new Error(`Quota check failed with status ${response.status}.`);
  }

  const quota = parseQuotaResult(await response.json());
  if (quota === null) {
    throw new Error("Quota check returned an unexpected response.");
  }

  return quota;
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

  const authHeader = req.headers.get("Authorization") ?? "";
  const userId = parseUserIdFromJwt(authHeader);
  const bypassQuota = userId !== null &&
    isDeveloperBypass(userId, Deno.env.get("AI_QUOTA_BYPASS_USER_IDS"));

  if (!bypassQuota) {
    let quota: QuotaResult;
    try {
      quota = await consumeQuota(req);
    } catch (error) {
      console.error(
        "Quota check failed:",
        error instanceof Error ? error.message : "unknown error",
      );
      return errorResponse(
        500,
        "quota_check_failed",
        "Could not process this request right now.",
      );
    }

    if (!quota.allowed) {
      return errorResponse(
        429,
        "quota_exceeded",
        "Daily AI limit reached. Please try again tomorrow.",
        {
          used: quota.used,
          limit: quota.limit,
          resetsAt: quota.resetsAt,
        },
      );
    }
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
