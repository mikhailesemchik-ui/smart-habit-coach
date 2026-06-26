import '../../home/domain/date_key.dart';
import '../../home/domain/habit.dart';

/// Number of habits completed on [day].
int dailyCompletionCount(List<Habit> habits, DateTime day) {
  final key = dateKey(day);
  return habits.where((h) => h.isCompletedOn(key)).length;
}

/// Fraction of habits completed on [day], in the range [0, 1].
/// Returns 0 when [habits] is empty.
double dailyCompletionPercentage(List<Habit> habits, DateTime day) {
  if (habits.isEmpty) return 0;
  return dailyCompletionCount(habits, day) / habits.length;
}

List<DateTime> last7Days(DateTime referenceDate) {
  final today = DateTime(
    referenceDate.year,
    referenceDate.month,
    referenceDate.day,
  );
  return List.generate(7, (index) => today.subtract(Duration(days: 6 - index)));
}

bool allHabitsCompletedOn(List<Habit> habits, DateTime day) {
  if (habits.isEmpty) return false;
  final key = dateKey(day);
  return habits.every((habit) => habit.isCompletedOn(key));
}

double weeklyCompletionRate(List<Habit> habits, DateTime referenceDate) {
  if (habits.isEmpty) return 0;

  final days = last7Days(referenceDate);
  var completedHabitDays = 0;
  for (final habit in habits) {
    for (final day in days) {
      if (habit.isCompletedOn(dateKey(day))) completedHabitDays++;
    }
  }
  return completedHabitDays / (habits.length * days.length);
}

int currentStreak(List<Habit> habits, DateTime referenceDate) {
  if (habits.isEmpty) return 0;

  var streak = 0;
  var day = DateTime(
    referenceDate.year,
    referenceDate.month,
    referenceDate.day,
  );
  while (allHabitsCompletedOn(habits, day)) {
    streak++;
    day = day.subtract(const Duration(days: 1));
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
    if (allHabitsCompletedOn(habits, day)) {
      current++;
      if (current > best) best = current;
    } else {
      current = 0;
    }
    day = day.add(const Duration(days: 1));
  }
  return best;
}
