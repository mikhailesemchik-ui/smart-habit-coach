// Setup type definitions for built-in Supabase Runtime APIs
import "@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "@supabase/supabase-js";
import { parseUserIdFromJwt } from "../_shared/quota_bypass.ts";

const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function jsonResponse(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

function errorResponse(status: number, code: string, message: string): Response {
  return jsonResponse({ success: false, error: { code, message } }, status);
}

/**
 * Deletes the authenticated caller's own Supabase Auth user and, by
 * `on delete cascade`, every user-owned row in `habits`,
 * `adaptive_suggestions`, `user_preferences`, and `ai_request_quotas`.
 *
 * Security model:
 * - `verify_jwt = true` (supabase/config.toml) rejects any request without
 *   a valid Supabase-issued JWT before this handler ever runs.
 * - The user id being deleted is derived *only* from that already-verified
 *   JWT's `sub` claim — the request body is never read for a user id, so a
 *   caller can never ask this function to delete anyone but themselves.
 * - The service-role key is read from an environment variable available
 *   only to this server-side function; it is never sent to, stored in, or
 *   reachable from the Flutter client.
 */
Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }

  if (req.method !== "POST") {
    return errorResponse(405, "method_not_allowed", "Only POST is supported.");
  }

  const authorization = req.headers.get("Authorization") ?? "";
  const userId = parseUserIdFromJwt(authorization);
  if (userId === null) {
    return errorResponse(401, "unauthenticated", "Authentication is required.");
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) {
    console.error("delete-account: server environment is not configured.");
    return errorResponse(
      500,
      "configuration_error",
      "The service is not configured correctly.",
    );
  }

  const adminClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  // Deleting the auth user is the single pivot point: on success, cascade
  // removes every user-owned row as an automatic Postgres consequence, not
  // as a separate step that could independently fail.
  const { error } = await adminClient.auth.admin.deleteUser(userId);
  if (error) {
    console.error(
      "delete-account: admin deleteUser failed for a user.",
      error.status ?? "unknown status",
    );
    return errorResponse(
      502,
      "remote_deletion_failed",
      "Could not delete the account right now. Please try again.",
    );
  }

  return jsonResponse({ success: true }, 200);
});

/* To invoke locally:

  1. Run `supabase start` (see: https://supabase.com/docs/reference/cli/supabase-start)
  2. Make an HTTP request with a real user access token:

  curl -i --location --request POST 'http://127.0.0.1:54321/functions/v1/delete-account' \
    --header 'Authorization: Bearer <user-access-token>'

*/
