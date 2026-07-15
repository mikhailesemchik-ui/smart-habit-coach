# Phase 11 — Final release readiness

## 1. Executive summary

Smart Habit Coach is functionally complete through Phase 10 and now has
safe, documented release-signing readiness (Phase 11). The codebase is
clean (`flutter analyze`: no issues) and the full automated test suite
passes (1035/1035). A debug build was produced successfully on this
machine; a **release** build was intentionally exercised and correctly
**fails fast** because no local signing keystore exists — this is by
design, not a defect (see §5–6).

The app is **not** ready for a Google Play submission: it has not been
signed with a real release key, has not had a release build installed
and exercised on a device, and has had only a single superficial
smoke-QA pass (Phase 10) on one device/OS combination.

## 2. Completed phase list

| Phase | Scope | Status |
|---|---|---|
| 0 | Functional audit baseline | Complete |
| 1A–1C | Local schema versioning, UID namespacing, mutation pipeline, tombstones/sync metadata/recovery snapshot | Complete |
| 2A–2B | Supabase auth spike + UI (anonymous → link → sign-in/out) | Complete |
| 3 | Cloud schema (RLS, cascade), cloud repositories | Complete |
| 4 | Explicit "Sync now" engine | Complete |
| 5 | Archive restore/delete, notification reconciliation | Complete |
| 6 | Privacy screen, local data export | Complete |
| 7 | Account deletion (Edge Function + client orchestration) | Complete |
| 8 | Accessibility/async hardening | Complete |
| 9 | CI workflow, test/architecture docs | Complete |
| 10 | Manual/device smoke QA (superficial) | Complete (limited scope — see Phase 10 doc) |
| 11 | Release signing readiness, final validation, final audit (this phase) | Complete |

No Phase 12 or new product features were started.

## 3. Automated validation results

Run on this machine, this session, after the Phase 11 changes:

```
dart format lib test   → Formatted 196 files (0 changed)
flutter analyze         → No issues found!
flutter test             → 1035/1035 passed
git diff --check         → exit 0 (no whitespace/conflict issues)
```

An earlier `flutter test` attempt in this session crashed at the Dart VM
level with an out-of-memory native allocation failure; this was traced to
host machine memory pressure (a concurrent Gradle daemon also crashed
with the same native OOM signature at the same time), not a code defect.
Re-run once the machine had freed memory: clean pass, 1035/1035.

## 4. Manual QA status (Phase 10)

Unchanged from `docs/manual_qa_phase_10.md`: one superficial smoke test
on a single physical device (Samsung SM-G990B, Android 15/API 35),
confirming the app builds, installs, and launches without crashing
against a live Supabase project. Deep flows (sync, notifications, AI
features, account deletion, offline/online transitions, multi-device
sync) remain **not deeply verified on-device** — see that document's
§7 for the full list. Phase 11 did not add any new device QA.

## 5. Signing readiness status

Resolves Phase 0 finding `AUDIT-P1-001`.

- `android/app/build.gradle.kts` now reads `android/key.properties`
  (git-ignored, local-only) at configure time.
- If all four required fields (`storeFile`, `storePassword`, `keyAlias`,
  `keyPassword`) are present, the `release` build type is signed with
  that real keystore.
- If the file is missing or incomplete, the `release` build type has
  **no** signing config, and `assembleRelease`/`bundleRelease` fail
  immediately with a clear message pointing to
  `docs/release_signing.md`. It never falls back to the debug keystore.
- `docs/release_signing.md` documents keystore creation
  (`keytool -genkey`), the exact `key.properties` fields (placeholders
  only), and confirms these files must never be committed.
- No real keystore, password, or `key.properties` file was created or
  committed as part of this phase.

Verified in this session: with no `android/key.properties` present,
`flutter build apk --release` compiled Dart/Kotlin successfully and then
failed at the `assembleRelease` Gradle task with exactly the intended
error message — confirming the guard works and does not silently
produce a debug-signed release artifact.

## 6. Release build status

| Build | Result |
|---|---|
| `flutter build apk --debug` (with real Supabase URL, placeholder anon key) | **Succeeded** — `build/app/outputs/flutter-apk/app-debug.apk` |
| `flutter build apk --release` (no local keystore) | **Failed by design** — release signing guard blocked it with a clear error, as intended |
| `flutter build appbundle --release` | Not attempted — would fail identically without a keystore; no value in re-demonstrating the same guard |

No APK/AAB was committed; build output lives only under the git-ignored
`build/` directory and was not staged.

A real release build has not been produced, signed, installed, or
manually tested on a device in this repository's history. Producing one
requires a developer to create a local keystore per
`docs/release_signing.md` — a deliberately manual, non-automated step.

## 7. Supabase readiness

