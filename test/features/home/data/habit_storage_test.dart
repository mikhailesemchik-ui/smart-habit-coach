import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_habit_coach/features/home/data/habit_storage.dart';
import 'package:smart_habit_coach/features/home/domain/habit.dart';

void main() {
  group('HabitStorage', () {
    test('loadHabits returns null when no data has been saved', () async {
      SharedPreferences.setMockInitialValues({});

      final result = await HabitStorage().loadHabits();

      expect(result, isNull);
    });

    test('saveHabits then loadHabits returns the same habits', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = HabitStorage();
      const habits = [
        Habit(
          id: '1',
          title: 'Drink water',
          scheduledTime: '08:00 AM',
          icon: Icons.local_drink_outlined,
        ),
        Habit(
          id: '2',
          title: 'Evening walk',
          scheduledTime: '07:00 PM',
          icon: Icons.directions_walk_outlined,
          completedDates: {'2026-06-19'},
        ),
      ];

      await storage.saveHabits(habits);
      final loaded = await storage.loadHabits();

      expect(loaded, isNotNull);
      expect(loaded!.length, 2);
      expect(loaded[0].id, '1');
      expect(loaded[0].title, 'Drink water');
      expect(loaded[1].completedDates, {'2026-06-19'});
    });

    test('loadHabits returns null for corrupted saved data', () async {
      SharedPreferences.setMockInitialValues({'habits': 'not valid json'});

      final result = await HabitStorage().loadHabits();

      expect(result, isNull);
    });

    test('loadHabits returns null when saved data is not a list', () async {
      SharedPreferences.setMockInitialValues({'habits': '{"id": "1"}'});

      final result = await HabitStorage().loadHabits();

      expect(result, isNull);
    });
  });
}
