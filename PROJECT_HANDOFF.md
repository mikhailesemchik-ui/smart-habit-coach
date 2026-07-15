# PROJECT_HANDOFF.md

## Project snapshot

Project: Smart Habit Coach
Local path: `D:\new_life\Smart_Habit_Coach`
Primary branch: `main`

This file tracks phase-by-phase completion status. It is updated at the
end of each phase — read it before starting new work, alongside
`AGENTS.md`.

## Phase status

| Phase | Scope | Status |
|---|---|---|
| 0 | Functional audit (baseline before local-first work) | Complete |
| 1A | Local schema versioning, UID namespacing, legacy migration, first-launch identity gate | Complete |
| 1B | Centralized mutation pipeline (`Clock`-stamped `updatedAt`, dirty-marking) | Complete |
| 1C | Tombstones, `SyncMetadata`, `RecoverySnapshot` primitives | Complete |
| 2A | Supabase auth API verification spike | Complete |
| 2B | Auth UI: anonymous → link → sign-in/out, S1/S2 identity-switch handling | Complete |
| 3 | Cloud schema (composite-key tables, RLS, cascade), cloud repositories | Complete |
| 4 | Explicit "Sync now" engine: handshake, deterministic merge, dirty ack, recovery snapshot, UseLocalDeviceData | Complete |
| 5 | Archive restore/permanent-delete, notification permission status + reconciliation | Complete |
| 6 | Privacy screen, local data export | Complete |
| 7 | Account deletion (Edge Function + client orchestration + local cleanup) | Complete |
| 8 | Hardening: accessibility semantics, duplicate-submit guards, error-copy audit, test noise fix | Complete |
| 9 | CI workflow, test/architecture docs, repo-quality cleanup | Complete |
| 10 | Manual / real-device smoke QA (superficial, one device) | Complete — see `docs/manual_qa_phase_10.md` |
| 11 | Release-signing readiness, final validation, final audit (this phase) | Complete — see `docs/final_release_readiness_phase_11.md` |

Phase 11 delivered **signing readiness**, not a shippable release: no
real keystore was created or committed, no signed release build has been
produced, and no store metadata exists. See
`docs/final_release_readiness_phase_11.md` §11 for what's still required
before a Google Play submission.

## What's implemented

See `docs/architecture.md` for the technical summary and `README.md` for
the user-facing feature overview. In short: local-first UID-scoped habit
tracking, an anonymous-by-default Supabase account you can upgrade to
email/password, fully manual/explicit cloud sync, a local Adaptive Habit
Coach, AI-assisted habit setup and weekly review, local data export, a
Privacy screen, and full account deletion (client + Edge Function +
cascading cloud cleanup).

## Verification

```bash
dart format lib test
flutter analyze
flutter test
git diff --check
```

Or run `scripts/test_all.ps1` (Windows) / `scripts/test_all.sh` (POSIX),
which run the same four steps in order. See `docs/testing.md` for focused
suites and what the tests do/don't require (no real Supabase project, no
network, no signing).

Last known full-suite status (end of Phase 11): **1035/1035 tests
passed**, `flutter analyze` clean. Re-run locally to confirm current
numbers before relying on this.

## CI

`.github/workflows/flutter-ci.yml` runs format/analyze/test on every
push/PR to `main`. It needs no secrets — every test that would otherwise
touch Supabase, notifications, or the network runs against an injected
fake instead.

## Environment / secrets

See the "Environment variables" table in `README.md`. In short: only
`SUPABASE_URL` and `SUPABASE_ANON_KEY` (both public) are ever passed to
the Flutter client, via `--dart-define`. `SUPABASE_SERVICE_ROLE_KEY` and
`OPENAI_API_KEY` exist only as Supabase project/Edge Function secrets and
must never appear in Flutter code, dart-defines, or commits.

## Edge Function deploy commands

```bash
npx supabase functions deploy generate-habit
npx supabase functions deploy generate-weekly-review
npx supabase functions deploy delete-account
```

After any function change: redeploy the affected function(s), verify an
authenticated call succeeds and an unauthenticated call is rejected. Local
config changes do not update a hosted project by themselves.

## Before starting new work

```bash
git status -sb
git log -3 --oneline
```

Read `AGENTS.md` first, then this file, then inspect only what's relevant
to the requested task.

## Release signing

Release builds require a local, git-ignored `android/key.properties`
pointing at a real keystore — see `docs/release_signing.md`. Without it,
`flutter build apk/appbundle --release` fails fast by design; the release
build type never falls back to debug signing.

## Next steps (not started)

Not part of any completed phase; do not start without an explicit
request:

- A real release keystore and a signed release build, manually installed
  and tested on at least one device.
- Deeper manual/device QA beyond the Phase 10 smoke test: notification
  permission prompts and long-term delivery, offline/online transitions,
  multi-device sync, and account deletion end-to-end against a real
  (disposable/test) Supabase project.
- iOS device QA (Phase 10 covered Android only).
- Play Store listing metadata and submission.
