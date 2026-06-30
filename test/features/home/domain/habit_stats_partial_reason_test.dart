import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_habit_coach/features/home/domain/habit.dart';
import 'package:smart_habit_coach/features/home/domain/habit_stats.dart';

// today = Monday, June 30, 2026
final _today = DateTime(2026, 6, 30);

Habit _quantHabit({
  Map<String, double> progress = const {},
  Map<String, HabitPartialReason> partialReasons = const {},
  double target = 3.0,
}) {
  return Habit(
    id: '1',
    title: 'Water',
    scheduledTime: '08:00 AM',
    icon: Icons.local_drink_outlined,
    trackingType: HabitTrackingType.quantitative,
    targetValue: target,
    unit: 'L',
    weekdays: const [1, 2, 3, 4, 5, 6, 7],
    quantitativeProgress: progress,
    partialReasons: partialReasons,
  );
}

void main() {
  test('habitPartialReasonCounts counts each reason correctly', () {
    final habit = _quantHabit(
      progress: {
        '2026-06-29': 1.0, // Sunday, partial
        '2026-06-28': 1.0, // Saturday, partial
        '2026-06-27': 1.0, // Friday, partial
      },
      partialReasons: {
        '2026-06-29': HabitPartialReason.noTime,
        '2026-06-28': HabitPartialReason.noTime,
        '2026-06-27': HabitPartialReason.tooTired,
      },
    );

    final counts = habitPartialReasonCounts(habit, _today);

    expect(counts[HabitPartialReason.noTime], 2);
    expect(counts[HabitPartialReason.tooTired], 1);
    expect(counts[HabitPartialReason.targetTooDifficult], 0);
  });

  test('habitMostCommonPartialReason returns the most frequent reason', () {
    final habit = _quantHabit(
      progress: {'2026-06-29': 1.0, '2026-06-28': 1.0, '2026-06-27': 1.0},
      partialReasons: {
        '2026-06-29': HabitPartialReason.tooTired,
        '2026-06-28': HabitPartialReason.tooTired,
        '2026-06-27': HabitPartialReason.noTime,
      },
    );

    final most = habitMostCommonPartialReason(habit, _today);

    expect(most?.key, HabitPartialReason.tooTired);
    expect(most?.value, 2);
  });

  test('habitMostCommonPartialReason returns null when no partial reasons', () {
    final habit = _quantHabit(progress: {'2026-06-29': 1.0});
    expect(habitMostCommonPartialReason(habit, _today), isNull);
  });

  test('habitPartialWithoutReasonCount counts partial days without reason', () {
    final habit = _quantHabit(
      progress: {
        '2026-06-29': 1.0, // partial, has reason
        '2026-06-28': 1.0, // partial, no reason
        '2026-06-27': 3.0, // full (= target), not partial
      },
      partialReasons: {'2026-06-29': HabitPartialReason.noTime},
    );

    final count = habitPartialWithoutReasonCount(habit, _today);

    expect(count, 1);
  });
}
