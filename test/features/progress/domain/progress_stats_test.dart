import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_habit_coach/features/home/domain/habit.dart';
import 'package:smart_habit_coach/features/progress/domain/progress_stats.dart';

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

  group('weeklyCompletionRate', () {
    test('returns 0 when there are no habits', () {
      expect(weeklyCompletionRate([], reference), 0);
    });

    test('computes completed habit-days over the last 7 days', () {
      final habits = [
        _habit('1', {'2026-06-17', '2026-06-18', '2026-06-19'}),
      ];

      expect(weeklyCompletionRate(habits, reference), closeTo(3 / 7, 0.0001));
    });
  });

  group('currentStreak', () {
    test('returns 0 when there are no habits', () {
      expect(currentStreak([], reference), 0);
    });

    test('counts consecutive completed days ending today', () {
      final habits = [
        _habit('1', {'2026-06-17', '2026-06-18', '2026-06-19'}),
      ];

      expect(currentStreak(habits, reference), 3);
    });

    test('stops at the first day that is not fully completed', () {
      final habits = [
        _habit('1', {'2026-06-19', '2026-06-17'}),
      ];

      expect(currentStreak(habits, reference), 1);
    });

    test('requires every habit to be completed on a day to count it', () {
      final habits = [
        _habit('1', {'2026-06-19'}),
        _habit('2', {}),
      ];

      expect(currentStreak(habits, reference), 0);
    });
  });

  group('bestStreak', () {
    test('returns 0 when there are no completed dates', () {
      expect(bestStreak([_habit('1', {})], reference), 0);
    });

    test('finds the longest run of fully completed days', () {
      final habits = [
        _habit('1', {
          '2026-06-10',
          '2026-06-11',
          '2026-06-12',
          '2026-06-17',
          '2026-06-18',
          '2026-06-19',
        }),
      ];

      expect(bestStreak(habits, reference), 3);
    });
  });
}
