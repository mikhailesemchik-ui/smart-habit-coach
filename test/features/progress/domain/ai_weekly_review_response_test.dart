import 'package:flutter_test/flutter_test.dart';
import 'package:smart_habit_coach/features/home/domain/habit.dart';
import 'package:smart_habit_coach/features/progress/domain/ai_weekly_review_exception.dart';
import 'package:smart_habit_coach/features/progress/domain/ai_weekly_review_response.dart';
import 'package:smart_habit_coach/features/progress/domain/weekly_review.dart';

const _metricsWithoutForgetting = WeeklyReviewMetrics(
  completionRate: 0,
  currentStreak: 0,
  bestStreak: 0,
  strongestDay: null,
  weakestDay: null,
  completedCount: 0,
  minimumCompletedCount: 0,
  totalPossibleCount: 7,
);

const _metricsWithForgetting = WeeklyReviewMetrics(
  completionRate: 0,
  currentStreak: 0,
  bestStreak: 0,
  strongestDay: null,
  weakestDay: null,
  completedCount: 0,
  minimumCompletedCount: 0,
  totalPossibleCount: 7,
  skipReasonCounts: {HabitSkipReason.forgot: 2},
);

const _metricsWithHabitTitles = WeeklyReviewMetrics(
  completionRate: 0.4,
  currentStreak: 0,
  bestStreak: 2,
  strongestDay: null,
  weakestDay: null,
  completedCount: 2,
  minimumCompletedCount: 0,
  totalPossibleCount: 7,
  habitSummaries: [
    WeeklyHabitSummary(
      habitId: 'steps',
      title: 'Steps',
      trackingType: HabitTrackingType.quantitative,
      scheduledOccurrences: 7,
      fullCompletions: 1,
      minimumCompletions: 0,
      partialOccurrences: 2,
      missedOccurrences: 4,
      consistencyOccurrences: 3,
      completionRate: 0.14285714285714285,
      consistencyRate: 0.42857142857142855,
      currentStreak: 0,
      bestStreak: 2,
      targetValue: 10000,
      unit: 'steps',
    ),
    WeeklyHabitSummary(
      habitId: 'reading',
      title: 'Reading',
      trackingType: HabitTrackingType.binary,
      scheduledOccurrences: 7,
      fullCompletions: 1,
      minimumCompletions: 0,
      partialOccurrences: 0,
      missedOccurrences: 6,
      consistencyOccurrences: 1,
      completionRate: 0.14285714285714285,
      consistencyRate: 0.14285714285714285,
      currentStreak: 0,
      bestStreak: 1,
    ),
  ],
);
Matcher throwsWeeklyReviewReason(String reason) {
  return throwsA(
    isA<AiWeeklyReviewException>().having((e) => e.reason, 'reason', reason),
  );
}

