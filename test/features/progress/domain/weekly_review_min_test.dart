import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_habit_coach/features/home/domain/habit.dart';
import 'package:smart_habit_coach/features/progress/domain/weekly_review.dart';

// Reference: Friday 2026-06-19.
// The 7-day window covers Mon 06-13 → Fri 06-19.
final _reference = DateTime(2026, 6, 19);

Habit _habit({
  String id = '1',
  Set<String> completedDates = const {},
  Set<String> minimumCompletedDates = const {},
  String? minimumVersion,
}) => Habit(
  id: id,
  title: 'Habit $id',
  scheduledTime: '08:00 AM',
  icon: Icons.local_drink_outlined,
  weekdays: const [1, 2, 3, 4, 5, 6, 7],
  completedDates: completedDates,
  minimumCompletedDates: minimumCompletedDates,
  minimumVersion: minimumVersion,
);

// ── Test 21: Weekly Review receives full/minimum/missed counts ────────────────

void main() {
  test(
    'minimumCompletedCount is 0 when no habits have minimum completions',
    () {
      final habits = [
        _habit(completedDates: {'2026-06-13', '2026-06-14'}),
      ];
      final metrics = calculateWeeklyReviewMetrics(habits, _reference);

      expect(metrics.minimumCompletedCount, 0);
      expect(metrics.completedCount, 2);
    },
  );

  test('minimumCompletedCount counts scheduled minimum-only days', () {
    final habits = [
      _habit(
        minimumVersion: 'Light jog',
        completedDates: {'2026-06-13'}, // full
        minimumCompletedDates: {'2026-06-14', '2026-06-15'}, // minimum × 2
      ),
    ];
    final metrics = calculateWeeklyReviewMetrics(habits, _reference);

    expect(metrics.completedCount, 1); // full only
    expect(metrics.minimumCompletedCount, 2);
  });

  test('minimumCompletedCount excludes dates outside the 7-day window', () {
    final habits = [
      _habit(
        minimumVersion: 'Light jog',
        // 06-12 is Sunday before the window; 06-13 is Monday inside.
        minimumCompletedDates: {'2026-06-12', '2026-06-13'},
      ),
    ];
    final metrics = calculateWeeklyReviewMetrics(habits, _reference);

    expect(metrics.minimumCompletedCount, 1); // only 06-13 is in window
  });

  test('minimumCompletedCount counts across multiple habits', () {
    final habits = [
      _habit(
        id: '1',
        minimumVersion: 'Short',
        minimumCompletedDates: {'2026-06-13'},
      ),
      _habit(
        id: '2',
        minimumVersion: 'Quick',
        minimumCompletedDates: {'2026-06-13'},
      ),
    ];
    final metrics = calculateWeeklyReviewMetrics(habits, _reference);

    expect(metrics.minimumCompletedCount, 2);
  });

  test('totalPossibleCount is unchanged by minimum completions', () {
    // 2 habits every day for 7 days = 14 total possible.
    final habits = [
      _habit(
        id: '1',
        minimumVersion: 'Light',
        minimumCompletedDates: {'2026-06-13', '2026-06-14'},
      ),
      _habit(id: '2'),
    ];
    final metrics = calculateWeeklyReviewMetrics(habits, _reference);

    expect(metrics.totalPossibleCount, 14);
    expect(metrics.minimumCompletedCount, 2);
  });

  test('empty habits returns zero for minimumCompletedCount', () {
    final metrics = calculateWeeklyReviewMetrics([], _reference);

    expect(metrics.minimumCompletedCount, 0);
    expect(metrics.completedCount, 0);
  });
}
