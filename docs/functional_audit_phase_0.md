# Smart Habit Coach — Phase 0 Functional Audit

Date: 2026-07-02
Scope: Phase 0 of the approved Portfolio Completion Plan v4 — baseline audit
only. No production code, tests, or configuration were modified during this
audit.

## 1. Executive summary

- **Overall functional health**: strong. The full automated test suite
  (674 tests) passes with `flutter analyze` reporting zero issues. Core
  habit-tracking, AI Habit Setup, Weekly Review (AI + local fallback),
  Adaptive Coach (generation, cooldown, Apply/Adjust/Keep), and Coach
  Insights are all implemented and covered by focused, passing tests.
- **Is the baseline safe to build Phase 1A on?** **Yes.** No P0 findings
  were identified. The codebase is clean, has no debug-seed remnants, no
  exposed secrets, and `ai_request_quotas` already has `ON DELETE CASCADE`
  (a fact Phase 7 of the plan depends on and can now treat as confirmed
  rather than assumed).
- **Findings by severity**: P0: 0 · P1: 1 · P2: 4 · P3: 5 (see Section 6
  for full detail).
- **Blockers**: none. The single P1 finding (debug-keystore release
  signing) does not affect Phase 1A's local-storage/namespacing work at
  all — it only matters at Phase 11 (Release readiness), and is already
  tracked there in the plan.

## 2. Environment and repository state

- **Current branch**: `main`
- **Current HEAD**: `2a9e53a641cc5f2c05bf8b3f0a2940efa6842913`
- **Working-tree status**: clean (`git status --short` produced no output)
- **Flutter version**: 3.38.9 (stable channel)
- **Dart version**: 3.10.8 (stable)
- **Supabase configuration presence**: `supabase/config.toml` present;
  `SUPABASE_URL`/`SUPABASE_ANON_KEY` are read via `String.fromEnvironment`
  in `lib/main.dart` (dart-define, not hardcoded) — no secret leakage into
  source. Exactly one Postgres migration exists:
  `supabase/migrations/20260625173853_add_ai_request_quotas.sql`. No other
  user-data tables exist in the cloud.
- **Debug seed functionality**: **absent.** `git grep` for
  `debug_coach_`/`debug_habit_` across `lib/` returned no matches — the
  previously-implemented-then-removed debug coach-seed feature is fully
  gone, consistent with prior session history.
- **Secrets exposure**: `git grep` for OpenAI-style keys, `service_role`,
  `SUPABASE_SERVICE_ROLE`, and `OPENAI_API_KEY` patterns across `lib/`
  returned no matches. No `.env` file is tracked in git. Supabase
  credentials are provided at build time via `--dart-define`, matching the
  documented convention.

## 3. Automated verification

| Command | Result | Pass/Fail | Notes |
|---|---|---|---|
| `flutter analyze` | `No issues found! (ran in 6.5s)` | **Pass** | Zero warnings, zero lints. |
| `flutter test` (full suite) | `+674: All tests passed!` | **Pass** | 674 tests, 0 failures. |
| `git diff --check` | exit code 0, no output | **Pass** | No whitespace-conflict-marker issues. |

