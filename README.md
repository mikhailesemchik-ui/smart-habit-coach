# Smart Habit Coach

A local-first Flutter habit tracker with adaptive, AI-assisted coaching and
optional cloud sync.

## Overview

- Daily/weekly habit tracking (binary and quantitative), streaks, and
  progress statistics — works fully offline once the app has been opened
  once.
- A locally-computed Adaptive Habit Coach that detects struggling habits
  from usage patterns and proposes concrete adjustments (no AI involved).
- AI Habit Setup and AI Weekly Review, both backed by Supabase Edge
  Functions calling OpenAI, with a deterministic local fallback for the
  weekly review.
- Optional Supabase account (anonymous by default, upgradeable to
  email/password) with explicit, manual cloud sync — never automatic or
  background.
- Local data export and a Privacy screen explaining what's stored where.
- Full account deletion, including cloud data.

See `docs/architecture.md` for how these fit together.

## Architecture at a glance

- **Local-first, UID-scoped storage.** Every user's data lives under
  `<key>:<uid>` in `SharedPreferences`. Different identities (anonymous or
  email) on the same device never share or merge data.
- **Auth.** Supabase anonymous sign-in on first launch; can be upgraded to
  email/password in place, or replaced by a returning user's sign-in with
  an explicit "preserve local data" step.
- **Sync.** Manual "Sync now" only — no background sync. Deterministic
  last-write-wins merge with explicit tombstone handling.
- **Privacy, export, and account deletion.** A Privacy screen explains
  local/cloud/AI data handling; users can export their local data as JSON,
  or permanently delete their account (email-backed accounts only).
- **Notifications.** Local reminders, reconciled (cancelled and
  rescheduled) whenever the active account identity changes.

## Setup

```bash
flutter pub get
```

To run against a real Supabase project, pass its public values as
dart-defines (never commit real values — see "Environment variables"
below):

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://<your-project>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<publishable-anon-key>
```

Without these, the app can still be built and its test suite runs — no
real Supabase project is required for local development or testing.

## Environment variables

| Name | Where it's used | Notes |
|---|---|---|
| `SUPABASE_URL` | Flutter client (`--dart-define`) | Public project URL. Safe to share. |
| `SUPABASE_ANON_KEY` | Flutter client (`--dart-define`) | Public anon/publishable key. Safe to share, but still don't commit real values in this repo. |
| `SUPABASE_SERVICE_ROLE_KEY` | `supabase/functions/delete-account` only | **Server-side only.** Must never be placed in Flutter code, dart-defines, logs, or committed anywhere. |
| `OPENAI_API_KEY` | `supabase/functions/generate-habit`, `generate-weekly-review` | **Server-side only** (Supabase project secret). Must never be placed in Flutter code. |
| `AI_QUOTA_BYPASS_USER_IDS` | AI Edge Functions | Server-side, optional. Comma-separated allowlist for quota bypass during development. |

## Testing

```bash
dart format lib test
flutter analyze
flutter test
git diff --check
```

See `docs/testing.md` for focused test suites, what the tests do and don't
require (no real Supabase project, no network), and the optional Supabase
CLI checks.

## CI

`.github/workflows/flutter-ci.yml` runs formatting, analysis, and the full
test suite on every push/PR to `main`. It requires no secrets and performs
no release build.

## Project status

Phases 1–9 (local-first foundation, auth, cloud sync, archive/notifications,
privacy/export, account deletion, hardening/accessibility, and this CI/docs
phase) are complete. Manual/device QA (Phase 10) and release signing
(Phase 11) have not been done yet. See `PROJECT_HANDOFF.md` for the full
phase-by-phase status.
