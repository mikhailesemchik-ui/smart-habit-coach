# Testing and validation

## Local validation commands

Run from the repo root (`D:\new_life\Smart_Habit_Coach`):

```bash
dart format lib test
flutter analyze
flutter test
git diff --check
```

Or use the bundled script, which runs the same steps in order and stops at
the first failure:

```powershell
.\scripts\test_all.ps1
```

```bash
./scripts/test_all.sh
```

## Focused suites

Useful when iterating on one area instead of the whole app:

```bash
flutter test test/features/auth/
flutter test test/features/sync/
flutter test test/features/privacy/
flutter test test/features/profile/
flutter test test/features/home/
flutter test test/features/startup/
flutter test test/core/
flutter test test/supabase/
```

`test/supabase/` contains static, file-content assertions about the
`delete-account` Edge Function's source (JWT handling, no arbitrary
`user_id` from the request body, no service-role material in the Flutter
client). It does not start a server or call Supabase.

## What the test suite does *not* require

- No real Supabase project, URL, or anon key.
- No network access.
- No Supabase CLI (`supabase start`, `supabase db`, etc.).
- No Android/iOS signing configuration.
- No real OpenAI key.

Every test that touches auth, sync, cloud storage, or the delete-account
flow does so against a hand-written fake (`FakeAuthRepository`, fake
`AccountDeletionRepository`, fake `NotificationService`, in-memory
`SharedPreferences`, etc.) — never a live backend. `LocalNamespaceResolver`
supports a `debugUidOverride` used throughout the suite (wired once in
`test/flutter_test_config.dart`) specifically so tests never need a real
Supabase session to exercise namespaced local storage.

## Optional: Supabase CLI checks

These are **not required** for `flutter test` or CI, and are safe,
non-destructive, read-only checks you can run locally if the Supabase CLI
is installed and the project is linked:

```bash
supabase db lint
supabase migration list
supabase functions list
```

If the CLI isn't installed, these are simply skipped — the app and its
test suite do not depend on them. Never run destructive Supabase commands
(`db reset`, `db push` against a real project, etc.) as part of routine
validation.

## Known noise (fixed in Phase 8)

Widget tests that don't inject a fake `NotificationService` construct a
real one with no platform channel registered, so its plugin calls always
fail — this is caught and was previously logged as
`NotificationService.initialize failed: LateInitializationError: ...` on
every such test. `test/flutter_test_config.dart` now sets
`NotificationService.debugSuppressLogging = true` for the whole suite, so
this expected-but-noisy log no longer appears. Production logging
behavior is unchanged.

## CI

`.github/workflows/flutter-ci.yml` runs `dart format --set-exit-if-changed`,
`flutter analyze`, `flutter test`, and `git diff --check` on every push and
pull request against `main`. It needs no secrets and performs no release
build or signing — see `docs/architecture.md` and `PROJECT_HANDOFF.md` for
what's still pending (Phase 10 manual/device QA, Phase 11 release
signing).
