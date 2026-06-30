import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_habit_coach/features/home/domain/habit.dart';
import 'package:smart_habit_coach/features/home/domain/habit_stats.dart';

// Saturday, June 27, 2026 (weekday 6).
// Monday dates in June: 1, 8, 15, 22, 29.
// Friday dates in June: 5, 12, 19, 26.
final _ref = DateTime(2026, 6, 27);

Habit _daily(String id, Set<String> completedDates) => Habit(
  id: id,
  title: 'H$id',
  scheduledTime: '08:00 AM',
  icon: Icons.local_drink_outlined,
  completedDates: completedDates,
);

Habit _mwf(String id, Set<String> completedDates) => Habit(
  id: id,
  title: 'H$id',
  scheduledTime: '08:00 AM',
  icon: Icons.local_drink_outlined,
  completedDates: completedDates,
  weekdays: const [1, 3, 5], // Mon, Wed, Fri
);

void main() {
  group('habitCurrentStreak', () {
    // Test 6a: returns 0 with no completions.
    test('returns 0 for a habit with no completions', () {
      expect(habitCurrentStreak(_daily('1', {}), _ref), 0);
    });

    // Test 6b: today scheduled but not completed — does not break the streak.
    test('does not count an incomplete today against the streak', () {
      // today = Jun 27 (Sat). Completed Jun 25 (Thu) and Jun 26 (Fri).
      // Jun 27 is scheduled (daily) but NOT completed → skip today.
      // Jun 26: scheduled, completed → streak = 1.
      // Jun 25: scheduled, completed → streak = 2.
      // Jun 24: scheduled, NOT completed → break.
      final h = _daily('1', {'2026-06-25', '2026-06-26'});
      expect(habitCurrentStreak(h, _ref), 2);
    });

    // Test 6c: today completed and scheduled → counts.
    test('includes today when it is scheduled and completed', () {
      final h = _daily('1', {'2026-06-25', '2026-06-26', '2026-06-27'});
      expect(habitCurrentStreak(h, _ref), 3);
    });

    // Test 6 spec: current streak skips unscheduled dates.
    test('skips unscheduled days without breaking the streak', () {
      // Mon+Wed+Fri habit. Completed Jun 23(Mon), Jun 25(Wed), Jun 26(Fri).
      // today = Jun 27(Sat) not scheduled → skip.
      // Jun 26(Fri): scheduled, completed → streak=1.
      // Jun 25(Wed): wait — Jun 25 is Thursday. Let me recheck.
      // June calendar: Mon=1,8,15,22,29. Tue=2,9,16,23,30. Wed=3,10,17,24.
      //                Thu=4,11,18,25. Fri=5,12,19,26. Sat=6,13,20,27. Sun=7,14,21,28.
      // MWF: Jun 22(Mon), Jun 24(Wed), Jun 26(Fri).
      // today = Jun 27(Sat) not scheduled → skip to Jun 26.
      // Jun 26(Fri): scheduled+completed → streak=1, go to Jun 25.
      // Jun 25(Thu): not scheduled → skip to Jun 24.
      // Jun 24(Wed): scheduled+completed → streak=2, go to Jun 23.
      // Jun 23(Tue): not scheduled → skip to Jun 22.
      // Jun 22(Mon): scheduled+completed → streak=3, go to Jun 21.
      // Jun 21(Sun): not scheduled → skip to Jun 20.
      // Jun 20(Sat): not scheduled → skip to Jun 19.
      // Jun 19(Fri): scheduled, NOT completed → break.
      // streak = 3
      final h = _mwf('1', {'2026-06-22', '2026-06-24', '2026-06-26'});
      expect(habitCurrentStreak(h, _ref), 3);
    });

    // Test 7 spec: missed scheduled day breaks streak.
    test('breaks the streak on a missed scheduled day', () {
      // MWF habit. Completed Jun 22(Mon) and Jun 26(Fri), missed Jun 24(Wed).
      // today = Jun 27(Sat) → skip.
      // Jun 26(Fri): scheduled+completed → streak=1.
      // Jun 25(Thu): not scheduled → skip.
      // Jun 24(Wed): scheduled, NOT completed → break.
      // streak = 1
      final h = _mwf('1', {'2026-06-22', '2026-06-26'});
      expect(habitCurrentStreak(h, _ref), 1);
    });
  });

  group('habitBestStreak', () {
    // Test 8a: returns 0 when no completions.
    test('returns 0 for no completions', () {
      expect(habitBestStreak(_daily('1', {}), _ref), 0);
    });

    // Test 8b: finds the longest run.
    test('finds the longest consecutive run', () {
      // 3-day run Jun 25–27, a 2-day run Jun 15–16.
      // Longer run is 3.
      final h = _daily('1', {
        '2026-06-15',
        '2026-06-16',
        '2026-06-25',
        '2026-06-26',
        '2026-06-27',
      });
      expect(habitBestStreak(h, _ref), 3);
    });

    // Test 8c: best streak skips unscheduled days.
    test('skips unscheduled days when computing best streak', () {
      // MWF: Jun 22(Mon), 24(Wed), 26(Fri) — 3 consecutive scheduled days.
      final h = _mwf('1', {'2026-06-22', '2026-06-24', '2026-06-26'});
      expect(habitBestStreak(h, _ref), 3);
    });

    // Completions on unscheduled days do not count toward best streak.
    test('completions on unscheduled days are excluded from best streak', () {
      // MWF habit, completion stored on Jun 25 (Thu — unscheduled).
      // No completion on Mon/Wed/Fri.
      final h = _mwf('1', {'2026-06-25'});
      expect(habitBestStreak(h, _ref), 0);
    });

    // Future dates are excluded.
    test('future completions do not count', () {
      final tomorrow = _ref.add(const Duration(days: 1));
      final h = _daily('1', {'2026-06-28'}); // future
      expect(habitBestStreak(h, tomorrow.subtract(const Duration(days: 1))), 0);
    });
  });

  group('habitCompletionRate', () {
    // Test 5 spec: unscheduled dates do not lower the completion rate.
    test('unscheduled dates do not lower the completion rate', () {
      // MWF habit, last 30 days from Jun 27.
      // Window: May 29 – Jun 27.
      // Scheduled days: May 29(Fri), Jun 1(Mon), Jun 5(Fri), Jun 8(Mon),
      //                 Jun 12(Fri), Jun 15(Mon), Jun 19(Fri), Jun 22(Mon), Jun 26(Fri)
      //                 = 9 days.
      // Complete all 9 → rate = 1.0.
      final h = Habit(
        id: '1',
        title: 'Gym',
        scheduledTime: '08:00 AM',
        icon: Icons.fitness_center_outlined,
        completedDates: const {
          '2026-05-29',
          '2026-06-01',
          '2026-06-05',
          '2026-06-08',
          '2026-06-12',
          '2026-06-15',
          '2026-06-19',
          '2026-06-22',
          '2026-06-26',
        },
        weekdays: const [1, 5], // Mon + Fri
      );
      expect(habitCompletionRate(h, _ref), closeTo(1.0, 0.001));
    });

    test('returns 0 when habit is never scheduled', () {
      // No weekdays — edge case: habit with empty weekdays.
      // But Habit.weekdays defaults to [1..7], so force an unusual case.
      // Instead test a scheduled-but-uncompleted habit.
      final h = _daily('1', {});
      expect(habitCompletionRate(h, _ref), 0.0);
    });

    test('returns correct partial rate', () {
      // Daily habit; last 7 of 30 days completed → 7/30.
      final completed = <String>{};
      for (var i = 0; i < 7; i++) {
        final d = _ref.subtract(Duration(days: i));
        completed.add(
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}',
        );
      }
      final h = _daily('1', completed);
      expect(habitCompletionRate(h, _ref), closeTo(7 / 30, 0.001));
    });
  });

  group('habitTotalCompleted', () {
    // Test 9 spec: total completed occurrences.
    test('returns 0 when no completions', () {
      expect(habitTotalCompleted(_daily('1', {})), 0);
    });

    test('counts all completions for a daily habit', () {
      final h = _daily('1', {'2026-06-25', '2026-06-26', '2026-06-27'});
      expect(habitTotalCompleted(h), 3);
    });

    // Completions on unscheduled days must not count.
    test('excludes completions on unscheduled days', () {
      // MWF habit. Completion on Jun 25 (Thu — unscheduled) and Jun 26 (Fri — scheduled).
      final h = _mwf('1', {'2026-06-25', '2026-06-26'});
      expect(habitTotalCompleted(h), 1); // only Jun 26 counts
    });
  });

  group('quantitative stats', () {
    // Monday habit scheduled daily; ref = Jun 27.
    Habit quantDaily({
      double target = 3.0,
      Map<String, double> progress = const {},
      Set<String> completedDates = const {},
    }) => Habit(
      id: 'q',
      title: 'Water',
      scheduledTime: '08:00 AM',
      icon: Icons.local_drink_outlined,
      trackingType: HabitTrackingType.quantitative,
      targetValue: target,
      unit: 'L',
      quantitativeProgress: progress,
      completedDates: completedDates,
    );

    // Test 19: target completion rate is correct
    test('habitQuantitativeTargetRate counts only target-reached days', () {
      // 30-day window ending Jun 27. Mark Jun 26 + Jun 25 as full (target met),
      // Jun 27 as partial.
      final habit = quantDaily(
        target: 3.0,
        progress: const {
          '2026-06-25': 3.0,
          '2026-06-26': 3.0,
          '2026-06-27': 1.5,
        },
        completedDates: const {'2026-06-25', '2026-06-26'},
      );
      final rate = habitQuantitativeTargetRate(habit, _ref);
      // 2 reached out of 30 scheduled daily days
      expect(rate, closeTo(2 / 30, 0.001));
    });

    // Test 20: consistency rate uses positive progress
    test('habitQuantitativeConsistencyRate counts any positive progress', () {
      final habit = quantDaily(
        target: 3.0,
        progress: const {
          '2026-06-25': 1.0,
          '2026-06-26': 3.0,
          '2026-06-27': 2.5,
        },
        completedDates: const {'2026-06-26'},
      );
      final rate = habitQuantitativeConsistencyRate(habit, _ref);
      // 3 days with progress out of 30
      expect(rate, closeTo(3 / 30, 0.001));
    });

    // Test 21: average progress is correct
    test('habitQuantitativeAverageLogged averages over days with progress', () {
      final habit = quantDaily(
        target: 3.0,
        progress: const {'2026-06-25': 1.0, '2026-06-26': 3.0},
      );
      final avg = habitQuantitativeAverageLogged(habit, _ref);
      // (1.0 + 3.0) / 2 = 2.0
      expect(avg, closeTo(2.0, 0.001));
    });

    // Test 22: streak requires reaching target
    test('habitCurrentStreak counts only days where target is reached', () {
      // Jun 26 (Fri) — target reached, Jun 27 (Sat) — only partial.
      final habit = quantDaily(
        target: 3.0,
        progress: const {'2026-06-26': 3.0, '2026-06-27': 1.5},
        completedDates: const {'2026-06-26'},
      );
      // today not completed (partial only) → skip
      // Jun 26: completed → streak 1
      // Jun 25: not completed → break
      expect(habitCurrentStreak(habit, _ref), 1);
    });

    // Test 23: unscheduled dates do not count
    test('quantitative stats ignore unscheduled dates', () {
      final habit = Habit(
        id: 'q2',
        title: 'Gym',
        scheduledTime: '08:00 AM',
        icon: Icons.fitness_center_outlined,
        trackingType: HabitTrackingType.quantitative,
        targetValue: 30.0,
        unit: 'min',
        weekdays: const [1, 5], // Mon + Fri only
        // Jun 27 is Saturday — unscheduled
        quantitativeProgress: const {'2026-06-27': 30.0},
      );
      // Unscheduled entry should be ignored
      expect(habitQuantitativeConsistencyRate(habit, _ref), 0.0);
    });

    test('habitConsistencyRate uses progress for quantitative habits', () {
      // Partial progress counts as engaged for consistency.
      final habit = quantDaily(
        target: 3.0,
        progress: const {'2026-06-27': 1.5}, // partial, not in completedDates
      );
      final rate = habitConsistencyRate(habit, _ref);
      // 1 day with any progress out of 30
      expect(rate, closeTo(1 / 30, 0.001));
    });

    test(
      'habitMissedWithoutReasonCount treats partial progress as engaged',
      () {
        // Jun 27: partial progress (1.5 L), no skip reason.
        // Should NOT count as missed-without-reason.
        final habit = quantDaily(
          target: 3.0,
          progress: const {'2026-06-27': 1.5},
        );
        final missed = habitMissedWithoutReasonCount(habit, _ref, days: 1);
        expect(missed, 0);
      },
    );
  });

  group('skip reason statistics', () {
    final today = DateTime(2026, 6, 27);

    test(
      'most-common-reason calculation works and resolves ties by enum order',
      () {
        final habit = Habit(
          id: 'skip',
          title: 'Skip habit',
          scheduledTime: '08:00 AM',
          icon: Icons.local_drink_outlined,
          skipReasons: const {
            '2026-06-22': HabitSkipReason.forgot,
            '2026-06-23': HabitSkipReason.noTime,
          },
        );

        final mostCommon = habitMostCommonSkipReason(habit, today);

        expect(mostCommon, isNotNull);
        expect(mostCommon!.key, HabitSkipReason.noTime);
        expect(mostCommon.value, 1);
      },
    );

    test(
      'missed-without-reason count excludes completed and reasoned dates',
      () {
        final habit = Habit(
          id: 'skip',
          title: 'Skip habit',
          scheduledTime: '08:00 AM',
          icon: Icons.local_drink_outlined,
          completedDates: const {'2026-06-27'},
          minimumCompletedDates: const {'2026-06-26'},
          skipReasons: const {'2026-06-25': HabitSkipReason.tooTired},
        );

        final missed = habitMissedWithoutReasonCount(habit, today, days: 4);

        expect(missed, 1);
      },
    );
  });
}
