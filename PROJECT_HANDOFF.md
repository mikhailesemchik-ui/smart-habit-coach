# PROJECT_HANDOFF.md

## Project Snapshot

Project: Smart Habit Coach  
Repository: `https://github.com/mikhailesemchik-ui/smart-habit-coach`  
Primary branch: `main`  
Latest verified commit: `879a789 fix(security): require authentication for AI functions`

Local path:

```text
D:\new_life\Smart_Habit_Coach
```

Known state:
- Local `main` is synchronized with `origin/main`.
- Working tree was clean.
- `flutter analyze` was clean.
- Full test suite passed: 101/101.
- Android real-device testing was performed on Samsung SM G990B.
- Supabase functions are deployed and working.
- Hosted Supabase anonymous sign-in is enabled.
- An anonymous user was successfully created.
- Both AI flows were manually verified after authentication changes.

## Product Summary

Smart Habit Coach is a local-first Flutter habit tracker with:
- daily habit tracking;
- local persistence;
- completion history;
- progress statistics;
- weekly reviews;
- reminders;
- onboarding;
- settings and themes;
- AI-assisted habit creation;
- AI-generated weekly review insights.

Core tracking works offline. AI features use Supabase Edge Functions and OpenAI.

## Implemented Features

### Today
- Daily habit list.
- Completion toggle for the current date.
- Daily completion summary.
- Add, edit, view, and delete habits.
- SharedPreferences persistence.

### Habit Model
- Stable ID.
- Title.
- Scheduled time.
- Icon identifier.
- Date-based completion history using `yyyy-MM-dd`.
- Backward migration from legacy `isCompleted`.

### Progress
- Last 7 days completion rate.
- Current streak.
- Best streak.
- Day-by-day summary.
- Local Weekly Review fallback.
- AI Weekly Review.

### AI Habit Setup
- Natural-language goal input.
- Supabase Edge Function calls OpenAI.
- Strict structured result: title, reason, scheduled time, supported icon ID.
- Loading, success, error, retry, and duplicate-request prevention.
- Accept, edit, or cancel.
- No real network calls in tests.

### AI Weekly Review
Local metrics remain authoritative:
- completion rate;
- current streak;
- best streak;
- strongest day;
- weakest day;
- completed count;
- total possible count.

AI generates:
- summary;
- strongest insight;
- weakest insight;
- recommendation.

Fallback:
- local deterministic review;
- non-technical notice;
- retry.

Prompt quality rules:
- no judgmental language;
- no repeated metrics;
- no generic filler;
- one concrete action;
- use only supplied metrics.

### Notifications
- Daily local notifications.
- Schedule on create.
- Reschedule on edit.
- Cancel on delete.
- Stable IDs.
- Permission denial does not crash the app.

### Profile and Settings
- Display name.
- Theme: system/light/dark.
- Start of week: Monday/Sunday.
- Local persistence.

### Onboarding
- Three-page first-launch flow.
- Skip and Get Started.
- Completion persisted locally.

### UI Hardening
Fixed and tested:
- Weekly Review overflow.
- Add/Edit habit safe area and keyboard overflow.
- Habit details safe area.
- AI setup action-row overflow.
- Narrow-screen Profile selector.
- Scrollable bottom sheets.
- Real Samsung device verification.

## Architecture

Feature-first:

```text
lib/
  features/
    ai_habit_setup/
      data/
      domain/
      presentation/
    home/
      data/
      domain/
      presentation/
    navigation/
      presentation/
    onboarding/
      data/
      domain/
      presentation/
    profile/
      data/
      domain/
      presentation/
    progress/
      data/
      domain/
      presentation/
```

Backend:

```text
supabase/
  functions/
    generate-habit/
    generate-weekly-review/
```

No global state-management package is used.

## Important Dependencies

- `shared_preferences`
- `flutter_local_notifications`
- `timezone`
- `supabase_flutter`

Do not add another state-management, persistence, routing, or networking package without a concrete need.

## Supabase and OpenAI

Supabase project ref:

```text
uprtgggltvordcxtwxix
```

Project URL:

```text
https://uprtgggltvordcxtwxix.supabase.co
```

Run the app with:

```powershell
flutter run -d RFCT40P949Z `
  --dart-define=SUPABASE_URL=https://uprtgggltvordcxtwxix.supabase.co `
  --dart-define=SUPABASE_ANON_KEY="<publishable-key>"
```

Never commit the publishable key.

OpenAI secret exists only in Supabase:

```text
OPENAI_API_KEY
```

Never request, reveal, print, commit, or move it into Flutter.

## Authentication and Security

Implemented:
- Supabase anonymous sign-in at startup.
- App remains usable offline if sign-in fails.
- Both AI functions require a valid Supabase JWT.
- Supabase client attaches the session JWT.
- Hosted anonymous sign-in is enabled.
- Anonymous user creation was manually verified.

Known limitation:
- Anonymous auth prevents fully unauthenticated calls.
- It does not provide a per-user OpenAI usage quota.
- A valid anonymous user could still call functions repeatedly.

## Highest-Priority Next Task

Add persistent server-side per-user quotas.

Suggested limits:
- `generate-habit`: 10 requests per user per day.
- `generate-weekly-review`: 3 requests per user per day.

Requirements:
- enforce server-side;
- identify the user from validated JWT / `auth.uid()`;
- return HTTP 429 when exceeded;
- do not use client-only counters;
- do not rely on CORS;
- use persistent Supabase/Postgres storage;
- include cleanup or retention;
- preserve offline-first behavior;
- show a friendly quota message in Flutter;
- test with fakes and no real network calls.

## Other Good Next Tasks

1. Portfolio-quality README:
   - overview;
   - screenshots;
   - features;
   - architecture diagram;
   - AI flow;
   - setup;
   - security;
   - testing;
   - roadmap.

2. Improve Weekly Review personalization with:
   - per-habit completion counts;
   - daily distribution;
   - habit names;
   while keeping calculations local.

3. Add CI for:
   - format;
   - analyze;
   - test.

4. Add full user accounts only if cross-device sync becomes necessary.

## Edge Function Deploy Commands

```powershell
npx supabase functions deploy generate-habit
npx supabase functions deploy generate-weekly-review
```

After security/function changes:
- redeploy affected functions;
- verify authenticated calls work;
- verify unauthenticated calls fail;
- do not assume local config alone updates hosted settings.

## Git State

Repository:

```text
https://github.com/mikhailesemchik-ui/smart-habit-coach.git
```

Latest known commit:

```text
879a789 fix(security): require authentication for AI functions
```

Expected state:

```text
## main...origin/main
nothing to commit, working tree clean
```

Before work:

```powershell
git status -sb
git log -3 --oneline
```

## Verification

Default:

```powershell
dart format .
flutter analyze
```

Logic changes:

```powershell
flutter test
```

Before commit:

```powershell
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
```

Last known full-suite status:

```text
101/101 tests passed
```

## Recommended First Codex Task

Do not edit code immediately.

Ask Codex to:
1. read `AGENTS.md`;
2. read this file;
3. inspect Git status, recent commits, and relevant structure;
4. confirm the current state;
5. propose a minimal plan for persistent per-user AI quotas;
6. make no changes until the plan is approved.
