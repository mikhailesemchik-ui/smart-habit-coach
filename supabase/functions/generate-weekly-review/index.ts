// Setup type definitions for built-in Supabase Runtime APIs
import "@supabase/functions-js/edge-runtime.d.ts";
import {
  isDeveloperBypass,
  parseUserIdFromJwt,
} from "../_shared/quota_bypass.ts";

const OPENAI_MODEL = "gpt-4o-mini";
const OPENAI_TIMEOUT_MS = 15_000;
const DAILY_QUOTA_LIMIT = 3;

const MAX_STREAK = 3650; // ~10 years; guards against bogus client input
const MAX_COUNT = 100_000;

const WEEKDAY_NAMES = [
  "Monday",
  "Tuesday",
  "Wednesday",
  "Thursday",
  "Friday",
  "Saturday",
  "Sunday",
] as const;

const SYSTEM_PROMPT = `You are a supportive, neutral habit-coaching assistant writing a short weekly review from already-calculated stats. Use only the supplied numbers and day names in the user message вЂ” never invent, estimate, or recalculate any statistic, day, count, cause, emotion, goal, or personal circumstance.

Tone rules:
- Be supportive and neutral. Never shame, blame, criticize, or imply laziness or lack of effort.
- Never infer a reason for an unlabelled miss, and never invent causes.
- Never use generic filler phrases such as "keep up the good work", "build momentum", "try harder", or "best effort" (or close variants of them).
- Do not repeat the same metric (the same percentage or count) in more than one field. Avoid duplicating day names or counts across fields unless naming a day is necessary to point to an action.

Field rules:
- summary: exactly one short sentence describing the overall pattern of the week. Do not restate the exact completion percentage вЂ” it is already shown elsewhere in the app.
- strongestInsight: exactly one short, neutral sentence about the supplied strongestDay. If strongestDay is null, note there wasn't a single standout day.
- weakestInsight: exactly one short, neutral sentence about the supplied weakestDay, without judgment. If weakestDay is null, note there wasn't a single low day this week.
- recommendation: exactly one concrete, behavior-based action for next week.
  - If completion is already strong, recommend maintaining the current routine rather than adding something new or more complex.
  - If weakestDay looks like it had no completions at all (for example because completedCount is low relative to totalPossibleCount), suggest one small, easy habit for that specific day rather than a broad change.

Examples below are for tone and style only вЂ” never reuse their numbers or wording, only the metrics supplied in the actual user message.

Example A вЂ” low completion:
Input: {"completionPercent":20,"currentStreak":0,"bestStreak":3,"strongestDay":"Tuesday","weakestDay":"Friday","completedCount":4,"totalPossibleCount":20}
Output: {"summary":"This week had a slower pace than usual.","strongestInsight":"Tuesday was the day you stayed most on track.","weakestInsight":"Friday saw the least activity this week.","recommendation":"Pick one habit to complete on Friday next week, even just once."}

Example B вЂ” partial completion:
Input: {"completionPercent":55,"currentStreak":2,"bestStreak":4,"strongestDay":"Wednesday","weakestDay":"Sunday","completedCount":11,"totalPossibleCount":20}
Output: {"summary":"Progress was steady with a few uneven days.","strongestInsight":"Wednesday had your most completed habits.","weakestInsight":"Sunday had fewer completions than the rest of the week.","recommendation":"Set a specific time on Sunday for just one habit to even out the week."}

Example C вЂ” strong completion:
Input: {"completionPercent":90,"currentStreak":6,"bestStreak":6,"strongestDay":"Monday","weakestDay":"Thursday","completedCount":18,"totalPossibleCount":20}
Output: {"summary":"This was a highly consistent week across most days.","strongestInsight":"Monday had every habit completed.","weakestInsight":"Thursday was slightly lower than the rest of the week.","recommendation":"Keep the same routine next week rather than adding new habits."}

Example D вЂ” weakest day with no completions:
Input: {"completionPercent":35,"currentStreak":1,"bestStreak":3,"strongestDay":"Tuesday","weakestDay":"Saturday","completedCount":7,"totalPossibleCount":20}
Output: {"summary":"Activity was concentrated on a few days this week.","strongestInsight":"Tuesday was your most active day.","weakestInsight":"Saturday didn't have any completed habits.","recommendation":"Choose one easy habit to do on Saturday next week, like a two-minute version of it."}`;

