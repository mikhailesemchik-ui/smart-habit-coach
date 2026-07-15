# Android release signing

Resolves the Phase 0 P1 finding (`AUDIT-P1-001`): the release build used
to always fall back to the debug keystore, which is not publishable and
not safe to ship. As of Phase 11, the release build type has **no**
signing config at all until a real keystore is supplied locally — it
never silently signs with the debug key.

None of this repo's files contain real signing material. You must create
your own keystore locally; it is git-ignored and must never be committed.

## 1. Create a release keystore (one-time, local only)

```bash
keytool -genkey -v -keystore ~/upload-keystore.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias upload
```

Store the resulting `.jks` file and its passwords somewhere safe (a
password manager or secrets vault) — losing the keystore means you can
never publish an update to an app already on the Play Store under the
same application id. Do **not** put the `.jks` file inside the repo.

## 2. Create `android/key.properties` (local only, git-ignored)

Create `android/key.properties` with these four fields — placeholders
shown, fill in your own real values locally, never commit this file:

```properties
storePassword=<your-keystore-password>
keyPassword=<your-key-password>
keyAlias=upload
storeFile=<absolute-or-relative-path-to-upload-keystore.jks>
```

`storeFile` may be an absolute path or a path relative to `android/`.

This file (`key.properties`, at the repo root or under `android/` or
`android/app/`), and any `*.jks`/`*.keystore` file, are excluded via
`.gitignore`. Verify before committing anything:

```bash
git status --short
```

If `key.properties` or a `.jks`/`.keystore` file ever shows as trackable,
stop and do not commit it.

## 3. How the build picks this up

`android/app/build.gradle.kts` reads `android/key.properties` at
configure time:

- If the file exists **and** all four fields (`storeFile`,
  `storePassword`, `keyAlias`, `keyPassword`) are present and non-blank,
  the `release` build type is signed with that keystore.
- Otherwise, the `release` build type has no signing config, and any
  `assembleRelease`/`bundleRelease` task fails immediately with a clear
  error pointing back to this file. It never falls back to debug signing.

No secret values are read from environment variables, dart-defines, or
committed anywhere in this repo — only from the local, git-ignored
`android/key.properties`.

## 4. Building a release artifact locally

Once `android/key.properties` exists:

```bash
flutter build apk --release \
  --dart-define=SUPABASE_URL=https://<your-project>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<publishable-anon-key>
```

or, for a Play Store upload bundle:

```bash
flutter build appbundle --release \
  --dart-define=SUPABASE_URL=https://<your-project>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<publishable-anon-key>
```

`SUPABASE_URL` and `SUPABASE_ANON_KEY` are the public project URL and
anon/publishable key — safe to pass on the command line, but still not
something to hardcode into a committed file. Build output lands under
`build/app/outputs/`, which is git-ignored; do not manually stage or
commit anything from that directory.

## 5. What CI does and does not do

`.github/workflows/flutter-ci.yml` runs formatting, analysis, and tests
only. It does **not** build a release APK/AAB and does not have access to
any signing material — release builds are a manual, local step performed
by whoever holds the keystore.

## 6. Scope

This document covers signing readiness only. It does not cover Play
Store listing metadata, versioning strategy, or store submission — none
of that exists in this repo yet.
