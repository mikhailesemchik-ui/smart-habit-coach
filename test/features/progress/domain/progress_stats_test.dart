import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_habit_coach/features/home/domain/habit.dart';
import 'package:smart_habit_coach/features/progress/domain/progress_stats.dart';

Habit _habit(String id, Set<String> completedDates, {List<int>? weekdays}) {
  return Habit(
    id: id,
    title: 'Habit $id',
    scheduledTime: '08:00 AM',
    icon: Icons.local_drink_outlined,
    completedDates: completedDates,
    weekdays: weekdays ?? const [1, 2, 3, 4, 5, 6, 7],
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

  // ── Scheduling-aware tests ────────────────────────────────────────────────

  // Test 13: weekly rate counts only scheduled occurrences.
  group('weeklyCompletionRate schedule-aware', () {
    // reference = Jun 19 (Fri, weekday=5).
    // last7Days = [Jun13(Sat,6), Jun14(Sun,7), Jun15(Mon,1),
    //              Jun16(Tue,2), Jun17(Wed,3), Jun18(Thu,4), Jun19(Fri,5)]
    test('counts only scheduled occurrences', () {
      // Habit scheduled Mon+Wed+Fri (weekdays 1,3,5) — 3 scheduled days.
      // Completed on all 3 → rate = 3/3 = 1.0
      final habits = [
        _habit(
          '1',
          {'2026-06-15', '2026-06-17', '2026-06-19'},
          weekdays: [1, 3, 5],
        ),
      ];

      expect(weeklyCompletionRate(habits, reference), closeTo(1.0, 0.0001));
    });

    // Test 14: days with no scheduled habits do not reduce the rate.
    test('unscheduled days do not count against completion rate', () {
      // Habit scheduled only on Friday (weekday=5) → 1 scheduled day in the week.
      // Completed on that Friday → rate = 1/1 = 1.0
      final habits = [
        _habit('1', {'2026-06-19'}, weekdays: [5]),
      ];

      expect(weeklyCompletionRate(habits, reference), closeTo(1.0, 0.0001));
    });

    test('returns 0 when no habits are scheduled in the window', () {
      // Habit scheduled only on Saturday (weekday=6 = Jun 13 in the window),
      // but not completed.
      final habits = [
        _habit('1', {}, weekdays: [6]),
      ];

      expect(weeklyCompletionRate(habits, reference), closeTo(0.0, 0.0001));
    });
  });

  // Test 15: unscheduled days do not break the streak.
  group('currentStreak schedule-aware', () {
    test('skips unscheduled days without breaking the streak', () {
      // Habit scheduled Mon+Wed+Fri (weekdays 1,3,5).
      // reference = Jun 19 (Fri). Completed Jun 15(Mon), 17(Wed), 19(Fri).
      // Jun 16(Tue), 18(Thu) are skipped as unscheduled.
      final habits = [
        _habit(
          '1',
          {'2026-06-15', '2026-06-17', '2026-06-19'},
          weekdays: [1, 3, 5],
        ),
      ];

      expect(currentStreak(habits, reference), 3);
    });

    // Test 16: a partially completed scheduled day breaks the streak.
    test('a missed scheduled day breaks the streak', () {
      // Scheduled Mon+Wed+Fri. Completed Jun 19(Fri) and 15(Mon), but NOT 17(Wed).
      final habits = [
        _habit('1', {'2026-06-15', '2026-06-19'}, weekdays: [1, 3, 5]),
      ];

      // Today=Jun19 succeeded. Jun18=Thu (unscheduled, skip). Jun17=Wed (scheduled, missed) → break.
      expect(currentStreak(habits, reference), 1);
    });
  });

  // calendar/daily schedule-awareness.
  group('dailyCompletionCount schedule-aware', () {
    test(
      'does not count a completed habit that is not scheduled for the day',
      () {
        // Jun 19 is Friday (weekday=5). Habit scheduled Mon only.
        final habits = [
          _habit('1', {'2026-06-19'}, weekdays: [1]),
        ];

        expect(dailyCompletionCount(habits, reference), 0);
      },
    );

    test('counts a completed habit that IS scheduled for the day', () {
      // Jun 19 is Friday (weekday=5). Habit scheduled Fri only.
      final habits = [
        _habit('1', {'2026-06-19'}, weekdays: [5]),
      ];

      expect(dailyCompletionCount(habits, reference), 1);
    });
  });
}