const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

interface SkipReasonCounts {
  noTime: number;
  forgot: number;
  tooTired: number;
  tooDifficult: number;
  other: number;
}

interface WeeklyReviewMetrics {
  completionRate: number;
  currentStreak: number;
  bestStreak: number;
  strongestDay: string | null;
  weakestDay: string | null;
  completedCount: number;
  totalPossibleCount: number;
  skipReasons: SkipReasonCounts;
  missedWithoutReason: number;
}

interface AiWeeklyReviewPayload {
  summary: string;
  strongestInsight: string;
  weakestInsight: string;
  recommendation: string;
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

function isFiniteNumber(value: unknown): value is number {
  return typeof value === "number" && Number.isFinite(value);
}

function isNonNegativeInt(value: unknown, max: number): value is number {
  return (
    isFiniteNumber(value) &&
    Number.isInteger(value) &&
    value >= 0 &&
    value <= max
  );
}

function isValidWeekday(value: unknown): value is string {
  return (
    typeof value === "string" &&
    (WEEKDAY_NAMES as readonly string[]).includes(value)
  );
}

function isValidDayOrNull(value: unknown): value is string | null {
  return value === null || isValidWeekday(value);
}

function parseSkipReasonCounts(raw: unknown): SkipReasonCounts | null {
  if (typeof raw !== "object" || raw === null) return null;
  const candidate = raw as Record<string, unknown>;
  const { noTime, forgot, tooTired, tooDifficult, other } = candidate;
  if (!isNonNegativeInt(noTime, MAX_COUNT)) return null;
  if (!isNonNegativeInt(forgot, MAX_COUNT)) return null;
  if (!isNonNegativeInt(tooTired, MAX_COUNT)) return null;
  if (!isNonNegativeInt(tooDifficult, MAX_COUNT)) return null;
  if (!isNonNegativeInt(other, MAX_COUNT)) return null;
  return { noTime, forgot, tooTired, tooDifficult, other };
}

// Parses and validates the request body into WeeklyReviewMetrics. Returns
// null if any field is missing, the wrong type, or out of a reasonable
// range.
function parseMetrics(raw: unknown): WeeklyReviewMetrics | null {
  if (typeof raw !== "object" || raw === null) return null;
  const candidate = raw as Record<string, unknown>;

  const {
    completionRate,
    currentStreak,
    bestStreak,
    strongestDay,
    weakestDay,
    completedCount,
    totalPossibleCount,
    skipReasons,
    missedWithoutReason,
  } = candidate;

  if (
    !isFiniteNumber(completionRate) ||
    completionRate < 0 ||
    completionRate > 1
  ) {
    return null;
  }
  if (!isNonNegativeInt(currentStreak, MAX_STREAK)) return null;
  if (!isNonNegativeInt(bestStreak, MAX_STREAK)) return null;
  if (!isValidDayOrNull(strongestDay)) return null;
  if (!isValidDayOrNull(weakestDay)) return null;
  if (!isNonNegativeInt(completedCount, MAX_COUNT)) return null;
  if (!isNonNegativeInt(totalPossibleCount, MAX_COUNT)) return null;
  if (completedCount > totalPossibleCount) return null;
  const parsedSkipReasons = parseSkipReasonCounts(skipReasons);
  if (parsedSkipReasons === null) return null;
  if (!isNonNegativeInt(missedWithoutReason, MAX_COUNT)) return null;

  return {
    completionRate,
    currentStreak,
    bestStreak,
    strongestDay,
    weakestDay,
    completedCount,
    totalPossibleCount,
    skipReasons: parsedSkipReasons,
    missedWithoutReason,
  };
}

function parseAiWeeklyReview(raw: unknown): AiWeeklyReviewPayload | null {
  if (typeof raw !== "object" || raw === null) return null;
  const candidate = raw as Record<string, unknown>;
  const { summary, strongestInsight, weakestInsight, recommendation } =
    candidate;

  if (typeof summary !== "string" || summary.trim().length === 0) {
    return null;
  }
  if (
    typeof strongestInsight !== "string" ||
    strongestInsight.trim().length === 0
  ) {
    return null;
  }
  if (
    typeof weakestInsight !== "string" ||
    weakestInsight.trim().length === 0
  ) {
    return null;
  }
  if (
    typeof recommendation !== "string" ||
    recommendation.trim().length === 0
  ) {
    return null;
  }

  return {
    summary: summary.trim(),
    strongestInsight: strongestInsight.trim(),
    weakestInsight: weakestInsight.trim(),
    recommendation: recommendation.trim(),
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

async function callOpenAi(
  metrics: WeeklyReviewMetrics,
  apiKey: string,
): Promise<unknown> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), OPENAI_TIMEOUT_MS);

