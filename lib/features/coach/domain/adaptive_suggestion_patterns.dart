import '../../home/domain/date_key.dart';
import '../../home/domain/habit.dart';
import 'adaptive_suggestion.dart';

const minOccurrenceEvidence = 3;
const minOccurrenceRatio = 0.4;

/// Rank of a suggestion's evidence code for cross-habit tie-breaking.
/// Lower is higher priority, per the product ranking rules.
const evidenceRank = <String, int>{
  'repeated_too_difficult': 1,
  'repeated_target_too_difficult_reason': 1,
  'repeated_too_tired': 2,
  'repeated_no_time': 3,
  'quantitative_consistency_gap': 4,
  'frequency_mismatch': 5,
};

class Candidate {
  final AdaptiveHabitSuggestion suggestion;
  final int rank;
  final int occurrenceCount;
  final double affectedRatio;

  const Candidate({
    required this.suggestion,
    required this.rank,
    required this.occurrenceCount,
    required this.affectedRatio,
  });
}

DateTime mondayOf(DateTime day) {
  final normalized = DateTime(day.year, day.month, day.day);
  return normalized.subtract(Duration(days: normalized.weekday - 1));
}

bool isEngagedOn(Habit habit, DateTime day) {
  final key = dateKey(day);
  if (habit.isCompletedOn(key)) return true;
  if (habit.isQuantitative) return (habit.quantitativeProgress[key] ?? 0) > 0;
  return habit.minimumCompletedDates.contains(key);
}

List<DateTime> scheduledDaysInWindow(
  Habit habit,
  DateTime start,
  DateTime end,
) {
  final days = <DateTime>[];
  var day = start;
  while (!day.isAfter(end)) {
    if (habit.isScheduledFor(day)) days.add(day);
    day = day.add(const Duration(days: 1));
  }
  return days;
}

double? median(List<double> values) {
  if (values.isEmpty) return null;
  final sorted = List<double>.of(values)..sort();
  final mid = sorted.length ~/ 2;
  if (sorted.length.isOdd) return sorted[mid];
  return (sorted[mid - 1] + sorted[mid]) / 2;
}

/// Conservative target proposal: the median of positive logged amounts in
/// the analysis window, clamped so it never exceeds the current target and
/// never drops below 50% of it. Rounded to one decimal place.
double? proposeTarget(Habit habit, List<double> positiveValuesInWindow) {
  final current = habit.targetValue;
  if (current == null || current <= 0) return null;
  final med = median(positiveValuesInWindow);
  if (med == null) return null;
  final minAllowed = current * 0.5;
  var proposed = med > current ? current : med;
  if (proposed < minAllowed) proposed = minAllowed;
  return double.parse(proposed.toStringAsFixed(1));
}

int skipReasonCount(
  Habit habit,
  List<DateTime> scheduledDays,
  HabitSkipReason reason,
) {
  var count = 0;
  for (final day in scheduledDays) {
    if (habit.skipReasonFor(day) == reason) count++;
  }
  return count;
}

int partialReasonCount(
  Habit habit,
  List<DateTime> scheduledDays,
  HabitPartialReason reason,
) {
  var count = 0;
  for (final day in scheduledDays) {
    if (habit.partialReasonFor(day) == reason) count++;
  }
  return count;
}

int minimumUsedCount(Habit habit, List<DateTime> scheduledDays) {
  var count = 0;
  for (final day in scheduledDays) {
    if (habit.minimumCompletedDates.contains(dateKey(day))) count++;
  }
  return count;
}

String suggestionId(
  String habitId,
  AdaptiveSuggestionType type,
  DateTime now,
) => '$habitId-${type.name}-${dateKey(now)}';

// ── Pattern 1: repeated "too difficult" ─────────────────────────────────────

Candidate? tooDifficultCandidate(
  Habit habit,
  List<DateTime> scheduledDays,
  DateTime start,
  DateTime end,
  DateTime now,
) {
  if (habit.isQuantitative || habit.hasMinimumVersion) return null;
  final tooDifficultCount = skipReasonCount(
    habit,
    scheduledDays,
    HabitSkipReason.tooDifficult,
  );
  final minUsedCount = minimumUsedCount(habit, scheduledDays);
  if (tooDifficultCount < minOccurrenceEvidence &&
      minUsedCount < minOccurrenceEvidence) {
    return null;
  }
  final occurrenceCount = tooDifficultCount >= minUsedCount
      ? tooDifficultCount
      : minUsedCount;
  return Candidate(
    suggestion: AdaptiveHabitSuggestion(
      id: suggestionId(habit.id, AdaptiveSuggestionType.addMinimumVersion, now),
      habitId: habit.id,
      type: AdaptiveSuggestionType.addMinimumVersion,
      createdAt: now,
      analysisStart: start,
      analysisEnd: end,
      evidenceCode: 'repeated_too_difficult',
      evidence: {
        'tooDifficultCount': tooDifficultCount,
        'minimumUsedCount': minUsedCount,
      },
    ),
    rank: evidenceRank['repeated_too_difficult']!,
    occurrenceCount: occurrenceCount,
    affectedRatio: occurrenceCount / scheduledDays.length,
  );
}

