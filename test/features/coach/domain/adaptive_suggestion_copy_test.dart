import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_habit_coach/features/coach/domain/adaptive_suggestion.dart';
import 'package:smart_habit_coach/features/coach/domain/adaptive_suggestion_copy.dart';
import 'package:smart_habit_coach/features/home/domain/habit.dart';

final _now = DateTime(2026, 7, 2);
final _end = DateTime(2026, 7, 1);
final _start = _end.subtract(const Duration(days: 29));

Habit _habit({
  String title = 'Read',
  HabitTrackingType trackingType = HabitTrackingType.binary,
  double? targetValue,
  String? unit,
}) {
  return Habit(
    id: 'h1',
    title: title,
    scheduledTime: '08:00 AM',
    icon: Icons.book,
    trackingType: trackingType,
    targetValue: targetValue,
    unit: unit,
  );
}

AdaptiveHabitSuggestion _suggestion({
  required AdaptiveSuggestionType type,
  required String evidenceCode,
  Map<String, num> evidence = const {},
  double? proposedTargetValue,
}) {
  return AdaptiveHabitSuggestion(
    id: 'h1-${type.name}-2026-07-02',
    habitId: 'h1',
    type: type,
    createdAt: _now,
    analysisStart: _start,
    analysisEnd: _end,
    evidenceCode: evidenceCode,
    evidence: evidence,
    proposedTargetValue: proposedTargetValue,
  );
}

void main() {
  group('addMinimumVersion copy', () {
    test(
      'uses too-difficult wording when evidenceCode is repeated_too_difficult',
      () {
        final habit = _habit(title: 'Read');
        final suggestion = _suggestion(
          type: AdaptiveSuggestionType.addMinimumVersion,
          evidenceCode: 'repeated_too_difficult',
          evidence: const {'tooDifficultCount': 4},
        );
        final copy = buildAdaptiveSuggestionCopy(suggestion, habit);
        expect(copy.title, contains('Read'));
        expect(copy.body, contains('too difficult'));
        expect(copy.body, contains('4'));
        expect(copy.body, isNot(contains('no time')));
      },
    );

    test('uses no-time wording when evidenceCode is repeated_no_time', () {
      final habit = _habit(title: 'Read');
      final suggestion = _suggestion(
        type: AdaptiveSuggestionType.addMinimumVersion,
        evidenceCode: 'repeated_no_time',
        evidence: const {'noTimeCount': 3},
      );
      final copy = buildAdaptiveSuggestionCopy(suggestion, habit);
      expect(copy.body, contains('no time'));
      expect(copy.body, contains('3'));
    });
  });

  group('reduceQuantitativeTarget copy', () {
    test(
      'mentions partial/reached counts and formats the proposed target with unit',
      () {
        final habit = _habit(
          title: 'Water',
          trackingType: HabitTrackingType.quantitative,
          targetValue: 10,
          unit: 'L',
        );
        final suggestion = _suggestion(
          type: AdaptiveSuggestionType.reduceQuantitativeTarget,
          evidenceCode: 'repeated_target_too_difficult_reason',
          evidence: const {'partialProgressCount': 12, 'reachedCount': 2},
          proposedTargetValue: 5.0,
        );
        final copy = buildAdaptiveSuggestionCopy(suggestion, habit);
        expect(copy.title, contains('Water'));
        expect(copy.body, contains('12'));
        expect(copy.body, contains('2'));
        expect(copy.suggestedTargetLine, 'Suggested target: 5 L');
      },
    );

    test('omits the suggested-target line when no target was proposed', () {
      final habit = _habit(
        trackingType: HabitTrackingType.quantitative,
        targetValue: 10,
      );
      final suggestion = _suggestion(
        type: AdaptiveSuggestionType.reduceQuantitativeTarget,
        evidenceCode: 'quantitative_consistency_gap',
        evidence: const {'partialProgressCount': 12, 'reachedCount': 0},
      );
      final copy = buildAdaptiveSuggestionCopy(suggestion, habit);
      expect(copy.suggestedTargetLine, isNull);
    });

    test('formats a fractional proposed target using habit progress rules', () {
      final habit = _habit(
        trackingType: HabitTrackingType.quantitative,
        targetValue: 10,
        unit: 'min',
      );
      final suggestion = _suggestion(
        type: AdaptiveSuggestionType.reduceQuantitativeTarget,
        evidenceCode: 'repeated_target_too_difficult_reason',
        evidence: const {'partialProgressCount': 10, 'reachedCount': 1},
        proposedTargetValue: 5.5,
      );
      final copy = buildAdaptiveSuggestionCopy(suggestion, habit);
      expect(copy.suggestedTargetLine, 'Suggested target: 5.5 min');
    });
  });

  group('changeScheduledTime copy', () {
    test('mentions tiredness count and never invents a time', () {
      final habit = _habit();
      final suggestion = _suggestion(
        type: AdaptiveSuggestionType.changeScheduledTime,
        evidenceCode: 'repeated_too_tired',
        evidence: const {'tooTiredCount': 5},
      );
      final copy = buildAdaptiveSuggestionCopy(suggestion, habit);
      expect(copy.body, contains('too tired'));
      expect(copy.body, contains('5'));
      // No proposed time exists on the suggestion, and copy must not
      // fabricate one (no digits formatted as a clock time like "8:00").
      expect(copy.body, isNot(matches(RegExp(r'\d{1,2}:\d{2}'))));
    });
  });

  group('reviewSchedule copy', () {
    test('mentions no-time count', () {
      final habit = _habit();
      final suggestion = _suggestion(
        type: AdaptiveSuggestionType.reviewSchedule,
        evidenceCode: 'repeated_no_time',
        evidence: const {'noTimeCount': 4},
      );
      final copy = buildAdaptiveSuggestionCopy(suggestion, habit);
      expect(copy.title, contains('schedule'));
      expect(copy.body, contains('4'));
    });
  });

  group('reduceFrequency copy', () {
    test('does not propose exact weekdays or a new frequency', () {
      final habit = _habit();
      final suggestion = _suggestion(
        type: AdaptiveSuggestionType.reduceFrequency,
        evidenceCode: 'frequency_mismatch',
        evidence: const {
          'expectedOccurrences': 30,
          'engagementRate': 0.2,
          'lowEngagementWeeks': 3,
        },
      );
      final copy = buildAdaptiveSuggestionCopy(suggestion, habit);
      expect(copy.title, contains('how often'));
      expect(copy.body, contains('three recent weeks'));
      expect(copy.body, isNot(contains('Monday')));
      expect(copy.suggestedTargetLine, isNull);
    });
  });
}
