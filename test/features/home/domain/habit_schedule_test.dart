import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_habit_coach/features/home/domain/habit.dart';

void main() {
  // Test 1: old JSON without weekdays defaults to all seven days.
  test('fromJson without weekdays field defaults to every day', () {
    final json = {
      'id': '1',
      'title': 'Legacy',
      'scheduledTime': '08:00 AM',
      'iconId': 'water',
      'completedDates': <String>[],
    };

    final habit = Habit.fromJson(json);

    expect(habit.weekdays, [1, 2, 3, 4, 5, 6, 7]);
  });

  // Test 2: round-trip serialisation preserves weekdays.
  test('toJson / fromJson round-trip preserves weekdays', () {
    const habit = Habit(
      id: '42',
      title: 'Gym',
      scheduledTime: '07:00 AM',
      icon: Icons.fitness_center_outlined,
      weekdays: [1, 3, 5],
    );

    final restored = Habit.fromJson(habit.toJson());

    expect(restored.weekdays, [1, 3, 5]);
    expect(restored.completedDates, isEmpty);
  });

  // Test 3: invalid / duplicate weekdays are normalised (unique, sorted, 1–7).
  test('fromJson normalises invalid and duplicate weekdays', () {
    final json = {
      'id': '1',
      'title': 'Odd',
      'scheduledTime': '08:00 AM',
      'iconId': 'water',
      'completedDates': <String>[],
      'weekdays': [5, 3, 3, 0, 8, 1], // 0 and 8 out of range, 3 duplicated
    };

    final habit = Habit.fromJson(json);

    expect(habit.weekdays, [1, 3, 5]);
  });

  // Test 4: copyWith with weekdays preserves completedDates.
  test('copyWith with new weekdays preserves completedDates', () {
    final habit = Habit(
      id: '1',
      title: 'Walk',
      scheduledTime: '06:00 AM',
      icon: Icons.directions_walk_outlined,
      completedDates: {'2026-06-15', '2026-06-20'},
    );

    final updated = habit.copyWith(weekdays: [1, 2]);

    expect(updated.weekdays, [1, 2]);
    expect(updated.completedDates, {'2026-06-15', '2026-06-20'});
  });

  // Test 5: isScheduledFor reflects ISO weekday correctly.
  group('isScheduledFor', () {
    const habit = Habit(
      id: '1',
      title: 'Gym',
      scheduledTime: '07:00 AM',
      icon: Icons.fitness_center_outlined,
      weekdays: [1, 3, 5], // Mon, Wed, Fri
    );

    test('returns true for a scheduled weekday', () {
      // 2026-06-15 is Monday (weekday=1)
      expect(habit.isScheduledFor(DateTime(2026, 6, 15)), isTrue);
      // 2026-06-17 is Wednesday (weekday=3)
      expect(habit.isScheduledFor(DateTime(2026, 6, 17)), isTrue);
    });

    test('returns false for an unscheduled weekday', () {
      // 2026-06-16 is Tuesday (weekday=2)
      expect(habit.isScheduledFor(DateTime(2026, 6, 16)), isFalse);
      // 2026-06-21 is Sunday (weekday=7)
      expect(habit.isScheduledFor(DateTime(2026, 6, 21)), isFalse);
    });

    test('default weekdays means every day is scheduled', () {
      const everyday = Habit(
        id: '2',
        title: 'Water',
        scheduledTime: '08:00 AM',
        icon: Icons.local_drink_outlined,
      );

      for (var w = 1; w <= 7; w++) {
        // Use known weekdays: Jun 15 (Mon) = base for offsets
        final day = DateTime(2026, 6, 15).add(Duration(days: w - 1));
        expect(everyday.isScheduledFor(day), isTrue);
      }
    });
  });
}
