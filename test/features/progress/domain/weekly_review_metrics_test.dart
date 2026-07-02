import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_habit_coach/features/home/domain/habit.dart';
import 'package:smart_habit_coach/features/progress/domain/weekly_review.dart';

Habit _habit({
  String id = '1',
  String title = 'Habit 1',
  Set<String> completedDates = const {},
  Set<String> minimumCompletedDates = const {},
  List<int> weekdays = const [1, 2, 3, 4, 5, 6, 7],
  HabitStatus status = HabitStatus.active,
  Map<String, HabitSkipReason> skipReasons = const {},
  Map<String, String> completionNotes = const {},
  String? minimumVersion,
  HabitTrackingType trackingType = HabitTrackingType.binary,
  double? targetValue,
  String? unit,
  Map<String, double> quantitativeProgress = const {},
  Map<String, HabitPartialReason> partialReasons = const {},
}) {
  return Habit(
    id: id,
    title: title,
    scheduledTime: '08:00 AM',
    icon: Icons.local_drink_outlined,
    completedDates: completedDates,
    minimumCompletedDates: minimumCompletedDates,
    weekdays: weekdays,
    status: status,
    skipReasons: skipReasons,
    completionNotes: completionNotes,
    minimumVersion: minimumVersion,
    trackingType: trackingType,
    targetValue: targetValue,
    unit: unit,
    quantitativeProgress: quantitativeProgress,
    partialReasons: partialReasons,
  );
}