// ── Pattern 2: quantitative target too difficult ────────────────────────────

Candidate? quantitativeTargetCandidate(
  Habit habit,
  List<DateTime> scheduledDays,
  int expectedOccurrences,
  DateTime start,
  DateTime end,
  DateTime now,
) {
  if (!habit.isQuantitative) return null;
  final target = habit.targetValue;
  if (target == null || target <= 0) return null;

  final targetTooDifficultCount = partialReasonCount(
    habit,
    scheduledDays,
    HabitPartialReason.targetTooDifficult,
  );
  var partialProgressCount = 0;
  var engagedCount = 0;
  var reachedCount = 0;
  final positiveValues = <double>[];
  for (final day in scheduledDays) {
    final key = dateKey(day);
    final value = habit.quantitativeProgress[key] ?? 0;
    if (value > 0) {
      positiveValues.add(value);
      engagedCount++;
    }
    if (habit.hasPartialProgressOn(key)) partialProgressCount++;
    if (habit.isTargetReached(day)) reachedCount++;
  }

  final targetCompletionRate = reachedCount / expectedOccurrences;
  final consistencyRate = engagedCount / expectedOccurrences;
  final explicitReason = targetTooDifficultCount >= minOccurrenceEvidence;
  final ratioReason =
      partialProgressCount >= minOccurrenceRatio * expectedOccurrences;

  if (!explicitReason && !ratioReason) return null;
  if (targetCompletionRate >= 0.30) return null;
  if (consistencyRate - targetCompletionRate <= 0.20) return null;

  final proposedTarget = proposeTarget(habit, positiveValues);
  final evidenceCode = explicitReason
      ? 'repeated_target_too_difficult_reason'
      : 'quantitative_consistency_gap';

  return Candidate(
    suggestion: AdaptiveHabitSuggestion(
      id: suggestionId(
        habit.id,
        AdaptiveSuggestionType.reduceQuantitativeTarget,
        now,
      ),
      habitId: habit.id,
      type: AdaptiveSuggestionType.reduceQuantitativeTarget,
      createdAt: now,
      analysisStart: start,
      analysisEnd: end,
      evidenceCode: evidenceCode,
      evidence: {
        'targetTooDifficultCount': targetTooDifficultCount,
        'partialProgressCount': partialProgressCount,
        'reachedCount': reachedCount,
        'targetCompletionRate': targetCompletionRate,
        'consistencyRate': consistencyRate,
        // Numeric snapshot duplicated here for evidence completeness; the
        // authoritative copy used for apply-eligibility checks is the
        // dedicated originalTargetValue/originalUnit fields below, since
        // evidence values are constrained to num and can't hold the unit.
        'originalTargetValue': target,
        // Marks that a unit snapshot was captured at creation time (the
        // unit itself may legitimately be null for a unit-less habit).
        // Suggestions predating Phase 3 never have this key.
        'hasUnitSnapshot': 1,
      },
      proposedTargetValue: proposedTarget,
      originalTargetValue: target,
      originalUnit: habit.unit,
    ),
    rank: evidenceRank[evidenceCode]!,
    occurrenceCount: explicitReason
        ? targetTooDifficultCount
        : partialProgressCount,
    affectedRatio: partialProgressCount / expectedOccurrences,
  );
}

// ── Pattern 3: repeated "no time" ───────────────────────────────────────────

