// Setup type definitions for built-in Supabase Runtime APIs
import "@supabase/functions-js/edge-runtime.d.ts";
import {
  isDeveloperBypass,
  parseUserIdFromJwt,
} from "../_shared/quota_bypass.ts";

const OPENAI_MODEL = "gpt-4o-mini";
const OPENAI_TIMEOUT_MS = 15_000;
const DAILY_QUOTA_LIMIT = 3;
const MAX_STREAK = 3650;
const MAX_COUNT = 100_000;
const MAX_RATE = 1;

const WEEKDAY_NAMES = [
  "Monday",
  "Tuesday",
  "Wednesday",
  "Thursday",
  "Friday",
  "Saturday",
  "Sunday",
] as const;

const SYSTEM_PROMPT = `You are a supportive habit-review assistant.

Your task is to create a concise weekly review using only the structured habit metrics provided in the request.

Never invent facts, causes, emotions, motivations, diagnoses, or user circumstances.

Core rules:
1. Use only the supplied metrics.
2. Do not infer why something happened unless the user explicitly recorded a reason.
3. Do not shame, blame, diagnose, or moralize.
4. Do not describe partial progress as failure.
5. Do not call one occurrence a pattern.
6. A repeated pattern requires at least 2 matching occurrences.
7. Keep statements specific, natural, and easy to understand.
8. Mention habit names for habit-specific observations.
9. Do not expose internal metric names, JSON keys, formulas, or implementation details.
10. Never include raw note text.
11. Do not recommend automatic habit changes.
12. Do not claim that a recommendation is guaranteed to work.

Completion terminology:
- Full completion means the habit target was fully reached.
- Minimum version means the easier minimum version of a binary habit was completed.
- Partial progress means the user logged a positive amount for a quantitative habit but did not reach its target.
- Missed means a scheduled habit had no completion or positive quantitative progress.
Never use the phrase "partial completion".
For quantitative habits, use "partial progress", "made progress", "logged progress", or "reached the target".
For minimum versions, use "used the minimum version" or "completed the minimum version".

Return exactly one JSON object with this shape:
{
  "whatWentWell": ["..."],
  "partialProgress": ["..."],
  "patterns": ["..."],
  "focusNextWeek": "..."
}
Do not return markdown, code fences, extra fields, or text outside the JSON.

whatWentWell: provide 1-2 concise factual observations. Prefer full completions, strong consistency, target reaches, maintained streaks, or the strongest habit. Avoid generic praise and do not say the user was disciplined, motivated, productive, or successful. When there is no positive recorded progress, use a neutral factual statement.

partialProgress: provide 0-2 factual observations. Mention minimum-version use for binary habits separately from quantitative partial progress. Do not call partial progress a failure, describe positive progress as missed, combine unrelated habits into one awkward sentence, use "partial completion", or repeatedly open with "A total of".

patterns: provide 0-2 factual repeated observations. A pattern requires at least 2 matching occurrences. Valid patterns include the same skip reason, the same partial-progress reason, partial progress on the same habit, Minimum Version use on the same habit, repeated full completion, or a clear gap between consistency and target completion. Do not call one event a pattern, merge unrelated habits merely because each has one event, infer unrecorded reasons, diagnose burnout, motivation, discipline, stress, mood, or health, or say the user "struggled" unless supplied data explicitly uses that wording.

focusNextWeek: return exactly one concise, practical focus grounded in supplied metrics. Priority order: repeated difficulty; repeated no-time reasons; repeated tiredness; repeated forgetting; repeated quantitative partial progress; repeated Minimum Version use; high consistency but low full completion; strong week without a clear problem; no scheduled data. Never recommend reminders unless forgot or forgotToContinue occurred at least twice. Never suggest reducing a target unless difficulty was recorded or repeated partial progress supports it. Do not recommend changing several habits at once. Do not provide several options joined by "or". Do not promise results. Do not tell the user to be more disciplined, motivated, consistent, or productive. The focus must be exactly one sentence.

Section separation:
- Do not duplicate the same fact across sections.
- What went well is for full achievements and strong engagement only.
- Do not put a plain quantitative partial-progress amount in whatWentWell.
- Put minimum-version use and quantitative below-target progress only in partialProgress.
Bad: "Logged progress on the steps habit with 8520 steps recorded." when the target was not reached.
Good: "You completed 'Evening walk' 3 times this week."
Good: "You engaged with 'Steps' on 6 of 7 scheduled days."

Habit-specific patterns:
- Each habit-specific pattern sentence must describe exactly one habit.
- Never join multiple habit titles in one pattern.
- Do not create aggregate habit lists.
- If more than 2 habit-specific patterns qualify, select the 2 strongest.
- Rank by repeated recorded reason count, then repeated partial/minimum occurrence count, then largest consistency versus full-completion gap.
Bad: "Repeated partial progress on the steps and 10k steps habits."
Good: "'Steps' had partial progress on 3 scheduled days."
Good: "'10k steps' had partial progress twice."
Allowed aggregate reason example: "Limited time was recorded 3 times."

Focus specificity:
- focusNextWeek must name one specific habit when habit data exists.
- focusNextWeek must contain one concrete action for one habit.
- Never refer to all habits, all scheduled habits, overall completion rates, general improvement, or habits the user wants to prioritize.
Bad: "Consider ways to improve completion rates for all scheduled habits."
Bad: "Try to be more consistent next week."
Bad: "Focus on improving your habits."
Good: "Try turning one partial 'Steps' day into a full target day next week."
Good: "Use the minimum version of 'Gym session' on one busy day instead of skipping it."
Good: "Protect one specific time slot for 'Evening walk' next week."
Good: "Set one reminder for 'Reading' on a day when it is commonly forgotten."

Quantitative grounding:
- Positive below-target progress is partial progress, never missed.
- Never call positive quantitative progress a missed day, skipped day, failed day, failure, or incomplete day.
- Never invent, estimate, interpolate, round, reduce, split, or suggest a numeric target.
- Only use numeric values supplied in the request: existing target values, exact logged values, averages, and counts.
- What went well must not contain raw below-target totals.
- For repeated quantitative partial progress, focusNextWeek must use one of these patterns:
  Good: "Try turning one partial 'Steps' day into a full target day next week."
  Good: "Aim to reach the 10,000-step target on one additional day next week."
- Use the stored target only if mentioning a target number.
Bad: "Try to reduce the number of missed days for 'Steps' by aiming for at least 7,000 steps next week."
Bad: "Aim for 7,000 steps."
Bad: "Try 8,000 steps instead."
Bad: "Increase your goal by 20%."
Style: supportive but not overly enthusiastic; calm, factual, and conversational; short sentences; natural singular/plural grammar; avoid corporate or clinical wording; maximum 2 sentences per list item; maximum 2 items per list.

Before responding, verify internally that every claim is supported by supplied data, no note text was used, no single event was called a pattern, quantitative partial progress was not called partial completion or missed, no numeric target was invented, reminder advice is supported by repeated forgetting, exactly one focus is returned, and output is valid JSON.`;

