import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/storage/local_namespace_resolver.dart';
import '../../../core/time/clock.dart';
import '../domain/habit.dart';

class HabitStorage {
  static const _habitsBaseKey = 'habits';

  final LocalNamespaceResolver _namespaceResolver;
  final Clock _clock;

  /// Serializes every write (normal and raw/bulk) issued through this
  /// instance, so a load→modify→save mutation can never interleave with
  /// another one on the same instance and silently lose an update. Chained
  /// with an error-swallowing continuation so one failed write cannot
  /// permanently block writes queued after it.
  Future<void> _writeQueue = Future.value();

  HabitStorage({LocalNamespaceResolver? namespaceResolver, Clock? clock})
    : _namespaceResolver = namespaceResolver ?? const LocalNamespaceResolver(),
      _clock = clock ?? const SystemClock();

  Future<T> _enqueueWrite<T>(Future<T> Function() action) {
    final result = _writeQueue.then((_) => action());
    _writeQueue = result.then((_) {}, onError: (_) {});
    return result;
  }

  /// Loads all valid habit records. Each JSON list entry is decoded
  /// independently — a single malformed entry is skipped rather than
  /// discarding every other valid record. Returns `null` only when the
  /// top-level stored value itself is missing, not a list, or not valid
  /// JSON (matching this method's existing "no usable data" contract), or
  /// when no local namespace is currently available.
  Future<List<Habit>?> loadHabits() async {
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

  /// **Normal mutation path.** Used by all production UI/service call
  /// sites that create or change a single habit.
  ///
  /// Loads the current namespaced collection, locates [habit] by id
  /// (appending it if not found), stamps `updatedAt` with the injected
  /// [Clock], and persists atomically through [saveHabits]. `createdAt` is
  /// always preserved from the existing stored record when one exists —
  /// never taken from [habit] itself, so a caller cannot accidentally
  /// regress it. For a genuinely new habit, `createdAt` and `updatedAt`
  /// are stamped with the *same* single [Clock] reading, discarding
  /// whatever legacy-sentinel/default timestamp [habit] happened to carry
  /// in memory (e.g. an in-memory sample habit persisted for the first
  /// time). `deletedAt` is always taken from [habit] as-is — callers
  /// express an explicit tombstone change (or its absence) via
  /// `Habit.copyWith`, and this method never second-guesses that.
  ///
  /// Queued behind any other in-flight write on this instance (see
  /// [_enqueueWrite]), so two near-simultaneous calls each see the other's
  /// result rather than racing on a stale load.
  ///
  /// Throws a [StateError] if no local namespace is currently available —
  /// same policy as [saveHabits].
  Future<Habit> upsertHabit(Habit habit) {
    return _enqueueWrite(() async {
      final current = await loadHabits() ?? [];
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

      await _saveHabitsUnqueued(current);
      return stamped;
    });
  }

  /// **Raw/bulk persistence path.** Preserves every supplied timestamp
  /// exactly as given — never stamps `updatedAt`, never touches
  /// `createdAt`/`deletedAt`. Reserved for the Phase 1A legacy/schema
  /// migrations, a future cloud-restore path, and tests that need exact
  /// timestamps. Production mutation call sites must use [upsertHabit]
  /// instead — this method has no way to know which fields actually
  /// changed, so it cannot apply an authoritative `updatedAt`.
  ///
  /// Queued behind any other in-flight write on this instance, same as
  /// [upsertHabit], so a raw bulk write can never interleave with one.
  ///
  /// Throws a [StateError] if no local namespace is currently available —
  /// silently dropping a save would be a silent data-loss risk, so callers
  /// must not be able to invoke this before an identity is established.
  Future<void> saveHabits(List<Habit> habits) {
    return _enqueueWrite(() => _saveHabitsUnqueued(habits));
  }

  Future<void> _saveHabitsUnqueued(List<Habit> habits) async {
    final result = _namespaceResolver.resolveKey(_habitsBaseKey);
    if (!result.isAvailable) {
      throw StateError('HabitStorage.saveHabits: no local namespace available');
    }
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(habits.map((habit) => habit.toJson()).toList());
    await prefs.setString(result.key!, encoded);
  }
}
