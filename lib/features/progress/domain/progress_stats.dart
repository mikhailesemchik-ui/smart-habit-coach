import '../../home/domain/date_key.dart';
import '../../home/domain/habit.dart';

/// Number of habits scheduled for [day] that were also completed on [day].
int dailyCompletionCount(List<Habit> habits, DateTime day) {
  final key = dateKey(day);
  return habits
      .where((h) => h.isScheduledFor(day) && h.isCompletedOn(key))
      .length;
}

/// Fraction of scheduled habits completed on [day], in the range [0, 1].
/// Returns 0 when no habits are scheduled on [day].
double dailyCompletionPercentage(List<Habit> habits, DateTime day) {
  final scheduled = habits.where((h) => h.isScheduledFor(day)).length;
  if (scheduled == 0) return 0;
  return dailyCompletionCount(habits, day) / scheduled;
}

List<DateTime> last7Days(DateTime referenceDate) {
  final today = DateTime(
    referenceDate.year,
    referenceDate.month,
    referenceDate.day,
  );
  return List.generate(7, (index) => today.subtract(Duration(days: 6 - index)));
}

bool _hasScheduledHabits(List<Habit> habits, DateTime day) =>
    habits.any((h) => h.isScheduledFor(day));

/// A day is "succeeded" when it has at least one scheduled habit and all
/// scheduled habits were completed. Days with no scheduled habits do not
/// succeed (they are skipped by callers, not counted as failures).
bool _scheduledDaySucceeded(List<Habit> habits, DateTime day) {
  final scheduled = habits.where((h) => h.isScheduledFor(day)).toList();
  if (scheduled.isEmpty) return false;
  final key = dateKey(day);
  return scheduled.every((h) => h.isCompletedOn(key));
}

/// Completion rate over the last 7 days, counting only scheduled occurrences.
///
/// Formula: completed scheduled habit-days ÷ total scheduled habit-days.
/// Days on which no habits are scheduled do not contribute to either count.
double weeklyCompletionRate(List<Habit> habits, DateTime referenceDate) {
  if (habits.isEmpty) return 0;

  final days = last7Days(referenceDate);
  var completed = 0;
  var total = 0;
  for (final day in days) {
    for (final habit in habits) {
      if (habit.isScheduledFor(day)) {
        total++;
        if (habit.isCompletedOn(dateKey(day))) completed++;
      }
    }
  }
  if (total == 0) return 0;
  return completed / total;
}

/// Current streak of fully-completed scheduled days, counting back from
/// [referenceDate]. Days with no scheduled habits are skipped (neither
/// counted nor treated as failures). Today is included when all its
/// scheduled habits have been completed. Uses a 365-day lookback to
/// prevent infinite loops for infrequent schedules.
int currentStreak(List<Habit> habits, DateTime referenceDate) {
  if (habits.isEmpty) return 0;

  var streak = 0;
  var day = DateTime(
    referenceDate.year,
    referenceDate.month,
    referenceDate.day,
  );

  for (var i = 0; i < 365; i++) {
    if (!_hasScheduledHabits(habits, day)) {
      day = day.subtract(const Duration(days: 1));
      continue;
    }
    if (_scheduledDaySucceeded(habits, day)) {
      streak++;
      day = day.subtract(const Duration(days: 1));
    } else {
      break;
    }
  }
  return streak;
}

int bestStreak(List<Habit> habits, DateTime referenceDate) {
  if (habits.isEmpty) return 0;

  final completedDays = habits
      .expand((habit) => habit.completedDates)
      .map(parseDateKey)
      .toList();
  if (completedDays.isEmpty) return 0;
  completedDays.sort();

  final today = DateTime(
    referenceDate.year,
    referenceDate.month,
    referenceDate.day,
  );
  var day = completedDays.first;
  var best = 0;
  var current = 0;

  while (!day.isAfter(today)) {
    if (!_hasScheduledHabits(habits, day)) {
      day = day.add(const Duration(days: 1));
      continue;
    }
    if (_scheduledDaySucceeded(habits, day)) {
      current++;
      if (current > best) best = current;
    } else {
      current = 0;
    }
    day = day.add(const Duration(days: 1));
  }
  return best;
}
