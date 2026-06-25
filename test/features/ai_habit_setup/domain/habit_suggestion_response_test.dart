import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_habit_coach/features/ai_habit_setup/domain/ai_habit_setup_exception.dart';
import 'package:smart_habit_coach/features/ai_habit_setup/domain/habit_suggestion_response.dart';

void main() {
  group('parseHabitSuggestionResponse with valid input', () {
    test('parses a well-formed response and converts the time to 12-hour', () {
      final suggestion = parseHabitSuggestionResponse({
        'title': 'Read for 20 minutes',
        'reason': 'Reading daily builds knowledge.',
        'scheduledTime': '20:00',
        'iconId': 'book',
      });

      expect(suggestion.title, 'Read for 20 minutes');
      expect(suggestion.reason, 'Reading daily builds knowledge.');
      expect(suggestion.scheduledTime, '08:00 PM');
      expect(suggestion.icon, Icons.menu_book_outlined);
    });

    test('converts midnight and noon correctly', () {
      final midnight = parseHabitSuggestionResponse({
        'title': 'Sleep',
        'reason': 'Rest well.',
        'scheduledTime': '00:15',
        'iconId': 'sleep',
      });
      expect(midnight.scheduledTime, '12:15 AM');

      final noon = parseHabitSuggestionResponse({
        'title': 'Walk',
        'reason': 'Move around.',
        'scheduledTime': '12:00',
        'iconId': 'walk',
      });
      expect(noon.scheduledTime, '12:00 PM');
    });

    test('trims surrounding whitespace from text fields', () {
      final suggestion = parseHabitSuggestionResponse({
        'title': '  Drink more water  ',
        'reason': '  Stay hydrated.  ',
        'scheduledTime': '09:00',
        'iconId': 'water',
      });

      expect(suggestion.title, 'Drink more water');
      expect(suggestion.reason, 'Stay hydrated.');
    });
  });

  group('parseHabitSuggestionResponse rejects invalid input', () {
    test('rejects a non-map response', () {
      expect(
        () => parseHabitSuggestionResponse('not a map'),
        throwsA(isA<AiHabitSetupException>()),
      );
    });

    test('rejects a missing title', () {
      expect(
        () => parseHabitSuggestionResponse({
          'reason': 'Some reason.',
          'scheduledTime': '09:00',
          'iconId': 'water',
        }),
        throwsA(isA<AiHabitSetupException>()),
      );
    });

    test('rejects an empty title', () {
      expect(
        () => parseHabitSuggestionResponse({
          'title': '   ',
          'reason': 'Some reason.',
          'scheduledTime': '09:00',
          'iconId': 'water',
        }),
        throwsA(isA<AiHabitSetupException>()),
      );
    });

    test('rejects a 12-hour scheduledTime format', () {
      expect(
        () => parseHabitSuggestionResponse({
          'title': 'Drink water',
          'reason': 'Some reason.',
          'scheduledTime': '09:00 AM',
          'iconId': 'water',
        }),
        throwsA(isA<AiHabitSetupException>()),
      );
    });

    test('rejects an out-of-range scheduledTime', () {
      expect(
        () => parseHabitSuggestionResponse({
          'title': 'Drink water',
          'reason': 'Some reason.',
          'scheduledTime': '24:00',
          'iconId': 'water',
        }),
        throwsA(isA<AiHabitSetupException>()),
      );
    });

    test('rejects an unsupported iconId', () {
      expect(
        () => parseHabitSuggestionResponse({
          'title': 'Drink water',
          'reason': 'Some reason.',
          'scheduledTime': '09:00',
          'iconId': 'rocket',
        }),
        throwsA(isA<AiHabitSetupException>()),
      );
    });
  });
}