const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

interface ReasonCounts {
  [key: string]: number;
}

interface WeeklyHabitSummary {
  habitId: string;
  title: string;
  trackingType: "binary" | "quantitative";
  scheduledOccurrences: number;
  fullCompletions: number;
  minimumCompletions: number;
  partialOccurrences: number;
  missedOccurrences: number;
  consistencyOccurrences: number;
  completionRate: number;
  consistencyRate: number;
  currentStreak: number;
  bestStreak: number;
  targetValue: number | null;
  unit: string | null;
  totalLogged: number;
  averageProgress: number;
  averageLoggedAmount: number;
  skipReasons: ReasonCounts;
  partialReasons: ReasonCounts;
  missedWithoutReason: number;
  partialWithoutReason: number;
}

interface EligiblePattern {
  type: string;
  habitId?: string;
  habitTitle?: string;
  reason?: string;
  count: number;
}

interface FocusSignals {
  repeatedForgot: boolean;
  repeatedForgotToContinue: boolean;
  repeatedNoTime: boolean;
  repeatedTooTired: boolean;
  repeatedDifficulty: boolean;
  repeatedPartialProgress: boolean;
  repeatedMinimumUse: boolean;
  highConsistencyLowFullCompletion: boolean;
  strongWeek: boolean;
  noScheduledData: boolean;
  primaryHabitTitle?: string;
}

