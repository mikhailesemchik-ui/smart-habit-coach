import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_habit_coach/features/home/domain/habit.dart';
import 'package:smart_habit_coach/features/progress/domain/weekly_review.dart';

Habit _habit(String id, Set<String> completedDates) {
  return Habit(
    id: id,
    title: 'Habit $id',
    scheduledTime: '08:00 AM',
    icon: Icons.local_drink_outlined,
    completedDates: completedDates,
  );
}

void main() {
  // Friday, June 19, 2026.
  final reference = DateTime(2026, 6, 19);

  test('returns zeroed metrics with no habits', () {
    final metrics = calculateWeeklyReviewMetrics([], reference);

    expect(metrics.completionRate, 0);
    expect(metrics.currentStreak, 0);
    expect(metrics.bestStreak, 0);
    expect(metrics.strongestDay, isNull);
    expect(metrics.weakestDay, isNull);
    expect(metrics.completedCount, 0);
    expect(metrics.totalPossibleCount, 0);
  });

  test('returns null days and zero completedCount with no completions', () {
    final habits = [_habit('1', {})];

    final metrics = calculateWeeklyReviewMetrics(habits, reference);

    expect(metrics.strongestDay, isNull);
    expect(metrics.weakestDay, isNull);
    expect(metrics.completedCount, 0);
    expect(metrics.totalPossibleCount, 7);
  });

  test(
    'computes completedCount, totalPossibleCount, and days consistently',
    () {
      final habits = [
        _habit('1', {'2026-06-17'}),
        _habit('2', {'2026-06-17'}),
      ];

      final metrics = calculateWeeklyReviewMetrics(habits, reference);

      expect(metrics.completedCount, 2);
      expect(metrics.totalPossibleCount, 14);
      expect(metrics.strongestDay, 'Wednesday');
      expect(metrics.weakestDay, isNotNull);
      expect(metrics.completionRate, closeTo(2 / 14, 0.0001));
    },
  );

  test('matches generateWeeklyReview day calculations', () {
    final habits = [
      _habit('1', {'2026-06-17'}),
      _habit('2', {'2026-06-17'}),
    ];

    final metrics = calculateWeeklyReviewMetrics(habits, reference);
    final review = generateWeeklyReview(habits, reference);

    expect(metrics.strongestDay, review.strongestDay);
    expect(metrics.weakestDay, review.weakestDay);
  });

  test('Weekly Review receives exact skip reason counts', () {
    final habits = [
      Habit(
        id: '1',
        title: 'Habit 1',
        scheduledTime: '08:00 AM',
        icon: Icons.local_drink_outlined,
        skipReasons: const {
          '2026-06-19': HabitSkipReason.tooTired,
          '2026-06-18': HabitSkipReason.noTime,
        },
      ),
      Habit(
        id: '2',
        title: 'Habit 2',
        scheduledTime: '08:00 AM',
        icon: Icons.local_drink_outlined,
        skipReasons: const {'2026-06-19': HabitSkipReason.other},
      ),
    ];

    final metrics = calculateWeeklyReviewMetrics(habits, reference);

    expect(metrics.skipReasonCounts[HabitSkipReason.noTime], 1);
    expect(metrics.skipReasonCounts[HabitSkipReason.forgot], 0);
    expect(metrics.skipReasonCounts[HabitSkipReason.tooTired], 1);
    expect(metrics.skipReasonCounts[HabitSkipReason.tooDifficult], 0);
    expect(metrics.skipReasonCounts[HabitSkipReason.other], 1);
  });

  // Test 25: Weekly Review receives exact quantitative summaries
  test('quantitative habit summaries are accurate', () {
    // reference = Jun 19 (Fri). Last 7 days: Jun 13–19.
    // Daily quantitative habit, target = 3 L.
    // Jun 15 (Mon) → 3.0 (reached), Jun 17 (Wed) → 1.5 (partial), rest 0.
    final habits = [
      Habit(
        id: 'w',
        title: 'Water',
        scheduledTime: '08:00 AM',
        icon: Icons.local_drink_outlined,
        trackingType: HabitTrackingType.quantitative,
        targetValue: 3.0,
        unit: 'L',
        quantitativeProgress: const {'2026-06-15': 3.0, '2026-06-17': 1.5},
        completedDates: const {'2026-06-15'},
      ),
    ];

    final metrics = calculateWeeklyReviewMetrics(habits, reference);

    expect(metrics.quantitativeHabits, hasLength(1));
    final summary = metrics.quantitativeHabits.first;
    expect(summary.title, 'Water');
    expect(summary.unit, 'L');
    expect(summary.target, 3.0);
    expect(summary.scheduledOccurrences, 7);
    expect(summary.targetReached, 1);
    expect(summary.partialOccurrences, 1);
    expect(summary.totalLogged, closeTo(4.5, 0.001));
    // averageLogged = 4.5 / 2 days with progress = 2.25
    expect(summary.averageLogged, closeTo(2.25, 0.001));
  });

  test('quantitative partial progress is NOT counted as missedWithoutReason', () {
    // Jun 19: partial progress (1.5 L) → not missed without reason.
    final habits = [
      Habit(
        id: 'w',
        title: 'Water',
        scheduledTime: '08:00 AM',
        icon: Icons.local_drink_outlined,
        trackingType: HabitTrackingType.quantitative,
        targetValue: 3.0,
        unit: 'L',
        quantitativeProgress: const {'2026-06-19': 1.5},
      ),
    ];
    final metrics = calculateWeeklyReviewMetrics(habits, reference);
    // Jun 19 has progress → not "missed without reason". 6 other days have nothing.
    expect(metrics.missedWithoutReason, 6);
  });

  test('Weekly Review missedWithoutReason count is exact', () {
    final habits = [
      Habit(
        id: '1',
        title: 'Habit 1',
        scheduledTime: '08:00 AM',
        icon: Icons.local_drink_outlined,
        completedDates: const {'2026-06-19'},
        minimumCompletedDates: const {'2026-06-18'},
        skipReasons: const {'2026-06-17': HabitSkipReason.forgot},
      ),
    ];

    final metrics = calculateWeeklyReviewMetrics(habits, reference);

    expect(metrics.totalPossibleCount, 7);
    expect(metrics.missedWithoutReason, 4);
  });

  // Test: Weekly Review receives separate skip and partial reason counts
  test(
    'calculates partialReasonCounts and partialWithoutReason for the week',
    () {
      final habits = [
        Habit(
          id: '1',
          title: 'Water',
          scheduledTime: '08:00 AM',
          icon: Icons.local_drink_outlined,
          weekdays: const [1, 2, 3, 4, 5, 6, 7],
          trackingType: HabitTrackingType.quantitative,
          targetValue: 3.0,
          unit: 'L',
          quantitativeProgress: const {
            '2026-06-19': 1.5, // Friday, partial, has reason
            '2026-06-18': 1.0, // Thursday, partial, no reason
            '2026-06-17': 1.0, // Wednesday, partial, has reason
          },
          partialReasons: const {
            '2026-06-19': HabitPartialReason.noTime,
            '2026-06-17': HabitPartialReason.tooTired,
          },
        ),
      ];

      final metrics = calculateWeeklyReviewMetrics(habits, reference);

      expect(metrics.partialReasonCounts[HabitPartialReason.noTime], 1);
      expect(metrics.partialReasonCounts[HabitPartialReason.tooTired], 1);
      expect(metrics.partialWithoutReason, 1);
    },
  );

  test('empty habits gives zero partialReasonCounts', () {
    final metrics = calculateWeeklyReviewMetrics([], reference);
    for (final reason in HabitPartialReason.values) {
      expect(metrics.partialReasonCounts[reason], 0);
    }
    expect(metrics.partialWithoutReason, 0);
  });
}
