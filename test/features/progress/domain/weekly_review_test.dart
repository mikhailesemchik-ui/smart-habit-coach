import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_habit_coach/features/home/domain/habit.dart';
import 'package:smart_habit_coach/features/progress/domain/weekly_review.dart';

Habit _habit(String id, Set<String> completedDates) {
  return Habit(
    id: id,
    title: 'Habit $id',
    scheduledTime: '08:00 AM',
    icon: Icons.local_drink_outlined,
    completedDates: completedDates,
  );
}

void main() {
  // Friday, June 19, 2026.
  final reference = DateTime(2026, 6, 19);

  test('no habits returns a prompt to create one, with no day breakdown', () {
    final review = generateWeeklyReview([], reference);

    expect(review.summary, 'Add a habit to start your weekly review.');
    expect(review.strongestDay, isNull);
    expect(review.weakestDay, isNull);
    expect(
      review.recommendation,
      'Create your first habit to start tracking weekly progress.',
    );
  });

  test('no completion data returns a no-progress summary', () {
    final habits = [_habit('1', {})];

    final review = generateWeeklyReview(habits, reference);

    expect(review.summary, "You didn't log any progress this week.");
    expect(review.strongestDay, isNull);
    expect(review.weakestDay, isNull);
    expect(
      review.recommendation,
      'Complete one habit tomorrow to start a new streak.',
    );
  });

  test('partial progress identifies the strongest and weakest day', () {
    // Two habits; only completed together on Wednesday (06-17).
    final habits = [
      _habit('1', {'2026-06-17'}),
      _habit('2', {'2026-06-17'}),
    ];

    final review = generateWeeklyReview(habits, reference);

    expect(review.summary, contains('made some progress'));
    expect(review.strongestDay, 'Wednesday');
    expect(review.weakestDay, isNotNull);
    expect(review.recommendation, contains(review.weakestDay!));
  });

  test('strong progress (>=70%) returns an encouraging summary', () {
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

    expect(review.summary, contains('Great week'));
    expect(review.summary, contains('100%'));
    expect(review.strongestDay, isNotNull);
    expect(
      review.recommendation,
      'Keep up the momentum and consider adding a new habit next week.',
    );
  });
}
