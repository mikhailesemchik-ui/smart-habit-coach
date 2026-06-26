/**
 * Extracts the `sub` claim (Supabase Auth user UUID) from a JWT that the
 * Supabase gateway has already validated (`verify_jwt = true`). Returns null
 * if the header is absent, the token has the wrong number of parts, or the
 * payload cannot be decoded and parsed. Never throws.
 */
export function parseUserIdFromJwt(authorization: string): string | null {
  if (!authorization.startsWith("Bearer ")) return null;
  const token = authorization.slice(7);
  const parts = token.split(".");
  if (parts.length !== 3) return null;

  try {
    // Base64url → base64: restore padding, swap URL-safe chars
    const raw = parts[1];
    const padded = raw + "=".repeat((4 - (raw.length % 4)) % 4);
    const decoded = atob(padded.replace(/-/g, "+").replace(/_/g, "/"));
    const claims = JSON.parse(decoded) as Record<string, unknown>;
    const sub = claims.sub;
    return typeof sub === "string" && sub.length > 0 ? sub : null;
  } catch {
    return null;
  }
}

/**
 * Returns true only when `userId` is found in the comma-separated
 * `AI_QUOTA_BYPASS_USER_IDS` allowlist passed as `allowlistRaw`.
 * Fails closed on every error path: missing, blank, or malformed input
 * returns false without bypassing quota. Never logs the allowlist.
 */
export function isDeveloperBypass(
  userId: string,
  allowlistRaw: string | undefined,
): boolean {
  if (!allowlistRaw || allowlistRaw.trim().length === 0) return false;
  const allowlist = allowlistRaw
    .split(",")
    .map((id) => id.trim())
    .filter((id) => id.length > 0);
  return allowlist.includes(userId);
}
