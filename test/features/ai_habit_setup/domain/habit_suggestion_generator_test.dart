import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_habit_coach/features/ai_habit_setup/domain/habit_suggestion_generator.dart';

void main() {
  group('generateHabitSuggestion matches supported goal types', () {
    test('matches water/hydration goals', () {
      final suggestion = generateHabitSuggestion('I want to drink more water');

      expect(suggestion.title, 'Drink more water');
      expect(suggestion.icon, Icons.local_drink_outlined);
    });

    test('matches reading goals', () {
      final suggestion = generateHabitSuggestion('I want to read more books');

      expect(suggestion.title, 'Read for 20 minutes');
      expect(suggestion.icon, Icons.menu_book_outlined);
    });

    test('matches walking/exercise goals', () {
      final suggestion = generateHabitSuggestion('I want to exercise more');

      expect(suggestion.title, 'Go for a 20-minute walk');
      expect(suggestion.icon, Icons.directions_walk_outlined);
    });

    test('matches sleep goals', () {
      final suggestion = generateHabitSuggestion('I want to sleep better');

      expect(suggestion.title, 'Keep a consistent sleep schedule');
      expect(suggestion.icon, Icons.bedtime_outlined);
    });

    test('matching is case-insensitive', () {
      final suggestion = generateHabitSuggestion('DRINK MORE WATER');

      expect(suggestion.title, 'Drink more water');
    });
  });

  group('fallback behavior', () {
    test('returns a generic suggestion for unrecognized goals', () {
      final suggestion = generateHabitSuggestion('I want to learn the violin');

      expect(suggestion.title, 'Build a new habit');
      expect(suggestion.icon, Icons.self_improvement_outlined);
    });

    test('returns the generic suggestion for empty input', () {
      final suggestion = generateHabitSuggestion('');

      expect(suggestion.title, 'Build a new habit');
    });
  });
}
