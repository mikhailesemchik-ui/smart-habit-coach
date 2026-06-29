import 'package:flutter_test/flutter_test.dart';
import 'package:smart_habit_coach/features/ai_habit_setup/domain/habit_suggestion_response.dart';

// ── Test 23: AI minimum version parsing ──────────────────────────────────────

Map<String, dynamic> _validBase({String? minimumVersion}) => {
  'title': 'Morning yoga',
  'reason': 'Improves flexibility.',
  'scheduledTime': '07:00',
  'iconId': 'fitness',
  'minimumVersion': ?minimumVersion,
};

void main() {
  test('minimumVersion is parsed when present in AI response', () {
    final suggestion = parseHabitSuggestionResponse(
      _validBase(minimumVersion: '5 minutes of stretching'),
    );

    expect(suggestion.minimumVersion, '5 minutes of stretching');
    expect(suggestion.minimumVersion, isNotNull);
  });

  test('minimumVersion is null when absent from AI response', () {
    final suggestion = parseHabitSuggestionResponse(_validBase());

    expect(suggestion.minimumVersion, isNull);
  });

  test('minimumVersion trims surrounding whitespace', () {
    final suggestion = parseHabitSuggestionResponse(
      _validBase(minimumVersion: '  5 minutes  '),
    );

    expect(suggestion.minimumVersion, '5 minutes');
  });

  test('empty string minimumVersion is treated as null', () {
    final raw = _validBase()..['minimumVersion'] = '';
    final suggestion = parseHabitSuggestionResponse(raw);

    expect(suggestion.minimumVersion, isNull);
  });

  test('non-string minimumVersion is ignored and treated as null', () {
    final raw = _validBase()..['minimumVersion'] = 42;
    final suggestion = parseHabitSuggestionResponse(raw);

    expect(suggestion.minimumVersion, isNull);
  });

  test('minimumVersion is forwarded to Habit via toHabit()', () {
    final suggestion = parseHabitSuggestionResponse(
      _validBase(minimumVersion: 'Light walk'),
    );

    expect(suggestion.isResolved, isTrue);
    final habit = suggestion.toHabit();
    expect(habit.minimumVersion, 'Light walk');
    expect(habit.hasMinimumVersion, isTrue);
  });

  test(
    'toHabit() with null minimumVersion produces habit without minimum version',
    () {
      final suggestion = parseHabitSuggestionResponse(_validBase());

      final habit = suggestion.toHabit();
      expect(habit.minimumVersion, isNull);
      expect(habit.hasMinimumVersion, isFalse);
    },
  );
}
