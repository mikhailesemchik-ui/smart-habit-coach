import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_habit_coach/features/ai_habit_setup/domain/habit_suggestion.dart';
import 'package:smart_habit_coach/features/ai_habit_setup/domain/habit_suggestion_response.dart';
import 'package:smart_habit_coach/features/home/data/habit_storage.dart';

Map<String, Object> _base({List<Object>? weekdays}) {
  final map = <String, Object>{
    'title': 'Test habit',
    'reason': 'For testing.',
    'scheduledTime': '08:00',
    'iconId': 'water',
  };
  if (weekdays != null) map['weekdays'] = weekdays;
  return map;
}

void main() {
  // Test 1: explicit weekdays parse to correct ISO values.
  test('explicit weekdays parse to correct ISO values', () {
    final s = parseHabitSuggestionResponse(_base(weekdays: [1, 3, 5]));
    expect(s.weekdays, [1, 3, 5]);
  });

  // Test 2: weekday list maps to Monday–Friday.
  test('[1,2,3,4,5] maps to Monday–Friday', () {
    final s = parseHabitSuggestionResponse(_base(weekdays: [1, 2, 3, 4, 5]));
    expect(s.weekdays, [1, 2, 3, 4, 5]);
  });

  // Test 3: weekend list maps to Saturday–Sunday.
  test('[6,7] maps to Saturday–Sunday', () {
    final s = parseHabitSuggestionResponse(_base(weekdays: [6, 7]));
    expect(s.weekdays, [6, 7]);
  });

  // Test 4: all-seven list maps to every day.
  test('[1..7] maps to every day', () {
    final s = parseHabitSuggestionResponse(
      _base(weekdays: [1, 2, 3, 4, 5, 6, 7]),
    );
    expect(s.weekdays, [1, 2, 3, 4, 5, 6, 7]);
  });

  // Test 5 & 11: missing weekdays defaults to every day (backward compat).
  test('missing weekdays field defaults to every day', () {
    final s = parseHabitSuggestionResponse(_base());
    expect(s.weekdays, [1, 2, 3, 4, 5, 6, 7]);
  });

  test('old AI responses without weekdays field remain compatible', () {
    final s = parseHabitSuggestionResponse({
      'title': 'Read',
      'reason': 'Books are good.',
      'scheduledTime': '20:00',
      'iconId': 'book',
    });
    expect(s.weekdays, [1, 2, 3, 4, 5, 6, 7]);
  });

  // Test 6: malformed values normalize safely.
  test('out-of-range values are discarded', () {
    final s = parseHabitSuggestionResponse(_base(weekdays: [1, 99, 3, -1]));
    expect(s.weekdays, [1, 3]);
  });

  test('entirely invalid values fall back to every day', () {
    final s = parseHabitSuggestionResponse(_base(weekdays: [99, -1, 0]));
    expect(s.weekdays, [1, 2, 3, 4, 5, 6, 7]);
  });

  test('non-integer values in the list are discarded', () {
    final s = parseHabitSuggestionResponse(_base(weekdays: [1, 'x', 3]));
    expect(s.weekdays, [1, 3]);
  });

  // Test 7: duplicates are removed and result is sorted.
  test('duplicate values are removed and the list is sorted', () {
    final s = parseHabitSuggestionResponse(_base(weekdays: [3, 1, 3, 5, 1]));
    expect(s.weekdays, [1, 3, 5]);
  });

  // Test 8: HabitSuggestion.toHabit() preserves AI schedule.
  test('HabitSuggestion.toHabit() preserves weekdays', () {
    const suggestion = HabitSuggestion(
      title: 'Gym',
      reason: 'Strength.',
      scheduledTime: '07:00 AM',
      icon: Icons.fitness_center_outlined,
      weekdays: [1, 3, 5],
    );
    final habit = suggestion.toHabit();
    expect(habit.weekdays, [1, 3, 5]);
  });

  test(
    'HabitSuggestion.toHabit() defaults to every day when not specified',
    () {
      const suggestion = HabitSuggestion(
        title: 'Walk',
        reason: 'Move.',
        scheduledTime: '08:00 AM',
        icon: Icons.directions_walk_outlined,
      );
      final habit = suggestion.toHabit();
      expect(habit.weekdays, [1, 2, 3, 4, 5, 6, 7]);
    },
  );

  // Test 9: AI-created habit persists schedule after storage reload.
  test(
    'AI-created habit weekdays survive a storage save/reload cycle',
    () async {
      SharedPreferences.setMockInitialValues({});

      const suggestion = HabitSuggestion(
        title: 'Work out',
        reason: 'Strength training.',
        scheduledTime: '07:00 AM',
        icon: Icons.fitness_center_outlined,
        weekdays: [1, 3, 5],
      );

      final habit = suggestion.toHabit();
      final storage = HabitStorage();
      await storage.saveHabits([habit]);

      final loaded = await storage.loadHabits();
      expect(loaded, isNotNull);
      expect(loaded!.first.weekdays, [1, 3, 5]);
    },
  );

  // requiredDaysPerWeek parsing.
  test('AI requiredDaysPerWeek field is parsed and preserved', () {
    final s = parseHabitSuggestionResponse({
      'title': 'Gym',
      'reason': 'Strength.',
      'scheduledTime': '07:00',
      'iconId': 'fitness',
      'requiredDaysPerWeek': 2,
    });
    expect(s.requiredDaysPerWeek, 2);
    expect(s.weekdays, isEmpty);
    expect(s.isResolved, isFalse);
  });

  test('local goal-hint frequency fallback sets requiredDaysPerWeek', () {
    final s = parseHabitSuggestionResponse(
      _base(),
      goalHint: 'gym twice a week',
    );
    expect(s.requiredDaysPerWeek, 2);
    expect(s.isResolved, isFalse);
  });

  test('explicit weekdays with no requiredDaysPerWeek leaves it null', () {
    final s = parseHabitSuggestionResponse(_base(weekdays: [1, 3, 5]));
    expect(s.requiredDaysPerWeek, isNull);
    expect(s.isResolved, isTrue);
  });

  test('withWeekdays creates a resolved copy when count matches', () {
    const unresolved = HabitSuggestion(
      title: 'Gym',
      reason: 'Get fit.',
      scheduledTime: '07:00 AM',
      icon: Icons.fitness_center_outlined,
      weekdays: [],
      requiredDaysPerWeek: 2,
    );
    expect(unresolved.isResolved, isFalse);
    final resolved = unresolved.withWeekdays([1, 3]);
    expect(resolved.isResolved, isTrue);
    expect(resolved.weekdays, [1, 3]);
    expect(resolved.requiredDaysPerWeek, 2);
  });

  // Test 15: toHabit() asserts on unresolved suggestions.
  test('toHabit() throws AssertionError for an unresolved suggestion', () {
    const unresolved = HabitSuggestion(
      title: 'Gym',
      reason: 'Get fit.',
      scheduledTime: '07:00 AM',
      icon: Icons.fitness_center_outlined,
      weekdays: [],
      requiredDaysPerWeek: 2,
    );
    expect(() => unresolved.toHabit(), throwsA(isA<AssertionError>()));
  });

  // Test 16: resolved frequency-based habit persists weekdays in storage.
  test('resolved frequency-based habit persists selected weekdays', () async {
    SharedPreferences.setMockInitialValues({});

    const unresolved = HabitSuggestion(
      title: 'Gym',
      reason: 'Twice a week.',
      scheduledTime: '07:00 AM',
      icon: Icons.fitness_center_outlined,
      weekdays: [],
      requiredDaysPerWeek: 2,
    );
    final resolved = unresolved.withWeekdays([2, 5]);
    final habit = resolved.toHabit();
    expect(habit.weekdays, [2, 5]);

    final storage = HabitStorage();
    await storage.saveHabits([habit]);
    final loaded = await storage.loadHabits();
    expect(loaded!.first.weekdays, [2, 5]);
  });
}