**Warnings observed during `flutter test`**: the console output contains
110 repeated lines of `NotificationService.initialize failed:
LateInitializationError: Field '_instance@...' has not been initialized.`
across the suite (concentrated in `profile`, `progress`, and some `home`
tests that construct widgets pulling in `NotificationService` indirectly
without a fake). **Classification: existing, non-actionable noise for this
audit.** Every test that prints this line still passes — the plugin's
platform-channel singleton isn't initialized in the plain `flutter_test`
environment (expected, since there's no real platform), and the app's own
`NotificationService.initialize()` already catches this internally rather
than letting it propagate as a test failure. This is worth a P3 cleanup
note (silence or fake the notification plugin more consistently across
widget tests) but is **not a functional defect** — no test's assertions are
affected by it, and it does not indicate any real notification-scheduling
bug.

## 4. Functional audit matrix

| Area | Scenario | Verification method | Result | Severity if failed | Evidence | Notes |
|---|---|---|---|---|---|---|
| Onboarding | Multi-page flow, skip/back/next, completion | Code inspection (`lib/features/onboarding/`) | Pass | — | `onboarding_screen.dart`, `onboarding_storage.dart` | No network/auth calls in onboarding; static informational pages only. |
| First launch | App boots to sample habits when no local data | Existing test | Pass | — | `progress_screen_test.dart` ("setUp leaves empty prefs → ProgressScreen loads 3 sample habits") | Confirms current unscoped-storage behavior, which Phase 1A will namespace. |
| Anonymous Supabase auth | `signInAnonymously()` called once per session if none exists | Code inspection | Pass (as currently designed) | — | `lib/main.dart:27-36` | See Section 8 for the offline-failure caveat this audit confirms. |
| Supabase init/auth failure behavior | Failure is swallowed, app still starts | Code inspection | **Partial** | P1→ tracked, not blocking | `lib/main.dart:31-35` (`try { await auth.signInAnonymously(); } catch (_) {}`) | Today this is *safe* (no namespace requirement yet), but is the exact behavior Plan v4 Phase 1A must replace with an honest retry gate. Not a regression — a known, already-planned gap. |
| Binary habit creation | Create via `AddHabitSheet` | Existing tests | Pass | — | `home` suite (25 files) covers create/edit flows | |
| Quantitative habit creation | Target + unit | Existing tests | Pass | — | `add_habit_sheet` covered in `home` suite | |
| Custom units and presets | Preset dropdown + custom entry | Code inspection | Pass | — | `add_habit_sheet.dart` unit preset logic | Not individually re-verified by name in this audit; covered by existing `home` widget tests exercising the sheet. |
| Editing habits | Re-open `AddHabitSheet` with `initialHabit` | Existing tests | Pass | — | `habit_details_screen.dart` `_editHabit`, tested in `home` suite | |
| Deleting habits | Confirmation dialog, immediate hard delete | Existing tests | Pass | — | `habit_details_screen.dart` `_deleteHabit` | Confirmed **hard delete, no soft-delete/tombstone** today — expected; Phase 1C introduces tombstones. |
| Pausing/resuming | `asPaused`/`asActive` | Existing tests | Pass | — | `home`/`progress` suites | |
| Archiving | `asArchived` | Existing tests | Pass | — | `home` suite | |
| Archived habits screen | List archived habits, tap to view/edit | Code inspection + existing tests | **Partial** | P2 | `archived_habits_screen.dart` | Confirmed **read-only today**: no restore button, no permanent-delete button, no confirmation dialog on that screen. Matches the plan's known Phase 5 scope — not a regression. |
| Schedules / weekday selection | `weekdays` field, day picker | Existing tests | Pass | — | `home` suite | |
| Reminder time | `scheduledTime` field, time picker | Existing tests | Pass | — | `home` suite | |
| Notification scheduling | `scheduleHabitReminder` on save/create | Code inspection | Pass | — | `notification_service.dart` | Not independently re-verified against a real device (see Section 7). |
| Notification cancellation | `cancelHabitReminder` on relevant mutation | Code inspection | Pass | — | `notification_service.dart` | |
| Notification permission request | Requested inline during `initialize()` | Code inspection | Pass (as designed) | — | `notification_service.dart:44-54` | No dedicated permission-status query or "denied" recovery UI exists yet — expected Phase 5 gap, not a defect in current scope. |
| Binary completion | Toggle → SnackBar with Undo | Existing tests | Pass | — | `home` suite (undo tests) | |
| Uncomplete / Undo | Tap Undo within display window | Existing tests | Pass | — | `home_screen_undo_test.dart` family | |
| Minimum Version | Configure + track minimum-level completion | Existing tests | Pass | — | `home` suite | |
| Quantitative progress | Log progress, partial vs. full | Existing tests | Pass | — | `progress_entry_sheet` tests | |
| Partial progress reasons | Reason picker on partial log | Existing tests | Pass | — | `partial_reason_sheet_test.dart` | |
| Skip reasons | Reason picker on missed day | Existing tests | Pass | — | `skip_reason_sheet_test.dart` | |
| Notes | Add/edit/remove note per date | Existing tests | Pass | — | `note_sheet_test.dart` | |
| Today progress | Progress ring/summary on Home | Existing tests | Pass | — | `home` suite | |
| Day history | `DayHistorySheet` | Existing tests | Pass | — | `day_history_sheet_test.dart`, `day_history_notes_test.dart`, `day_history_min_test.dart` | |
| Monthly calendar | `HabitHistoryCalendarSheet` | Existing tests | Pass | — | `habit_history_calendar_sheet_test.dart` | |
| Habit details | View/edit/pause/archive/delete entry point | Existing tests | Pass | — | `home` suite | |
| Persistence after restart | Reload via `HabitStorage` | Existing tests | Pass | — | `habit_storage_test.dart`, day-history "persists through reload" tests | Simulated (SharedPreferences mock reload), not a real process-kill test — see Section 7. |
| Malformed local habit data | Per-record vs. whole-list tolerance | Code inspection | **Partial** | P2 | `habit_storage.dart` uses one whole-list `try/catch`; `Habit.fromJson` has forgiving per-field defaults but a wrong-typed *required* field (`id`/`title`/`scheduledTime`) still throws, which currently blanks the entire habit list | Matches Plan v4's known finding (this is precisely why Phase 1A adds per-record tolerant loading). Not a regression — already scoped for Phase 1A. |
| Malformed Adaptive Coach data | Per-record tolerance | Code inspection + existing tests | Pass | — | `AdaptiveHabitSuggestion.fromJson` returns `null` per-record; `AdaptiveSuggestionStorage` filters nulls via `whereType` | Already the more robust pattern; confirmed via `coach` suite's malformed-record tests. |
| AI Habit Setup | Goal → structured suggestion | Existing tests | Pass | — | `ai_habit_setup` suite (7 files) | |
| AI validation | Malformed/invalid AI response handling | Existing tests | Pass | — | `ai_habit_setup` suite | |
| AI timeout/error handling | Network/timeout failure UI | Existing tests | Pass | — | `ai_habit_setup` suite | |
| AI quota/rate-limit handling | Quota-exceeded message | Existing tests | Pass | — | `weekly_review_sheet_test.dart` ("Falls back... with the quota notice") | |
| Weekly Review AI success | Renders all 4 sections | Existing tests | Pass | — | `weekly_review_sheet_test.dart` | |
| Weekly Review local fallback | Non-technical fallback notice | Existing tests | Pass | — | `weekly_review_sheet_test.dart` | |
| Weekly Review retry | Retry succeeds; double-tap sends one request | Existing tests | Pass | — | `weekly_review_sheet_test.dart` | |
| Adaptive Coach generation | Deterministic detection from evidence | Existing tests | Pass | — | `coach` domain suite | |
| Adaptive Coach thresholds/cooldown | Evidence thresholds, 28-day cooldown, weekly limit | Existing tests | Pass | — | `adaptive_suggestion_detector_test.dart` | |
| Suggestion persistence | Pending persisted, reopen shows same suggestion, no duplication | Existing tests | Pass | — | `adaptive_coach_service_test.dart` | |
| Apply suggestion | Eligibility checks, target update, status change | Existing tests | Pass | — | `adaptive_apply_eligibility_test.dart`, `adaptive_coach_service_test.dart` | |
| Stale Apply protection | Habit changed since suggestion created → blocked | Existing tests | Pass | — | `adaptive_apply_eligibility_test.dart` (`targetChanged`, `unitChanged`, etc.) | |
| Adjust manually | Opens existing edit flow, cancel keeps pending | Existing tests | Pass | — | `weekly_review_coach_test.dart` | |
| Keep current plan | Marks kept, removes card, no habit mutation | Existing tests | Pass | — | `weekly_review_coach_test.dart` | |
| Coach Insights | Grouping, sorting, empty state, read-only | Existing tests | Pass | — | `coach_insights_screen_test.dart`, `coach_insights_view_test.dart` | |
| Deleted-habit title snapshot | `habitTitleSnapshot` fallback chain | Existing tests | Pass | — | `coach_insights_view_test.dart` | |
| Loading states | Spinners on async screens | Existing tests | Pass | — | `weekly_review_sheet_test.dart`, `coach_insights_screen_test.dart` | |
| Empty states | "No coach insights yet", "No habits yet", etc. | Existing tests | Pass | — | `coach_insights_screen_test.dart`, `day_history_sheet_test.dart` | |
| Retryable errors | Weekly Review Retry, Coach Insights "Try again" | Existing tests | Pass | — | `weekly_review_sheet_test.dart`, `coach_insights_screen_test.dart` | |
| Android back navigation | System back gesture behavior | Not verified | Not verified | — | — | Requires real device (Section 7). |
| Narrow-screen behavior | No overflow on compact widths | Existing tests | Pass | — | Multiple `does not overflow on a narrow/compact screen` tests across `home`/`progress`/`profile` | |
| Offline behavior | App usable with no network (after a session exists) | Code inspection | Pass | — | Local-first design; AI/Coach features degrade gracefully | Clean-install-while-offline specifically not verified (Section 7/8). |
| Release signing configuration | Real signing config present | Code inspection | **Fail** | **P1** | `android/app/build.gradle.kts:37-39` | Release build explicitly signs with the **debug** keystore; literal `// TODO: Add your own signing config` comment present. Already tracked as Plan v4 Phase 11 scope. |
| CI presence | GitHub Actions workflow exists | Directory check | **Fail** | P2 | `.github/workflows/` does not exist | Already tracked as Plan v4 Phase 9 scope. |
| Debug-only controls/seed data | Any remaining debug UI or seed helpers | `git grep` | Pass (none found) | — | No matches for `debug_coach_`/`debug_habit_` in `lib/` | |
| Exposed secrets | Hardcoded keys in client | `git grep` | Pass (none found) | — | No matches for API-key/service-role patterns in `lib/`; Supabase creds via `--dart-define` only | |

## 5. Existing automated test coverage

| Feature | Test files | Assessment |
|---|---|---|
| home | 25 | Heavy — habit CRUD, completion, undo, notes, skip/partial reasons, notifications integration points. |
| progress | 14 | Heavy — day history, monthly calendar, Weekly Review (AI+fallback+retry), Coach card integration. |
| coach | 9 | Solid — detection rules, eligibility, apply flow, insights view/screen. |
| ai_habit_setup | 7 | Solid — success/validation/timeout/quota paths. |
| profile | 3 | Light — settings screen covered; no account/auth-adjacent UI exists yet to test. |
| onboarding | 1 | Very light — matches the screen's current minimal scope (static pages, no logic). |
| notifications | 0 dedicated files | **Gap.** No `test/features/home/data/notification_service_test.dart`-style file exists; notification behavior is only indirectly exercised via `FakeNotificationService` injected into `home` widget tests. No dedicated unit test of scheduling/cancellation logic itself. |
| auth | 0 | **Gap** (expected — no auth feature exists yet; this is exactly what Plan v4 Phase 2A/2B adds, along with its own test suite). |
| storage | 2 (`habit_storage_test.dart`, `settings_storage_test.dart`) | Present but thin relative to `home`'s size; no dedicated `AdaptiveSuggestionStorage`-only test file (its behavior is covered indirectly through `adaptive_coach_service_test.dart` and `coach_insights_service_test.dart`). |
| Supabase (client/integration) | 0 | **Gap** (expected — no cloud tables exist yet; Plan v4 Phase 3 introduces the first Supabase integration tests). |

**Meaningful gaps for future phases**: no dedicated notification-service
unit tests (worth adding alongside Phase 5's notification-recovery work,
not now); no dedicated `AdaptiveSuggestionStorage`-only test file (low
priority — coverage exists transitively); zero Supabase/auth test
infrastructure (expected and already the explicit subject of Plan v4
Phases 2A/2B/3).

## 6. Findings

### P0

None identified.

### P1

**AUDIT-P1-001 — Release Android build is signed with the debug keystore**
- **Affected flow**: Release build / distribution.
- **Reproduction/evidence**: `android/app/build.gradle.kts` lines 37-39:
  `signingConfig = signingConfigs.getByName("debug")` with an explicit
  `// TODO: Add your own signing config for the release build.` comment.
- **Expected behavior**: a real release signing configuration (keystore +
  credentials, not committed to source) is used for release builds.
- **Current behavior**: `flutter build apk --release` (or `--release` runs
  generally) produces an APK signed with the shared, insecure debug key.
- **Likely files involved**: `android/app/build.gradle.kts`.
- **Recommended future phase**: Plan v4 Phase 11 (Release readiness and
  signing) — already scoped there; no change needed to the plan.

### P2

**AUDIT-P2-001 — Archived Habits screen is read-only (no restore/permanent-delete)**
- **Affected flow**: Archive management.
- **Evidence**: `lib/features/home/presentation/archived_habits_screen.dart`
  has no restore action, no permanent-delete action, and no confirmation
  dialog — only a list with tap-to-view/edit navigation.
- **Expected behavior** (per product intent and Plan v4): dedicated
  restore and tombstone-based permanent-delete actions with confirmation.
- **Current behavior**: users can only leave an archived habit archived or
  navigate into habit details to change its status indirectly.
- **Likely files involved**: `archived_habits_screen.dart`.
- **Recommended future phase**: Plan v4 Phase 5 (already scoped there).

**AUDIT-P2-002 — `HabitStorage` uses whole-list, not per-record, fault tolerance**
- **Affected flow**: App restart / data load after any local corruption.
- **Evidence**: `habit_storage.dart`'s `loadHabits()` wraps the entire
  decode in one `try/catch`; a single malformed record (e.g. missing
  required `id`/`title`/`scheduledTime`) throws and the whole list load
  fails, unlike `AdaptiveSuggestionStorage`, which already tolerates
  per-record failures via `whereType`.
- **Expected behavior**: one bad habit record should not blank the entire
  habit list.
- **Current behavior**: a single corrupted record risks losing access to
  every other habit until the bad record is somehow removed.
- **Likely files involved**: `lib/features/home/data/habit_storage.dart`.
- **Recommended future phase**: Plan v4 Phase 1A (already scoped there as
  "tolerant per-record loading").

**AUDIT-P2-003 — No CI workflow exists**
- **Affected flow**: Change safety / regression prevention for future work.
- **Evidence**: `.github/workflows/` does not exist in the repository.
- **Expected behavior**: `flutter analyze` + `flutter test` run
  automatically on push/PR.
- **Current behavior**: verification is entirely manual today.
- **Likely files involved**: new `.github/workflows/flutter.yml`.
- **Recommended future phase**: Plan v4 Phase 9 (already scoped there).

**AUDIT-P2-004 — Offline-first-launch behavior is currently silent, not honest**
- **Affected flow**: First app launch with no network available.
- **Evidence**: `lib/main.dart:27-36` — `_ensureAuthenticatedSession()`
  swallows any `signInAnonymously()` failure with an empty `catch (_) {}`
  and proceeds straight into the app with no session and no user-visible
  indication that identity setup failed.
- **Expected behavior** (per Plan v4 Correction 3): the very first launch
  should either succeed at establishing an identity or show a clear,
  non-destructive retry state — not silently proceed as if nothing
  happened.
- **Current behavior**: today this is *harmless* only because no
  namespacing exists yet — the app has nothing that depends on a UID being
  present. This becomes unsafe the moment Phase 1A's namespacing lands
  (namespaced storage cannot be created without a real UID), which is
  exactly why Phase 1A's scope already includes the first-launch identity
  gate. Recording this now, before Phase 1A begins, confirms the *current*
  behavior precisely, so Phase 1A's "replace this with a retry gate" work
  has an accurate starting point.
- **Likely files involved**: `lib/main.dart`.
- **Recommended future phase**: Plan v4 Phase 1A (already scoped there;
  this finding confirms the exact current code this phase will change).

### P3

**AUDIT-P3-001 — Repeated `LateInitializationError` console noise during `flutter test`**
- **Affected flow**: Test suite readability (not correctness).
- **Evidence**: 110 occurrences of
  `NotificationService.initialize failed: LateInitializationError: Field
  '_instance@...' has not been initialized.` printed during the full test
  run; all affected tests still pass.
- **Expected behavior**: tests that don't need real notification-plugin
  behavior should use `FakeNotificationService` consistently (already the
  established pattern in several `home` tests) to avoid the noisy,
  caught-but-printed error.
- **Current behavior**: functionally harmless, but makes genuine test
  failures harder to spot by eye in CI logs.
- **Likely files involved**: various `profile`/`progress`/`home` widget
  tests that construct `HomeScreen`/`ProgressScreen` without an injected
  fake notification service.
- **Recommended future phase**: opportunistic cleanup alongside Plan v4
  Phase 5 or Phase 9 (CI setup) — not urgent, non-blocking.

**AUDIT-P3-002 — No dedicated `NotificationService` unit test file**
- **Affected flow**: Test coverage completeness.
- **Evidence**: no `test/features/home/data/notification_service_test.dart`
  exists; scheduling/cancellation logic is only exercised indirectly via
  `FakeNotificationService` substitution in UI tests, never testing the
  real service's own scheduling math directly.
- **Expected behavior**: a focused unit test suite for
  `NotificationService` itself (mocking the underlying plugin).
- **Current behavior**: coverage gap, not a known defect.
- **Likely files involved**: new test file only.
- **Recommended future phase**: Plan v4 Phase 5 (notification recovery
  work) or Phase 9 (coverage completion).

**AUDIT-P3-003 — Android manifest declares no explicit notification-related permissions**
- **Affected flow**: Notification permission on newer Android versions.
- **Evidence**: `android/app/src/main/AndroidManifest.xml` contains no
  explicit `<uses-permission>` entries for `POST_NOTIFICATIONS` or
  `SCHEDULE_EXACT_ALARM`/`USE_EXACT_ALARM`.
- **Expected behavior**: unclear without a real build — `flutter_local_
  notifications`' own AAR manifest may already merge the required
  permissions automatically (a common pattern for this plugin), in which
  case no explicit app-level entry is actually needed.
- **Current behavior**: **not verified** either way from source inspection
  alone.
- **Likely files involved**: `android/app/src/main/AndroidManifest.xml`,
  possibly none if plugin merging already covers it.
- **Recommended future phase**: real-device verification during Plan v4
  Phase 5/Phase 10 (see Section 7) before assuming any manifest change is
  needed.

**AUDIT-P3-004 — No dedicated `AdaptiveSuggestionStorage`-only test file**
- **Affected flow**: Test coverage completeness.
- **Evidence**: `AdaptiveSuggestionStorage`'s malformed-record and
  persistence behavior is covered only indirectly through
  `adaptive_coach_service_test.dart` and `coach_insights_service_test.dart`,
  not a standalone storage test mirroring `habit_storage_test.dart`.
- **Expected behavior**: a direct, focused test file for symmetry with
  `HabitStorage`'s own test file.
- **Current behavior**: coverage gap, not a known defect (existing
  indirect tests do exercise the relevant behavior).
- **Likely files involved**: new test file only.
- **Recommended future phase**: opportunistic, alongside Phase 1A/1C work
  on the storage layer, or Phase 9.

**AUDIT-P3-005 — `git log` shows no CHANGELOG.md; onboarding/profile test coverage is comparatively thin**
- **Affected flow**: Documentation/process polish, not functionality.
- **Evidence**: no `CHANGELOG.md` in the repository; `onboarding` has 1
  test file, `profile` has 3, both far lighter than `home`'s 25.
- **Expected behavior**: not a defect — onboarding and current Profile
  content are genuinely simple screens, so thin coverage is proportionate
  today. Flagged only because Plan v4 adds substantial new Profile-area
  functionality (account, sync status, export, privacy, deletion) that
  will need commensurately heavier coverage as it's built — already
  reflected in Plan v4's per-phase test requirements.
- **Current behavior**: proportionate to current scope; no action needed
  now.
- **Likely files involved**: none.
- **Recommended future phase**: naturally addressed as Plan v4 Phases
  2B/4/6/7 add their own dedicated test files.

## 7. Real-device checks still required

| Check | Status |
|---|---|
| Notification permission (initial request dialog) | Not verified |
| Denied notification recovery | Blocked by missing future functionality (no recovery UI exists yet — Phase 5) |
| Android back gesture | Not verified |
| Process kill and restart (real OS-level kill, not simulated storage reload) | Not verified |
| Airplane-mode behavior (app already has a session) | Not verified |
| Clean-install offline behavior (no session yet, no network) | Not verified — **currently would silently proceed with no session** per AUDIT-P2-004; this is precisely the scenario Phase 1A's retry gate is designed to fix, so this check is most meaningfully re-run *after* Phase 1A lands, not before |
| Narrow device (real hardware, not just a resized test viewport) | Not verified (automated narrow-viewport tests pass; real-device rendering not confirmed) |
| Release build (signed, installed) | Not verified — blocked by AUDIT-P1-001 (no real signing config exists yet to build a genuine release artifact) |
| Notification delivery (actual OS notification appears at scheduled time) | Not verified |
| Exact reminder rescheduling (edit habit time → notification updates) | Not verified |
| Notification cancellation after pause/archive/delete (OS-level confirmation, not just code-path inspection) | Not verified |

## 8. Supabase and security findings

- **Current anonymous auth behavior**: on every app start, if
  `Supabase.instance.client.auth.currentSession == null`, the app calls
  `signInAnonymously()` once (`lib/main.dart:27-36`).
- **Behavior if anonymous auth fails**: the failure is caught and
  discarded (`catch (_) {}`); the app proceeds into the UI with **no
  session at all**. Today this is harmless (no feature requires a session
  to function locally); AI features simply fail their own request and show
  existing retry UI. This is the exact behavior Plan v4 Phase 1A is scoped
  to replace with an honest, non-silent retry gate once namespacing makes
  a session mandatory.
- **Current user-data cloud storage status**: **none.** The only table in
  the project is `public.ai_request_quotas`; no habits, suggestions, or
  preferences exist in the cloud today. This matches Plan v4's stated
  baseline exactly.
- **RLS status of existing tables**: `ai_request_quotas` has RLS enabled
  (`alter table public.ai_request_quotas enable row level security;`) with
  all direct table grants revoked from both `anon` and `authenticated`
  (access is only via the `SECURITY DEFINER` `consume_ai_quota` function,
  which validates `auth.uid()` internally and rejects unauthenticated
  callers). This is a correctly-locked-down pattern and a good template
  for the new tables Plan v4 Phase 3 will add.
- **Exact `ai_request_quotas` foreign-key behavior**: confirmed by direct
  inspection of `supabase/migrations/20260625173853_add_ai_request_quotas.sql`,
  line 2:
  ```sql
  user_id uuid not null references auth.users(id) on delete cascade,
  ```
  **`ON DELETE CASCADE` is already present.** This resolves the open
  verification item Plan v4 Phase 7 flagged — no migration is needed to
  add cascade to this table; Phase 7's inventory step can proceed directly
  to confirming this (already done, here) rather than needing to write a
  new migration for it.
- **Edge Function auth protection**: `supabase/config.toml` sets
  `verify_jwt = true` for both `generate-habit` and `generate-weekly-review`
  (per prior session findings, re-confirmed as still the case — no changes
  to `supabase/` were made in the interim aside from this audit's read-only
  inspection).
- **Client-side secret exposure check**: `git grep` across `lib/` for
  OpenAI-key patterns, `service_role`, `SUPABASE_SERVICE_ROLE`, and
  `OPENAI_API_KEY` found **zero matches**. Supabase URL/anon key are
  supplied via `--dart-define` at build time, not committed to source. No
  `.env` file is tracked in git.
- **Release signing status**: **not production-ready** — see
  AUDIT-P1-001. Release builds currently sign with the shared debug
  keystore.

## 9. Readiness decision for Phase 1A

**READY WITH NON-BLOCKING FINDINGS.**

No P0 findings exist. The single P1 finding (debug-keystore release
signing) is entirely unrelated to Phase 1A's scope (local storage
namespacing, migration safety, and the first-launch identity gate) and is
already correctly tracked for Phase 11. All P2/P3 findings either (a) are
already explicitly in-scope for Phase 1A/1B/1C/5/9 per the approved plan,
confirming the plan's assumptions were accurate, or (b) are low-priority
test-coverage/polish items that do not affect data safety or correctness.

