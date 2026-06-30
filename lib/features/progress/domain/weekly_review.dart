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

/// Summary of a single quantitative habit over the review week.
class QuantitativeHabitSummary {
  final String title;
  final String unit;
  final double target;
  final int scheduledOccurrences;
  final int targetReached;
  final int partialOccurrences;
  final double totalLogged;
  final double averageLogged;

  const QuantitativeHabitSummary({
    required this.title,
    required this.unit,
    required this.target,
    required this.scheduledOccurrences,
    required this.targetReached,
    required this.partialOccurrences,
    required this.totalLogged,
    required this.averageLogged,
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
  final Map<HabitSkipReason, int> skipReasonCounts;
  final int missedWithoutReason;
  final List<QuantitativeHabitSummary> quantitativeHabits;

  final Map<HabitPartialReason, int> partialReasonCounts;
  final int partialWithoutReason;

  const WeeklyReviewMetrics({
    required this.completionRate,
    required this.currentStreak,
    required this.bestStreak,
    required this.strongestDay,
    required this.weakestDay,
    required this.completedCount,
    required this.minimumCompletedCount,
    required this.totalPossibleCount,
    this.skipReasonCounts = const {},
    this.missedWithoutReason = 0,
    this.quantitativeHabits = const [],
    this.partialReasonCounts = const {},
    this.partialWithoutReason = 0,
  });
}

/// Pure, deterministic calculation of this week's habit metrics.
WeeklyReviewMetrics calculateWeeklyReviewMetrics(
  List<Habit> habits,
  DateTime referenceDate,
) {
  if (habits.isEmpty) {
    return WeeklyReviewMetrics(
      completionRate: 0,
      currentStreak: 0,
      bestStreak: 0,
      strongestDay: null,
      weakestDay: null,
      completedCount: 0,
      minimumCompletedCount: 0,
      totalPossibleCount: 0,
      skipReasonCounts: {
        HabitSkipReason.noTime: 0,
        HabitSkipReason.forgot: 0,
        HabitSkipReason.tooTired: 0,
        HabitSkipReason.tooDifficult: 0,
        HabitSkipReason.other: 0,
      },
      missedWithoutReason: 0,
      quantitativeHabits: const [],
      partialReasonCounts: {for (final r in HabitPartialReason.values) r: 0},
      partialWithoutReason: 0,
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

  var minimumCompletedCount = 0;
  for (final day in days) {
    final key = dateKey(day);
    for (final h in habits) {
      if (h.isScheduledFor(day) && h.minimumCompletedDates.contains(key)) {
        minimumCompletedCount++;
      }
    }
  }

  final skipReasonCounts = {
    for (final reason in HabitSkipReason.values) reason: 0,
  };
  var missedWithoutReason = 0;
  for (final day in days) {
    final key = dateKey(day);
    for (final h in habits) {
      if (!h.isScheduledFor(day)) continue;
      // For quantitative habits, any positive progress counts as engaged.
      final isDone =
          h.completedDates.contains(key) ||
          h.minimumCompletedDates.contains(key) ||
          (h.isQuantitative && (h.quantitativeProgress[key] ?? 0) > 0);
      if (isDone) continue;
      final reason = h.skipReasonFor(day);
      if (reason == null) {
        missedWithoutReason++;
      } else {
        skipReasonCounts[reason] = skipReasonCounts[reason]! + 1;
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

  // Aggregate partial reason counts across all quantitative habits.
  final partialReasonCounts = {
    for (final reason in HabitPartialReason.values) reason: 0,
  };
  var partialWithoutReason = 0;
  for (final day in days) {
    final key = dateKey(day);
    for (final h in habits) {
      if (!h.isQuantitative || !h.isScheduledFor(day)) continue;
      if (!h.hasPartialProgressOn(key)) continue;
      final reason = h.partialReasons[key];
      if (reason == null) {
        partialWithoutReason++;
      } else {
        partialReasonCounts[reason] = partialReasonCounts[reason]! + 1;
      }
    }
  }

  // Build quantitative summaries.
  final quantitativeHabits = <QuantitativeHabitSummary>[];
  for (final habit in habits) {
    if (!habit.isQuantitative) continue;
    final target = habit.targetValue;
    if (target == null || target <= 0) continue;
    var scheduled = 0;
    var reached = 0;
    var partial = 0;
    var total = 0.0;
    for (final day in days) {
      if (!habit.isScheduledFor(day)) continue;
      scheduled++;
      final v = habit.quantitativeProgress[dateKey(day)] ?? 0;
      total += v;
      if (v >= target) {
        reached++;
      } else if (v > 0) {
        partial++;
      }
    }
    final loggedDays = reached + partial;
    final avgLogged = loggedDays > 0 ? total / loggedDays : 0.0;
    quantitativeHabits.add(
      QuantitativeHabitSummary(
        title: habit.title,
        unit: habit.unit ?? '',
        target: target,
        scheduledOccurrences: scheduled,
        targetReached: reached,
        partialOccurrences: partial,
        totalLogged: total,
        averageLogged: avgLogged,
      ),
    );
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
    skipReasonCounts: skipReasonCounts,
    missedWithoutReason: missedWithoutReason,
    quantitativeHabits: quantitativeHabits,
    partialReasonCounts: partialReasonCounts,
    partialWithoutReason: partialWithoutReason,
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
