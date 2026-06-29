import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_habit_coach/features/home/domain/habit.dart';
import 'package:smart_habit_coach/features/home/domain/habit_stats.dart';

// Fixed reference dates.
// Sat 2026-06-27 is the outer reference; Wed 2026-06-24 used in streak tests.
final _today = DateTime(2026, 6, 27);

Habit _makeHabit({
  String id = '1',
  Set<String> completedDates = const {},
  Set<String> minimumCompletedDates = const {},
  String? minimumVersion,
  HabitStatus status = HabitStatus.active,
  String? pausedFromDate,
}) => Habit(
  id: id,
  title: 'Test habit',
  scheduledTime: '08:00 AM',
  icon: Icons.local_drink_outlined,
  weekdays: const [1, 2, 3, 4, 5, 6, 7],
  completedDates: completedDates,
  minimumCompletedDates: minimumCompletedDates,
  minimumVersion: minimumVersion,
  status: status,
  pausedFromDate: pausedFromDate,
);

void main() {
  // ── Test 1: old JSON without minimum fields loads correctly ────────────────
  test(
    'old JSON without minimumVersion and minimumCompletedDates loads correctly',
    () {
      final json = {
        'id': '1',
        'title': 'Old habit',
        'scheduledTime': '08:00 AM',
        'iconId': 'water',
        'completedDates': <String>[],
        'weekdays': [1, 2, 3, 4, 5, 6, 7],
        // minimumVersion and minimumCompletedDates absent — must default safely
      };

      final habit = Habit.fromJson(json);

      expect(habit.minimumVersion, isNull);
      expect(habit.minimumCompletedDates, isEmpty);
      expect(habit.hasMinimumVersion, isFalse);
    },
  );

  // ── Test 2: minimumVersion serializes and reloads ─────────────────────────
  test('minimumVersion round-trips through toJson/fromJson', () {
    final original = _makeHabit(minimumVersion: '5 minutes of stretching');
    final restored = Habit.fromJson(original.toJson());

    expect(restored.minimumVersion, '5 minutes of stretching');
    expect(restored.hasMinimumVersion, isTrue);
  });

  // ── Test 3: minimumCompletedDates serializes and reloads ──────────────────
  test('minimumCompletedDates round-trips through toJson/fromJson', () {
    final original = _makeHabit(
      minimumCompletedDates: {'2026-06-01', '2026-06-02'},
    );
    final restored = Habit.fromJson(original.toJson());

    expect(restored.minimumCompletedDates, {'2026-06-01', '2026-06-02'});
    expect(restored.completedDates, isEmpty);
  });

  // ── Test 4: a date cannot remain in both sets ──────────────────────────────
  test(
    'date cannot exist in both completedDates and minimumCompletedDates',
    () {
      const key = '2026-06-01';
      // Start as minimum then set to full.
      final habit = _makeHabit(minimumCompletedDates: {key});
      final updated = habit.setCompletionStatus(
        key,
        HabitCompletionStatus.full,
      );

      expect(updated.completedDates.contains(key), isTrue);
      expect(updated.minimumCompletedDates.contains(key), isFalse);
    },
  );

  // ── Test 5: setting Full removes Minimum ──────────────────────────────────
  test('setting Full removes date from minimumCompletedDates', () {
    const key = '2026-06-01';
    final habit = _makeHabit(minimumCompletedDates: {key});
    final updated = habit.setCompletionStatus(key, HabitCompletionStatus.full);

    expect(updated.completionStatusFor(key), HabitCompletionStatus.full);
    expect(updated.minimumCompletedDates, isEmpty);
  });

  // ── Test 6: setting Minimum removes Full ──────────────────────────────────
  test('setting Minimum removes date from completedDates', () {
    const key = '2026-06-01';
    final habit = _makeHabit(completedDates: {key});
    final updated = habit.setCompletionStatus(
      key,
      HabitCompletionStatus.minimum,
    );

    expect(updated.completionStatusFor(key), HabitCompletionStatus.minimum);
    expect(updated.completedDates, isEmpty);
  });

  // ── Test 7: setting None removes both ─────────────────────────────────────
  test('setting None removes date from both sets', () {
    const key = '2026-06-01';
    final habit = _makeHabit(completedDates: {key});
    final updated = habit.setCompletionStatus(key, HabitCompletionStatus.none);

    expect(updated.completedDates.contains(key), isFalse);
    expect(updated.minimumCompletedDates.contains(key), isFalse);
  });

  // ── Test 8: editing preserves both histories ───────────────────────────────
  test('copyWith preserves both completedDates and minimumCompletedDates', () {
    final original = _makeHabit(
      completedDates: {'2026-06-01'},
      minimumCompletedDates: {'2026-06-02'},
      minimumVersion: 'Light walk',
    );
    final copy = original.copyWith();

    expect(copy.completedDates, {'2026-06-01'});
    expect(copy.minimumCompletedDates, {'2026-06-02'});
    expect(copy.minimumVersion, 'Light walk');
  });

  // ── Test 16: full completion rate counts only full ─────────────────────────
  test('habitCompletionRate counts only full completions', () {
    // 3 fully completed days, 2 minimum-only days. All 7 days scheduled/week.
    final habit = _makeHabit(
      completedDates: {'2026-06-22', '2026-06-23', '2026-06-24'},
      minimumCompletedDates: {'2026-06-25', '2026-06-26'},
    );

    final fullRate = habitCompletionRate(habit, _today);
    final consistencyRate = habitConsistencyRate(habit, _today);

    // Consistency counts full + minimum → higher than full-only rate.
    expect(fullRate, lessThan(consistencyRate));
    // Verify full rate doesn't count minimums by checking exact ratio isn't inflated.
    expect(fullRate, lessThan(0.3)); // 3 out of 30 days ≈ 0.1
  });

  // ── Test 17: consistency rate counts full + minimum ────────────────────────
  test('habitConsistencyRate counts full and minimum completions', () {
    final today = DateTime(2026, 6, 24); // Wednesday
    // Mon-Tue fully completed, Wed minimum.
    final habit = _makeHabit(
      completedDates: {'2026-06-22', '2026-06-23'},
      minimumCompletedDates: {'2026-06-24'},
    );

    final fullRate = habitCompletionRate(habit, today);
    final rate = habitConsistencyRate(habit, today);

    // Consistency should count all 3 days; full only counts 2.
    expect(rate, greaterThan(fullRate));
  });

  // ── Test 18: unscheduled days do not count ─────────────────────────────────
  test('habitMinimumCompletedCount excludes unscheduled days', () {
    // Habit scheduled Monday only; minimum completion on Sunday (unscheduled).
    final habit = Habit(
      id: '1',
      title: 'Gym',
      scheduledTime: '07:00 AM',
      icon: Icons.local_drink_outlined,
      weekdays: const [1], // Monday only
      completedDates: const {'2026-06-22'}, // Monday — counts
      minimumCompletedDates: const {'2026-06-21'}, // Sunday — not scheduled
    );

    expect(habitMinimumCompletedCount(habit), 0);
  });

  // ── Test 19: paused days do not accumulate ─────────────────────────────────
  test('paused habit rate does not penalise post-pause days', () {
    // All 3 active days (Mon-Wed) fully completed; paused from Thu.
    final paused = _makeHabit(
      completedDates: {'2026-06-22', '2026-06-23', '2026-06-24'},
      status: HabitStatus.paused,
      pausedFromDate: '2026-06-25',
    );
    // Equivalent active habit with same completions — Thu/Fri/Sat count as misses.
    final active = _makeHabit(
      completedDates: {'2026-06-22', '2026-06-23', '2026-06-24'},
    );

    // Paused habit's effective window ends at Wed → no extra misses → higher rate.
    expect(
      habitCompletionRate(paused, _today),
      greaterThanOrEqualTo(habitCompletionRate(active, _today)),
    );
  });

  // ── Test 20: minimum does not count toward full streak ─────────────────────
  test('minimum completion does not count toward habitCurrentStreak', () {
    // Mon (full), Tue (minimum), Wed (full).
    final habit = _makeHabit(
      completedDates: {'2026-06-22', '2026-06-24'},
      minimumCompletedDates: {'2026-06-23'},
    );
    final today = DateTime(2026, 6, 24); // Wednesday

    // Full streak: Wed full (1), Tue minimum → break → streak = 1.
    expect(habitCurrentStreak(habit, today), 1);
    // Consistency streak: Wed + Tue + Mon = 3.
    expect(habitConsistencyStreak(habit, today), 3);
  });

  // ── Test 22: removing minimumVersion does not erase minimum history ─────────
  test('setting minimumVersion to null preserves minimumCompletedDates', () {
    final habit = _makeHabit(
      minimumVersion: 'Light walk',
      minimumCompletedDates: {'2026-06-22', '2026-06-23'},
    );

    final updated = habit.copyWith(minimumVersion: null);

    expect(updated.minimumVersion, isNull);
    expect(updated.hasMinimumVersion, isFalse);
    expect(updated.minimumCompletedDates, {'2026-06-22', '2026-06-23'});
  });
}