Candidate? noTimeCandidate(
  Habit habit,
  List<DateTime> scheduledDays,
  DateTime start,
  DateTime end,
  DateTime now,
) {
  final noTimeCount = habit.isQuantitative
      ? partialReasonCount(habit, scheduledDays, HabitPartialReason.noTime)
      : skipReasonCount(habit, scheduledDays, HabitSkipReason.noTime);
  if (noTimeCount < minOccurrenceEvidence) return null;

  final type = habit.hasMinimumVersion
      ? AdaptiveSuggestionType.reviewSchedule
      : (habit.isQuantitative
            ? null
            : AdaptiveSuggestionType.addMinimumVersion);
  if (type == null) return null;

  return Candidate(
    suggestion: AdaptiveHabitSuggestion(
      id: suggestionId(habit.id, type, now),
      habitId: habit.id,
      type: type,
      createdAt: now,
      analysisStart: start,
      analysisEnd: end,
      evidenceCode: 'repeated_no_time',
      evidence: {'noTimeCount': noTimeCount},
    ),
    rank: evidenceRank['repeated_no_time']!,
    occurrenceCount: noTimeCount,
    affectedRatio: noTimeCount / scheduledDays.length,
  );
}

// ── Pattern 4: repeated "too tired" ─────────────────────────────────────────

Candidate? tooTiredCandidate(
  Habit habit,
  List<DateTime> scheduledDays,
  DateTime start,
  DateTime end,
  DateTime now,
) {
  final tooTiredCount = habit.isQuantitative
      ? partialReasonCount(habit, scheduledDays, HabitPartialReason.tooTired)
      : skipReasonCount(habit, scheduledDays, HabitSkipReason.tooTired);
  if (tooTiredCount < minOccurrenceEvidence) return null;

  return Candidate(
    suggestion: AdaptiveHabitSuggestion(
      id: suggestionId(
        habit.id,
        AdaptiveSuggestionType.changeScheduledTime,
        now,
      ),
      habitId: habit.id,
      type: AdaptiveSuggestionType.changeScheduledTime,
      createdAt: now,
      analysisStart: start,
      analysisEnd: end,
      evidenceCode: 'repeated_too_tired',
      evidence: {'tooTiredCount': tooTiredCount},
      // No proposedTime yet: Phase 1 has no evidence-backed replacement time.
    ),
    rank: evidenceRank['repeated_too_tired']!,
    occurrenceCount: tooTiredCount,
    affectedRatio: tooTiredCount / scheduledDays.length,
  );
}

// ── Pattern 6: frequency mismatch ───────────────────────────────────────────

bool _weekEngagementLow(
  Habit habit,
  DateTime weekStart,
  DateTime windowStart,
  DateTime windowEnd,
) {
  final weekEnd = weekStart.add(const Duration(days: 6));
  // Only a fully-contained calendar week carries enough evidence to
  // evaluate; a week clipped by the analysis window boundary is skipped
  // rather than judged on partial data.
  if (weekStart.isBefore(windowStart) || weekEnd.isAfter(windowEnd)) {
    return false;
  }
  var scheduled = 0;
  var engaged = 0;
  for (var i = 0; i < 7; i++) {
    final day = weekStart.add(Duration(days: i));
    if (!habit.isScheduledFor(day)) continue;
    scheduled++;
    if (isEngagedOn(habit, day)) engaged++;
  }
  if (scheduled == 0) return false;
  return engaged / scheduled < 0.5;
}

Candidate? frequencyMismatchCandidate(
  Habit habit,
  int expectedOccurrences,
  DateTime start,
  DateTime end,
  DateTime now,
) {
  if (habit.weekdays.length <= 3) return null;
  if (expectedOccurrences < 8) return null;

  var engagedCount = 0;
  var day = start;
  while (!day.isAfter(end)) {
    if (habit.isScheduledFor(day) && isEngagedOn(habit, day)) engagedCount++;
    day = day.add(const Duration(days: 1));
  }
  final engagementRate = engagedCount / expectedOccurrences;
  if (engagementRate >= 0.50) return null;

  final currentWeekMonday = mondayOf(end);
  var lowWeeks = 0;
  for (var i = 1; i <= 3; i++) {
    final weekStart = currentWeekMonday.subtract(Duration(days: 7 * i));
    if (_weekEngagementLow(habit, weekStart, start, end)) lowWeeks++;
  }
  if (lowWeeks < 3) return null;

  return Candidate(
    suggestion: AdaptiveHabitSuggestion(
      id: suggestionId(habit.id, AdaptiveSuggestionType.reduceFrequency, now),
      habitId: habit.id,
      type: AdaptiveSuggestionType.reduceFrequency,
      createdAt: now,
      analysisStart: start,
      analysisEnd: end,
      evidenceCode: 'frequency_mismatch',
      evidence: {
        'expectedOccurrences': expectedOccurrences,
        'engagementRate': engagementRate,
        'lowEngagementWeeks': lowWeeks,
      },
    ),
    rank: evidenceRank['frequency_mismatch']!,
    occurrenceCount: expectedOccurrences - engagedCount,
    affectedRatio: 1 - engagementRate,
  );
}
