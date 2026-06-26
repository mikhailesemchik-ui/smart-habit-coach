import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { isDeveloperBypass, parseUserIdFromJwt } from "./quota_bypass.ts";

// Builds a minimal Bearer token whose payload encodes the given UUID as `sub`.
function makeBearer(sub: string): string {
  const payloadJson = JSON.stringify({ sub, role: "authenticated" });
  const b64url = btoa(payloadJson)
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");
  return `Bearer eyJ.${b64url}.fakesig`;
}

const UUID_A = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee";
const UUID_B = "11111111-2222-3333-4444-555555555555";

// ── parseUserIdFromJwt ──────────────────────────────────────────────────────

Deno.test("parseUserIdFromJwt: extracts sub from a valid Bearer token", () => {
  assertEquals(parseUserIdFromJwt(makeBearer(UUID_A)), UUID_A);
});

Deno.test("parseUserIdFromJwt: returns null when Bearer prefix is missing", () => {
  assertEquals(parseUserIdFromJwt("not-a-bearer-token"), null);
});

Deno.test("parseUserIdFromJwt: returns null for a token with too few parts", () => {
  assertEquals(parseUserIdFromJwt("Bearer only.two"), null);
});

Deno.test("parseUserIdFromJwt: returns null for a non-JWT payload", () => {
  assertEquals(parseUserIdFromJwt("Bearer !!!.!!!.!!!"), null);
});

// ── isDeveloperBypass ───────────────────────────────────────────────────────

Deno.test("isDeveloperBypass: matching UUID bypasses quota", () => {
  assertEquals(isDeveloperBypass(UUID_A, UUID_A), true);
});

Deno.test("isDeveloperBypass: non-matching UUID does not bypass quota", () => {
  assertEquals(isDeveloperBypass(UUID_B, UUID_A), false);
});

Deno.test("isDeveloperBypass: missing allowlist does not bypass quota", () => {
  assertEquals(isDeveloperBypass(UUID_A, undefined), false);
});

Deno.test("isDeveloperBypass: blank allowlist does not bypass quota", () => {
  assertEquals(isDeveloperBypass(UUID_A, ""), false);
  assertEquals(isDeveloperBypass(UUID_A, "   "), false);
});

Deno.test("isDeveloperBypass: comma-only allowlist does not bypass quota", () => {
  assertEquals(isDeveloperBypass(UUID_A, ",,,"), false);
});

Deno.test("isDeveloperBypass: multiple comma-separated UUIDs all match", () => {
  const allowlist = `${UUID_A}, ${UUID_B}`;
  assertEquals(isDeveloperBypass(UUID_A, allowlist), true);
  assertEquals(isDeveloperBypass(UUID_B, allowlist), true);
});

Deno.test("isDeveloperBypass: non-listed UUID does not bypass with multi-entry allowlist", () => {
  const other = "99999999-8888-7777-6666-555555555555";
  assertEquals(isDeveloperBypass(other, `${UUID_A}, ${UUID_B}`), false);
});

Deno.test("isDeveloperBypass: trims whitespace around UUIDs in allowlist", () => {
  assertEquals(isDeveloperBypass(UUID_A, `  ${UUID_A}  `), true);
  assertEquals(isDeveloperBypass(UUID_A, ` ${UUID_B} , ${UUID_A} `), true);
});
