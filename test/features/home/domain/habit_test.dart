import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_habit_coach/features/home/domain/date_key.dart';
import 'package:smart_habit_coach/features/home/domain/habit.dart';

void main() {
  test('toJson/fromJson round trip preserves all fields', () {
    const habit = Habit(
      id: '42',
      title: 'Drink water',
      scheduledTime: '08:00 AM',
      icon: Icons.local_drink_outlined,
      completedDates: {'2026-06-18', '2026-06-19'},
    );

    final restored = Habit.fromJson(habit.toJson());

    expect(restored.id, habit.id);
    expect(restored.title, habit.title);
    expect(restored.scheduledTime, habit.scheduledTime);
    expect(restored.icon, habit.icon);
    expect(restored.completedDates, habit.completedDates);
  });

  test('fromJson falls back to the default icon for an unknown iconId', () {
    final json = {
      'id': '1',
      'title': 'Mystery habit',
      'scheduledTime': '09:00 AM',
      'iconId': 'not_a_real_icon',
      'completedDates': <String>[],
    };

    final habit = Habit.fromJson(json);

    expect(habit.icon, Icons.local_drink_outlined);
  });

  test('toggleDate adds today completion and isCompletedToday reflects it', () {
    const habit = Habit(
      id: '1',
      title: 'Drink water',
      scheduledTime: '08:00 AM',
      icon: Icons.local_drink_outlined,
    );

    final toggledOn = habit.toggleDate(todayKey());
    expect(toggledOn.isCompletedToday, isTrue);

    final toggledOff = toggledOn.toggleDate(todayKey());
    expect(toggledOff.isCompletedToday, isFalse);
  });

  test('toggleDate off removes today only and leaves prior dates intact', () {
    const prior = '2025-01-01';
    final today = todayKey();
    final habit = Habit(
      id: '1',
      title: 'Drink water',
      scheduledTime: '08:00 AM',
      icon: Icons.local_drink_outlined,
      completedDates: {prior, today},
    );

    final toggled = habit.toggleDate(today);

    expect(toggled.isCompletedToday, isFalse);
    expect(toggled.completedDates, {prior});
  });

  group('legacy isCompleted migration', () {
    test('isCompleted=true migrates to a completedDates entry for today', () {
      final json = {
        'id': '5',
        'title': 'Legacy habit',
        'scheduledTime': '08:00 AM',
        'iconId': 'water',
        'isCompleted': true,
      };

      final habit = Habit.fromJson(json);

      expect(habit.completedDates, {todayKey()});
      expect(habit.isCompletedToday, isTrue);
    });

    test('isCompleted=false migrates to no completed dates', () {
      final json = {
        'id': '6',
        'title': 'Legacy habit',
        'scheduledTime': '08:00 AM',
        'iconId': 'water',
        'isCompleted': false,
      };

      final habit = Habit.fromJson(json);

      expect(habit.completedDates, isEmpty);
    });
  });

  group('skip reasons', () {
    final scheduledDate = DateTime(2026, 6, 22); // Monday
    const scheduledKey = '2026-06-22';

    Habit baseHabit({
      Set<String> completedDates = const {},
      Set<String> minimumCompletedDates = const {},
      Map<String, HabitSkipReason> skipReasons = const {},
      Map<String, String> skipReasonNotes = const {},
      List<int> weekdays = const [1, 2, 3, 4, 5, 6, 7],
    }) {
      return Habit(
        id: 'skip',
        title: 'Skip habit',
        scheduledTime: '08:00 AM',
        icon: Icons.local_drink_outlined,
        completedDates: completedDates,
        minimumCompletedDates: minimumCompletedDates,
        skipReasons: skipReasons,
        skipReasonNotes: skipReasonNotes,
        weekdays: weekdays,
        minimumVersion: 'Small version',
      );
    }

    test('old JSON without skip reason fields loads empty reason maps', () {
      final habit = Habit.fromJson({
        'id': '1',
        'title': 'Old habit',
        'scheduledTime': '08:00 AM',
        'iconId': 'water',
        'completedDates': <String>[],
      });

      expect(habit.skipReasons, isEmpty);
      expect(habit.skipReasonNotes, isEmpty);
    });

    test('skip reasons serialize and reload', () {
      final habit = baseHabit().setSkipReason(
        scheduledDate,
        HabitSkipReason.tooTired,
      );

      final restored = Habit.fromJson(habit.toJson());

      expect(restored.skipReasonFor(scheduledDate), HabitSkipReason.tooTired);
    });

    test('malformed skip reasons and dates are ignored', () {
      final habit = Habit.fromJson({
        'id': '1',
        'title': 'Bad habit',
        'scheduledTime': '08:00 AM',
        'iconId': 'water',
        'weekdays': [1],
        'completedDates': <String>[],
        'skipReasons': {
          'not-a-date': 'forgot',
          '2026-06-22': 'not_real',
          '2026-06-23': 'forgot',
        },
        'skipReasonNotes': {'not-a-date': 'bad'},
      });

      expect(habit.skipReasons, isEmpty);
      expect(habit.skipReasonNotes, isEmpty);
    });

    test('Other note persists', () {
      final habit = baseHabit().setSkipReason(
        scheduledDate,
        HabitSkipReason.other,
        note: '  Travel day  ',
      );
      final restored = Habit.fromJson(habit.toJson());

      expect(restored.skipReasonFor(scheduledDate), HabitSkipReason.other);
      expect(restored.skipReasonNoteFor(scheduledDate), 'Travel day');
    });

    test('non-Other reason removes obsolete note', () {
      final habit = baseHabit(
        skipReasons: const {scheduledKey: HabitSkipReason.other},
        skipReasonNotes: const {scheduledKey: 'Travel'},
      ).setSkipReason(scheduledDate, HabitSkipReason.forgot);

      expect(habit.skipReasonFor(scheduledDate), HabitSkipReason.forgot);
      expect(habit.skipReasonNoteFor(scheduledDate), isNull);
    });

    test('setting a reason removes full completion', () {
      final habit = baseHabit(
        completedDates: const {scheduledKey},
      ).setSkipReason(scheduledDate, HabitSkipReason.noTime);

      expect(habit.completedDates, isNot(contains(scheduledKey)));
      expect(habit.skipReasonFor(scheduledDate), HabitSkipReason.noTime);
    });

    test('setting a reason removes minimum completion', () {
      final habit = baseHabit(
        minimumCompletedDates: const {scheduledKey},
      ).setSkipReason(scheduledDate, HabitSkipReason.noTime);

      expect(habit.minimumCompletedDates, isNot(contains(scheduledKey)));
      expect(habit.skipReasonFor(scheduledDate), HabitSkipReason.noTime);
    });

    test('setting full clears reason and note', () {
      final habit = baseHabit(
        skipReasons: const {scheduledKey: HabitSkipReason.other},
        skipReasonNotes: const {scheduledKey: 'Travel'},
      ).setCompletionStatus(scheduledKey, HabitCompletionStatus.full);

      expect(habit.skipReasonFor(scheduledDate), isNull);
      expect(habit.skipReasonNoteFor(scheduledDate), isNull);
    });

    test('setting minimum clears reason and note', () {
      final habit = baseHabit(
        skipReasons: const {scheduledKey: HabitSkipReason.other},
        skipReasonNotes: const {scheduledKey: 'Travel'},
      ).setCompletionStatus(scheduledKey, HabitCompletionStatus.minimum);

      expect(habit.skipReasonFor(scheduledDate), isNull);
      expect(habit.skipReasonNoteFor(scheduledDate), isNull);
    });

    test('clearing a reason leaves the date incomplete', () {
      final habit = baseHabit(
        skipReasons: const {scheduledKey: HabitSkipReason.forgot},
      ).setSkipReason(scheduledDate, null);

      expect(habit.skipReasonFor(scheduledDate), isNull);
      expect(
        habit.completionStatusFor(scheduledKey),
        HabitCompletionStatus.none,
      );
    });

    test('only the selected date changes', () {
      final otherDate = DateTime(2026, 6, 23);
      final habit = baseHabit(
        skipReasons: const {'2026-06-23': HabitSkipReason.forgot},
      ).setSkipReason(scheduledDate, HabitSkipReason.noTime);

      expect(habit.skipReasonFor(scheduledDate), HabitSkipReason.noTime);
      expect(habit.skipReasonFor(otherDate), HabitSkipReason.forgot);
    });

    test('unscheduled dates ignore reasons safely', () {
      final habit = baseHabit(
        weekdays: const [2],
      ).setSkipReason(scheduledDate, HabitSkipReason.noTime);

      expect(habit.skipReasons, isEmpty);
    });
  });

  group('quantitative habits', () {
    final monday = DateTime(2026, 6, 22); // weekday 1
    const mondayKey = '2026-06-22';

    Habit quantHabit({
      double target = 3.0,
      String unit = 'L',
      Map<String, double> progress = const {},
      Set<String> completedDates = const {},
      Map<String, HabitSkipReason> skipReasons = const {},
    }) => Habit(
      id: 'q1',
      title: 'Drink water',
      scheduledTime: '08:00 AM',
      icon: Icons.local_drink_outlined,
      trackingType: HabitTrackingType.quantitative,
      targetValue: target,
      unit: unit,
      quantitativeProgress: progress,
      completedDates: completedDates,
      skipReasons: skipReasons,
    );

    // Test 1: old JSON defaults to binary
    test('old JSON without trackingType defaults to binary', () {
      final habit = Habit.fromJson({
        'id': '1',
        'title': 'Old habit',
        'scheduledTime': '08:00 AM',
        'iconId': 'water',
        'completedDates': <String>[],
      });
      expect(habit.trackingType, HabitTrackingType.binary);
      expect(habit.targetValue, isNull);
      expect(habit.unit, isNull);
      expect(habit.quantitativeProgress, isEmpty);
    });

    // Test 2: quantitative fields serialize and reload
    test('quantitative fields survive toJson/fromJson round trip', () {
      final habit = quantHabit(
        progress: const {mondayKey: 2.5},
        completedDates: const {},
      );
      final restored = Habit.fromJson(habit.toJson());

      expect(restored.trackingType, HabitTrackingType.quantitative);
      expect(restored.targetValue, 3.0);
      expect(restored.unit, 'L');
      expect(restored.quantitativeProgress[mondayKey], 2.5);
    });

    // Test 3: malformed target/unit handled safely
    test('malformed targetValue and unit fall back safely', () {
      final habit = Habit.fromJson({
        'id': '1',
        'title': 'Bad quant',
        'scheduledTime': '08:00 AM',
        'iconId': 'water',
        'completedDates': <String>[],
        'trackingType': 'quantitative',
        'targetValue': -5,
        'unit': '',
      });
      expect(habit.targetValue, isNull);
      expect(habit.unit, isNull);
    });

    // Test 4: progress values serialize and reload
    test('quantitative progress map round trips correctly', () {
      final habit = quantHabit(progress: const {mondayKey: 1.5});
      final restored = Habit.fromJson(habit.toJson());
      expect(restored.progressFor(monday), 1.5);
    });

    // Test 5: negative value normalizes to zero
    test('setProgress clamps negative values to zero', () {
      final habit = quantHabit();
      final updated = habit.setProgress(monday, -2.0);
      expect(updated.progressFor(monday), 0.0);
      expect(updated.quantitativeProgress, isEmpty);
    });

    // Test 6: value may exceed target while ratio caps at 100%
    test('progress may exceed target; ratio is clamped to 1.0', () {
      final habit = quantHabit(target: 3.0);
      final updated = habit.setProgress(monday, 5.0);
      expect(updated.progressFor(monday), 5.0);
      expect(updated.progressRatioFor(monday), 1.0);
      expect(updated.isTargetReached(monday), isTrue);
    });

    // Test 7: reaching target adds Full completion
    test('setProgress at target marks date as full completion', () {
      final habit = quantHabit(target: 3.0);
      final updated = habit.setProgress(monday, 3.0);
      expect(updated.completedDates, contains(mondayKey));
      expect(
        updated.completionStatusFor(mondayKey),
        HabitCompletionStatus.full,
      );
    });

    // Test 8: lowering below target removes Full completion
    test('setProgress below target removes full completion', () {
      final habit = quantHabit(
        target: 3.0,
        progress: const {mondayKey: 3.0},
        completedDates: const {mondayKey},
      );
      final updated = habit.setProgress(monday, 1.0);
      expect(updated.completedDates, isNot(contains(mondayKey)));
      expect(updated.progressFor(monday), 1.0);
    });

    // Test 9: positive progress clears skip reason
    test('positive setProgress removes skip reason for that date', () {
      final habit = quantHabit(
        skipReasons: const {mondayKey: HabitSkipReason.forgot},
      );
      final updated = habit.setProgress(monday, 1.0);
      expect(updated.skipReasonFor(monday), isNull);
    });

    // Test 10: setting skip reason clears numeric progress
    test('setSkipReason clears quantitative progress for that date', () {
      final habit = quantHabit(progress: const {mondayKey: 2.0});
      final updated = habit.setSkipReason(monday, HabitSkipReason.noTime);
      expect(updated.quantitativeProgress, isNot(contains(mondayKey)));
      expect(updated.skipReasonFor(monday), HabitSkipReason.noTime);
    });

    // hasPartialProgressOn
    test('hasPartialProgressOn returns true for value > 0 and < target', () {
      final habit = quantHabit(progress: const {mondayKey: 1.5});
      expect(habit.hasPartialProgressOn(mondayKey), isTrue);
    });

    test('hasPartialProgressOn returns false at target', () {
      final habit = quantHabit(
        progress: const {mondayKey: 3.0},
        completedDates: const {mondayKey},
      );
      expect(habit.hasPartialProgressOn(mondayKey), isFalse);
    });

    // completionStatusFor for quantitative never returns minimum
    test(
      'completionStatusFor never returns minimum for quantitative habit',
      () {
        final habit = quantHabit(
          progress: const {mondayKey: 1.5},
        ).copyWith(minimumCompletedDates: const {mondayKey});
        expect(
          habit.completionStatusFor(mondayKey),
          HabitCompletionStatus.none,
        );
      },
    );
  });
}
