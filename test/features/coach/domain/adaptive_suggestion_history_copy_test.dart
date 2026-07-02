import 'package:flutter_test/flutter_test.dart';
import 'package:smart_habit_coach/features/coach/domain/adaptive_suggestion.dart';
import 'package:smart_habit_coach/features/coach/domain/adaptive_suggestion_history_copy.dart';

final _now = DateTime(2026, 7, 2);
final _end = DateTime(2026, 7, 1);
final _start = _end.subtract(const Duration(days: 29));

AdaptiveHabitSuggestion _suggestion({
  required AdaptiveSuggestionType type,
  AdaptiveSuggestionStatus status = AdaptiveSuggestionStatus.pending,
  String evidenceCode = 'x',
  Map<String, num> evidence = const {},
  double? proposedTargetValue,
}) {
  return AdaptiveHabitSuggestion(
    id: 'h1-${type.name}',
    habitId: 'h1',
    type: type,
    status: status,
    createdAt: _now,
    analysisStart: _start,
    analysisEnd: _end,
    evidenceCode: evidenceCode,
    evidence: evidence,
    proposedTargetValue: proposedTargetValue,
  );
}

void main() {
  group('type labels', () {
    test('addMinimumVersion', () {
      expect(
        adaptiveSuggestionTypeLabel(AdaptiveSuggestionType.addMinimumVersion),
        'Add a Minimum Version',
      );
    });
    test('reduceQuantitativeTarget', () {
      expect(
        adaptiveSuggestionTypeLabel(
          AdaptiveSuggestionType.reduceQuantitativeTarget,
        ),
        'Reduce the target',
      );
    });
    test('changeScheduledTime', () {
      expect(
        adaptiveSuggestionTypeLabel(AdaptiveSuggestionType.changeScheduledTime),
        'Review the scheduled time',
      );
    });
    test('reviewSchedule', () {
      expect(
        adaptiveSuggestionTypeLabel(AdaptiveSuggestionType.reviewSchedule),
        'Review the schedule',
      );
    });
    test('reduceFrequency', () {
      expect(
        adaptiveSuggestionTypeLabel(AdaptiveSuggestionType.reduceFrequency),
        'Reduce weekly frequency',
      );
    });
  });

  group('status labels', () {
    test('pending', () {
      expect(
        adaptiveSuggestionStatusLabel(AdaptiveSuggestionStatus.pending),
        'Pending',
      );
    });
    test('applied', () {
      expect(
        adaptiveSuggestionStatusLabel(AdaptiveSuggestionStatus.applied),
        'Applied',
      );
    });
    test('adjusted', () {
      expect(
        adaptiveSuggestionStatusLabel(AdaptiveSuggestionStatus.adjusted),
        'Adjusted manually',
      );
    });
    test('kept', () {
      expect(
        adaptiveSuggestionStatusLabel(AdaptiveSuggestionStatus.kept),
        'Current plan kept',
      );
    });
    test('rejected', () {
      expect(
        adaptiveSuggestionStatusLabel(AdaptiveSuggestionStatus.rejected),
        'No longer available',
      );
    });
    test('never exposes a raw enum name', () {
      for (final status in AdaptiveSuggestionStatus.values) {
        expect(adaptiveSuggestionStatusLabel(status), isNot(status.name));
      }
    });
  });

  group('evidence text', () {
    test('reduceQuantitativeTarget shows partial and reached counts', () {
      final suggestion = _suggestion(
        type: AdaptiveSuggestionType.reduceQuantitativeTarget,
        evidence: const {'partialProgressCount': 12, 'reachedCount': 3},
      );
      final text = buildAdaptiveSuggestionEvidenceText(suggestion);
      expect(text, contains('12'));
      expect(text, contains('3'));
      expect(text, isNot(contains('partialProgressCount')));
      expect(text, isNot(contains('reachedCount')));
    });

    test('changeScheduledTime never invents a time', () {
      final suggestion = _suggestion(
        type: AdaptiveSuggestionType.changeScheduledTime,
        evidence: const {'tooTiredCount': 5},
      );
      final text = buildAdaptiveSuggestionEvidenceText(suggestion);
      expect(text, contains('5'));
      expect(text, isNot(matches(RegExp(r'\d{1,2}:\d{2}'))));
    });

    test('reduceFrequency never invents an exact frequency', () {
      final suggestion = _suggestion(
        type: AdaptiveSuggestionType.reduceFrequency,
        evidence: const {'expectedOccurrences': 30, 'engagementRate': 0.2},
      );
      final text = buildAdaptiveSuggestionEvidenceText(suggestion);
      expect(text, contains('three recent weeks'));
      expect(text, isNot(contains('expectedOccurrences')));
      expect(text, isNot(RegExp(r'\d+x/week')));
    });
  });

  group('adaptiveSuggestionTargetLine', () {
    test(
      'a valid proposed target is shown historically for a resolved status',
      () {
        final suggestion = _suggestion(
          type: AdaptiveSuggestionType.reduceQuantitativeTarget,
          status: AdaptiveSuggestionStatus.applied,
          proposedTargetValue: 5.0,
        );
        expect(
          adaptiveSuggestionTargetLine(suggestion, 'L'),
          'Suggested target at the time: 5 L',
        );
      },
    );

    test('a pending suggestion uses the plain phrasing', () {
      final suggestion = _suggestion(
        type: AdaptiveSuggestionType.reduceQuantitativeTarget,
        proposedTargetValue: 5.0,
      );
      expect(
        adaptiveSuggestionTargetLine(suggestion, 'L'),
        'Suggested target: 5 L',
      );
    });

    test('a malformed proposed target is not shown', () {
      for (final value in [null, double.nan, double.infinity, 0.0, -1.0]) {
        final suggestion = _suggestion(
          type: AdaptiveSuggestionType.reduceQuantitativeTarget,
          proposedTargetValue: value,
        );
        expect(adaptiveSuggestionTargetLine(suggestion, 'L'), isNull);
      }
    });

    test('non-reduceQuantitativeTarget types never show a target line', () {
      final suggestion = _suggestion(
        type: AdaptiveSuggestionType.addMinimumVersion,
        proposedTargetValue: 5.0,
      );
      expect(adaptiveSuggestionTargetLine(suggestion, 'L'), isNull);
    });
  });
}