interface WeeklyReviewMetrics {
  completionRate: number;
  currentStreak: number;
  bestStreak: number;
  strongestDay: string | null;
  weakestDay: string | null;
  completedCount: number;
  minimumCompletedCount: number;
  totalPossibleCount: number;
  skipReasons: ReasonCounts;
  missedWithoutReason: number;
  partialReasons: ReasonCounts;
  partialWithoutReason: number;
  habitSummaries: WeeklyHabitSummary[];
  eligiblePatterns: EligiblePattern[];
  focusSignals: FocusSignals;
}

interface AiWeeklyReviewPayload {
  whatWentWell: string[];
  partialProgress: string[];
  patterns: string[];
  focusNextWeek: string;
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
  return isFiniteNumber(value) && Number.isInteger(value) && value >= 0 && value <= max;
}

function isNonNegativeNumber(value: unknown, max: number): value is number {
  return isFiniteNumber(value) && value >= 0 && value <= max;
}

function isRate(value: unknown): value is number {
  return isFiniteNumber(value) && value >= 0 && value <= MAX_RATE;
}

function isValidWeekday(value: unknown): value is string {
  return typeof value === "string" && (WEEKDAY_NAMES as readonly string[]).includes(value);
}

function isValidDayOrNull(value: unknown): value is string | null {
  return value === null || isValidWeekday(value);
}

function readString(value: unknown, maxLength = 120): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  if (trimmed.length === 0 || trimmed.length > maxLength) return null;
  return trimmed;
}

function parseReasonCounts(raw: unknown, keys: string[]): ReasonCounts | null {
  if (typeof raw !== "object" || raw === null) return null;
  const candidate = raw as Record<string, unknown>;
  const result: ReasonCounts = {};
  for (const key of keys) {
    const value = candidate[key];
    if (!isNonNegativeInt(value, MAX_COUNT)) return null;
    result[key] = value;
  }
  return result;
}