void main() {
  group('parseAiWeeklyReviewResponse with structured input', () {
    test('parses a well-formed four-section response', () {
      final review = parseAiWeeklyReviewResponse({
        'whatWentWell': ['You completed reading on 5 of 7 scheduled days.'],
        'partialProgress': ['You used the minimum version twice.'],
        'patterns': ['Limited time was recorded on 3 days.'],
        'focusNextWeek': 'Choose one protected 20-minute reading slot.',
      });

      expect(review.whatWentWell, [
        'You completed reading on 5 of 7 scheduled days.',
      ]);
      expect(review.partialProgress, ['You used the minimum version twice.']);
      expect(review.patterns, ['Limited time was recorded on 3 days.']);
      expect(
        review.focusNextWeek,
        'Choose one protected 20-minute reading slot.',
      );
      expect(review.summary, 'You completed reading on 5 of 7 scheduled days.');
      expect(
        review.recommendation,
        'Choose one protected 20-minute reading slot.',
      );
    });

    test('allows empty optional partial and pattern sections', () {
      final review = parseAiWeeklyReviewResponse({
        'whatWentWell': ['No full completions were recorded this week.'],
        'partialProgress': <String>[],
        'patterns': <String>[],
        'focusNextWeek': 'Choose one scheduled habit to complete once.',
      });

      expect(review.partialProgress, isEmpty);
      expect(review.patterns, isEmpty);
      expect(review.weakestInsight, isEmpty);
    });

    test('trims strings and caps oversized AI lists', () {
      final review = parseAiWeeklyReviewResponse({
        'whatWentWell': ['  One.  ', '  Two.  ', '  Three.  '],
        'partialProgress': ['  A.  ', '  B.  ', '  C.  '],
        'patterns': [
          '  Pattern one.  ',
          '  Pattern two.  ',
          '  Pattern three.  ',
        ],
        'focusNextWeek': '  Focus.  ',
      });

      expect(review.whatWentWell, ['One.', 'Two.']);
      expect(review.partialProgress, ['A.', 'B.']);
      expect(review.patterns, ['Pattern one.', 'Pattern two.']);
      expect(review.focusNextWeek, 'Focus.');
    });

    test('rejects empty AI strings', () {
      expect(
        () => parseAiWeeklyReviewResponse({
          'whatWentWell': ['Valid.'],
          'partialProgress': ['   '],
          'patterns': ['No repeated patterns.'],
          'focusNextWeek': 'Focus.',
        }),
        throwsA(isA<AiWeeklyReviewException>()),
      );
    });

    test('rejects missing required structured fields', () {
      expect(
        () => parseAiWeeklyReviewResponse({
          'whatWentWell': ['Valid.'],
          'partialProgress': ['Valid.'],
          'patterns': ['Valid.'],
        }),
        throwsA(isA<AiWeeklyReviewException>()),
      );
    });

    test('rejects partial completion wording', () {
      expect(
        () => parseAiWeeklyReviewResponse({
          'whatWentWell': ['Valid.'],
          'partialProgress': ['You had 2 partial completions.'],
          'patterns': <String>[],
          'focusNextWeek': 'Focus on one habit.',
        }),
        throwsA(isA<AiWeeklyReviewException>()),
      );
    });

    test(
      'rejects unsupported reminder advice when forgetting did not repeat',
      () {
        expect(
          () => parseAiWeeklyReviewResponse({
            'whatWentWell': ['Valid.'],
            'partialProgress': <String>[],
            'patterns': <String>[],
            'focusNextWeek': 'Set a reminder for your habit next week.',
          }, metrics: _metricsWithoutForgetting),
          throwsA(isA<AiWeeklyReviewException>()),
        );
      },
    );

    test('rejects generic all-habits focus', () {
      expect(
        () => parseAiWeeklyReviewResponse({
          'whatWentWell': ['You completed Reading once.'],
          'partialProgress': ['You made partial progress on Steps twice.'],
          'patterns': <String>[],
          'focusNextWeek':
              'Consider ways to improve completion rates for all scheduled habits.',
        }, metrics: _metricsWithHabitTitles),
        throwsA(isA<AiWeeklyReviewException>()),
      );
    });

    test('rejects improve completion rates focus', () {
      expect(
        () => parseAiWeeklyReviewResponse({
          'whatWentWell': ['You completed Reading once.'],
          'partialProgress': ['You made partial progress on Steps twice.'],
          'patterns': <String>[],
          'focusNextWeek': 'Try to improve completion rates for Steps.',
        }, metrics: _metricsWithHabitTitles),
        throwsA(isA<AiWeeklyReviewException>()),
      );
    });

    test(
      'rejects focus without a known habit title when habit data exists',
      () {
        expect(
          () => parseAiWeeklyReviewResponse({
            'whatWentWell': ['You completed Reading once.'],
            'partialProgress': ['You made partial progress on Steps twice.'],
            'patterns': <String>[],
            'focusNextWeek':
                'Try turning one partial day into a full target day.',
          }, metrics: _metricsWithHabitTitles),
          throwsA(isA<AiWeeklyReviewException>()),
        );
      },
    );

    test('rejects AI pattern containing two known habit titles', () {
      expect(
        () => parseAiWeeklyReviewResponse({
          'whatWentWell': ['You completed Reading once.'],
          'partialProgress': ['You made partial progress on Steps twice.'],
          'patterns': ['Steps and Reading both showed repeated patterns.'],
          'focusNextWeek':
              'Try turning one partial Steps day into a full target day.',
        }, metrics: _metricsWithHabitTitles),
        throwsA(isA<AiWeeklyReviewException>()),
      );
    });

    test('rejects duplicated normalized observations across sections', () {
      expect(
        () => parseAiWeeklyReviewResponse({
          'whatWentWell': ['You made partial progress on Steps twice.'],
          'partialProgress': ['  You made partial progress on Steps twice.  '],
          'patterns': <String>[],
          'focusNextWeek':
              'Try turning one partial Steps day into a full target day.',
        }, metrics: _metricsWithHabitTitles),
        throwsA(isA<AiWeeklyReviewException>()),
      );
    });

    test('allows missed-day focus when not grounded in partial progress', () {
      final review = parseAiWeeklyReviewResponse({
        'whatWentWell': ['You completed Reading once.'],
        'partialProgress': <String>[],
        'patterns': ['Steps had missed days this week.'],
        'focusNextWeek': 'Try reducing one missed day for Steps next week.',
      }, metrics: _metricsWithHabitTitles);

      expect(review.focusNextWeek, contains('missed day'));
    });

    test('allows target-reach wording in what went well', () {
      final review = parseAiWeeklyReviewResponse({
        'whatWentWell': ['You reached the Steps target on 1 scheduled day.'],
        'partialProgress': ['You made partial progress on Steps twice.'],
        'patterns': ["'Steps' had partial progress on 2 scheduled days."],
        'focusNextWeek':
            'Aim to reach the 10,000 steps target for Steps on one additional day next week.',
      }, metrics: _metricsWithHabitTitles);

      expect(review.whatWentWell.single, contains('reached'));
    });

    test('allows consistency wording in what went well', () {
      final review = parseAiWeeklyReviewResponse({
        'whatWentWell': ['You engaged with Steps on 3 of 7 scheduled days.'],
        'partialProgress': ['You made partial progress on Steps twice.'],
        'patterns': ["'Steps' had partial progress on 2 scheduled days."],
        'focusNextWeek':
            'Aim to reach the 10,000 steps target for Steps on one additional day next week.',
      }, metrics: _metricsWithHabitTitles);

      expect(review.whatWentWell.single, contains('engaged with'));
    });
    test(
      'rejects AI focus that calls repeated partial progress missed days',
      () {
        expect(
          () => parseAiWeeklyReviewResponse({
            'whatWentWell': ['You completed Reading once.'],
            'partialProgress': ['You made partial progress on Steps twice.'],
            'patterns': ["'Steps' had partial progress on 2 scheduled days."],
            'focusNextWeek':
                'Try to reduce the number of missed days for Steps next week.',
          }, metrics: _metricsWithHabitTitles),
          throwsA(isA<AiWeeklyReviewException>()),
        );
      },
    );

    test(
      'rejects AI focus that calls repeated partial progress skipped days',
      () {
        expect(
          () => parseAiWeeklyReviewResponse({
            'whatWentWell': ['You completed Reading once.'],
            'partialProgress': ['You made partial progress on Steps twice.'],
            'patterns': ["'Steps' had partial progress on 2 scheduled days."],
            'focusNextWeek': 'Try to reduce skipped days for Steps next week.',
          }, metrics: _metricsWithHabitTitles),
          throwsA(isA<AiWeeklyReviewException>()),
        );
      },
    );

    test('rejects AI focus with an invented numeric target', () {
      expect(
        () => parseAiWeeklyReviewResponse({
          'whatWentWell': ['You completed Reading once.'],
          'partialProgress': ['You made partial progress on Steps twice.'],
          'patterns': ["'Steps' had partial progress on 2 scheduled days."],
          'focusNextWeek': 'Aim for 7,000 steps for Steps next week.',
        }, metrics: _metricsWithHabitTitles),
        throwsA(isA<AiWeeklyReviewException>()),
      );
    });

    test('accepts AI focus using the existing target value', () {
      final review = parseAiWeeklyReviewResponse({
        'whatWentWell': ['You completed Reading once.'],
        'partialProgress': ['You made partial progress on Steps twice.'],
        'patterns': ["'Steps' had partial progress on 2 scheduled days."],
        'focusNextWeek':
            'Aim to reach the 10,000 steps target for Steps on one additional day next week.',
      }, metrics: _metricsWithHabitTitles);

      expect(review.focusNextWeek, contains('10,000'));
    });

    test('rejects below-target quantitative raw progress in what went well', () {
      expect(
        () => parseAiWeeklyReviewResponse({
          'whatWentWell': [
            'You made progress on Steps with 8520 steps logged.',
          ],
          'partialProgress': ['You made partial progress on Steps twice.'],
          'patterns': ["'Steps' had partial progress on 2 scheduled days."],
          'focusNextWeek':
              'Try turning one partial Steps day into a full target day next week.',
        }, metrics: _metricsWithHabitTitles),
        throwsA(isA<AiWeeklyReviewException>()),
      );
    });

    test('rejects duplicated quantitative observation across sections', () {
      expect(
        () => parseAiWeeklyReviewResponse({
          'whatWentWell': ["'Steps' had partial progress on 2 scheduled days."],
          'partialProgress': ['You made partial progress on Steps twice.'],
          'patterns': ["'Steps' had partial progress on 2 scheduled days."],
          'focusNextWeek':
              'Try turning one partial Steps day into a full target day next week.',
        }, metrics: _metricsWithHabitTitles),
        throwsA(isA<AiWeeklyReviewException>()),
      );
    });
    test('allows reminder advice when forgetting repeated', () {
      final review = parseAiWeeklyReviewResponse({
        'whatWentWell': ['Valid.'],
        'partialProgress': <String>[],
        'patterns': ['Forgetting was recorded as a reason twice.'],
        'focusNextWeek': 'Set one reminder for your habit next week.',
      }, metrics: _metricsWithForgetting);

      expect(review.focusNextWeek, contains('reminder'));
    });
  });

  group('parseAiWeeklyReviewResponse diagnostic reasons', () {
    test('reports unsupported reminder reason', () {
      expect(
        () => parseAiWeeklyReviewResponse({
          'whatWentWell': ['Valid.'],
          'partialProgress': <String>[],
          'patterns': <String>[],
          'focusNextWeek': 'Set a reminder for your habit next week.',
        }, metrics: _metricsWithoutForgetting),
        throwsWeeklyReviewReason('unsupported_reminder_advice'),
      );
    });

    test('reports invented numeric target reason', () {
      expect(
        () => parseAiWeeklyReviewResponse({
          'whatWentWell': ['You completed Reading once.'],
          'partialProgress': ['You made partial progress on Steps twice.'],
          'patterns': ["'Steps' had partial progress on 2 scheduled days."],
          'focusNextWeek': 'Aim for 7,000 steps for Steps next week.',
        }, metrics: _metricsWithHabitTitles),
        throwsWeeklyReviewReason('invented_numeric_target'),
      );
    });

    test('reports partial progress called missed reason', () {
      expect(
        () => parseAiWeeklyReviewResponse({
          'whatWentWell': ['You completed Reading once.'],
          'partialProgress': ['You made partial progress on Steps twice.'],
          'patterns': ["'Steps' had partial progress on 2 scheduled days."],
          'focusNextWeek':
              'Try to reduce the number of missed days for Steps next week.',
        }, metrics: _metricsWithHabitTitles),
        throwsWeeklyReviewReason('partial_progress_called_missed'),
      );
    });

    test('reports below-target progress in what went well reason', () {
      expect(
        () => parseAiWeeklyReviewResponse({
          'whatWentWell': [
            'You made progress on Steps with 8520 steps logged.',
          ],
          'partialProgress': ['You made partial progress on Steps twice.'],
          'patterns': ["'Steps' had partial progress on 2 scheduled days."],
          'focusNextWeek':
              'Try turning one partial Steps day into a full target day next week.',
        }, metrics: _metricsWithHabitTitles),
        throwsWeeklyReviewReason('below_target_progress_in_what_went_well'),
      );
    });

    test('reports multi-habit pattern reason', () {
      expect(
        () => parseAiWeeklyReviewResponse({
          'whatWentWell': ['You completed Reading once.'],
          'partialProgress': ['You made partial progress on Steps twice.'],
          'patterns': ['Steps and Reading both showed repeated patterns.'],
          'focusNextWeek':
              'Try turning one partial Steps day into a full target day.',
        }, metrics: _metricsWithHabitTitles),
        throwsWeeklyReviewReason('multi_habit_pattern'),
      );
    });

    test('reports generic focus reason', () {
      expect(
        () => parseAiWeeklyReviewResponse({
          'whatWentWell': ['You completed Reading once.'],
          'partialProgress': ['You made partial progress on Steps twice.'],
          'patterns': <String>[],
          'focusNextWeek':
              'Consider ways to improve completion rates for all scheduled habits.',
        }, metrics: _metricsWithHabitTitles),
        throwsWeeklyReviewReason('generic_focus'),
      );
    });
  });

  group('parseAiWeeklyReviewResponse with legacy input', () {
    test('parses the previous response shape for compatibility', () {
      final review = parseAiWeeklyReviewResponse({
        'summary': 'You completed 45% of your habits this week.',
        'strongestInsight': 'Wednesday was your most consistent day.',
        'weakestInsight': 'Sunday could use more attention.',
        'recommendation': 'Plan a lighter Sunday routine next week.',
      });

      expect(review.summary, 'You completed 45% of your habits this week.');
      expect(
        review.strongestInsight,
        'Wednesday was your most consistent day.',
      );
      expect(review.weakestInsight, 'Sunday could use more attention.');
      expect(review.recommendation, 'Plan a lighter Sunday routine next week.');
      expect(review.whatWentWell, hasLength(2));
      expect(review.partialProgress, isEmpty);
      expect(review.focusNextWeek, 'Plan a lighter Sunday routine next week.');
    });
  });

  group('parseAiWeeklyReviewResponse rejects invalid input', () {
    test('rejects a non-map response', () {
      expect(
        () => parseAiWeeklyReviewResponse('not a map'),
        throwsA(isA<AiWeeklyReviewException>()),
      );
    });

    test('rejects a non-string legacy field', () {
      expect(
        () => parseAiWeeklyReviewResponse({
          'summary': 42,
          'strongestInsight': 'Wednesday stood out.',
          'weakestInsight': 'Sunday lagged behind.',
          'recommendation': 'Keep it up.',
        }),
        throwsA(isA<AiWeeklyReviewException>()),
      );
    });
  });
}
