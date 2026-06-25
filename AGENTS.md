# AGENTS.md

## Project

Smart Habit Coach is a Flutter mobile application for building, tracking, and improving habits with AI-assisted suggestions and weekly reviews.

Current target platforms:
- Android
- iOS

Use English for code, filenames, comments, commits, tests, and UI text unless a task explicitly says otherwise.

## Instruction Priority

Follow these rules for all work in this repository.

Before starting any task:
1. Read this file.
2. Read `PROJECT_HANDOFF.md`.
3. Inspect only the files relevant to the current task.
4. Check `git status`.
5. Do not modify anything unrelated.

If instructions conflict:
- Follow the user's current explicit request first.
- Then follow this file.
- Preserve existing project behavior and architecture unless change is required.

## Core Principles

1. KISS — choose the simplest correct solution.
2. YAGNI — do not build speculative functionality.
3. Single Responsibility — each class, method, and file should have one clear purpose.
4. Fail Fast — validate important assumptions and handle errors early.
5. Prefer maintainable code over clever code.
6. Do not introduce abstractions, architecture, or dependencies without a concrete need.

## Cost-Efficient Agent Behavior

- Do not scan the entire repository unless necessary.
- Do not repeatedly read the same files.
- Do not run expensive commands more than needed.
- Do not produce long explanations unless requested.
- Do not generate extra documentation files unless requested.
- Do not propose unrelated improvements in the final response.
- Prefer one focused implementation pass followed by relevant checks.
- Ask a question only when a missing detail blocks safe implementation.
- Never continue exploring after the requested task is complete.

## Task Scope

- Change only files required for the task.
- Do not refactor unrelated code.
- Do not rename or move unrelated files.
- Do not add speculative features.
- Do not add packages unless necessary.
- Reuse existing project patterns.
- Preserve existing behavior unless explicitly changing it.
- Do not modify `AGENTS.md`, `CLAUDE.md`, or `PROJECT_HANDOFF.md` unless explicitly requested.
- Do not commit or push unless explicitly requested.

## Flutter and Dart Standards

- Use stable Flutter and Dart versions available in the environment.
- Use null safety.
- Use Material 3.
- Follow Effective Dart conventions.
- Format with `dart format`.
- Keep `flutter analyze` clean.
- Prefer immutable widgets and models where practical.
- Use `const` constructors whenever valid.
- Avoid `dynamic` unless required by an external API.
- Avoid force unwraps (`!`) unless safety is guaranteed and obvious.
- Do not suppress analyzer warnings without a strong reason.
- Avoid deeply nested widget trees; extract meaningful widgets only when readability improves.
- Keep UI, business logic, persistence, and remote services separated.

## Naming

- Files: `snake_case.dart`
- Variables and methods: `lowerCamelCase`
- Classes, enums, typedefs: `UpperCamelCase`
- Constants: `lowerCamelCase`
- Private members: `_leadingUnderscore`
- Booleans: `isLoading`, `hasError`, `canSubmit`

Use descriptive domain names.

## Project Structure

Use feature-first organization.

```text
lib/
  app/
  core/
  features/
    feature_name/
      data/
      domain/
      presentation/
```

The project also contains:
- `supabase/functions/` for Edge Functions
- `test/` mirroring application features

Rules:
- Keep feature code inside its feature folder.
- Put shared code in `core/` only when used by multiple features.
- Do not create empty layers.
- Do not add Clean Architecture boilerplate without demonstrated complexity.
- Keep tests structurally close to the feature they cover.

## State Management

- Continue using the current local state patterns.
- Do not add Riverpod, BLoC, Provider, GetX, or another state package unless explicitly required.
- Keep simple transient UI state inside widgets.
- Keep business logic in domain functions/services.
- Do not mix state-management approaches without a clear reason.

## Dependencies

- Check `pubspec.yaml` before adding packages.
- Use `flutter pub add <package>` where practical.
- Do not upgrade unrelated dependencies.
- Do not add overlapping packages.
- Prefer maintained packages with clear documentation.

## Supabase and OpenAI Security

- Never commit API keys, tokens, passwords, certificates, or secrets.
- Never place `OPENAI_API_KEY` in Flutter code, assets, committed `.env` files, dart defines, logs, tests, or documentation.
- OpenAI secrets must remain in Supabase project secrets.
- Flutter may use only public Supabase values through:
  - `SUPABASE_URL`
  - `SUPABASE_ANON_KEY` / publishable key
