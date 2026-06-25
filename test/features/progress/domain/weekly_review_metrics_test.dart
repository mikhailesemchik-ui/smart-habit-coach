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
}