  const completionPercent = Math.round(metrics.completionRate * 100);

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
            content: SYSTEM_PROMPT,
          },
          {
            role: "user",
            content: JSON.stringify({
              completionPercent,
              currentStreak: metrics.currentStreak,
              bestStreak: metrics.bestStreak,
              strongestDay: metrics.strongestDay,
              weakestDay: metrics.weakestDay,
              completedCount: metrics.completedCount,
              totalPossibleCount: metrics.totalPossibleCount,
              skipReasons: metrics.skipReasons,
              missedWithoutReason: metrics.missedWithoutReason,
            }),
          },
        ],
        text: {
          format: {
            type: "json_schema",
            name: "weekly_review",
            strict: true,
            schema: {
              type: "object",
              properties: {
                summary: {
                  type: "string",
                  description:
                    "One short, neutral sentence on the week's overall " +
                    "pattern. Do not state the exact completion " +
                    "percentage; it's already shown elsewhere.",
                },
                strongestInsight: {
                  type: "string",
                  description:
                    "One short, neutral sentence about the supplied " +
                    "strongestDay. If strongestDay is null, note there " +
                    "wasn't a clear standout day.",
                },
                weakestInsight: {
                  type: "string",
                  description:
                    "One short, non-judgmental sentence about the " +
                    "supplied weakestDay. If weakestDay is null, note " +
                    "there wasn't a clear low day.",
                },
                recommendation: {
                  type: "string",
                  description:
                    "Exactly one concrete, behavior-based action for " +
                    "next week. Suggest maintaining the routine if " +
                    "completion is already strong, or one small habit " +
                    "for the weakest day if it likely had no " +
                    "completions.",
                },
              },
              required: [
                "summary",
                "strongestInsight",
                "weakestInsight",
                "recommendation",
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
        target_function_name: "generate-weekly-review",
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

  const metrics = parseMetrics(body);
  if (metrics === null) {
    return errorResponse(
      400,
      "invalid_metrics",
      "Request body did not contain valid weekly review metrics.",
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
    openAiPayload = await callOpenAi(metrics, apiKey);
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
      "Could not generate a weekly review right now.",
    );
  }

  const outputText = extractOutputText(openAiPayload);
  if (outputText === null) {
    console.error("OpenAI response did not contain output text.");
    return errorResponse(
      502,
      "upstream_error",
      "Could not generate a weekly review right now.",
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
      "Could not generate a weekly review right now.",
    );
  }

  const review = parseAiWeeklyReview(parsedJson);
  if (review === null) {
    console.error("OpenAI output did not match the expected review shape.");
    return errorResponse(
      502,
      "invalid_model_output",
      "Could not generate a weekly review right now.",
    );
  }

  return jsonResponse(review, 200);
});

/* To invoke locally:

  1. Run `supabase start` (see: https://supabase.com/docs/reference/cli/supabase-start)
  2. Make an HTTP request:

  curl -i --location --request POST 'http://127.0.0.1:54321/functions/v1/generate-weekly-review' \
    --header 'Content-Type: application/json' \
    --data '{
      "completionRate": 0.45,
      "currentStreak": 2,
      "bestStreak": 5,
      "strongestDay": "Wednesday",
      "weakestDay": "Sunday",
      "completedCount": 9,
      "totalPossibleCount": 20,
      "skipReasons": {"noTime": 3,"forgot": 1,"tooTired": 4,"tooDifficult": 0,"other": 1},
      "missedWithoutReason": 2
    }'

*/