void main() {
  // Friday, June 19, 2026. The review window is Jun 13-19.
  final reference = DateTime(2026, 6, 19);

  test('returns zeroed metrics with no habits', () {
    final metrics = calculateWeeklyReviewMetrics([], reference);

    expect(metrics.completionRate, 0);
    expect(metrics.currentStreak, 0);
    expect(metrics.bestStreak, 0);
    expect(metrics.strongestDay, isNull);
    expect(metrics.weakestDay, isNull);
    expect(metrics.completedCount, 0);
    expect(metrics.totalPossibleCount, 0);
    expect(metrics.habitSummaries, isEmpty);
  });

  test('scheduled occurrences exclude unscheduled dates', () {
    final habits = [
      _habit(
        title: 'Reading',
        weekdays: const [1, 3, 5],
        completedDates: {'2026-06-16', '2026-06-17', '2026-06-19'},
      ),
    ];

    final metrics = calculateWeeklyReviewMetrics(habits, reference);
    final summary = metrics.habitSummaries.single;

    expect(summary.scheduledOccurrences, 3);
    expect(summary.fullCompletions, 2);
    expect(metrics.totalPossibleCount, 3);
    expect(metrics.completedCount, 2);
  });

  test('paused and archived inactive habits are excluded', () {
    final habits = [
      _habit(id: 'active', completedDates: {'2026-06-19'}),
      _habit(
        id: 'paused',
        status: HabitStatus.paused,
        completedDates: {'2026-06-19'},
      ),
      _habit(
        id: 'archived',
        status: HabitStatus.archived,
        completedDates: {'2026-06-19'},
      ),
    ];

    final metrics = calculateWeeklyReviewMetrics(habits, reference);

    expect(metrics.habitSummaries, hasLength(1));
    expect(metrics.habitSummaries.single.habitId, 'active');
    expect(metrics.totalPossibleCount, 7);
    expect(metrics.completedCount, 1);
  });

  test('future dates outside the review window are excluded', () {
    final habits = [
      _habit(completedDates: {'2026-06-19', '2026-06-20'}),
    ];

    final metrics = calculateWeeklyReviewMetrics(habits, reference);
    final summary = metrics.habitSummaries.single;

    expect(summary.fullCompletions, 1);
    expect(metrics.completedCount, 1);
  });

  test('binary full, minimum, and missed counts are exact', () {
    final habits = [
      _habit(
        minimumVersion: 'Read one page',
        completedDates: {'2026-06-13', '2026-06-14'},
        minimumCompletedDates: {'2026-06-15'},
      ),
    ];

    final metrics = calculateWeeklyReviewMetrics(habits, reference);
    final summary = metrics.habitSummaries.single;

    expect(summary.fullCompletions, 2);
    expect(summary.minimumCompletions, 1);
    expect(summary.partialOccurrences, 0);
    expect(summary.missedOccurrences, 4);
    expect(summary.consistencyOccurrences, 3);
    expect(metrics.minimumCompletedCount, 1);
  });

  test('quantitative full, partial, and missed counts are exact', () {
    final habits = [
      _habit(
        title: 'Walk',
        trackingType: HabitTrackingType.quantitative,
        targetValue: 10000,
        unit: 'steps',
        completedDates: {'2026-06-13', '2026-06-14'},
        quantitativeProgress: const {
          '2026-06-13': 10000,
          '2026-06-14': 12000,
          '2026-06-15': 5000,
          '2026-06-16': 7000,
        },
      ),
    ];

    final metrics = calculateWeeklyReviewMetrics(habits, reference);
    final summary = metrics.habitSummaries.single;

    expect(summary.fullCompletions, 2);
    expect(summary.partialOccurrences, 2);
    expect(summary.missedOccurrences, 3);
    expect(summary.consistencyOccurrences, 4);
    expect(summary.totalLogged, 34000);
    expect(summary.averageProgress, closeTo(34000 / 7, 0.001));
    expect(summary.averageLoggedAmount, closeTo(8500, 0.001));
  });

  test('skip reason counts are exact', () {
    final habits = [
      _habit(
        skipReasons: const {
          '2026-06-19': HabitSkipReason.tooTired,
          '2026-06-18': HabitSkipReason.noTime,
        },
      ),
      _habit(id: '2', skipReasons: const {'2026-06-19': HabitSkipReason.other}),
    ];

    final metrics = calculateWeeklyReviewMetrics(habits, reference);

    expect(metrics.skipReasonCounts[HabitSkipReason.noTime], 1);
    expect(metrics.skipReasonCounts[HabitSkipReason.forgot], 0);
    expect(metrics.skipReasonCounts[HabitSkipReason.tooTired], 1);
    expect(metrics.skipReasonCounts[HabitSkipReason.tooDifficult], 0);
    expect(metrics.skipReasonCounts[HabitSkipReason.other], 1);
  });

  test('partial reason counts are exact', () {
    final habits = [
      _habit(
        trackingType: HabitTrackingType.quantitative,
        targetValue: 3,
        unit: 'L',
        quantitativeProgress: const {
          '2026-06-19': 1.5,
          '2026-06-18': 1,
          '2026-06-17': 1,
        },
        partialReasons: const {
          '2026-06-19': HabitPartialReason.noTime,
          '2026-06-17': HabitPartialReason.tooTired,
        },
      ),
    ];

    final metrics = calculateWeeklyReviewMetrics(habits, reference);

    expect(metrics.partialReasonCounts[HabitPartialReason.noTime], 1);
    expect(metrics.partialReasonCounts[HabitPartialReason.tooTired], 1);
    expect(
      metrics.partialReasonCounts[HabitPartialReason.targetTooDifficult],
      0,
    );
    expect(metrics.partialWithoutReason, 1);
  });

  test('unlabelled missed and partial counts are exact', () {
    final habits = [
      _habit(
        completedDates: {'2026-06-19'},
        minimumCompletedDates: {'2026-06-18'},
        skipReasons: const {'2026-06-17': HabitSkipReason.forgot},
      ),
      _habit(
        id: 'q',
        trackingType: HabitTrackingType.quantitative,
        targetValue: 10,
        quantitativeProgress: const {'2026-06-19': 5},
      ),
    ];

    final metrics = calculateWeeklyReviewMetrics(habits, reference);

    expect(metrics.missedWithoutReason, 10);
    expect(metrics.partialWithoutReason, 1);
  });

  test('one occurrence is not described as a repeated pattern', () {
    final review = generateWeeklyReview([
      _habit(skipReasons: const {'2026-06-19': HabitSkipReason.noTime}),
    ], reference);

    expect(review.patterns.join(' '), isNot(contains('Limited time')));
    expect(review.patterns, isEmpty);
  });

  test('two or more matching reasons may be described as repeated', () {
    final review = generateWeeklyReview([
      _habit(
        skipReasons: const {
          '2026-06-18': HabitSkipReason.noTime,
          '2026-06-19': HabitSkipReason.noTime,
        },
      ),
    ], reference);

    expect(review.patterns.join(' '), contains('Limited time'));
    expect(review.patterns.join(' '), contains('2 times'));
  });

  test('local fallback has all four sections and exactly one focus', () {
    final review = generateWeeklyReview([
      _habit(completedDates: {'2026-06-19'}),
    ], reference);

    expect(review.whatWentWell, isNotEmpty);
    expect(review.partialProgress, isA<List<String>>());
    expect(review.patterns, isA<List<String>>());
    expect(review.focusNextWeek, isNotEmpty);
    expect(
      review.focusNextWeek.split('.').where((s) => s.trim().isNotEmpty),
      hasLength(1),
    );
  });

  test('local fallback works with no habits', () {
    final review = generateWeeklyReview([], reference);

    expect(
      review.whatWentWell.single,
      'No scheduled habit data was available for this week.',
    );
    expect(
      review.focusNextWeek,
      'Choose one realistic habit to track next week.',
    );
  });

  test('local fallback works with zero scheduled occurrences', () {
    final review = generateWeeklyReview([
      _habit(weekdays: const []),
    ], DateTime(2026, 6, 20));

    expect(
      review.whatWentWell.single,
      'No scheduled habit data was available for this week.',
    );
    expect(review.patterns, isEmpty);
  });

  test('quantitative habit summaries remain backward compatible', () {
    final habits = [
      _habit(
        title: 'Water',
        trackingType: HabitTrackingType.quantitative,
        targetValue: 3,
        unit: 'L',
        quantitativeProgress: const {'2026-06-15': 3, '2026-06-17': 1.5},
        completedDates: const {'2026-06-15'},
      ),
    ];

    final metrics = calculateWeeklyReviewMetrics(habits, reference);
    final summary = metrics.quantitativeHabits.single;

    expect(summary.title, 'Water');
    expect(summary.unit, 'L');
    expect(summary.target, 3);
    expect(summary.scheduledOccurrences, 7);
    expect(summary.targetReached, 1);
    expect(summary.partialOccurrences, 1);
    expect(summary.totalLogged, closeTo(4.5, 0.001));
    expect(summary.averageLogged, closeTo(2.25, 0.001));
  });

  test(
    'local fallback uses partial progress wording for quantitative habits',
    () {
      final review = generateWeeklyReview([
        _habit(
          title: 'Steps',
          trackingType: HabitTrackingType.quantitative,
          targetValue: 10000,
          unit: 'steps',
          quantitativeProgress: const {'2026-06-18': 5000, '2026-06-19': 7000},
        ),
      ], reference);

      final combined = [
        ...review.whatWentWell,
        ...review.partialProgress,
        ...review.patterns,
        review.focusNextWeek,
      ].join(' ');

      expect(combined, contains('partial progress'));
      expect(combined, isNot(contains('partial completion')));
      expect(
        review.patterns,
        contains("'Steps' had partial progress on 2 scheduled days."),
      );
    },
  );

  test('separate one-off partial habits are not merged into a pattern', () {
    final review = generateWeeklyReview([
      _habit(
        id: 'steps',
        title: 'Steps',
        trackingType: HabitTrackingType.quantitative,
        targetValue: 10000,
        unit: 'steps',
        quantitativeProgress: const {'2026-06-19': 5000},
      ),
      _habit(
        id: 'water',
        title: 'Water',
        trackingType: HabitTrackingType.quantitative,
        targetValue: 3,
        unit: 'L',
        quantitativeProgress: const {'2026-06-19': 1},
      ),
    ], reference);

    expect(review.patterns, isEmpty);
  });

  test('repeated forgetting allows reminder focus', () {
    final review = generateWeeklyReview([
      _habit(
        title: 'Reading',
        skipReasons: const {
          '2026-06-18': HabitSkipReason.forgot,
          '2026-06-19': HabitSkipReason.forgot,
        },
      ),
    ], reference);

    expect(review.focusNextWeek.toLowerCase(), contains('reminder'));
  });

  test('reminders are not suggested without repeated forgetting', () {
    final review = generateWeeklyReview([
      _habit(
        title: 'Reading',
        skipReasons: const {'2026-06-19': HabitSkipReason.noTime},
      ),
    ], reference);

    expect(review.focusNextWeek.toLowerCase(), isNot(contains('reminder')));
  });

  test('focus is grounded by repeated no time', () {
    final review = generateWeeklyReview([
      _habit(
        title: 'Reading',
        skipReasons: const {
          '2026-06-18': HabitSkipReason.noTime,
          '2026-06-19': HabitSkipReason.noTime,
        },
      ),
    ], reference);

    expect(review.focusNextWeek, contains('time slot'));
  });

  test('focus is grounded by repeated tiredness', () {
    final review = generateWeeklyReview([
      _habit(
        title: 'Reading',
        skipReasons: const {
          '2026-06-18': HabitSkipReason.tooTired,
          '2026-06-19': HabitSkipReason.tooTired,
        },
      ),
    ], reference);

    expect(review.focusNextWeek, contains('easier time of day'));
  });

  test('focus is grounded by repeated difficulty', () {
    final review = generateWeeklyReview([
      _habit(
        title: 'Steps',
        skipReasons: const {
          '2026-06-18': HabitSkipReason.tooDifficult,
          '2026-06-19': HabitSkipReason.tooDifficult,
        },
      ),
    ], reference);

    expect(review.focusNextWeek, contains('target or scope'));
  });

  test('focus is grounded by repeated quantitative partial progress', () {
    final review = generateWeeklyReview([
      _habit(
        title: 'Steps',
        trackingType: HabitTrackingType.quantitative,
        targetValue: 10000,
        unit: 'steps',
        quantitativeProgress: const {'2026-06-18': 5000, '2026-06-19': 7000},
      ),
    ], reference);

    expect(review.focusNextWeek, contains('full target day'));
  });

  test('focus is grounded by repeated minimum version use', () {
    final review = generateWeeklyReview([
      _habit(
        title: 'Reading',
        minimumVersion: 'Read one page',
        minimumCompletedDates: const {'2026-06-18', '2026-06-19'},
      ),
    ], reference);

    expect(review.focusNextWeek, contains('minimum version'));
  });

  test('singular and plural wording is correct', () {
    final oneDay = generateWeeklyReview([
      _habit(title: 'Reading', completedDates: {'2026-06-19'}),
    ], reference);
    final twoDays = generateWeeklyReview([
      _habit(title: 'Reading', completedDates: {'2026-06-18', '2026-06-19'}),
    ], reference);

    expect(oneDay.whatWentWell.first, contains('1 of 7 scheduled days'));
    expect(twoDays.whatWentWell.first, contains('2 of 7 scheduled days'));
  });

  test('quantitative partial value is not duplicated in what went well', () {
    final review = generateWeeklyReview([
      _habit(
        title: 'Steps',
        trackingType: HabitTrackingType.quantitative,
        targetValue: 10000,
        unit: 'steps',
        quantitativeProgress: const {'2026-06-19': 8520},
      ),
    ], reference);

    expect(review.whatWentWell.join(' '), isNot(contains('8520')));
    expect(review.whatWentWell.join(' '), isNot(contains('partial progress')));
    expect(review.partialProgress.join(' '), contains('partial progress'));
  });

  test('full completion remains eligible for what went well', () {
    final review = generateWeeklyReview([
      _habit(title: 'Evening walk', completedDates: {'2026-06-19'}),
    ], reference);

    expect(review.whatWentWell.first, contains("'Evening walk'"));
    expect(review.whatWentWell.first, contains('completed'));
  });

  test('strong consistency can appear in what went well', () {
    final review = generateWeeklyReview([
      _habit(
        title: 'Steps',
        trackingType: HabitTrackingType.quantitative,
        targetValue: 10000,
        unit: 'steps',
        quantitativeProgress: const {
          '2026-06-13': 5000,
          '2026-06-14': 6000,
          '2026-06-15': 7000,
          '2026-06-16': 8000,
          '2026-06-17': 9000,
        },
      ),
    ], reference);

    expect(review.whatWentWell.first, contains("engaged with 'Steps'"));
    expect(review.whatWentWell.first, contains('5 of 7 scheduled days'));
  });

  test('one pattern sentence mentions at most one known habit title', () {
    final review = generateWeeklyReview([
      _habit(
        id: 'steps',
        title: 'Steps',
        trackingType: HabitTrackingType.quantitative,
        targetValue: 10000,
        unit: 'steps',
        quantitativeProgress: const {'2026-06-18': 5000, '2026-06-19': 7000},
      ),
      _habit(
        id: 'water',
        title: 'Water',
        trackingType: HabitTrackingType.quantitative,
        targetValue: 3,
        unit: 'L',
        quantitativeProgress: const {'2026-06-18': 1, '2026-06-19': 2},
      ),
    ], reference);

    expect(review.patterns, hasLength(2));
    for (final pattern in review.patterns) {
      final matches = ['Steps', 'Water']
          .where((title) => pattern.toLowerCase().contains(title.toLowerCase()))
          .length;
      expect(matches, lessThanOrEqualTo(1));
    }
  });

  test('two qualifying habits produce separate pattern candidates', () {
    final metrics = calculateWeeklyReviewMetrics([
      _habit(
        id: 'steps',
        title: 'Steps',
        trackingType: HabitTrackingType.quantitative,
        targetValue: 10000,
        unit: 'steps',
        quantitativeProgress: const {'2026-06-18': 5000, '2026-06-19': 7000},
      ),
      _habit(
        id: 'water',
        title: 'Water',
        trackingType: HabitTrackingType.quantitative,
        targetValue: 3,
        unit: 'L',
        quantitativeProgress: const {'2026-06-18': 1, '2026-06-19': 2},
      ),
    ], reference);

    final partialPatterns = eligibleWeeklyReviewPatterns(
      metrics,
    ).where((pattern) => pattern.type == 'partialProgress').toList();

    expect(partialPatterns, hasLength(2));
    expect(
      partialPatterns.map((pattern) => pattern.habitTitle),
      contains('Steps'),
    );
    expect(
      partialPatterns.map((pattern) => pattern.habitTitle),
      contains('Water'),
    );
  });

  test('only the strongest two patterns are selected', () {
    final review = generateWeeklyReview([
      _habit(
        title: 'Reading',
        skipReasons: const {
          '2026-06-17': HabitSkipReason.noTime,
          '2026-06-18': HabitSkipReason.noTime,
          '2026-06-19': HabitSkipReason.noTime,
        },
      ),
      _habit(
        title: 'Steps',
        trackingType: HabitTrackingType.quantitative,
        targetValue: 10000,
        unit: 'steps',
        quantitativeProgress: const {'2026-06-18': 5000, '2026-06-19': 7000},
      ),
      _habit(
        title: 'Gym',
        minimumVersion: 'Stretch for five minutes',
        minimumCompletedDates: const {'2026-06-18', '2026-06-19'},
      ),
    ], reference);

    expect(review.patterns, hasLength(2));
    expect(review.patterns.first, contains('Limited time'));
  });

  test('focus names one specific habit and one concrete action', () {
    final review = generateWeeklyReview([
      _habit(
        title: 'Steps',
        trackingType: HabitTrackingType.quantitative,
        targetValue: 10000,
        unit: 'steps',
        quantitativeProgress: const {'2026-06-18': 5000, '2026-06-19': 7000},
      ),
    ], reference);

    expect(review.focusNextWeek, contains("'Steps'"));
    expect(review.focusNextWeek, contains('Try turning one partial'));
    expect(review.focusNextWeek.toLowerCase(), isNot(contains('all habits')));
    expect(
      review.focusNextWeek.toLowerCase(),
      isNot(contains('completion rates')),
    );
  });

  test('repeated partial progress focus does not use missed wording', () {
    final review = generateWeeklyReview([
      _habit(
        title: 'Steps',
        trackingType: HabitTrackingType.quantitative,
        targetValue: 10000,
        unit: 'steps',
        quantitativeProgress: const {'2026-06-18': 5000, '2026-06-19': 7000},
      ),
    ], reference);

    expect(review.focusNextWeek.toLowerCase(), isNot(contains('missed')));
    expect(review.focusNextWeek.toLowerCase(), isNot(contains('skipped')));
    expect(review.focusNextWeek, contains('one partial'));
  });

  test('fallback never invents a numeric target', () {
    final review = generateWeeklyReview([
      _habit(
        title: 'Steps',
        trackingType: HabitTrackingType.quantitative,
        targetValue: 10000,
        unit: 'steps',
        quantitativeProgress: const {'2026-06-18': 5000, '2026-06-19': 7000},
      ),
    ], reference);

    expect(review.focusNextWeek, isNot(contains('7,000')));
    expect(review.focusNextWeek, isNot(contains('8000')));
    expect(review.focusNextWeek, isNot(contains('20%')));
  });

  test('fallback may mention the existing target value', () {
    final review = generateWeeklyReview([
      _habit(
        title: 'Steps',
        trackingType: HabitTrackingType.quantitative,
        targetValue: 10000,
        unit: 'steps',
        quantitativeProgress: const {'2026-06-18': 5000, '2026-06-19': 7000},
      ),
    ], reference);

    expect(review.partialProgress.join(' '), contains('10000 steps'));
  });
}