- Two migrations exist (`20260625173853_add_ai_request_quotas.sql`,
  `20260708120000_add_user_data_tables.sql`) defining
  `ai_request_quotas`, `habits`, `adaptive_suggestions`, and
  `user_preferences`, all with row-level security scoped to
  `auth.uid() = user_id` and `on delete cascade` from `auth.users`.
- Three Edge Functions exist (`delete-account`, `generate-habit`,
  `generate-weekly-review`), all requiring a valid Supabase JWT
  (`verify_jwt = true`).
- The Supabase CLI was **not** invoked in this phase (no `supabase db
  lint`/`migration list`/`functions list` run) — its availability in
  this environment was not re-verified this session. Treat as
  unconfirmed rather than assuming it is installed.
- No destructive or remote Supabase commands were run.

## 8. Account deletion Edge Function readiness

Unchanged from Phase 7/9: `supabase/functions/delete-account/index.ts`
derives the user id to delete solely from the caller's JWT (never the
request body), uses the service-role key only via
`Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")` (never hardcoded, never
present in the Flutter client), and Postgres cascade handles cleanup of
all user-owned rows. `test/supabase/delete_account_function_test.dart`
statically asserts all of this against the function's actual source —
these tests passed in this session's full run.

This function has **not** been exercised against a real, deployed
Supabase project in Phase 11. Any live testing of account deletion must
use a disposable/test account only, never a real user account.

## 9. Secret audit result

Full-repo `git grep` (excluding lockfiles) for: `SUPABASE_SERVICE_ROLE_KEY`,
`service_role`, `access_token`, `refresh_token`, `OPENAI_API_KEY`, `sk-`,
`eyJ`, `password=`, `private_key`, `keyPassword`, `storePassword`,
`keyAlias`, `.jks`, `.keystore`, `key.properties`,
`account_refresh_error`, `build/app/outputs`, `.apk`, `.aab`.

| Finding | Classification |
|---|---|
| `SUPABASE_SERVICE_ROLE_KEY` / `service_role` mentions in README/PROJECT_HANDOFF/AGENTS/docs | Allowed — documentation naming the env var, no value |
| `Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")` / `Deno.env.get("OPENAI_API_KEY")` in Edge Functions | Allowed — server-side env access, no literal secret |
| `service_role`/`SUPABASE_SERVICE_ROLE`/`OPENAI_API_KEY`/`access_token`/`refresh_token` strings in test files | Allowed — tests asserting these strings are *absent* from exports/migrations/functions |
| `keyPassword`/`storePassword`/`keyAlias` property-name references in `build.gradle.kts` | Allowed — property-name lookups against a git-ignored local file, no values |
| `eyJ.${b64url}.fakesig` in a test helper; `isNot(contains('eyJhbGciOi'))` in a test | Allowed — synthetic fake JWT shape for a test double, and an assertion that a real JWT prefix is absent |
| `*.jks` / `*.keystore` / `key.properties` entries in `.gitignore` (root and `android/`) | Allowed — ignore rules, not secrets |
| `*.apk` / `*.aab` entries in `.gitignore` | Allowed — ignore rules |
| `sk-`, `password=`, `private_key`, `account_refresh_error`, `build/app/outputs` | **Zero matches** |
| Tracked `.jks`/`.keystore`/`key.properties`/`.apk`/`.aab` files (`git ls-files` check) | **Zero matches** |

**No suspicious findings. No real secrets, keystores, or build artifacts
are tracked in the repository.**

## 10. Known limitations

- Phase 10 was a superficial smoke QA pass on one device, not exhaustive
  device QA — deep flows (sync, notifications, AI, account deletion,
  offline/online transitions) are not manually verified on-device.
- Multi-device sync has not been manually verified.
- Long-term/scheduled notification delivery (across reboots, battery
  optimization, extended time) has not been manually verified.
- Account deletion has only been verified via static source-inspection
  tests, not against a real deployed project; any live test must use a
  disposable account.
- Release signing requires a local keystore that does not exist in this
  repository and must be created per `docs/release_signing.md` before a
  publishable release build is possible.
- Supabase CLI availability in this environment was not reconfirmed this
  session.
- No release APK/AAB has ever been built, signed, or installed from this
  repository.
- No Play Store listing, metadata, or submission material exists.

## 11. Final recommendation

**Not ready for a Google Play submission.** The codebase is clean and
fully covered by a passing automated suite, and release-signing
readiness is now safely documented and enforced (no debug-signed release
is possible). What remains before a real submission: (1) create and
securely store a real release keystore, (2) produce and manually install
a real signed release build on at least one device, (3) exercise the
deep flows listed in §10 on that build, and (4) prepare Play Store
listing/metadata — all explicitly out of scope for this phase.
