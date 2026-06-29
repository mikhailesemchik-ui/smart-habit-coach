import '../../home/domain/date_key.dart';
import '../../home/domain/habit.dart';
import 'progress_stats.dart';

const _weekdayNames = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

const _strongProgressThreshold = 0.7;

class WeeklyReview {
  final String summary;
  final String? strongestDay;
  final String? weakestDay;
  final String recommendation;

  const WeeklyReview({
    required this.summary,
    required this.strongestDay,
    required this.weakestDay,
    required this.recommendation,
  });
}

/// Locally calculated, authoritative metrics for a week of habit
/// completions. Used both to build the deterministic [WeeklyReview] and as
/// the request payload sent to the AI weekly review edge function.
class WeeklyReviewMetrics {
  final double completionRate;
  final int currentStreak;
  final int bestStreak;
  final String? strongestDay;
  final String? weakestDay;
  final int completedCount;

  /// Habit-days completed at minimum level (distinct from full completions).
  final int minimumCompletedCount;
  final int totalPossibleCount;

  const WeeklyReviewMetrics({
    required this.completionRate,
    required this.currentStreak,
    required this.bestStreak,
    required this.strongestDay,
    required this.weakestDay,
    required this.completedCount,
    required this.minimumCompletedCount,
    required this.totalPossibleCount,
  });
}

/// Pure, deterministic calculation of this week's habit metrics. No
/// networking or AI calls.
WeeklyReviewMetrics calculateWeeklyReviewMetrics(
  List<Habit> habits,
  DateTime referenceDate,
) {
  if (habits.isEmpty) {
    return const WeeklyReviewMetrics(
      completionRate: 0,
      currentStreak: 0,
      bestStreak: 0,
      strongestDay: null,
      weakestDay: null,
      completedCount: 0,
      minimumCompletedCount: 0,
      totalPossibleCount: 0,
    );
  }

  final days = last7Days(referenceDate);
  final dailyCounts = [
    for (final day in days)
      habits
          .where((h) => h.isScheduledFor(day) && h.isCompletedOn(dateKey(day)))
          .length,
  ];
  final completedCount = dailyCounts.fold(0, (sum, count) => sum + count);

  // Minimum completions: scheduled days with minimum (not full) completion.
  var minimumCompletedCount = 0;
  for (final day in days) {
    final key = dateKey(day);
    for (final h in habits) {
      if (h.isScheduledFor(day) && h.minimumCompletedDates.contains(key)) {
        minimumCompletedCount++;
      }
    }
  }

  String? strongestDay;
  String? weakestDay;
  if (completedCount > 0) {
    var strongestIndex = 0;
    var weakestIndex = 0;
    for (var i = 1; i < dailyCounts.length; i++) {
      if (dailyCounts[i] > dailyCounts[strongestIndex]) strongestIndex = i;
      if (dailyCounts[i] < dailyCounts[weakestIndex]) weakestIndex = i;
    }
    strongestDay = _weekdayNames[days[strongestIndex].weekday - 1];
    weakestDay = _weekdayNames[days[weakestIndex].weekday - 1];
  }

  return WeeklyReviewMetrics(
    completionRate: weeklyCompletionRate(habits, referenceDate),
    currentStreak: currentStreak(habits, referenceDate),
    bestStreak: bestStreak(habits, referenceDate),
    strongestDay: strongestDay,
    weakestDay: weakestDay,
    completedCount: completedCount,
    minimumCompletedCount: minimumCompletedCount,
    totalPossibleCount: days.fold(
      0,
      (sum, day) => sum + habits.where((h) => h.isScheduledFor(day)).length,
    ),
  );
}

/// Pure, deterministic weekly review generator. No networking or AI calls.
WeeklyReview generateWeeklyReview(List<Habit> habits, DateTime referenceDate) {
  if (habits.isEmpty) {
    return const WeeklyReview(
      summary: 'Add a habit to start your weekly review.',
      strongestDay: null,
      weakestDay: null,
      recommendation:
          'Create your first habit to start tracking weekly progress.',
    );
  }

  final metrics = calculateWeeklyReviewMetrics(habits, referenceDate);

  if (metrics.completedCount == 0) {
    return const WeeklyReview(
      summary: "You didn't log any progress this week.",
      strongestDay: null,
      weakestDay: null,
      recommendation: 'Complete one habit tomorrow to start a new streak.',
    );
  }

  final percentage = (metrics.completionRate * 100).round();

  if (metrics.completionRate >= _strongProgressThreshold) {
    return WeeklyReview(
      summary: 'Great week! You completed $percentage% of your habits.',
      strongestDay: metrics.strongestDay,
      weakestDay: metrics.weakestDay,
      recommendation:
          'Keep up the momentum and consider adding a new habit next week.',
    );
  }

  return WeeklyReview(
    summary: 'You made some progress this week ($percentage% completed).',
    strongestDay: metrics.strongestDay,
    weakestDay: metrics.weakestDay,
    recommendation:
        'Try to stay consistent on ${metrics.weakestDay} to build momentum next week.',
  );
}
