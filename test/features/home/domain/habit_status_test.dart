import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_habit_coach/features/home/domain/habit.dart';
import 'package:smart_habit_coach/features/home/domain/habit_stats.dart';
import 'package:smart_habit_coach/features/progress/domain/progress_stats.dart';

// Fixed reference date: Saturday 2026-06-27.
// Pause boundary used in tests: 2026-06-25 (Thursday).
// Active window with that boundary: Mon 22 – Wed 24 (3 days).
final _today = DateTime(2026, 6, 27);
const _pauseDate = '2026-06-25';

Habit _makeHabit({
  String id = '1',
  Set<String> completedDates = const {},
  HabitStatus status = HabitStatus.active,
  String? pausedFromDate,
}) => Habit(
  id: id,
  title: 'Test habit',
  scheduledTime: '08:00 AM',
  icon: Icons.local_drink_outlined,
  completedDates: completedDates,
  weekdays: const [1, 2, 3, 4, 5, 6, 7],
  status: status,
  pausedFromDate: pausedFromDate,
);

void main() {
  // ── Test 1: old JSON defaults to active ────────────────────────────────────
  test('old JSON without status field defaults to active', () {
    final json = {
      'id': '1',
      'title': 'Old habit',
      'scheduledTime': '08:00 AM',
      'iconId': 'water',
      'completedDates': <String>[],
      'weekdays': [1, 2, 3, 4, 5, 6, 7],
      // 'status' absent — must default to active
    };

    final habit = Habit.fromJson(json);

    expect(habit.status, HabitStatus.active);
    expect(habit.pausedFromDate, isNull);
  });

  // ── Test 2: status serializes and reloads ──────────────────────────────────
  test('paused status round-trips through toJson/fromJson', () {
    final original = _makeHabit(
      status: HabitStatus.paused,
      pausedFromDate: _pauseDate,
    );

    final restored = Habit.fromJson(original.toJson());

    expect(restored.status, HabitStatus.paused);
    expect(restored.pausedFromDate, _pauseDate);
  });

  test('archived status round-trips through toJson/fromJson', () {
    final original = _makeHabit(
      status: HabitStatus.archived,
      pausedFromDate: _pauseDate,
    );

    final restored = Habit.fromJson(original.toJson());

    expect(restored.status, HabitStatus.archived);
    expect(restored.pausedFromDate, _pauseDate);
  });

  // ── Test 3: malformed status defaults safely ───────────────────────────────
  test('unknown status string defaults to active', () {
    final json = {
      'id': '1',
      'title': 'Habit',
      'scheduledTime': '08:00 AM',
      'iconId': 'water',
      'completedDates': <String>[],
      'weekdays': [1, 2, 3, 4, 5, 6, 7],
      'status': 'not_a_real_status',
    };

    final habit = Habit.fromJson(json);

    expect(habit.status, HabitStatus.active);
  });

  test('null status value defaults to active', () {
    final json = {
      'id': '1',
      'title': 'Habit',
      'scheduledTime': '08:00 AM',
      'iconId': 'water',
      'completedDates': <String>[],
      'weekdays': [1, 2, 3, 4, 5, 6, 7],
      'status': null,
    };

    final habit = Habit.fromJson(json);

    expect(habit.status, HabitStatus.active);
  });

  // ── Test 4: pause preserves completion history ─────────────────────────────
  test('pausing a habit preserves all completion history', () {
    const dates = {'2026-06-22', '2026-06-23', '2026-06-24'};
    final active = _makeHabit(completedDates: dates);

    final paused = active.asPaused(_pauseDate);

    expect(paused.status, HabitStatus.paused);
    expect(paused.completedDates, dates);
    expect(paused.pausedFromDate, _pauseDate);
  });

  // ── Test 5: resume preserves completion history ────────────────────────────
  test('resuming a paused habit preserves all completion history', () {
    const dates = {'2026-06-22', '2026-06-23'};
    final paused = _makeHabit(
      completedDates: dates,
      status: HabitStatus.paused,
      pausedFromDate: _pauseDate,
    );

    final resumed = paused.asActive();

    expect(resumed.status, HabitStatus.active);
    expect(resumed.completedDates, dates);
    expect(resumed.pausedFromDate, isNull);
  });

  // ── Test 6: archive preserves completion history ───────────────────────────
  test('archiving a habit preserves all completion history', () {
    const dates = {'2026-06-20', '2026-06-21', '2026-06-22'};
    final active = _makeHabit(completedDates: dates);

    final archived = active.asArchived(_pauseDate);

    expect(archived.status, HabitStatus.archived);
    expect(archived.completedDates, dates);
  });

  // ── Test 7: restore preserves completion history ───────────────────────────
  test('restoring an archived habit preserves all completion history', () {
    const dates = {'2026-06-10', '2026-06-11', '2026-06-12'};
    final archived = _makeHabit(
      completedDates: dates,
      status: HabitStatus.archived,
      pausedFromDate: _pauseDate,
    );

    final restored = archived.asActive();

    expect(restored.status, HabitStatus.active);
    expect(restored.completedDates, dates);
    expect(restored.pausedFromDate, isNull);
  });

  // ── Test 10: paused habits do not count in weekly completion rate ──────────
  // Progress screen filters to active habits before calling weeklyCompletionRate.
  test('active-only list excludes paused habit from weeklyCompletionRate', () {
    // Active habit: completed 3 of 7 days this week.
    final active = _makeHabit(
      id: 'active',
      completedDates: const {'2026-06-21', '2026-06-22', '2026-06-23'},
    );
    final paused = _makeHabit(
      id: 'paused',
      completedDates: const {},
      status: HabitStatus.paused,
      pausedFromDate: '2026-06-22',
    );

    final rateAll = weeklyCompletionRate([active, paused], _today);
    final rateActiveOnly = weeklyCompletionRate([active], _today);

    // Including the paused habit increases the denominator → lower rate.
    expect(rateAll, lessThan(rateActiveOnly));
  });

  // ── Test 11: archived habits do not count in weekly completion rate ─────────
  test(
    'active-only list excludes archived habit from weeklyCompletionRate',
    () {
      final active = _makeHabit(
        id: 'active',
        completedDates: const {'2026-06-21', '2026-06-22', '2026-06-23'},
      );
      final archived = _makeHabit(
        id: 'archived',
        completedDates: const {},
        status: HabitStatus.archived,
        pausedFromDate: _pauseDate,
      );

      final rateActiveOnly = weeklyCompletionRate([active], _today);
      final rateWithArchived = weeklyCompletionRate([active, archived], _today);

      // Active-only rate is higher because archived adds missed scheduled days.
      expect(rateActiveOnly, greaterThan(rateWithArchived));
    },
  );

  // ── Test 12: paused habits do not break streaks ────────────────────────────
  test('paused habit streak stops at pausedFromDate not at actual today', () {
    // Completed Mon-Wed; paused from Thu onwards; today is Sat.
    final paused = _makeHabit(
      completedDates: const {'2026-06-22', '2026-06-23', '2026-06-24'},
      status: HabitStatus.paused,
      pausedFromDate: _pauseDate, // Thu 25
    );

    // Effective reference = Wed 24 (one day before pause).
    // Mon-Wed all completed → streak = 3.
    final streak = habitCurrentStreak(paused, _today);

    expect(streak, 3);
  });

  test('paused habit with gap before pause has correct streak', () {
    // Completed only Mon; paused from Tue.
    final paused = _makeHabit(
      completedDates: const {'2026-06-22'},
      status: HabitStatus.paused,
      pausedFromDate: '2026-06-23', // Tue
    );

    // Effective today = Mon 22. Mon completed → streak 1.
    final streak = habitCurrentStreak(paused, _today);

    expect(streak, 1);
  });

  // ── Test 13: archived habits do not break streaks ──────────────────────────
  test('archived habit streak uses last active day as reference', () {
    // Completed Mon-Wed; archived from Thu (boundary preserved via pausedFromDate).
    final archived = _makeHabit(
      completedDates: const {'2026-06-22', '2026-06-23', '2026-06-24'},
      status: HabitStatus.archived,
      pausedFromDate: _pauseDate, // Thu 25
    );

    // Effective today = Wed 24. All 3 days complete → streak = 3.
    final streak = habitCurrentStreak(archived, _today);

    expect(streak, 3);
  });
}
