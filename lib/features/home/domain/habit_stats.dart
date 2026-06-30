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
    final lastActiveDay = pauseDay.subtract(const Duration(days: 1));
    return lastActiveDay.isBefore(today) ? lastActiveDay : today;
  }
  return today;
}

/// True when [habit] counts as "engaged" on [key] for consistency purposes.
/// Binary: full or minimum completion.
/// Quantitative: any positive logged progress (or full completion).
bool _isEngaged(Habit habit, String key) {
  if (habit.isCompletedOn(key)) return true;
  if (habit.isQuantitative) {
    return (habit.quantitativeProgress[key] ?? 0) > 0;
  }
  return habit.minimumCompletedDates.contains(key);
}

/// Current streak for [habit] as of [today].
///
/// Walks backward from [today] counting consecutive scheduled days on
/// which the habit was completed. For quantitative habits, "completed" means
/// the daily target was reached. Unscheduled days are skipped.
int habitCurrentStreak(Habit habit, DateTime today) {
  final ref = _effectiveToday(habit, today);
  final refNorm = DateTime(ref.year, ref.month, ref.day);
  var streak = 0;
  var day = refNorm;

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

/// Total completed occurrences for [habit] on scheduled days only.
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
/// was completed at full OR minimum level (binary), or had any positive
/// logged progress (quantitative).
double habitConsistencyRate(Habit habit, DateTime today) {
  final ref = _effectiveToday(habit, today);
  final refNorm = DateTime(ref.year, ref.month, ref.day);
  var scheduled = 0;
  var engaged = 0;

  for (var i = 0; i < 30; i++) {
    final day = refNorm.subtract(Duration(days: i));
    if (!habit.isScheduledFor(day)) continue;
    scheduled++;
    if (_isEngaged(habit, dateKey(day))) engaged++;
  }

  if (scheduled == 0) return 0;
  return engaged / scheduled;
}

/// Consistency streak: consecutive scheduled days with any engagement (full,
/// minimum, or for quantitative any positive progress).
int habitConsistencyStreak(Habit habit, DateTime today) {
  final ref = _effectiveToday(habit, today);
  final refNorm = DateTime(ref.year, ref.month, ref.day);
  var streak = 0;
  var day = refNorm;

  if (habit.isScheduledFor(day) && !_isEngaged(habit, dateKey(day))) {
    day = day.subtract(const Duration(days: 1));
  }

  for (var i = 0; i < 365; i++) {
    if (!habit.isScheduledFor(day)) {
      day = day.subtract(const Duration(days: 1));
      continue;
    }
    if (_isEngaged(habit, dateKey(day))) {
      streak++;
      day = day.subtract(const Duration(days: 1));
    } else {
      break;
    }
  }
  return streak;
}

// ── Quantitative-specific stats ──────────────────────────────────────────────

/// Fraction of scheduled days in the last 30 days where [habit] reached
/// its daily target. Returns 0 for binary habits or habits without a target.
double habitQuantitativeTargetRate(Habit habit, DateTime today) {
  if (!habit.isQuantitative) return 0;
  final target = habit.targetValue;
  if (target == null || target <= 0) return 0;
  final ref = _effectiveToday(habit, today);
  final refNorm = DateTime(ref.year, ref.month, ref.day);
  var scheduled = 0;
  var reached = 0;

  for (var i = 0; i < 30; i++) {
    final day = refNorm.subtract(Duration(days: i));
    if (!habit.isScheduledFor(day)) continue;
    scheduled++;
    if (habit.isCompletedOn(dateKey(day))) reached++;
  }

  if (scheduled == 0) return 0;
  return reached / scheduled;
}

/// Fraction of scheduled days in the last 30 days where [habit] logged any
/// positive progress (regardless of whether target was reached).
double habitQuantitativeConsistencyRate(Habit habit, DateTime today) {
  if (!habit.isQuantitative) return 0;
  final ref = _effectiveToday(habit, today);
  final refNorm = DateTime(ref.year, ref.month, ref.day);
  var scheduled = 0;
  var withProgress = 0;

  for (var i = 0; i < 30; i++) {
    final day = refNorm.subtract(Duration(days: i));
    if (!habit.isScheduledFor(day)) continue;
    scheduled++;
    if ((habit.quantitativeProgress[dateKey(day)] ?? 0) > 0) withProgress++;
  }

  if (scheduled == 0) return 0;
  return withProgress / scheduled;
}

/// Total amount logged for [habit] across all scheduled days.
double habitQuantitativeTotalLogged(Habit habit) {
  var total = 0.0;
  for (final entry in habit.quantitativeProgress.entries) {
    final day = parseDateKey(entry.key);
    if (habit.isScheduledFor(day)) total += entry.value;
  }
  return total;
}

/// Average progress per scheduled occurrence over the last 30 days.
/// Includes days with zero progress in the denominator.
double habitQuantitativeAverageProgress(Habit habit, DateTime today) {
  if (!habit.isQuantitative) return 0;
  final ref = _effectiveToday(habit, today);
  final refNorm = DateTime(ref.year, ref.month, ref.day);
  var scheduled = 0;
  var total = 0.0;

  for (var i = 0; i < 30; i++) {
    final day = refNorm.subtract(Duration(days: i));
    if (!habit.isScheduledFor(day)) continue;
    scheduled++;
    total += habit.quantitativeProgress[dateKey(day)] ?? 0;
  }

  if (scheduled == 0) return 0;
  return total / scheduled;
}

/// Average progress on days where any amount was logged (last 30 days).
/// Excludes zero-progress days from the denominator.
double habitQuantitativeAverageLogged(Habit habit, DateTime today) {
  if (!habit.isQuantitative) return 0;
  final ref = _effectiveToday(habit, today);
  final refNorm = DateTime(ref.year, ref.month, ref.day);
  var loggedDays = 0;
  var total = 0.0;

  for (var i = 0; i < 30; i++) {
    final day = refNorm.subtract(Duration(days: i));
    if (!habit.isScheduledFor(day)) continue;
    final v = habit.quantitativeProgress[dateKey(day)] ?? 0;
    if (v > 0) {
      loggedDays++;
      total += v;
    }
  }

  if (loggedDays == 0) return 0;
  return total / loggedDays;
}

// ── Skip reason stats ─────────────────────────────────────────────────────────

bool _isCountableMissedReason(Habit habit, String key, DateTime refNorm) {
  final day = parseDateKey(key);
  if (day.isAfter(refNorm) || !habit.isScheduledFor(day)) return false;
  return !habit.completedDates.contains(key) &&
      !habit.minimumCompletedDates.contains(key);
}

int habitRecordedSkipReasonCount(Habit habit, DateTime today) {
  final ref = _effectiveToday(habit, today);
  final refNorm = DateTime(ref.year, ref.month, ref.day);
  return habit.skipReasons.keys
      .where((key) => _isCountableMissedReason(habit, key, refNorm))
      .length;
}

Map<HabitSkipReason, int> habitSkipReasonCounts(Habit habit, DateTime today) {
  final ref = _effectiveToday(habit, today);
  final refNorm = DateTime(ref.year, ref.month, ref.day);
  final counts = {for (final reason in HabitSkipReason.values) reason: 0};
  for (final entry in habit.skipReasons.entries) {
    if (_isCountableMissedReason(habit, entry.key, refNorm)) {
      counts[entry.value] = counts[entry.value]! + 1;
    }
  }
  return counts;
}

MapEntry<HabitSkipReason, int>? habitMostCommonSkipReason(
  Habit habit,
  DateTime today,
) {
  final counts = habitSkipReasonCounts(habit, today);
  MapEntry<HabitSkipReason, int>? best;
  for (final reason in HabitSkipReason.values) {
    final count = counts[reason] ?? 0;
    if (count == 0) continue;
    if (best == null || count > best.value) {
      best = MapEntry(reason, count);
    }
  }
  return best;
}

int habitMissedWithoutReasonCount(
  Habit habit,
  DateTime today, {
  int days = 30,
}) {
  final ref = _effectiveToday(habit, today);
  final refNorm = DateTime(ref.year, ref.month, ref.day);
  var count = 0;
  for (var i = 0; i < days; i++) {
    final day = refNorm.subtract(Duration(days: i));
    if (!habit.isScheduledFor(day)) continue;
    final key = dateKey(day);
    if (_isEngaged(habit, key)) continue;
    if (!habit.skipReasons.containsKey(key)) count++;
  }
  return count;
}

bool _isCountablePartialReason(Habit habit, String key, DateTime refNorm) {
  if (!habit.isQuantitative) return false;
  final day = parseDateKey(key);
  if (day.isAfter(refNorm) || !habit.isScheduledFor(day)) return false;
  return habit.hasPartialProgressOn(key);
}

Map<HabitPartialReason, int> habitPartialReasonCounts(
  Habit habit,
  DateTime today,
) {
  final ref = _effectiveToday(habit, today);
  final refNorm = DateTime(ref.year, ref.month, ref.day);
  final counts = {for (final reason in HabitPartialReason.values) reason: 0};
  for (final entry in habit.partialReasons.entries) {
    if (_isCountablePartialReason(habit, entry.key, refNorm)) {
      counts[entry.value] = counts[entry.value]! + 1;
    }
  }
  return counts;
}

MapEntry<HabitPartialReason, int>? habitMostCommonPartialReason(
  Habit habit,
  DateTime today,
) {
  final counts = habitPartialReasonCounts(habit, today);
  MapEntry<HabitPartialReason, int>? best;
  for (final reason in HabitPartialReason.values) {
    final count = counts[reason] ?? 0;
    if (count == 0) continue;
    if (best == null || count > best.value) {
      best = MapEntry(reason, count);
    }
  }
  return best;
}

int habitPartialWithoutReasonCount(
  Habit habit,
  DateTime today, {
  int days = 30,
}) {
  final ref = _effectiveToday(habit, today);
  final refNorm = DateTime(ref.year, ref.month, ref.day);
  var count = 0;
  for (var i = 0; i < days; i++) {
    final day = refNorm.subtract(Duration(days: i));
    if (!habit.isScheduledFor(day)) continue;
    final key = dateKey(day);
    if (!habit.hasPartialProgressOn(key)) continue;
    if (!habit.partialReasons.containsKey(key)) count++;
  }
  return count;
}
