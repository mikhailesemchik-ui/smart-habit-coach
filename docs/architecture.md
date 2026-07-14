# Architecture summary

This is a working summary of what's actually implemented, written at the
end of Phase 9. It is not a design proposal — for the phase-by-phase
implementation history and rationale, see `PROJECT_HANDOFF.md`.

## Layering

Feature-first, `lib/features/<feature>/{data,domain,presentation}`, with
cross-feature shared code in `lib/core/`. No global state-management
package — `ChangeNotifier`-based controllers per feature (e.g.
`AccountController`, `SyncController`) plus plain `StatefulWidget` state
for local UI concerns.

## Local-first, UID-scoped storage

Every piece of user-owned local data is namespaced by the active Supabase
auth UID: `habits:<uid>`, `adaptive_suggestions:<uid>`, `app_settings:<uid>`,
`sync_metadata:<uid>`, `recovery_snapshot:<uid>`, `local_schema_version:<uid>`.
`LocalNamespaceResolver` is the single source of truth for the active UID
and for building these keys — no storage class ever falls back to an
unscoped key. A dedicated `LegacyMigrationRunner` handles the one-time,
permanently-marked migration of pre-namespacing data into the first real
UID.

Mutations go through narrow, centralized methods (`upsertHabit`,
`tombstoneHabit`, `updateSettings`, …) that stamp `updatedAt` via an
injectable `Clock` (never `DateTime.now()` directly in a storage write
path) and mark the record dirty in `SyncMetadataStorage` *before* the data
write — so a crash between the two leaves, at worst, a harmless spurious
dirty id, never a silently-unsynced change.

Deletes are tombstones (`deletedAt` set, record kept in raw storage, never
physically removed) with no automatic garbage collection yet. Normal reads
filter tombstones out; raw reads (used by sync, export, and recovery
snapshots) include them.

`RecoverySnapshotStorage` keeps a single latest raw JSON backup per UID,
created before destructive local replacements (sync's remote-wins path,
tombstone deletes). It is not used as a backup ahead of account deletion —
see below.

## Authentication

`AuthRepository` abstracts `supabase_flutter`'s `GoTrueClient`. The app
always has a session: an anonymous one is established on first launch
(`AuthSessionGateway`), and can be upgraded in place to an email/password
account (uid preserved) or replaced by a returning user's sign-in (a
different uid, with an explicit "preserve local data" confirmation step
before the switch — see `ReturningUserSignInService`). Sign-out always
returns to a fresh anonymous identity; no data is ever deleted by sign-out
or sign-in.

## Sync

`SyncCoordinator` (Phase 4) is the only code that talks to the cloud
repositories. It is explicit and manual (a "Sync now" button) — no
background or periodic sync. For each record type it compares local vs.
remote `updatedAt`, resolves ties via tombstone-wins-then-canonical-JSON
(never wall-clock "now"), and only clears a dirty flag after confirming
the currently-stored record still matches what was acknowledged remotely.
"Use data on this device" makes the cloud genuinely match the device by
diffing and explicitly tombstoning remote-only records, not by a plain
upsert.

## Cloud schema

Three Postgres tables (`habits`, `adaptive_suggestions`, `user_preferences`),
each with a composite `(user_id, id)` primary key (or `user_id` alone for
preferences), `on delete cascade` from `auth.users`, and row-level security
scoped to `auth.uid() = user_id`. `anon` has no grants; `authenticated`
relies entirely on RLS. A fourth table, `ai_request_quotas` (predates this
phase's account-deletion work), also cascades on user deletion.

## Notifications

`NotificationService` wraps `flutter_local_notifications`. Reminder IDs are
derived from habit id (not UID), so `NotificationReconciliationService`
cancels every scheduled reminder and reschedules only the active
namespace's active habits whenever the active identity changes (sign-in,
sign-out, account deletion) — this is what actually prevents a previous
identity's reminders from lingering, not the ID scheme itself.

## Privacy and export

`LocalDataExportService` builds a deterministic, read-only JSON snapshot of
the active UID's local data (habits and suggestions including tombstones,
settings, sync metadata, and the latest recovery snapshot) for personal
backup — never auth tokens, session data, or cloud credentials. The Privacy
screen explains local storage, cloud sync, AI data usage, notifications,
and how to export, without claiming GDPR compliance.

## Account deletion

A `delete-account` Supabase Edge Function (`verify_jwt = true`) derives the
user id to delete solely from the caller's own JWT — the request body is
never read for a user id, so a caller can never name another account. It
uses the Supabase service-role key to call the Admin API's `deleteUser`;
that key exists only in the function's server-side environment, never in
the Flutter client. Postgres cascade removes every user-owned row as an
automatic consequence. `AccountDeletionService` on the client only wipes
local data (via `LocalNamespaceCleanupService`, the one place in the app
allowed to bulk-remove a namespace, and only for an explicit uid it's told
to wipe) *after* the backend confirms deletion, and reports a distinct
partial-failure state if local cleanup or re-establishing a fresh
anonymous identity fails afterward — it never claims full success unless
every step completed.

## AI features

Two Edge Functions (`generate-habit`, `generate-weekly-review`) call
OpenAI with strict structured-output schemas and per-user daily quotas
enforced in Postgres (`consume_ai_quota`). Both require a valid Supabase
JWT. The Flutter client sends only the minimum needed (a free-form goal
string, or numeric/enum weekly aggregates) — never habit notes or raw
history.

## What this is not (yet)

- No CI-driven release build or signing (Phase 11).
- No completed manual/device QA pass (Phase 10).
- No background or periodic sync.
- No automatic tombstone garbage collection.
- No multi-recovery-snapshot history (single latest only).