function parseHabitSummary(raw: unknown): WeeklyHabitSummary | null {
  if (typeof raw !== "object" || raw === null) return null;
  const candidate = raw as Record<string, unknown>;
  const habitId = readString(candidate.habitId);
  const title = readString(candidate.title);
  const trackingType = candidate.trackingType;
  const scheduledOccurrences = candidate.scheduledOccurrences;
  const fullCompletions = candidate.fullCompletions;
  const minimumCompletions = candidate.minimumCompletions;
  const partialOccurrences = candidate.partialOccurrences;
  const missedOccurrences = candidate.missedOccurrences;
  const consistencyOccurrences = candidate.consistencyOccurrences;
  const completionRate = candidate.completionRate;
  const consistencyRate = candidate.consistencyRate;
  const currentStreak = candidate.currentStreak;
  const bestStreak = candidate.bestStreak;
  const targetValue = candidate.targetValue;
  const unit = candidate.unit;
  const totalLogged = candidate.totalLogged;
  const averageProgress = candidate.averageProgress;
  const averageLoggedAmount = candidate.averageLoggedAmount;
  const skipReasons = parseReasonCounts(candidate.skipReasons, [
    "noTime",
    "forgot",
    "tooTired",
    "tooDifficult",
    "other",
  ]);
  const partialReasons = parseReasonCounts(candidate.partialReasons, [
    "noTime",
    "tooTired",
    "targetTooDifficult",
    "forgotToContinue",
    "other",
  ]);
  const missedWithoutReason = candidate.missedWithoutReason;
  const partialWithoutReason = candidate.partialWithoutReason;

  if (habitId === null || title === null) return null;
  if (trackingType !== "binary" && trackingType !== "quantitative") return null;
  if (!isNonNegativeInt(scheduledOccurrences, MAX_COUNT)) return null;
  if (!isNonNegativeInt(fullCompletions, MAX_COUNT)) return null;
  if (!isNonNegativeInt(minimumCompletions, MAX_COUNT)) return null;
  if (!isNonNegativeInt(partialOccurrences, MAX_COUNT)) return null;
  if (!isNonNegativeInt(missedOccurrences, MAX_COUNT)) return null;
  if (!isNonNegativeInt(consistencyOccurrences, MAX_COUNT)) return null;
  if (!isRate(completionRate) || !isRate(consistencyRate)) return null;
  if (!isNonNegativeInt(currentStreak, MAX_STREAK)) return null;
  if (!isNonNegativeInt(bestStreak, MAX_STREAK)) return null;
  if (targetValue !== null && !isNonNegativeNumber(targetValue, MAX_COUNT)) return null;
  if (unit !== null && typeof unit !== "string") return null;
  if (!isNonNegativeNumber(totalLogged, MAX_COUNT)) return null;
  if (!isNonNegativeNumber(averageProgress, MAX_COUNT)) return null;
  if (!isNonNegativeNumber(averageLoggedAmount, MAX_COUNT)) return null;
  if (skipReasons === null || partialReasons === null) return null;
  if (!isNonNegativeInt(missedWithoutReason, MAX_COUNT)) return null;
  if (!isNonNegativeInt(partialWithoutReason, MAX_COUNT)) return null;
  if (fullCompletions + minimumCompletions + partialOccurrences + missedOccurrences !== scheduledOccurrences) return null;

  return {
    habitId,
    title,
    trackingType,
    scheduledOccurrences,
    fullCompletions,
    minimumCompletions,
    partialOccurrences,
    missedOccurrences,
    consistencyOccurrences,
    completionRate,
    consistencyRate,
    currentStreak,
    bestStreak,
    targetValue: targetValue === null ? null : targetValue,
    unit: unit === null ? null : unit.trim(),
    totalLogged,
    averageProgress,
    averageLoggedAmount,
    skipReasons,
    partialReasons,
    missedWithoutReason,
    partialWithoutReason,
  };
}

function parseEligiblePattern(raw: unknown): EligiblePattern | null {
  if (typeof raw !== "object" || raw === null) return null;
  const candidate = raw as Record<string, unknown>;
  const type = readString(candidate.type);
  const count = candidate.count;
  const habitId = candidate.habitId === undefined ? undefined : readString(candidate.habitId);
  const habitTitle = candidate.habitTitle === undefined ? undefined : readString(candidate.habitTitle);
  const reason = candidate.reason === undefined ? undefined : readString(candidate.reason);
  if (type === null) return null;
  if (!isNonNegativeInt(count, MAX_COUNT) || count < 2) return null;
  if (habitId === null || habitTitle === null || reason === null) return null;
  return {
    type,
    count,
    ...(habitId === undefined ? {} : { habitId }),
    ...(habitTitle === undefined ? {} : { habitTitle }),
    ...(reason === undefined ? {} : { reason }),
  };
}

function parseFocusSignals(raw: unknown): FocusSignals | null {
  if (typeof raw !== "object" || raw === null) return null;
  const candidate = raw as Record<string, unknown>;
  const requiredBooleans = [
    "repeatedForgot",
    "repeatedForgotToContinue",
    "repeatedNoTime",
    "repeatedTooTired",
    "repeatedDifficulty",
    "repeatedPartialProgress",
    "repeatedMinimumUse",
    "highConsistencyLowFullCompletion",
    "strongWeek",
    "noScheduledData",
  ];
  for (const key of requiredBooleans) {
    if (typeof candidate[key] !== "boolean") return null;
  }
  const primaryHabitTitle = candidate.primaryHabitTitle === undefined
    ? undefined
    : readString(candidate.primaryHabitTitle);
  if (primaryHabitTitle === null) return null;
  return {
    repeatedForgot: candidate.repeatedForgot as boolean,
    repeatedForgotToContinue: candidate.repeatedForgotToContinue as boolean,
    repeatedNoTime: candidate.repeatedNoTime as boolean,
    repeatedTooTired: candidate.repeatedTooTired as boolean,
    repeatedDifficulty: candidate.repeatedDifficulty as boolean,
    repeatedPartialProgress: candidate.repeatedPartialProgress as boolean,
    repeatedMinimumUse: candidate.repeatedMinimumUse as boolean,
    highConsistencyLowFullCompletion: candidate.highConsistencyLowFullCompletion as boolean,
    strongWeek: candidate.strongWeek as boolean,
    noScheduledData: candidate.noScheduledData as boolean,
    ...(primaryHabitTitle === undefined ? {} : { primaryHabitTitle }),
  };
}

