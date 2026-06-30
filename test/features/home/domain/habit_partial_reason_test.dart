import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_habit_coach/features/home/domain/date_key.dart';
import 'package:smart_habit_coach/features/home/domain/habit.dart';

Habit _quantHabit({
  Map<String, double> progress = const {},
  Map<String, HabitPartialReason> partialReasons = const {},
  Map<String, String> partialReasonNotes = const {},
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
    partialReasonNotes: partialReasonNotes,
  );
}

void main() {
  // Monday June 30 2026
  final day = DateTime(2026, 6, 30);
  final key = dateKey(day);

  group('setPartialReason', () {
    test('records partial reason when progress is partial', () {
      final habit = _quantHabit(progress: {key: 1.5});
      final updated = habit.setPartialReason(day, HabitPartialReason.noTime);

      expect(updated.partialReasonFor(day), HabitPartialReason.noTime);
    });

    test('stores note for "other" partial reason', () {
      final habit = _quantHabit(progress: {key: 1.5});
      final updated = habit.setPartialReason(
        day,
        HabitPartialReason.other,
        note: 'unexpected meeting',
      );

      expect(updated.partialReasonFor(day), HabitPartialReason.other);
      expect(updated.partialReasonNoteFor(day), 'unexpected meeting');
    });

    test('clears partial reason when reason is null', () {
      final habit = _quantHabit(
        progress: {key: 1.5},
        partialReasons: {key: HabitPartialReason.tooTired},
      );
      final updated = habit.setPartialReason(day, null);

      expect(updated.partialReasonFor(day), isNull);
    });

    test('returns unchanged habit when not quantitative', () {
      final binary = Habit(
        id: '1',
        title: 'Read',
        scheduledTime: '09:00 AM',
        icon: Icons.book,
        weekdays: const [1, 2, 3, 4, 5, 6, 7],
      );
      final result = binary.setPartialReason(day, HabitPartialReason.noTime);
      expect(result, same(binary));
    });

    test('returns unchanged habit when progress is zero', () {
      final habit = _quantHabit(); // no progress
      final result = habit.setPartialReason(day, HabitPartialReason.noTime);
      expect(result, same(habit));
    });

    test('returns unchanged habit when progress is at or above target', () {
      final habit = _quantHabit(progress: {key: 3.0}); // = target
      final result = habit.setPartialReason(day, HabitPartialReason.noTime);
      expect(result, same(habit));
    });
  });

  group('setProgress clears partialReason', () {
    test('reaching target clears partial reason', () {
      final habit = _quantHabit(
        progress: {key: 1.5},
        partialReasons: {key: HabitPartialReason.tooTired},
      );
      final updated = habit.setProgress(day, 3.0); // at target

      expect(updated.partialReasonFor(day), isNull);
      expect(updated.completedDates, contains(key));
    });

    test('resetting progress to zero clears partial reason', () {
      final habit = _quantHabit(
        progress: {key: 1.5},
        partialReasons: {key: HabitPartialReason.noTime},
      );
      final updated = habit.setProgress(day, 0.0);

      expect(updated.partialReasonFor(day), isNull);
      expect(updated.quantitativeProgress[key], isNull);
    });

    test(
      'setting positive partial progress preserves existing partial reason',
      () {
        final habit = _quantHabit(
          progress: {key: 1.5},
          partialReasons: {key: HabitPartialReason.noTime},
        );
        // Update to still-partial value
        final updated = habit.setProgress(day, 2.0);

        expect(updated.partialReasonFor(day), HabitPartialReason.noTime);
      },
    );
  });

  group('serialization', () {
    test('toJson/fromJson round-trips partial reason and note', () {
      final habit = _quantHabit(
        progress: {key: 1.5},
        partialReasons: {key: HabitPartialReason.forgotToContinue},
        partialReasonNotes: const {},
      );

      final restored = Habit.fromJson(habit.toJson());

      expect(
        restored.partialReasonFor(day),
        HabitPartialReason.forgotToContinue,
      );
    });

    test(
      'fromJson with missing partialReasons loads empty map (backward compat)',
      () {
        final json = {
          'id': '1',
          'title': 'Water',
          'scheduledTime': '08:00 AM',
          'iconId': 'water',
          'completedDates': <String>[],
          'weekdays': [1, 2, 3, 4, 5, 6, 7],
          'trackingType': 'quantitative',
          'targetValue': 3.0,
          'unit': 'L',
          'quantitativeProgress': {key: 1.5},
          // No partialReasons key — simulates old JSON
        };

        final habit = Habit.fromJson(json);
        expect(habit.partialReasons, isEmpty);
        expect(habit.partialReasonNotes, isEmpty);
      },
    );
  });

  group('habitPartialReasonLabel', () {
    test('returns correct labels', () {
      expect(habitPartialReasonLabel(HabitPartialReason.noTime), 'No time');
      expect(habitPartialReasonLabel(HabitPartialReason.tooTired), 'Too tired');
      expect(
        habitPartialReasonLabel(HabitPartialReason.targetTooDifficult),
        'Target too difficult',
      );
      expect(
        habitPartialReasonLabel(HabitPartialReason.forgotToContinue),
        'Forgot to continue',
      );
      expect(habitPartialReasonLabel(HabitPartialReason.other), 'Other');
    });
  });
}
