import 'date_key.dart';
import 'habit.dart';

/// The latest date that counts as "active" for [habit].
///
/// For paused or archived habits with a [Habit.pausedFromDate], stats should
/// not accumulate new misses after that date. We use the day before the
/// pause boundary as the effective reference date, so the streak/rate stops
/// cleanly at the last active day.
DateTime _effectiveToday(Habit habit, DateTime today) {
  if (habit.isActive) return today;
  final pfd = habit.pausedFromDate;
  if (pfd != null) {
    final pauseDay = parseDateKey(pfd);
    // One day before the pause: the last day the habit was expected.
    final lastActiveDay = pauseDay.subtract(const Duration(days: 1));
    // Never go past the actual today (e.g. if pause date is in the future).
    return lastActiveDay.isBefore(today) ? lastActiveDay : today;
  }
  // Paused/archived without a boundary — treat today as the cutoff so no
  // future days accumulate, but history is still counted.
  return today;
}

/// Current streak for [habit] as of [today].
///
/// Walks backward from [today] counting consecutive scheduled days on
/// which the habit was completed. Unscheduled days are skipped (neither
/// counted nor treated as failures). For paused/archived habits the walk
/// stops at the day before [Habit.pausedFromDate] so inactive days do not
/// break the streak.
int habitCurrentStreak(Habit habit, DateTime today) {
  final ref = _effectiveToday(habit, today);
  final refNorm = DateTime(ref.year, ref.month, ref.day);
  var streak = 0;
  var day = refNorm;

  // Skip the reference day if scheduled but still incomplete.
  if (habit.isScheduledFor(day) && !habit.isCompletedOn(dateKey(day))) {
    day = day.subtract(const Duration(days: 1));
  }

  for (var i = 0; i < 365; i++) {
    if (!habit.isScheduledFor(day)) {
      day = day.subtract(const Duration(days: 1));
      continue;
    }
    if (habit.isCompletedOn(dateKey(day))) {
      streak++;
      day = day.subtract(const Duration(days: 1));
    } else {
      break;
    }
  }
  return streak;
}

/// Best streak for [habit] as of [today].
///
/// Longest consecutive run of completed scheduled days in history.
/// Unscheduled days are skipped. Future dates and post-pause dates are
/// excluded.
int habitBestStreak(Habit habit, DateTime today) {
  final ref = _effectiveToday(habit, today);
  final refNorm = DateTime(ref.year, ref.month, ref.day);
  if (habit.completedDates.isEmpty) return 0;

  final scheduledCompleted =
      habit.completedDates
          .map(parseDateKey)
          .where((d) => !d.isAfter(refNorm) && habit.isScheduledFor(d))
          .toList()
        ..sort();

  if (scheduledCompleted.isEmpty) return 0;

  var day = scheduledCompleted.first;
  var best = 0;
  var current = 0;

  while (!day.isAfter(refNorm)) {
    if (!habit.isScheduledFor(day)) {
      day = day.add(const Duration(days: 1));
      continue;
    }
    if (habit.isCompletedOn(dateKey(day))) {
      current++;
      if (current > best) best = current;
    } else {
      current = 0;
    }
    day = day.add(const Duration(days: 1));
  }
  return best;
}

/// Completion rate for [habit] over the last 30 calendar days ending on [today].
///
/// For paused/archived habits the window ends at the last active day so
/// inactive days do not count as misses.
///
/// Denominator: scheduled days in the 30-day window.
/// Numerator: scheduled days that were completed.
/// Returns 0.0 when no days in the window are scheduled.
double habitCompletionRate(Habit habit, DateTime today) {
  final ref = _effectiveToday(habit, today);
  final refNorm = DateTime(ref.year, ref.month, ref.day);
  var scheduled = 0;
  var completed = 0;

  for (var i = 0; i < 30; i++) {
    final day = refNorm.subtract(Duration(days: i));
    if (!habit.isScheduledFor(day)) continue;
    scheduled++;
    if (habit.isCompletedOn(dateKey(day))) completed++;
  }

  if (scheduled == 0) return 0;
  return completed / scheduled;
}

/// Total completed occurrences for [habit].
///
/// Only completions on scheduled days count; completions stored on
/// unscheduled days (e.g. before the schedule was changed) are excluded.
int habitTotalCompleted(Habit habit) {
  return habit.completedDates
      .where((key) => habit.isScheduledFor(parseDateKey(key)))
      .length;
}

/// Total minimum-completion occurrences for [habit] on scheduled days only.
int habitMinimumCompletedCount(Habit habit) {
  return habit.minimumCompletedDates
      .where((key) => habit.isScheduledFor(parseDateKey(key)))
      .length;
}

/// Full completions + minimum completions on scheduled days.
int habitTotalEngaged(Habit habit) =>
    habitTotalCompleted(habit) + habitMinimumCompletedCount(habit);

/// Fraction of scheduled days in the last 30 calendar days where the habit
/// was completed at full OR minimum level, ending at [today] (or the last
/// active day for paused/archived habits).
double habitConsistencyRate(Habit habit, DateTime today) {
  final ref = _effectiveToday(habit, today);
  final refNorm = DateTime(ref.year, ref.month, ref.day);
  var scheduled = 0;
  var engaged = 0;

  for (var i = 0; i < 30; i++) {
    final day = refNorm.subtract(Duration(days: i));
    if (!habit.isScheduledFor(day)) continue;
    scheduled++;
    final key = dateKey(day);
    if (habit.isCompletedOn(key) || habit.minimumCompletedDates.contains(key)) {
      engaged++;
    }
  }

  if (scheduled == 0) return 0;
  return engaged / scheduled;
}

/// Consistency streak for [habit]: consecutive scheduled days with full OR
/// minimum completion, counted back from [today] (or the last active day for
/// paused/archived habits).
int habitConsistencyStreak(Habit habit, DateTime today) {
  final ref = _effectiveToday(habit, today);
  final refNorm = DateTime(ref.year, ref.month, ref.day);
  var streak = 0;
  var day = refNorm;

  bool engaged(DateTime d) {
    final key = dateKey(d);
    return habit.isCompletedOn(key) ||
        habit.minimumCompletedDates.contains(key);
  }

  // Skip the reference day if scheduled but not engaged yet.
  if (habit.isScheduledFor(day) && !engaged(day)) {
    day = day.subtract(const Duration(days: 1));
  }

  for (var i = 0; i < 365; i++) {
    if (!habit.isScheduledFor(day)) {
      day = day.subtract(const Duration(days: 1));
      continue;
    }
    if (engaged(day)) {
      streak++;
      day = day.subtract(const Duration(days: 1));
    } else {
      break;
    }
  }
  return streak;
}