function parseMetrics(raw: unknown): WeeklyReviewMetrics | null {
  if (typeof raw !== "object" || raw === null) return null;
  const candidate = raw as Record<string, unknown>;
  const skipReasons = parseReasonCounts(candidate.skipReasons, [
    "noTime",
    "forgot",
    "tooTired",
    "tooDifficult",
    "other",
  ]);
  const partialReasons = parseReasonCounts(candidate.partialReasons, [
    "noTime",
    "tooTired",
    "targetTooDifficult",
    "forgotToContinue",
    "other",
  ]);
  const rawHabitSummaries = candidate.habitSummaries;
  if (!Array.isArray(rawHabitSummaries) || rawHabitSummaries.length > 50) return null;
  const habitSummaries = rawHabitSummaries.map(parseHabitSummary);
  if (habitSummaries.some((summary) => summary === null)) return null;

  const rawEligiblePatterns = candidate.eligiblePatterns;
  if (!Array.isArray(rawEligiblePatterns) || rawEligiblePatterns.length > 50) return null;
  const eligiblePatterns = rawEligiblePatterns.map(parseEligiblePattern);
  if (eligiblePatterns.some((pattern) => pattern === null)) return null;
  const focusSignals = parseFocusSignals(candidate.focusSignals);
  if (focusSignals === null) return null;

  const completionRate = candidate.completionRate;
  const currentStreak = candidate.currentStreak;
  const bestStreak = candidate.bestStreak;
  const strongestDay = candidate.strongestDay;
  const weakestDay = candidate.weakestDay;
  const completedCount = candidate.completedCount;
  const minimumCompletedCount = candidate.minimumCompletedCount;
  const totalPossibleCount = candidate.totalPossibleCount;
  const missedWithoutReason = candidate.missedWithoutReason;
  const partialWithoutReason = candidate.partialWithoutReason;

  if (!isRate(completionRate)) return null;
  if (!isNonNegativeInt(currentStreak, MAX_STREAK)) return null;
  if (!isNonNegativeInt(bestStreak, MAX_STREAK)) return null;
  if (!isValidDayOrNull(strongestDay)) return null;
  if (!isValidDayOrNull(weakestDay)) return null;
  if (!isNonNegativeInt(completedCount, MAX_COUNT)) return null;
  if (!isNonNegativeInt(minimumCompletedCount, MAX_COUNT)) return null;
  if (!isNonNegativeInt(totalPossibleCount, MAX_COUNT)) return null;
  if (completedCount > totalPossibleCount) return null;
  if (skipReasons === null || partialReasons === null) return null;
  if (!isNonNegativeInt(missedWithoutReason, MAX_COUNT)) return null;
  if (!isNonNegativeInt(partialWithoutReason, MAX_COUNT)) return null;

  return {
    completionRate,
    currentStreak,
    bestStreak,
    strongestDay,
    weakestDay,
    completedCount,
    minimumCompletedCount,
    totalPossibleCount,
    skipReasons,
    missedWithoutReason,
    partialReasons,
    partialWithoutReason,
    habitSummaries: habitSummaries as WeeklyHabitSummary[],
    eligiblePatterns: eligiblePatterns as EligiblePattern[],
    focusSignals,
  };
}

function parseStringList(raw: unknown, min: number, max: number): string[] | null {
  if (!Array.isArray(raw) || raw.length < min || raw.length > max) return null;
  const values = raw.map((item) => readString(item, 240));
  if (values.some((value) => value === null)) return null;
  return values as string[];
}

