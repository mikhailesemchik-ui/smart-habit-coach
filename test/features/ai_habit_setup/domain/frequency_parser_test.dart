import 'package:flutter_test/flutter_test.dart';
import 'package:smart_habit_coach/features/ai_habit_setup/domain/frequency_parser.dart';

void main() {
  group('parseFrequencyFromGoal', () {
    // Tests 1–5: explicit frequency expressions.
    test('once a week → 1', () {
      expect(parseFrequencyFromGoal('I want to go for a run once a week'), 1);
    });

    test('twice a week → 2', () {
      expect(parseFrequencyFromGoal('I want to do gym twice a week'), 2);
    });

    test('2 times a week → 2', () {
      expect(parseFrequencyFromGoal('meditate 2 times a week'), 2);
    });

    test('three times per week → 3', () {
      expect(parseFrequencyFromGoal('walk three times per week'), 3);
    });

    test('3x weekly → 3', () {
      expect(parseFrequencyFromGoal('workout 3x weekly'), 3);
    });

    // Test 6: boundary / normalization.
    test('7 times a week is valid', () {
      expect(parseFrequencyFromGoal('7 times a week'), 7);
    });

    test('once per week → 1', () {
      expect(parseFrequencyFromGoal('yoga once per week'), 1);
    });

    test('4 times per week → 4', () {
      expect(parseFrequencyFromGoal('swim 4 times per week'), 4);
    });

    // Test 7: invalid counts are ignored.
    test('8 times a week returns null (out of range)', () {
      expect(parseFrequencyFromGoal('8 times a week'), isNull);
    });

    test('0 times a week returns null', () {
      expect(parseFrequencyFromGoal('0 times a week'), isNull);
    });

    // No frequency → null.
    test('daily goal returns null (no frequency pattern)', () {
      expect(
        parseFrequencyFromGoal('I want to drink more water daily'),
        isNull,
      );
    });

    test('no schedule mention returns null', () {
      expect(parseFrequencyFromGoal('I want to read more books'), isNull);
    });

    test('explicit weekday mention does not trigger frequency', () {
      expect(
        parseFrequencyFromGoal('work out on Monday Wednesday Friday'),
        isNull,
      );
    });

    // Case-insensitive.
    test('case insensitive: TWICE A WEEK → 2', () {
      expect(parseFrequencyFromGoal('I want to run TWICE A WEEK'), 2);
    });
  });
}
