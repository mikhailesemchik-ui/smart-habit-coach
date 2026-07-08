import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/storage/local_namespace_resolver.dart';
import '../../../core/sync/recovery_snapshot_storage.dart';
import '../../../core/sync/sync_metadata_storage.dart';
import '../../../core/time/clock.dart';
import '../domain/habit.dart';

class HabitStorage {
  static const _habitsBaseKey = 'habits';

  final LocalNamespaceResolver _namespaceResolver;
  final Clock _clock;
  final SyncMetadataStorage _syncMetadataStorage;
  final RecoverySnapshotStorage? _recoverySnapshotStorageOverride;
  RecoverySnapshotStorage? _lazyRecoverySnapshotStorage;

  /// Serializes every write (normal and raw/bulk) issued through this
  /// instance, so a load→modify→save mutation can never interleave with
  /// another one on the same instance and silently lose an update. Chained
  /// with an error-swallowing continuation so one failed write cannot
  /// permanently block writes queued after it.
  Future<void> _writeQueue = Future.value();

  HabitStorage({
    LocalNamespaceResolver? namespaceResolver,
    Clock? clock,
    SyncMetadataStorage? syncMetadataStorage,
    RecoverySnapshotStorage? recoverySnapshotStorage,
  }) : _namespaceResolver = namespaceResolver ?? const LocalNamespaceResolver(),
       _clock = clock ?? const SystemClock(),
       _syncMetadataStorage = syncMetadataStorage ?? SyncMetadataStorage(),
       _recoverySnapshotStorageOverride = recoverySnapshotStorage;

  // Built lazily (not in the constructor) and reuses `this` rather than
  // constructing a fresh HabitStorage, so HabitStorage <->
  // RecoverySnapshotStorage never recurse into each other at construction
  // time.
  RecoverySnapshotStorage get _recoverySnapshotStorage =>
      _recoverySnapshotStorageOverride ??
      (_lazyRecoverySnapshotStorage ??= RecoverySnapshotStorage(
        namespaceResolver: _namespaceResolver,
        clock: _clock,
        habitStorage: this,
      ));

  Future<T> _enqueueWrite<T>(Future<T> Function() action) {
    final result = _writeQueue.then((_) => action());
    _writeQueue = result.then((_) {}, onError: (_) {});
    return result;
  }

  /// **Visible read.** Used by all normal UI/domain call sites. Excludes
  /// tombstoned records (`deletedAt != null`). Returns `null` only when the
  /// top-level stored value is missing, not a list, invalid JSON, or no
  /// namespace is available — never when the namespace exists but every
  /// record happens to be tombstoned (that case returns an empty list),
  /// which is exactly what lets first-load sample-habit logic distinguish
  /// "never initialized" from "everything was deleted."
  Future<List<Habit>?> loadHabits() async {
    final all = await loadHabitsRaw();
    if (all == null) return null;
    return all.where((h) => h.deletedAt == null).toList();
  }

  /// **Raw/all-record read.** Includes tombstoned records. Used by
  /// [upsertHabit]/[tombstoneHabit] (so re-saving never drops existing
  /// tombstones), [RecoverySnapshotStorage], and future sync/migration/
  /// tests. Each JSON list entry is decoded independently — a single
  /// malformed entry is skipped rather than discarding every other valid
  /// record.
  Future<List<Habit>?> loadHabitsRaw() async {
    final result = _namespaceResolver.resolveKey(_habitsBaseKey);
    if (!result.isAvailable) return null;

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(result.key!);
    if (raw == null) return null;

    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return null;
    }
    if (decoded is! List) return null;

