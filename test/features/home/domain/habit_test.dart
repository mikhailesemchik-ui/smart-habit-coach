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
}