function parseAiWeeklyReview(raw: unknown): AiWeeklyReviewPayload | null {
  if (typeof raw !== "object" || raw === null) return null;
  const candidate = raw as Record<string, unknown>;
  const whatWentWell = parseStringList(candidate.whatWentWell, 1, 2);
  const partialProgress = parseStringList(candidate.partialProgress, 0, 2);
  const patterns = parseStringList(candidate.patterns, 0, 2);
  const focusNextWeek = readString(candidate.focusNextWeek, 240);
  if (whatWentWell === null || partialProgress === null || patterns === null || focusNextWeek === null) {
    return null;
  }
  return { whatWentWell, partialProgress, patterns, focusNextWeek };
}

function extractOutputText(payload: unknown): string | null {
  if (typeof payload !== "object" || payload === null) return null;
  const output = (payload as Record<string, unknown>).output;
  if (!Array.isArray(output)) return null;
  for (const item of output) {
    if (typeof item !== "object" || item === null) continue;
    if ((item as Record<string, unknown>).type !== "message") continue;
    const content = (item as Record<string, unknown>).content;
    if (!Array.isArray(content)) continue;
    for (const part of content) {
      if (typeof part !== "object" || part === null) continue;
      const record = part as Record<string, unknown>;
      if (record.type === "output_text" && typeof record.text === "string") {
        return record.text;
      }
    }
  }
  return null;
}

async function callOpenAi(metrics: WeeklyReviewMetrics, apiKey: string): Promise<unknown> {
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
          { role: "user", content: JSON.stringify(metrics) },
        ],
        text: {
          format: {
            type: "json_schema",
            name: "weekly_review",
            strict: true,
            schema: {
              type: "object",
              properties: {
                whatWentWell: {
                  type: "array",
                  minItems: 1,
                  maxItems: 2,
                  items: { type: "string" },
                },
                partialProgress: {
                  type: "array",
                  minItems: 0,
                  maxItems: 2,
                  items: { type: "string" },
                },
                patterns: {
                  type: "array",
                  minItems: 0,
                  maxItems: 2,
                  items: { type: "string" },
                },
                focusNextWeek: { type: "string" },
              },
              required: [
                "whatWentWell",
                "partialProgress",
                "patterns",
                "focusNextWeek",
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
  const response = await fetch(`${supabaseUrl}/rest/v1/rpc/consume_ai_quota`, {
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
  });
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
    return errorResponse(400, "invalid_json", "Request body must be valid JSON.");
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
    return errorResponse(500, "configuration_error", "The service is not configured correctly.");
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
      return errorResponse(500, "quota_check_failed", "Could not process this request right now.");
    }
    if (!quota.allowed) {
      return errorResponse(
        429,
        "quota_exceeded",
        "Daily AI limit reached. Please try again tomorrow.",
        { used: quota.used, limit: quota.limit, resetsAt: quota.resetsAt },
      );
    }
  }

  let openAiPayload: unknown;
  try {
    openAiPayload = await callOpenAi(metrics, apiKey);
  } catch (error) {
    if (error instanceof DOMException && error.name === "AbortError") {
      console.error("OpenAI request timed out.");
      return errorResponse(504, "upstream_timeout", "The request took too long. Please try again.");
    }
    console.error(
      "OpenAI request failed:",
      error instanceof Error ? error.message : "unknown error",
    );
    return errorResponse(502, "upstream_error", "Could not generate a weekly review right now.");
  }

  const outputText = extractOutputText(openAiPayload);
  if (outputText === null) {
    console.error("OpenAI response did not contain output text.");
    return errorResponse(502, "upstream_error", "Could not generate a weekly review right now.");
  }

  let parsedJson: unknown;
  try {
    parsedJson = JSON.parse(outputText);
  } catch {
    console.error("OpenAI output text was not valid JSON.");
    return errorResponse(502, "invalid_model_output", "Could not generate a weekly review right now.");
  }

  const review = parseAiWeeklyReview(parsedJson);
  if (review === null) {
    console.error("OpenAI output did not match the expected review shape.");
    return errorResponse(502, "invalid_model_output", "Could not generate a weekly review right now.");
  }

  return jsonResponse(review, 200);
});