    var skipped = 0;
    final habits = <Habit>[];
    for (final item in decoded) {
      if (item is! Map<String, dynamic>) {
        skipped++;
        continue;
      }
      try {
        habits.add(Habit.fromJson(item));
      } catch (_) {
        skipped++;
      }
    }
    if (skipped > 0) {
      debugPrint('HabitStorage: skipped $skipped malformed habit record(s)');
    }
    return habits;
  }

  /// Ensures every habit in [habits] exists in raw storage, without
  /// disturbing any that already do and without touching existing
  /// tombstones. Habits already present (matched by id) are left exactly
  /// as stored — no restamp, no dirty mark, just because the app happened
  /// to look at them. Habits not yet present (e.g. in-memory-only sample
  /// habits nobody has edited yet) are inserted with `createdAt`/
  /// `updatedAt` stamped to one shared [Clock] reading for the whole call,
  /// and their ids are marked dirty.
  ///
  /// Exists so a screen that only mutates *one* habit from a list (e.g.
  /// [tombstoneHabit] deleting a single item) can rely on every *other*
  /// currently-displayed habit also being safely readable afterward via
  /// [loadHabits] — without this, siblings that were never individually
  /// persisted would silently vanish from view once raw storage stops
  /// being empty. Call this once before an operation like that; it is not
  /// needed before [upsertHabit], which already handles a missing record
  /// on its own.
  /// Dirty-first: every newly-persisted id is marked dirty *before* the
  /// data write happens (see [upsertHabit] for the full rationale). If the
  /// process dies or the data write fails between the two, the worst case
  /// is a dirty id with no corresponding record yet — harmless, since a
  /// future sync engine simply finds nothing to push for it. The reverse
  /// order (data first) risks the opposite: a persisted record that no
  /// sync would ever know to upload, which is unrecoverable without a
  /// full local rescan.
  Future<void> ensurePersisted(List<Habit> habits) {
    return _enqueueWrite(() async {
      final current = await loadHabitsRaw() ?? [];
      final existingIds = current.map((h) => h.id).toSet();
      final missing = habits.where((h) => !existingIds.contains(h.id)).toList();
      if (missing.isEmpty) return;

      for (final habit in missing) {
        await _syncMetadataStorage.markHabitDirty(habit.id);
      }

      final now = _clock.now();
      for (final habit in missing) {
        current.add(habit.copyWith(createdAt: now, updatedAt: now));
      }

      await writeHabitsRaw(current);
    });
  }

  /// **Normal mutation path.** Used by all production UI/service call
  /// sites that create or change a single habit.
  ///
  /// Loads the current namespaced collection (including tombstones, so
  /// none are ever dropped by the re-save), locates [habit] by id
  /// (appending it if not found), stamps `updatedAt` with the injected
  /// [Clock], persists atomically through [saveHabits], and marks the
  /// habit's id dirty in [SyncMetadataStorage]. `createdAt` is always
  /// preserved from the existing stored record when one exists — never
  /// taken from [habit] itself, so a caller cannot accidentally regress
  /// it. For a genuinely new habit, `createdAt` and `updatedAt` are
  /// stamped with the *same* single [Clock] reading, discarding whatever
  /// legacy-sentinel/default timestamp [habit] happened to carry in memory
  /// (e.g. an in-memory sample habit persisted for the first time).
  /// `deletedAt` is always taken from [habit] as-is — callers express an
  /// explicit tombstone change (or its absence) via `Habit.copyWith`, and
  /// this method never second-guesses that (use [tombstoneHabit] to
  /// delete).
  ///
  /// Queued behind any other in-flight write on this instance (see
  /// [_enqueueWrite]), so two near-simultaneous calls each see the other's
  /// result rather than racing on a stale load.
  ///
  /// Throws a [StateError] if no local namespace is currently available —
  /// same policy as [saveHabits].
  ///
  /// **Dirty-first ordering**: the id is marked dirty *before* the data
  /// write happens, not after. A crash (or a data-write failure) between
  /// the two leaves a spurious dirty id with no matching data change —
  /// harmless, since a future sync engine just re-uploads the unchanged
  /// current record for it. The reverse order would risk the opposite: a
  /// successfully-persisted change that no sync would ever know to
  /// upload, which nothing but a full local rescan could recover from.
  /// Retrying this same call after either kind of failure is always safe
  /// and idempotent.
  Future<Habit> upsertHabit(Habit habit) {
    return _enqueueWrite(() async {
      await _syncMetadataStorage.markHabitDirty(habit.id);

      final current = await loadHabitsRaw() ?? [];
      final index = current.indexWhere((h) => h.id == habit.id);
      final now = _clock.now();

      final Habit stamped;
      if (index >= 0) {
        stamped = habit.copyWith(
          createdAt: current[index].createdAt,
          updatedAt: now,
        );
        current[index] = stamped;
      } else {
        stamped = habit.copyWith(createdAt: now, updatedAt: now);
        current.add(stamped);
      }

      await writeHabitsRaw(current);
      return stamped;
    });
  }

  /// **Tombstone delete.** The only production deletion path — a habit is
  /// never physically removed from storage. Creates a
  /// [RecoverySnapshotStorage] snapshot of the full current dataset first
  /// (so this destructive-looking change can always be recovered from
  /// locally), then sets `deletedAt` and `updatedAt` to the *same* single
  /// [Clock] reading and marks the id dirty.
  ///
  /// Takes the full in-memory [habit] (not just its id) and behaves like an
  /// upsert-then-tombstone: if a record with this id already exists in raw
  /// storage, its `createdAt` is preserved and only `deletedAt`/`updatedAt`
  /// change; if it does not (e.g. an in-memory-only sample habit the user
  /// deletes before ever mutating it), [habit] is inserted already
  /// tombstoned, with `createdAt`/`updatedAt`/`deletedAt` all stamped to
  /// the same single [Clock] reading — mirroring [upsertHabit]'s own
  /// "discard the in-memory legacy timestamp for a genuinely new record"
  /// rule. This means callers never need to pre-flush a habit into storage
  /// before deleting it.
  ///
  /// Returns the tombstoned [Habit]. Throws a [StateError] if no local
  /// namespace is available. Calling this twice on the same id is safe —
  /// the second call just re-stamps a later `updatedAt` on an
  /// already-deleted record.
  /// Ordering: the recovery snapshot is taken first (capturing the true
  /// pre-mutation state, including whatever was dirty *before* this
  /// delete), then the id is marked dirty, and only then is the data
  /// actually tombstoned — same dirty-first rationale as [upsertHabit].
  Future<Habit> tombstoneHabit(Habit habit) {
    return _enqueueWrite(() async {
      await _recoverySnapshotStorage.create(reason: 'beforeHabitTombstone');
      await _syncMetadataStorage.markHabitDirty(habit.id);

      final current = await loadHabitsRaw() ?? [];
      final index = current.indexWhere((h) => h.id == habit.id);
      final now = _clock.now();

      final Habit tombstoned;
      if (index >= 0) {
        tombstoned = current[index].copyWith(deletedAt: now, updatedAt: now);
        current[index] = tombstoned;
      } else {
        tombstoned = habit.copyWith(
          createdAt: now,
          updatedAt: now,
          deletedAt: now,
        );
        current.add(tombstoned);
      }

      await writeHabitsRaw(current);
      return tombstoned;
    });
  }

  /// **Raw/bulk persistence path.** Preserves every supplied timestamp
  /// exactly as given — never stamps `updatedAt`, never touches
  /// `createdAt`/`deletedAt`, never marks anything dirty. Reserved for the
  /// Phase 1A legacy/schema migrations, a future cloud-restore path, and
  /// tests that need exact timestamps. Production mutation call sites must
  /// use [upsertHabit]/[tombstoneHabit] instead — this method has no way
  /// to know which fields actually changed, so it cannot apply an
  /// authoritative `updatedAt` or dirty marker.
  ///
  /// Queued behind any other in-flight write on this instance, same as
  /// [upsertHabit], so a raw bulk write can never interleave with one.
  ///
  /// Throws a [StateError] if no local namespace is currently available —
  /// silently dropping a save would be a silent data-loss risk, so callers
  /// must not be able to invoke this before an identity is established.
  Future<void> saveHabits(List<Habit> habits) {
    return _enqueueWrite(() => writeHabitsRaw(habits));
  }

  /// Actual unqueued write, shared by [saveHabits], [upsertHabit], and
  /// [tombstoneHabit]. Deliberately not private (and not queued itself) so
  /// test fakes can subclass `HabitStorage` and override this single choke
  /// point to simulate a storage failure inside any of the three — the
  /// public [saveHabits] can't serve that role because [upsertHabit]/
  /// [tombstoneHabit] must call the *unqueued* write directly to avoid a
  /// same-instance write deadlocking against its own already-enqueued
  /// caller.
  Future<void> writeHabitsRaw(List<Habit> habits) async {
    final result = _namespaceResolver.resolveKey(_habitsBaseKey);
    if (!result.isAvailable) {
      throw StateError('HabitStorage.saveHabits: no local namespace available');
    }
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(habits.map((habit) => habit.toJson()).toList());
    await prefs.setString(result.key!, encoded);
  }
}
