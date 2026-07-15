# UI/UX Redesign Implementation Plan

## Context

Phases 0–11 (functional/architecture work) are complete and committed; the
app is stable, local-first, tested (1035+ tests), and release-signing
ready. Visually, the app is 100% default Material 3
(`ColorScheme.fromSeed(Colors.teal)`, stock `Card`/`ListTile`/`AppBar`/
`NavigationBar`, no custom typography, no shared widget layer). A
reference concept (`docs/design/smart_habbit_design_1v.png`, 8 screens:
Today/Home, Add Habit, Note sheet, Habit Details, Progress, Weekly Review
sheet, Coach Insights, Profile/Account) provides visual direction — not a
pixel spec. This document is a phased plan for a gradual redesign that
never touches sync/auth/storage/account-deletion logic and never breaks
the existing test suite.

## 1. Current UI architecture overview

- **Entry point**: `lib/app.dart` builds `MaterialApp` with `theme`/
  `darkTheme` both set to `ThemeData(colorScheme: ColorScheme.fromSeed(seedColor:
  Colors.teal), useMaterial3: true)` — inline in `build()` (lines 174–190),
  no separate theme file. `themeMode` comes from `AppSettings`. Default
  Material 3 type scale, no custom fonts.
- **Navigation**: `lib/features/navigation/presentation/main_navigation_screen.dart`
  (80 lines) — `Scaffold` + `IndexedStack` + stock `NavigationBar` (Today,
  Progress, Profile), default icons/labels, no custom styling.
- **Screens** (all `StatefulWidget`): `home_screen.dart` (756 lines),
  `add_habit_sheet.dart` (511), `note_sheet.dart` (101),
  `habit_details_screen.dart` (1050, largest), `habit_details_sheet.dart`
  (64), `progress_screen.dart` (387), `weekly_review_sheet.dart` (342),
  `coach_insights_screen.dart` (289), `adaptive_coach_card.dart` (92),
  `profile_screen.dart` (254), `account_screen.dart` (760,
  second-largest), `archived_habits_screen.dart` (235),
  `privacy_screen.dart` (241). Each composes stock Material widgets
  directly (`Card`, `ListTile`, `LinearProgressIndicator`,
  `OutlinedButton.icon`, `PopupMenuButton`, `SnackBar`) with local helper
  widgets named by convention (`_XyzCard`/`_XyzTile`/`_XyzSection`).
- **Shared components**: only one true cross-feature reusable widget
  exists — `AdaptiveCoachCard` (`lib/features/coach/presentation/adaptive_coach_card.dart`),
  reused by `weekly_review_sheet.dart`. No `core/widgets/` directory; no
  shared card/button/chip/bottom-sheet/status-badge component despite
  near-identical "elevated container" and "status badge" patterns
  recurring independently in `account_screen._StatusCard`,
  `coach_insights_screen._CoachInsightCard`, `day_history_sheet.dart`, and
  `habit_history_calendar_sheet.dart`.
- **Color/typography usage**: theme-derived (`Theme.of(context).colorScheme`/
  `.textTheme`) in the main flows, but 275 direct `Colors.*` literals exist
  app-wide, concentrated in `habit_details_screen.dart` (39),
  `account_screen.dart` (29), `progress_screen.dart` (25),
  `day_history_sheet.dart` (23), `coach_insights_screen.dart`/
  `ai_habit_setup_sheet.dart` (13–16 each). No custom fonts anywhere.
- **Where styles are duplicated / inconsistent**: five uncoordinated
  `BorderRadius.circular(...)` values — 2, 8 (privacy, account, progress),
  10 (archived habits), 12 (coach insights, habit details), 24 (add-habit
  sheet) — with no shared radius token. "Elevated container" is expressed
  inconsistently too: `Card` in `home_screen.dart`/`progress_screen.dart`/
  `coach_insights_screen.dart`/`adaptive_coach_card.dart`, but hand-rolled
  `Container` + `BoxDecoration` in `account_screen._StatusCard`,
  `coach_insights_screen._CoachInsightCard`'s internal badge,
  `day_history_sheet.dart`, and `habit_history_calendar_sheet.dart` for the
  same visual role. No shared `EdgeInsets`/spacing constants exist
  anywhere (ad hoc per-file values).

