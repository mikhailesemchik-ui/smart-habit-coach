import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_habit_coach/features/home/domain/habit.dart';
import 'package:smart_habit_coach/features/progress/data/ai_weekly_review_service.dart';
import 'package:smart_habit_coach/features/progress/domain/weekly_review.dart';

void main() {
  group('isAiWeeklyReviewQuotaExceeded', () {
    test('detects HTTP 429 responses', () {
      expect(isAiWeeklyReviewQuotaExceeded(429, null), isTrue);
    });

    test('detects quota_exceeded backend error code', () {
      expect(
        isAiWeeklyReviewQuotaExceeded(500, {
          'error': {'code': 'quota_exceeded'},
        }),
        isTrue,
      );
    });

    test('ignores unrelated backend errors', () {
      expect(
        isAiWeeklyReviewQuotaExceeded(502, {
          'error': {'code': 'upstream_error'},
        }),
        isFalse,
      );
    });
  });

  group('buildAiWeeklyReviewPayload', () {
    test('excludes raw note text and sends compact per-habit summaries', () {
      final metrics = calculateWeeklyReviewMetrics([
        Habit(
          id: 'walk',
          title: 'Walk',
          scheduledTime: '08:00 AM',
          icon: Icons.directions_walk,
          trackingType: HabitTrackingType.quantitative,
          targetValue: 10000,
          unit: 'steps',
          completedDates: const {'2026-06-19'},
          quantitativeProgress: const {'2026-06-19': 10000, '2026-06-18': 5000},
          partialReasons: const {'2026-06-18': HabitPartialReason.noTime},
          completionNotes: const {'2026-06-19': 'Private note text'},
        ),
      ], DateTime(2026, 6, 19));

      final payload = buildAiWeeklyReviewPayload(metrics);
      final payloadText = payload.toString();

      expect(payloadText, isNot(contains('Private note text')));
      expect(payload, contains('habitSummaries'));
      final summaries = payload['habitSummaries']! as List<Object?>;
      expect(summaries, hasLength(1));
      final summary = summaries.single! as Map<String, Object?>;
      expect(summary['habitId'], 'walk');
      expect(summary['title'], 'Walk');
      expect(summary['trackingType'], 'quantitative');
      expect(summary['scheduledOccurrences'], 7);
      expect(summary['fullCompletions'], 1);
      expect(summary['partialOccurrences'], 1);
      expect(summary['partialReasons'], containsPair('noTime', 1));
      expect(summary.containsKey('completionNotes'), isFalse);
    });

    test('includes compact grounding signals', () {
      final metrics = calculateWeeklyReviewMetrics([
        Habit(
          id: 'walk',
          title: 'Walk',
          scheduledTime: '08:00 AM',
          icon: Icons.directions_walk,
          trackingType: HabitTrackingType.quantitative,
          targetValue: 10000,
          unit: 'steps',
          quantitativeProgress: const {'2026-06-18': 5000, '2026-06-19': 7000},
        ),
      ], DateTime(2026, 6, 19));

      final payload = buildAiWeeklyReviewPayload(metrics);

      expect(payload, contains('eligiblePatterns'));
      final patterns = payload['eligiblePatterns']! as List<Object?>;
      expect(patterns, hasLength(1));
      final pattern = patterns.single! as Map<String, Object?>;
      expect(pattern['type'], 'partialProgress');
      expect(pattern['habitId'], 'walk');
      expect(pattern['habitTitle'], 'Walk');
      expect(pattern['count'], 2);

      expect(payload, contains('focusSignals'));
      final signals = payload['focusSignals']! as Map<String, Object?>;
      expect(signals['repeatedPartialProgress'], isTrue);
      expect(signals['repeatedForgot'], isFalse);
      expect(signals['primaryHabitTitle'], 'Walk');
    });
  });
}