- Never use Supabase `service_role` or secret keys in the Flutter client.
- Do not log JWTs, sessions, user IDs, headers, API keys, or secret values.
- AI Edge Functions must require a valid authenticated Supabase session.
- Preserve anonymous-auth startup behavior unless explicitly replacing it with a full account flow.
- Treat AI endpoints as billable endpoints.
- Any future quota or rate-limit implementation must be enforced server-side.
- CORS is not a security boundary for mobile clients.
- Do not weaken `verify_jwt` without explicit approval.

## Edge Functions

- Keep each Edge Function focused on one task.
- Validate all request payloads.
- Use strict structured JSON outputs from OpenAI.
- Validate model responses before returning them.
- Return safe, consistent error JSON.
- Never return raw OpenAI errors or stack traces.
- Use timeouts for network requests.
- Do not log secrets.
- Do not deploy functions unless explicitly requested.
- After changing a function, report the exact deploy command.

## Local-First Behavior

- Core habit tracking must continue working offline.
- AI failures must not block app startup or basic habit tracking.
- Preserve friendly fallback behavior for Weekly Review.
- SharedPreferences persistence must remain backward-compatible when models change.
- Avoid destructive migrations.

## Error Handling

- Never silently ignore failures unless offline-first startup explicitly requires it.
- Catch only errors that can be handled meaningfully.
- Show user-friendly messages.
- Keep technical details out of user-facing text.
- Handle loading, empty, success, and error states.
- Prevent duplicate submissions and repeated network calls.

## Async and Lifecycle

- Await futures when order or error handling matters.
- Avoid unawaited work unless intentional.
- Check widget lifecycle before using `BuildContext` after async gaps.
- Cancel subscriptions, controllers, and timers in `dispose`.
- Do not block app startup for optional network features.

## UI and Accessibility

- Support narrow Android screens.
- Use `SafeArea` where system insets can affect content.
- Bottom sheets must remain scrollable and reachable with the keyboard open.
- Avoid fixed heights that can overflow.
- Keep touch targets usable.
- Avoid text wrapping inside compact controls when possible.
- Preserve light and dark mode readability.
- Do not redesign the app unless explicitly asked.

## Testing

Add tests for:
- business logic;
- parsing and validation;
- state transitions;
- persistence migrations;
- critical UI behavior;
- security-sensitive behavior where practical.

Rules:
- Use descriptive test names.
- Cover success, failure, and edge cases.
- Keep tests deterministic.
- Do not make real network calls.
- Use injectable fakes for Supabase/OpenAI services.
- Do not add low-value tests only for coverage.
- Do not claim behavior is tested when it is only manually verified.

## Required Validation

Default after Dart changes:

```bash
dart format .
flutter analyze
```

Run tests when logic or tested behavior changed:

```bash
flutter test
```

Prefer targeted tests first for narrow changes:

```bash
flutter test test/path/to/test_file.dart
```

Before a commit:

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
```

Do not repeatedly run the full suite without a reason.

## Commands and Search

Use efficient commands:

```bash
rg "pattern"
rg --files
rg --files -g "*.dart"
```

Do not inspect generated/vendor directories:
- `.git/`
- `.dart_tool/`
- `build/`
- `node_modules/`
- `supabase/.temp/`

## Git and GitHub

- Never mention Codex, Claude, AI-generated, or similar wording in commit messages.
- Do not commit unless explicitly asked.
- Do not push unless explicitly asked.
- Do not rewrite history.
- Do not discard user changes.
- Check `git status` before destructive operations.
- Never commit secrets, `.env`, build outputs, local Supabase state, APK/AAB files, logs, or credentials.

Commit format:

```text
<type>(<scope>): <subject>
```

Allowed types:
- `feat`
- `fix`
- `refactor`
- `test`
- `docs`
- `style`
- `chore`

## Final Response Format

Keep the final response concise.

Include only:
1. What changed.
2. Files changed.
3. Checks run and results.
4. Manual/deploy steps.
5. Remaining issue, if any.

## Critical Restrictions

- Do not modify unrelated files.
- Do not add unnecessary dependencies.
- Do not overengineer.
- Do not guess credentials, paths, APIs, or project state.
- Verify relevant names and paths before editing.
- Do not claim checks passed unless actually run.
- Do not hide failures.
- Do not replace working code to match personal preference.
- Do not weaken security controls for convenience.
