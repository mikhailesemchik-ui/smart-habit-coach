import '../../home/domain/date_key.dart';
import '../../home/domain/habit.dart';
import 'adaptive_suggestion.dart';
import 'adaptive_suggestion_patterns.dart';

// Phase 1 assumption: Habit has no creation date field, so "history length"
// is approximated by a fixed analysis window rather than actual habit age.
// The window always ends the day before [now] so the current, possibly
// incomplete, day never contributes evidence.
const _windowDays = 30;
const _minWindowDays = 14;
const _minExpectedOccurrences = 6;
const _cooldownDays = 28;

DateTime _normalize(DateTime d) => DateTime(d.year, d.month, d.day);

/// True when any suggestion (of any status) was created during the local
/// calendar week (Monday-start) containing [now].
bool hasSuggestionThisWeek(
  List<AdaptiveHabitSuggestion> previousSuggestions,
  DateTime now,
) {
  final weekStart = mondayOf(now);
  final weekEnd = weekStart.add(const Duration(days: 7));
  return previousSuggestions.any((s) {
    final created = _normalize(s.createdAt);
    return !created.isBefore(weekStart) && created.isBefore(weekEnd);
  });
}

bool _isOnCooldown(
  List<AdaptiveHabitSuggestion> previousSuggestions,
  String habitId,
  AdaptiveSuggestionType type,
  DateTime now,
  DateTime candidateAnalysisEnd,
) {
  final today = _normalize(now);
  for (final s in previousSuggestions) {
    if (s.habitId != habitId || s.type != type) continue;
    final daysSince = today.difference(_normalize(s.createdAt)).inDays;
    if (daysSince < 0) continue;
    final rejectedOrKept =
        s.status == AdaptiveSuggestionStatus.rejected ||
        s.status == AdaptiveSuggestionStatus.kept;
    final appliedOrAdjusted =
        s.status == AdaptiveSuggestionStatus.applied ||
        s.status == AdaptiveSuggestionStatus.adjusted;

    if (daysSince < _cooldownDays) {
      if (rejectedOrKept || appliedOrAdjusted) return true;
      continue;
    }

    // Past the 28-day cooldown: rejected/kept may be freely reconsidered,
    // but applied/adjusted suggestions require evidence newer than what
    // the prior suggestion was based on, so we don't re-propose the same
    // adjustment from stale data.
    if (appliedOrAdjusted &&
        !candidateAnalysisEnd.isAfter(_normalize(s.analysisEnd))) {
      return true;
    }
  }
  return false;
}

/// Detects at most one deterministic, evidence-backed habit adjustment
/// suggestion across [habits], subject to the weekly limit and per-habit
/// rejection/keep/apply cooldowns recorded in [previousSuggestions].
///
/// Pure and deterministic: given the same inputs it always returns the same
/// result. Never mutates habits or previous suggestions.
AdaptiveHabitSuggestion? detectAdaptiveSuggestion({
  required List<Habit> habits,
  required DateTime now,
  required List<AdaptiveHabitSuggestion> previousSuggestions,
}) {
  if (hasSuggestionThisWeek(previousSuggestions, now)) return null;

  final end = _normalize(now).subtract(const Duration(days: 1));
  final start = end.subtract(const Duration(days: _windowDays - 1));
  if (end.difference(start).inDays + 1 < _minWindowDays) return null;

  final candidates = <Candidate>[];
  for (final habit in habits) {
    if (!habit.isActive) continue;
    candidates.addAll(
      _candidatesForHabit(habit, start, end, now, previousSuggestions),
    );
  }
  if (candidates.isEmpty) return null;

  candidates.sort((a, b) {
    if (a.rank != b.rank) return a.rank.compareTo(b.rank);
    if (a.occurrenceCount != b.occurrenceCount) {
      return b.occurrenceCount.compareTo(a.occurrenceCount);
    }
    if (a.affectedRatio != b.affectedRatio) {
      return b.affectedRatio.compareTo(a.affectedRatio);
    }
    final habitCompare = a.suggestion.habitId.compareTo(b.suggestion.habitId);
    if (habitCompare != 0) return habitCompare;
    return a.suggestion.type.index.compareTo(b.suggestion.type.index);
  });

  return candidates.first.suggestion;
}

/// Earliest date with any recorded activity for [habit] (completion, skip
/// reason, or progress), used as a proxy for how long the habit has been
/// tracked since [Habit] has no creation-date field.
DateTime? _earliestActivityDate(Habit habit) {
  DateTime? earliest;
  void consider(String key) {
    try {
      final date = parseDateKey(key);
      if (earliest == null || date.isBefore(earliest!)) earliest = date;
    } catch (_) {
      // Malformed key: ignore rather than let it skew the history window.
    }
  }

  habit.completedDates.forEach(consider);
  habit.minimumCompletedDates.forEach(consider);
  habit.skipReasons.keys.forEach(consider);
  habit.quantitativeProgress.keys.forEach(consider);
  habit.partialReasons.keys.forEach(consider);
  return earliest;
}

List<Candidate> _candidatesForHabit(
  Habit habit,
  DateTime start,
  DateTime end,
  DateTime now,
  List<AdaptiveHabitSuggestion> previousSuggestions,
) {
  final earliestActivity = _earliestActivityDate(habit);
  if (earliestActivity == null) return const [];
  final historyDays = end.difference(earliestActivity).inDays + 1;
  if (historyDays < _minWindowDays) return const [];

  final scheduledDays = scheduledDaysInWindow(habit, start, end);
  final expectedOccurrences = scheduledDays.length;
  if (expectedOccurrences < _minExpectedOccurrences) return const [];

  final candidates = <Candidate>[];
  void addIfAllowed(Candidate? candidate) {
    if (candidate == null) return;
    if (_isOnCooldown(
      previousSuggestions,
      habit.id,
      candidate.suggestion.type,
      now,
      end,
    )) {
      return;
    }
    candidates.add(candidate);
  }

  addIfAllowed(tooDifficultCandidate(habit, scheduledDays, start, end, now));
  addIfAllowed(
    quantitativeTargetCandidate(
      habit,
      scheduledDays,
      expectedOccurrences,
      start,
      end,
      now,
    ),
  );
  addIfAllowed(noTimeCandidate(habit, scheduledDays, start, end, now));
  addIfAllowed(tooTiredCandidate(habit, scheduledDays, start, end, now));
  addIfAllowed(
    frequencyMismatchCandidate(habit, expectedOccurrences, start, end, now),
  );

  return candidates;
}
