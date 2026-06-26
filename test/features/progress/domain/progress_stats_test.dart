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

  group('dailyCompletionCount', () {
    test('returns 0 for an empty habit list', () {
      expect(dailyCompletionCount([], reference), 0);
    });

    test('returns 0 when no habits were completed on that day', () {
      final habits = [_habit('1', {}), _habit('2', {})];
      expect(dailyCompletionCount(habits, reference), 0);
    });

    test('counts only habits completed on the exact given day', () {
      final habits = [
        _habit('1', {'2026-06-19'}),
        _habit('2', {'2026-06-18'}),
      ];
      expect(dailyCompletionCount(habits, reference), 1);
    });

    test('returns total count when all habits completed on that day', () {
      final habits = [
        _habit('1', {'2026-06-19'}),
        _habit('2', {'2026-06-19'}),
      ];
      expect(dailyCompletionCount(habits, reference), 2);
    });
  });

  group('dailyCompletionPercentage', () {
    test('returns 0 for an empty habit list', () {
      expect(dailyCompletionPercentage([], reference), 0);
    });

    test('returns 0.0 when no habits completed', () {
      expect(dailyCompletionPercentage([_habit('1', {})], reference), 0.0);
    });

    test('returns 0.5 when half of habits completed', () {
      final habits = [
        _habit('1', {'2026-06-19'}),
        _habit('2', {}),
      ];
      expect(dailyCompletionPercentage(habits, reference), 0.5);
    });

    test('returns 1.0 when all habits completed', () {
      final habits = [
        _habit('1', {'2026-06-19'}),
        _habit('2', {'2026-06-19'}),
      ];
      expect(dailyCompletionPercentage(habits, reference), 1.0);
    });
  });

  // Test 8: future dates cannot be edited (last7Days never returns future dates)
  group('last7Days', () {
    test('returns exactly 7 dates', () {
      expect(last7Days(reference), hasLength(7));
    });

    test('contains only dates on or before the reference date', () {
      final today = DateTime(reference.year, reference.month, reference.day);
      expect(last7Days(reference).every((d) => !d.isAfter(today)), isTrue);
    });

    test('last element is the reference date itself', () {
      final days = last7Days(reference);
      final today = DateTime(reference.year, reference.month, reference.day);
      expect(days.last, today);
    });

    test('first element is six days before the reference date', () {
      final days = last7Days(reference);
      final sixDaysAgo = DateTime(
        reference.year,
        reference.month,
        reference.day,
      ).subtract(const Duration(days: 6));
      expect(days.first, sixDaysAgo);
    });
  });

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