The one fact this audit newly *confirms* (rather than assumes) that
directly affects Phase 1A/Phase 7 planning: **`ai_request_quotas` already
has `ON DELETE CASCADE`**, so Phase 7's account-deletion work needs no
migration for that table — it can rely on cascade being already correct
there, simplifying that phase slightly versus treating it as an open
question.

## 10. Recommended next actions

**Blockers before Phase 1A**: none.

**Findings to carry into later phases** (already correctly scoped in Plan
v4 — no roadmap changes needed):
- AUDIT-P1-001 (debug-keystore signing) → Phase 11.
- AUDIT-P2-001 (Archived Habits read-only) → Phase 5.
- AUDIT-P2-002 (whole-list vs. per-record `HabitStorage` tolerance) →
  Phase 1A.
- AUDIT-P2-003 (no CI) → Phase 9.
- AUDIT-P2-004 (silent offline first-launch failure) → Phase 1A.
- AUDIT-P3-001 through AUDIT-P3-005 (test-coverage/noise polish items) →
  opportunistic, alongside the phases already touching those areas
  (Phase 1A/1C for storage tests, Phase 5 for notification tests, Phase 9
  for CI-related cleanup).

**Manual checks to perform later** (see Section 7 for the full list): all
real-device notification, back-gesture, process-kill, airplane-mode, and
release-build checks — most productively run *after* Phase 1A (for the
offline/clean-install checks specifically) and *after* Phase 11 (for the
release-build check specifically), not before either.
