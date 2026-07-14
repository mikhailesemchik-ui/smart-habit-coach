# Phase 10 — Manual/device QA

This documents a single manual smoke test on a real Android device. It is
**not** exhaustive production QA — see sections 6–8 for what was and
wasn't covered.

## 1. Device / environment

| Field | Value |
|---|---|
| Device | Samsung Galaxy S21 FE (model `SM-G990B`) |
| Device id | `RFCT40P949Z` |
| OS | Android 15, API 35 |
| Connection | `flutter run -d <device-id>` (USB/ADB) |
| Supabase project | `uprtgggltvordcxtwxix.supabase.co` |

## 2. Build/run command

```bash
flutter run -d RFCT40P949Z \
  --dart-define=SUPABASE_URL=https://uprtgggltvordcxtwxix.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<redacted>
```

Debug build (`flutter run`, not a release build). No signing configuration
was exercised — that remains Phase 11 scope.

## 3. Automated validation before manual QA

Run immediately before this session, from the Phase 9 baseline:

```bash
flutter analyze   # clean, no issues
flutter test      # 1035/1035 passed
```

## 4. Manual smoke QA checklist

| # | Check | Performed |
|---|---|---|
| 1 | App builds and launches on the physical device | Yes |
| 2 | App reaches a usable screen without crashing on launch | Yes |
| 3 | Basic navigation / superficial interaction | Yes |
| 4 | Watch logcat/console output for uncaught exceptions during the above | Yes |

No further flows (habit creation, sync, notifications, AI features,
account deletion, etc.) were exercised on-device in this session.

## 5. Result table

| # | Check | Result |
|---|---|---|
| 1 | App builds and launches on device | Pass |
| 2 | Reaches usable screen, no crash on launch | Pass |
| 3 | Basic/superficial interaction | Pass |
| 4 | No obvious crashes or blocking errors observed | Pass |

## 6. Items verified superficially

- App installs and launches successfully on a real Android 15 device via
  `flutter run` with real Supabase dart-defines.
- The app reaches an interactive state (does not crash on cold start).
- No crash or blocking error was observed during this brief session.

This was a **surface-level smoke check only** — enough to confirm the app
runs on real hardware against a real backend, not a functional walkthrough
of individual features.

## 7. Items not deeply verified yet

No direct on-device evidence exists yet for:

- Account creation / email sign-up / sign-in flow end-to-end on-device.
- Habit CRUD, streaks, and statistics on-device.
- Cloud sync ("Sync now"), including conflict resolution and
  "Use data on this device", on a real device or across two devices.
- Multi-device sync scenarios.
- Notification scheduling and actual delivery over time (including after
  device reboot, battery optimization, or app being backgrounded/killed).
- Offline/online transition edge cases (airplane mode, flaky network,
  reconnect-and-sync).
- AI Habit Setup and AI Weekly Review calls against the live Edge
  Functions.
- Local data export on-device.
- Account deletion end-to-end on-device (Edge Function call, cascading
  cloud cleanup, local cleanup, re-establishing a fresh anonymous
  identity).
- Accessibility behavior (TalkBack, font scaling, contrast) on-device.
- Long-running/extended-use stability.

These should not be assumed to work correctly on-device based on this
session alone; they are covered only by the existing automated test suite
(fakes, no real device or backend).

## 8. Known limitations

- Only one device model/OS version was tested (`SM-G990B`, Android 15).
  No coverage of other Android versions, screen sizes, or iOS.
- Debug build only; no release-mode behavior (release builds can differ,
  e.g. different notification/background behavior, R8/ProGuard effects).
- Release signing is still the debug keystore (unchanged, tracked as
  Phase 11).
- Session was brief and superficial; no structured test plan with
  step-by-step expected outcomes was executed.
- No screenshots, logs, or recordings were captured from this session.

## 9. Final Phase 10 verdict

**Phase 10 (manual/device QA): partially complete.**

A superficial smoke test confirms the app builds, installs, and launches
without crashing on a real Android 15 device against a real Supabase
project. This is real, positive evidence that the build and basic startup
path work outside the emulator/test-fake environment.

It is **not** evidence that any specific feature (sync, notifications,
AI features, account deletion, offline handling) works correctly
end-to-end on a real device. Those flows remain unverified beyond the
existing automated test suite and should be treated as open risk until
exercised directly.

No Phase 11 (release signing, keystore, store metadata, release build
config) work was started.