## 2. Visual direction from the reference

Extracted as **directional tokens**, not pixel-exact values (confirm exact
hex/dp during implementation against Flutter's rendering, not the
mockup):

- **Palette**: deep teal/forest green primary (close to the current
  `Colors.teal` seed — low-risk starting point), soft mint/pale-green tonal
  backgrounds for progress rings and highlighted chips, off-white/
  very-light grey screen background (not pure white), near-black text,
  muted grey secondary text, coral/red reserved strictly for destructive
  actions (Delete, streak-at-risk).
- **Background**: flat, low-contrast light grey-green, not white.
- **Card style**: fully-rounded corners (~16–20dp), no visible border, very
  soft/low elevation shadow, generous internal padding.
- **Radius**: large and consistent across cards, buttons, chips, and sheet
  top corners — one shared radius scale (small/medium/large), replacing
  today's uncoordinated 2/8/10/12/24 values.
- **Shadows**: minimal — soft, diffuse, low-opacity; not Material's default
  crisp elevation shadow.
- **Typography hierarchy**: bold, larger page titles ("Today", "Add
  Habit"); medium-weight section labels; regular body text; small
  muted-grey metadata/subtitle text. Numbers (stats, streaks, percentages)
  are visually emphasized.
- **Buttons**: primary actions are solid pill/rounded-rect filled buttons
  in the primary green ("Create with AI", "Save", "Edit habit"); secondary
  actions are outlined or text buttons; the FAB is a small filled circular
  "+" consistent with current usage.
- **Chips / segmented controls**: pill-shaped two-option segmented toggles
  (Binary/Amount, Every day/Specific days) with a solid-filled selected
  state and pale/unfilled unselected state.
- **Bottom navigation**: light background, active tab shown via a filled
  pill/rounded highlight behind the icon plus color change, inactive tabs
  muted grey — achievable via Material 3 theming, not a custom widget.
- **Modal/bottom sheet style**: rounded top corners matching the card
  radius, a small centered drag handle, consistent header pattern (title +
  close/check or Cancel/Save action pair), consistent bottom
  padding/safe-area handling.
- **Destructive actions**: red text/icon on a pale-red or outlined
  background (e.g. the Delete button in Habit Details), visually separated
  from Pause/Archive.

## 3. Safe implementation phases

### UI Phase 1A — Theme extraction only

**Goal**:
- Extract the existing inline `ThemeData` from `lib/app.dart` into a
  dedicated theme file.
- Preserve the current visual appearance as much as possible.
- No visual redesign yet.
- No color/radius/typography changes yet.
- No screen-level UI changes unless strictly required for imports/compilation.

**Expected files**:
- `lib/app.dart`
- `lib/app/theme/app_theme.dart` (or similar)

**Validation**:
```bash
dart format lib test
flutter analyze
flutter test
git diff --check
git status --short
```

**Purpose**: create a behavior-neutral baseline so future visual changes
are easy to review and bisect.

**Commit idea**: `refactor: extract app theme`

### UI Phase 1B — Design tokens and global theme polish

**Goal**:
- Introduce design tokens and a polished global visual direction inspired
  by the reference image.
- Add `AppColors` / `AppSpacing` / `AppRadii` / `AppShadows` if useful.
- Update `ColorScheme` toward the selected teal/mint/off-white direction.
- Add or improve: `CardTheme`, `FilledButtonTheme`, `OutlinedButtonTheme`,
  `TextButtonTheme`, `InputDecorationTheme`, `BottomSheetTheme`,
  `NavigationBarTheme`, `ChipTheme`/`SegmentedButtonTheme` if appropriate.
- Keep screen layouts unchanged.
- Avoid editing individual screens except where necessary for compatibility.
- Preserve all existing widget keys.
- Preserve business logic.

**Expected files**:
- `lib/app/theme/**`
- possibly `lib/core/widgets/**` only if a repeated low-risk shared
  component is introduced (e.g. unifying the `Card` vs `BoxDecoration`
  status-badge split) — do not introduce large component abstractions yet.

**Validation**:
```bash
dart format lib test
flutter analyze
flutter test
git diff --check
git status --short
```
Plus a manual visual smoke check on Today, Add Habit, Habit Details,
Profile.

**Commit idea**: `style: add app design tokens and global theme polish`

### UI Phase 2 — Today/Home redesign

`home_screen.dart`: restyle `_ProgressCard` and `_HabitCard` (both binary
and quantitative variants) to the new card/typography tokens, restyle the
"Create with AI" button and FAB, polish bottom-nav appearance (theme-driven,
from Phase 1B).

### UI Phase 3 — Add/Edit Habit + Note sheet

`add_habit_sheet.dart`, `note_sheet.dart`: form field styling, `_IconChoice`
selector, Binary/Amount and Every day/Specific days as segmented controls,
consistent sheet header/footer, replace the sheet's one-off
`BorderRadius.circular(24)` with the shared token.

### UI Phase 4 — Habit Details

`habit_details_screen.dart` (largest file — budget extra care/time),
`habit_details_sheet.dart`: hero icon/title card, stats grid
(`_StatTile`s: streak/best/last-30-days/total), calendar month view
(`_CalendarDayCell`), Pause/Archive/Delete action row styling.

### UI Phase 5 — Progress + Weekly Review + Coach Insights

`progress_screen.dart` (`_WeeklyReviewCard`, `_StatsCard`, `_StreakTile`,
`_WeekSummary`, `_DayIndicator`), `weekly_review_sheet.dart`
(`_ReviewSection`, embeds `AdaptiveCoachCard`), `coach_insights_screen.dart`
(`_CoachInsightCard`, `_EmptyState`, `_ErrorState`),
`adaptive_coach_card.dart`: progress/stat cards, weekly-review sheet
sections, insight cards with Pending/Applied/Adjusted status chips —
consolidate `_CoachInsightCard`'s internal `BoxDecoration` badge onto the
same shared status-badge component as `account_screen._StatusCard`.

### UI Phase 6 — Profile/Account/Privacy/Archive polish

`profile_screen.dart`, `account_screen.dart` (second-largest file — many
sub-widgets: `_SyncSection`, `_StatusCard`, `_MessageBanner`,
`_UnauthenticatedSection`, `_AnonymousSection`, `_LinkedSection`,
`_DeleteAccountDialog`, `_LinkAccountSheet`, `_SignInSheet`,
`_AccountFormShell`), `privacy_screen.dart` (`_Section`),
`archived_habits_screen.dart` (`_ArchivedHabitTile`): settings list
styling, account/profile header card, sync status card (reuse Phase 1B's
status-badge component), privacy/export state cards, archived-habit action
styling.

### UI Phase 7 — Final UI QA

Text-scale (accessibility large-font) check, small-screen layouts,
light/dark mode parity (the reference is light-mode only — dark theme
needs its own token mapping, not a direct copy), semantics/contrast check,
side-by-side screenshot comparison against the reference, full
`flutter test` + `flutter analyze` pass.

## 4. Risk analysis

### Phase 1A risk

**Low risk**: refactor only; no intentional visual changes; mostly
`app.dart` and a new theme file.
**Main risk**: accidentally changing `ThemeData` defaults during the move.

### Phase 1B risk

**Medium risk**: affects all screens globally; `Card`/`Button`/`Input`/
`NavigationBar` theme changes can have wide visual impact.
**Main risk**: global component theme changes may make some screens
overflow or break widget assumptions (e.g. fixed-height rows sized for the
old default padding).

### Remaining phases

| Phase | Files likely touched | Risk | Tests to run | Do not touch |
|---|---|---|---|---|
| 2 | `home_screen.dart` | Low–Medium | `flutter test test/features/home/`, manual Today screen check | `add_habit_sheet.dart` and other sheets it opens |
| 3 | `add_habit_sheet.dart`, `note_sheet.dart` | Low | relevant widget tests, manual sheet check | Habit validation/save logic |
| 4 | `habit_details_screen.dart` (1050 lines — largest, budget extra time), `habit_details_sheet.dart` | Low–Medium (calendar rendering) | `flutter test test/features/home/`, manual check | Pause/Archive/Delete business logic |
| 5 | `progress_screen.dart`, `weekly_review_sheet.dart`, `coach_insights_screen.dart`, `adaptive_coach_card.dart` | Medium (AI/coach data-shape coupling; `adaptive_coach_card.dart` is shared — check both call sites after editing) | `flutter test test/features/progress/ test/features/coach/` | AI service calls, Adaptive Coach detection rules |
| 6 | `profile_screen.dart`, `account_screen.dart` (760 lines, auth-sensitive), `privacy_screen.dart`, `archived_habits_screen.dart` | Low–Medium | `flutter test test/features/profile/ test/features/auth/ test/features/privacy/` | Auth/sync/export/account-deletion logic — style-only edits |
| 7 | none (verification only) | Low | Full `flutter test`, `flutter analyze`, `dart format`, `git diff --check` | — |

General constraints for every phase: visual/styling changes only — no
widget-tree restructuring that changes navigation, state, or data flow;
existing `Key`s used by widget tests must be preserved; each phase ends
with a green `flutter analyze` + `flutter test` before moving to the next.

## 5. UI redesign guardrails

- Visual/styling changes only.
- No sync/auth/storage/account-deletion logic changes.
- No database/Supabase changes.
- No new product features.
- No widget key removals unless tests are updated intentionally.
- No large route/navigation rewrites.
- No dependency additions unless explicitly approved.
- Every UI phase must pass `flutter analyze` and full `flutter test`.
- Each phase should be committed separately.

## 6. Ready prompt: UI Phase 1A — Theme extraction only

```text
Continue Smart Habit Coach UI redesign, Phase 1A only.

Project path: D:\new_life\Smart_Habit_Coach

Implement only theme extraction:
- Create lib/app/theme/app_theme.dart.
- Move the existing inline ThemeData from lib/app.dart into it.
- Preserve ColorScheme.fromSeed(seedColor: Colors.teal).
- Preserve useMaterial3: true.
- Preserve themeMode behavior (from AppSettings).
- No visual redesign.
- No color/radius/typography changes.
- No screen-level edits unless required for compilation.

Validation:
- dart format lib test
- flutter analyze
- flutter test
- git diff --check
- git status --short

Do not commit or push.

Report: files changed, and the result of each validation command.
```

## Summary

The current UI is unstyled default Material 3 (one `Colors.teal` seed, no
custom typography) with 275 direct `Colors.*` literals and five
uncoordinated corner-radius values (2/8/10/12/24) but no problematic
structural duplication — every screen already follows a consistent
`StatefulWidget` + private-`StatelessWidget` pattern. This is a clean base
for a low-risk, incremental redesign that mainly needs a missing
design-token/shared-widget layer rather than untangling existing mess.

Implementation sequence: **1A** theme extraction only → **1B** design
tokens and global theme polish → **2** Today/Home → **3** Add/Edit Habit +
Note sheet → **4** Habit Details → **5** Progress/Weekly Review/Coach
Insights → **6** Profile/Account/Privacy/Archive → **7** final UI QA.
