import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_habit_coach/features/home/domain/habit.dart';
import 'package:smart_habit_coach/features/progress/domain/weekly_review.dart';

Habit _habit(
  String id,
  Set<String> completedDates, {
  String? title,
  Set<String> minimumCompletedDates = const {},
  String? minimumVersion,
}) {
  return Habit(
    id: id,
    title: title ?? 'Habit $id',
    scheduledTime: '08:00 AM',
    icon: Icons.local_drink_outlined,
    completedDates: completedDates,
    minimumCompletedDates: minimumCompletedDates,
    minimumVersion: minimumVersion,
  );
}

void main() {
  // Friday, June 19, 2026.
  final reference = DateTime(2026, 6, 19);

  test('no habits returns the empty weekly review sections', () {
    final review = generateWeeklyReview([], reference);

    expect(
      review.summary,
      'No scheduled habit data was available for this week.',
    );
    expect(review.strongestDay, isNull);
    expect(review.weakestDay, isNull);
    expect(review.whatWentWell, hasLength(1));
    expect(review.partialProgress, isEmpty);
    expect(review.patterns, isEmpty);
    expect(
      review.recommendation,
      'Choose one realistic habit to track next week.',
    );
  });

  test('no completion data returns factual sections without invented causes', () {
    final habits = [_habit('1', {})];

    final review = generateWeeklyReview(habits, reference);

    expect(
      review.whatWentWell.single,
      'There were no full completions this week, but the review can still help identify a manageable next step.',
    );
    expect(review.partialProgress, isEmpty);
    expect(review.patterns, isEmpty);
    expect(review.focusNextWeek, "Try completing 'Habit 1' once next week.");
  });

  test('partial progress identifies the strongest and weakest day', () {
    final habits = [
      _habit('1', {'2026-06-17'}),
      _habit('2', {'2026-06-17'}),
    ];

    final review = generateWeeklyReview(habits, reference);

    expect(review.summary, "You completed 'Habit 1' on 1 of 7 scheduled days.");
    expect(review.strongestDay, 'Wednesday');
    expect(review.weakestDay, isNotNull);
    expect(
      review.focusNextWeek,
      "Aim for one additional full completion of 'Habit 1' next week.",
    );
  });

  test('strong progress recommends keeping the current routine', () {
    final habits = [
      _habit('1', {
        '2026-06-13',
        '2026-06-14',
        '2026-06-15',
        '2026-06-16',
        '2026-06-17',
        '2026-06-18',
        '2026-06-19',
      }),
    ];

    final review = generateWeeklyReview(habits, reference);

    expect(review.summary, "You completed 'Habit 1' on 7 of 7 scheduled days.");
    expect(review.strongestDay, isNotNull);
    expect(
      review.recommendation,
      "Repeat the same schedule for 'Habit 1' next week.",
    );
  });

  test('minimum version is described separately from partial progress', () {
    final review = generateWeeklyReview([
      _habit(
        'reading',
        {},
        title: 'Reading',
        minimumVersion: 'Read one page',
        minimumCompletedDates: {'2026-06-18', '2026-06-19'},
      ),
    ], reference);

    expect(review.partialProgress, [
      "You used the minimum version of 'Reading' on 2 days.",
    ]);
    expect(
      review.partialProgress.join(' '),
      isNot(contains('partial completion')),
    );
  });
}
