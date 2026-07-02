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
const _highConsistencyThreshold = 0.7;
const _allSkipReasonCounts = {
  HabitSkipReason.noTime: 0,
  HabitSkipReason.forgot: 0,
  HabitSkipReason.tooTired: 0,
  HabitSkipReason.tooDifficult: 0,
  HabitSkipReason.other: 0,
};
const _allPartialReasonCounts = {
  HabitPartialReason.noTime: 0,
  HabitPartialReason.tooTired: 0,
  HabitPartialReason.targetTooDifficult: 0,
  HabitPartialReason.forgotToContinue: 0,
  HabitPartialReason.other: 0,
};

class WeeklyReview {
  final List<String> whatWentWell;
  final List<String> partialProgress;
  final List<String> patterns;
  final String focusNextWeek;
  final String? strongestDay;
  final String? weakestDay;
  final String summary;
  final String recommendation;

  const WeeklyReview({
    String? summary,
    this.strongestDay,
    this.weakestDay,
    String? recommendation,
    this.whatWentWell = const [],
    this.partialProgress = const [],
    this.patterns = const [],
    String? focusNextWeek,
  }) : summary = summary ?? '',
       recommendation = recommendation ?? focusNextWeek ?? '',
       focusNextWeek = focusNextWeek ?? recommendation ?? '';
}

class WeeklyReviewPattern {
  final String type;
  final String? habitId;
  final String? habitTitle;
  final String? reason;
  final int count;

  const WeeklyReviewPattern({
    required this.type,
    this.habitId,
    this.habitTitle,
    this.reason,
    required this.count,
  });
}

class _PatternCandidate {
  final String text;
  final int priority;
  final int count;
  final int gap;
  final String sortKey;

  const _PatternCandidate({
    required this.text,
    required this.priority,
    required this.count,
    this.gap = 0,
    required this.sortKey,
  });
}

class WeeklyReviewFocusSignals {
  final bool repeatedForgot;
  final bool repeatedForgotToContinue;
  final bool repeatedNoTime;
  final bool repeatedTooTired;
  final bool repeatedDifficulty;
  final bool repeatedPartialProgress;
  final bool repeatedMinimumUse;
  final bool highConsistencyLowFullCompletion;
  final bool strongWeek;
  final bool noScheduledData;
  final String? primaryHabitTitle;

  const WeeklyReviewFocusSignals({
    required this.repeatedForgot,
    required this.repeatedForgotToContinue,
    required this.repeatedNoTime,
    required this.repeatedTooTired,
    required this.repeatedDifficulty,
    required this.repeatedPartialProgress,
    required this.repeatedMinimumUse,
    required this.highConsistencyLowFullCompletion,
    required this.strongWeek,
    required this.noScheduledData,
    this.primaryHabitTitle,
  });
}

/// Summary of a single habit over the review week.
class WeeklyHabitSummary {
  final String habitId;
  final String title;
  final HabitTrackingType trackingType;
  final int scheduledOccurrences;
  final int fullCompletions;
  final int minimumCompletions;
  final int partialOccurrences;
  final int missedOccurrences;
  final int consistencyOccurrences;
  final double completionRate;
  final double consistencyRate;
  final int currentStreak;
  final int bestStreak;
  final double? targetValue;
  final String? unit;
  final double totalLogged;
  final double averageProgress;
  final double averageLoggedAmount;
  final Map<HabitSkipReason, int> skipReasons;
  final Map<HabitPartialReason, int> partialReasons;
  final int missedWithoutReason;
  final int partialWithoutReason;

  const WeeklyHabitSummary({
    required this.habitId,
    required this.title,
    required this.trackingType,
    required this.scheduledOccurrences,
    required this.fullCompletions,
    required this.minimumCompletions,
    required this.partialOccurrences,
    required this.missedOccurrences,
    required this.consistencyOccurrences,
    required this.completionRate,
    required this.consistencyRate,
    required this.currentStreak,
    required this.bestStreak,
    this.targetValue,
    this.unit,
    this.totalLogged = 0,
    this.averageProgress = 0,
    this.averageLoggedAmount = 0,
    this.skipReasons = _allSkipReasonCounts,
    this.partialReasons = _allPartialReasonCounts,
    this.missedWithoutReason = 0,
    this.partialWithoutReason = 0,
  });
}

/// Backward-compatible quantitative summary used by existing tests/callers.
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

class WeeklyReviewMetrics {
  final double completionRate;
  final int currentStreak;
  final int bestStreak;
  final String? strongestDay;
  final String? weakestDay;
  final int completedCount;
  final int minimumCompletedCount;
  final int totalPossibleCount;
  final Map<HabitSkipReason, int> skipReasonCounts;
  final int missedWithoutReason;
  final List<QuantitativeHabitSummary> quantitativeHabits;
  final Map<HabitPartialReason, int> partialReasonCounts;
  final int partialWithoutReason;
  final List<WeeklyHabitSummary> habitSummaries;

  const WeeklyReviewMetrics({
    required this.completionRate,
    required this.currentStreak,
    required this.bestStreak,
    required this.strongestDay,
    required this.weakestDay,
    required this.completedCount,
    required this.minimumCompletedCount,
    required this.totalPossibleCount,
    this.skipReasonCounts = _allSkipReasonCounts,
    this.missedWithoutReason = 0,
    this.quantitativeHabits = const [],
    this.partialReasonCounts = _allPartialReasonCounts,
    this.partialWithoutReason = 0,
    this.habitSummaries = const [],
  });
}

WeeklyReviewMetrics _emptyMetrics() {
  return const WeeklyReviewMetrics(
    completionRate: 0,
    currentStreak: 0,
    bestStreak: 0,
    strongestDay: null,
    weakestDay: null,
    completedCount: 0,
    minimumCompletedCount: 0,
    totalPossibleCount: 0,
    skipReasonCounts: _allSkipReasonCounts,
    missedWithoutReason: 0,
    quantitativeHabits: [],
    partialReasonCounts: _allPartialReasonCounts,
    partialWithoutReason: 0,
    habitSummaries: [],
  );
}

WeeklyReviewMetrics calculateWeeklyReviewMetrics(
  List<Habit> habits,
  DateTime referenceDate,
) {
  final activeHabits = habits.where((h) => h.isActive).toList();
  if (activeHabits.isEmpty) return _emptyMetrics();

  final days = last7Days(referenceDate);
  final dailyCounts = [
    for (final day in days)
      activeHabits
          .where((h) => h.isScheduledFor(day) && h.isCompletedOn(dateKey(day)))
          .length,
  ];
  final completedCount = dailyCounts.fold(0, (sum, count) => sum + count);
  final totalPossibleCount = days.fold(
    0,
    (sum, day) => sum + activeHabits.where((h) => h.isScheduledFor(day)).length,
  );

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

  final habitSummaries = [
    for (final habit in activeHabits)
      _buildHabitSummary(habit, days, referenceDate),
  ];

  final skipReasonCounts = {
    for (final reason in HabitSkipReason.values) reason: 0,
  };
  final partialReasonCounts = {
    for (final reason in HabitPartialReason.values) reason: 0,
  };
  var minimumCompletedCount = 0;
  var missedWithoutReason = 0;
  var partialWithoutReason = 0;

  for (final summary in habitSummaries) {
    minimumCompletedCount += summary.minimumCompletions;
    missedWithoutReason += summary.missedWithoutReason;
    partialWithoutReason += summary.partialWithoutReason;
    for (final reason in HabitSkipReason.values) {
      skipReasonCounts[reason] =
          skipReasonCounts[reason]! + (summary.skipReasons[reason] ?? 0);
    }
    for (final reason in HabitPartialReason.values) {
      partialReasonCounts[reason] =
          partialReasonCounts[reason]! + (summary.partialReasons[reason] ?? 0);
    }
  }

  final quantitativeHabits = [
    for (final summary in habitSummaries)
      if (summary.trackingType == HabitTrackingType.quantitative &&
          summary.targetValue != null &&
          summary.targetValue! > 0)
        QuantitativeHabitSummary(
          title: summary.title,
          unit: summary.unit ?? '',
          target: summary.targetValue!,
          scheduledOccurrences: summary.scheduledOccurrences,
          targetReached: summary.fullCompletions,
          partialOccurrences: summary.partialOccurrences,
          totalLogged: summary.totalLogged,
          averageLogged: summary.averageLoggedAmount,
        ),
  ];

  return WeeklyReviewMetrics(
    completionRate: weeklyCompletionRate(activeHabits, referenceDate),
    currentStreak: currentStreak(activeHabits, referenceDate),
    bestStreak: bestStreak(activeHabits, referenceDate),
    strongestDay: strongestDay,
    weakestDay: weakestDay,
    completedCount: completedCount,
    minimumCompletedCount: minimumCompletedCount,
    totalPossibleCount: totalPossibleCount,
    skipReasonCounts: skipReasonCounts,
    missedWithoutReason: missedWithoutReason,
    quantitativeHabits: quantitativeHabits,
    partialReasonCounts: partialReasonCounts,
    partialWithoutReason: partialWithoutReason,
    habitSummaries: habitSummaries,
  );
}

WeeklyHabitSummary _buildHabitSummary(
  Habit habit,
  List<DateTime> days,
  DateTime referenceDate,
) {
  var scheduled = 0;
  var full = 0;
  var minimum = 0;
  var partial = 0;
  var missed = 0;
  var totalLogged = 0.0;
  var loggedOccurrences = 0;
  final skipReasons = {for (final reason in HabitSkipReason.values) reason: 0};
  final partialReasons = {
    for (final reason in HabitPartialReason.values) reason: 0,
  };
  var missedWithoutReason = 0;
  var partialWithoutReason = 0;

  for (final day in days) {
    if (!habit.isScheduledFor(day)) continue;
    scheduled++;
    final key = dateKey(day);
    final progress = habit.isQuantitative
        ? (habit.quantitativeProgress[key] ?? 0.0)
        : 0.0;
    final target = habit.targetValue;
    final reachedTarget =
        habit.isQuantitative &&
        target != null &&
        target > 0 &&
        progress >= target;
    if (habit.isQuantitative) totalLogged += progress;

    if (habit.completedDates.contains(key) || reachedTarget) {
      full++;
      if (habit.isQuantitative && progress > 0) loggedOccurrences++;
      continue;
    }

    if (!habit.isQuantitative && habit.minimumCompletedDates.contains(key)) {
      minimum++;
      continue;
    }

    if (habit.isQuantitative && habit.hasPartialProgressOn(key)) {
      partial++;
      loggedOccurrences++;
      final reason = habit.partialReasons[key];
      if (reason == null) {
        partialWithoutReason++;
      } else {
        partialReasons[reason] = partialReasons[reason]! + 1;
      }
      continue;
    }

    missed++;
    final reason = habit.skipReasonFor(day);
    if (reason == null) {
      missedWithoutReason++;
    } else {
      skipReasons[reason] = skipReasons[reason]! + 1;
    }
  }

  final consistency = full + minimum + partial;
  return WeeklyHabitSummary(
    habitId: habit.id,
    title: habit.title,
    trackingType: habit.trackingType,
    scheduledOccurrences: scheduled,
    fullCompletions: full,
    minimumCompletions: minimum,
    partialOccurrences: partial,
    missedOccurrences: missed,
    consistencyOccurrences: consistency,
    completionRate: scheduled == 0 ? 0 : full / scheduled,
    consistencyRate: scheduled == 0 ? 0 : consistency / scheduled,
    currentStreak: currentStreak([habit], referenceDate),
    bestStreak: bestStreak([habit], referenceDate),
    targetValue: habit.isQuantitative ? habit.targetValue : null,
    unit: habit.isQuantitative ? habit.unit : null,
    totalLogged: totalLogged,
    averageProgress: scheduled == 0 ? 0 : totalLogged / scheduled,
    averageLoggedAmount: loggedOccurrences == 0
        ? 0
        : totalLogged / loggedOccurrences,
    skipReasons: skipReasons,
    partialReasons: partialReasons,
    missedWithoutReason: missedWithoutReason,
    partialWithoutReason: partialWithoutReason,
  );
}

WeeklyReview generateWeeklyReview(List<Habit> habits, DateTime referenceDate) {
  final metrics = calculateWeeklyReviewMetrics(habits, referenceDate);

  if (metrics.totalPossibleCount == 0) {
    return const WeeklyReview(
      summary: 'No scheduled habit data was available for this week.',
      strongestDay: null,
      weakestDay: null,
      recommendation: 'Choose one realistic habit to track next week.',
      whatWentWell: ['No scheduled habit data was available for this week.'],
      partialProgress: [],
      patterns: [],
      focusNextWeek: 'Choose one realistic habit to track next week.',
    );
  }

  final whatWentWell = _buildWhatWentWell(metrics);
  final partialProgress = _buildPartialProgress(metrics);
  final patterns = _buildPatterns(metrics);
  final focus = _buildFocus(metrics);

  return WeeklyReview(
    summary: whatWentWell.first,
    strongestDay: metrics.strongestDay,
    weakestDay: metrics.weakestDay,
    recommendation: focus,
    whatWentWell: whatWentWell,
    partialProgress: partialProgress,
    patterns: patterns,
    focusNextWeek: focus,
  );
}

List<WeeklyReviewPattern> eligibleWeeklyReviewPatterns(
  WeeklyReviewMetrics metrics,
) {
  final patterns = <WeeklyReviewPattern>[];

  for (final reason in HabitSkipReason.values) {
    final count = metrics.skipReasonCounts[reason] ?? 0;
    if (count >= 2) {
      patterns.add(
        WeeklyReviewPattern(
          type: 'skipReason',
          reason: reason.name,
          count: count,
        ),
      );
    }
  }
  for (final reason in HabitPartialReason.values) {
    final count = metrics.partialReasonCounts[reason] ?? 0;
    if (count >= 2) {
      patterns.add(
        WeeklyReviewPattern(
          type: 'partialReason',
          reason: reason.name,
          count: count,
        ),
      );
    }
  }
  for (final summary in metrics.habitSummaries) {
    if (summary.partialOccurrences >= 2) {
      patterns.add(
        WeeklyReviewPattern(
          type: 'partialProgress',
          habitId: summary.habitId,
          habitTitle: summary.title,
          count: summary.partialOccurrences,
        ),
      );
    }
    if (summary.minimumCompletions >= 2) {
      patterns.add(
        WeeklyReviewPattern(
          type: 'minimumVersion',
          habitId: summary.habitId,
          habitTitle: summary.title,
          count: summary.minimumCompletions,
        ),
      );
    }
    if (summary.fullCompletions >= 2) {
      patterns.add(
        WeeklyReviewPattern(
          type: 'fullCompletion',
          habitId: summary.habitId,
          habitTitle: summary.title,
          count: summary.fullCompletions,
        ),
      );
    }
    if (_hasConsistencyGap(summary)) {
      patterns.add(
        WeeklyReviewPattern(
          type: 'consistencyGap',
          habitId: summary.habitId,
          habitTitle: summary.title,
          count: summary.consistencyOccurrences - summary.fullCompletions,
        ),
      );
    }
  }

  return patterns;
}

WeeklyReviewFocusSignals weeklyReviewFocusSignals(WeeklyReviewMetrics metrics) {
  final repeatedForgot =
      (metrics.skipReasonCounts[HabitSkipReason.forgot] ?? 0) >= 2;
  final repeatedForgotToContinue =
      (metrics.partialReasonCounts[HabitPartialReason.forgotToContinue] ?? 0) >=
      2;
  final repeatedNoTime =
      (metrics.skipReasonCounts[HabitSkipReason.noTime] ?? 0) +
          (metrics.partialReasonCounts[HabitPartialReason.noTime] ?? 0) >=
      2;
  final repeatedTooTired =
      (metrics.skipReasonCounts[HabitSkipReason.tooTired] ?? 0) +
          (metrics.partialReasonCounts[HabitPartialReason.tooTired] ?? 0) >=
      2;
  final repeatedDifficulty =
      (metrics.skipReasonCounts[HabitSkipReason.tooDifficult] ?? 0) +
          (metrics.partialReasonCounts[HabitPartialReason.targetTooDifficult] ??
              0) >=
      2;
  final repeatedPartialProgress = metrics.habitSummaries.any(
    (summary) => summary.partialOccurrences >= 2,
  );
  final repeatedMinimumUse = metrics.habitSummaries.any(
    (summary) => summary.minimumCompletions >= 2,
  );
  final highConsistencyLowFullCompletion = metrics.habitSummaries.any(
    _hasConsistencyGap,
  );

  return WeeklyReviewFocusSignals(
    repeatedForgot: repeatedForgot,
    repeatedForgotToContinue: repeatedForgotToContinue,
    repeatedNoTime: repeatedNoTime,
    repeatedTooTired: repeatedTooTired,
    repeatedDifficulty: repeatedDifficulty,
    repeatedPartialProgress: repeatedPartialProgress,
    repeatedMinimumUse: repeatedMinimumUse,
    highConsistencyLowFullCompletion: highConsistencyLowFullCompletion,
    strongWeek: metrics.completionRate >= _strongProgressThreshold,
    noScheduledData: metrics.totalPossibleCount == 0,
    primaryHabitTitle: _primaryFocusHabit(metrics)?.title,
  );
}

List<String> _buildWhatWentWell(WeeklyReviewMetrics metrics) {
  final lines = <String>[];
  final strongest = _strongestHabit(metrics);

  if (strongest != null && strongest.fullCompletions > 0) {
    if (strongest.trackingType == HabitTrackingType.quantitative) {
      lines.add(
        'You reached your ${_quoted(strongest.title)} target ${strongest.fullCompletions} ${_plural(strongest.fullCompletions, 'time', 'times')} this week.',
      );
    } else {
      lines.add(
        'You completed ${_quoted(strongest.title)} on ${strongest.fullCompletions} of ${strongest.scheduledOccurrences} scheduled ${_plural(strongest.scheduledOccurrences, 'day', 'days')}.',
      );
    }
  } else if (strongest != null && _hasConsistencyGap(strongest)) {
    lines.add(
      'You engaged with ${_quoted(strongest.title)} on ${strongest.consistencyOccurrences} of ${strongest.scheduledOccurrences} scheduled ${_plural(strongest.scheduledOccurrences, 'day', 'days')}.',
    );
  } else {
    lines.add(
      'There were no full completions this week, but the review can still help identify a manageable next step.',
    );
  }

  if (metrics.currentStreak > 0) {
    lines.add(
      'Your current full-completion streak is ${metrics.currentStreak} ${_plural(metrics.currentStreak, 'day', 'days')}.',
    );
  } else if (strongest != null &&
      strongest.consistencyOccurrences > 0 &&
      strongest.fullCompletions > 0 &&
      !lines.first.contains(strongest.title)) {
    lines.add(
      'Your strongest habit this week was ${_quoted(strongest.title)}.',
    );
  }

  return lines.take(2).toList();
}

List<String> _buildPartialProgress(WeeklyReviewMetrics metrics) {
  final lines = <String>[];
  for (final summary in metrics.habitSummaries) {
    if (summary.minimumCompletions > 0) {
      lines.add(
        'You used the minimum version of ${_quoted(summary.title)} on ${summary.minimumCompletions} ${_plural(summary.minimumCompletions, 'day', 'days')}.',
      );
    }
    if (summary.partialOccurrences > 0) {
      lines.add(
        'You made partial progress on ${_quoted(summary.title)} on ${summary.partialOccurrences} scheduled ${_plural(summary.partialOccurrences, 'day', 'days')}.',
      );
      final target = summary.targetValue;
      final unit = summary.unit;
      if (target != null && target > 0 && unit != null && unit.isNotEmpty) {
        lines.add(
          'You logged an average of ${_formatNumber(summary.averageLoggedAmount)} of ${_formatNumber(target)} $unit on days with progress.',
        );
      }
    }
  }

  return lines.take(2).toList();
}

List<String> _buildPatterns(WeeklyReviewMetrics metrics) {
  final candidates = <_PatternCandidate>[];

  for (final reason in HabitSkipReason.values) {
    final count = metrics.skipReasonCounts[reason] ?? 0;
    if (count >= 2) {
      candidates.add(
        _PatternCandidate(
          text:
              '${_skipReasonPatternLabel(reason)} was recorded $count ${_plural(count, 'time', 'times')}.',
          priority: 1,
          count: count,
          sortKey: reason.name,
        ),
      );
    }
  }
  for (final reason in HabitPartialReason.values) {
    final count = metrics.partialReasonCounts[reason] ?? 0;
    if (count >= 2) {
      candidates.add(
        _PatternCandidate(
          text:
              '${_partialReasonPatternLabel(reason)} affected partial progress $count ${_plural(count, 'time', 'times')}.',
          priority: 1,
          count: count,
          sortKey: reason.name,
        ),
      );
    }
  }
  for (final summary in metrics.habitSummaries) {
    if (summary.partialOccurrences >= 2) {
      candidates.add(
        _PatternCandidate(
          text:
              '${_quoted(summary.title)} had partial progress on ${summary.partialOccurrences} scheduled ${_plural(summary.partialOccurrences, 'day', 'days')}.',
          priority: 2,
          count: summary.partialOccurrences,
          sortKey: summary.title,
        ),
      );
    }
    if (summary.minimumCompletions >= 2) {
      candidates.add(
        _PatternCandidate(
          text:
              'You used the minimum version of ${_quoted(summary.title)} ${_countWord(summary.minimumCompletions)}.',
          priority: 2,
          count: summary.minimumCompletions,
          sortKey: summary.title,
        ),
      );
    }
    if (_hasConsistencyGap(summary)) {
      final gap = summary.consistencyOccurrences - summary.fullCompletions;
      candidates.add(
        _PatternCandidate(
          text:
              'You engaged with ${_quoted(summary.title)} on ${summary.consistencyOccurrences} days but reached the full target on ${summary.fullCompletions}.',
          priority: 3,
          count: summary.consistencyOccurrences,
          gap: gap,
          sortKey: summary.title,
        ),
      );
    }
  }

  candidates.sort((a, b) {
    final byPriority = a.priority.compareTo(b.priority);
    if (byPriority != 0) return byPriority;
    final byCount = b.count.compareTo(a.count);
    if (byCount != 0) return byCount;
    final byGap = b.gap.compareTo(a.gap);
    if (byGap != 0) return byGap;
    return a.sortKey.compareTo(b.sortKey);
  });

  return candidates.map((candidate) => candidate.text).take(2).toList();
}

String _buildFocus(WeeklyReviewMetrics metrics) {
  final signals = weeklyReviewFocusSignals(metrics);
  final habit = signals.primaryHabitTitle;

  if (signals.noScheduledData || habit == null) {
    return 'Choose one realistic habit to track next week.';
  }
  if (signals.repeatedDifficulty) {
    return 'Review the target or scope of ${_quoted(habit)} before next week starts.';
  }
  if (signals.repeatedNoTime) {
    return 'Protect one specific time slot for ${_quoted(habit)} next week.';
  }
  if (signals.repeatedTooTired) {
    return 'Try ${_quoted(habit)} at an easier time of day next week.';
  }
  if (signals.repeatedForgot || signals.repeatedForgotToContinue) {
    return 'Set one reminder for ${_quoted(habit)} on a day when it is commonly forgotten.';
  }
  if (signals.repeatedPartialProgress) {
    return 'Try turning one partial ${_quoted(habit)} day into a full target day next week.';
  }
  if (signals.repeatedMinimumUse) {
    return 'Use the minimum version of ${_quoted(habit)} intentionally on one busy day next week.';
  }
  if (signals.highConsistencyLowFullCompletion) {
    return 'Keep engaging with ${_quoted(habit)} and aim for one additional full completion.';
  }
  if (signals.strongWeek) {
    return 'Repeat the same schedule for ${_quoted(habit)} next week.';
  }
  if (metrics.completedCount == 0) {
    return 'Try completing ${_quoted(habit)} once next week.';
  }

  return 'Aim for one additional full completion of ${_quoted(habit)} next week.';
}

WeeklyHabitSummary? _primaryFocusHabit(WeeklyReviewMetrics metrics) {
  return _habitWithDifficulty(metrics) ??
      _habitWithNoTime(metrics) ??
      _habitWithTooTired(metrics) ??
      _habitWithForgot(metrics) ??
      _habitWithRepeatedPartial(metrics) ??
      _habitWithRepeatedMinimum(metrics) ??
      _habitWithConsistencyGap(metrics) ??
      _strongestHabit(metrics);
}

WeeklyHabitSummary? _habitWithDifficulty(WeeklyReviewMetrics metrics) {
  return _firstHabitWhere(metrics, (summary) {
    return (summary.skipReasons[HabitSkipReason.tooDifficult] ?? 0) +
            (summary.partialReasons[HabitPartialReason.targetTooDifficult] ??
                0) >=
        2;
  });
}

WeeklyHabitSummary? _habitWithNoTime(WeeklyReviewMetrics metrics) {
  return _firstHabitWhere(metrics, (summary) {
    return (summary.skipReasons[HabitSkipReason.noTime] ?? 0) +
            (summary.partialReasons[HabitPartialReason.noTime] ?? 0) >=
        2;
  });
}

WeeklyHabitSummary? _habitWithTooTired(WeeklyReviewMetrics metrics) {
  return _firstHabitWhere(metrics, (summary) {
    return (summary.skipReasons[HabitSkipReason.tooTired] ?? 0) +
            (summary.partialReasons[HabitPartialReason.tooTired] ?? 0) >=
        2;
  });
}

WeeklyHabitSummary? _habitWithForgot(WeeklyReviewMetrics metrics) {
  return _firstHabitWhere(metrics, (summary) {
    return (summary.skipReasons[HabitSkipReason.forgot] ?? 0) +
            (summary.partialReasons[HabitPartialReason.forgotToContinue] ??
                0) >=
        2;
  });
}

WeeklyHabitSummary? _habitWithRepeatedPartial(WeeklyReviewMetrics metrics) {
  return _firstHabitWhere(
    metrics,
    (summary) => summary.partialOccurrences >= 2,
  );
}

WeeklyHabitSummary? _habitWithRepeatedMinimum(WeeklyReviewMetrics metrics) {
  return _firstHabitWhere(
    metrics,
    (summary) => summary.minimumCompletions >= 2,
  );
}

WeeklyHabitSummary? _habitWithConsistencyGap(WeeklyReviewMetrics metrics) {
  return _firstHabitWhere(metrics, _hasConsistencyGap);
}

WeeklyHabitSummary? _firstHabitWhere(
  WeeklyReviewMetrics metrics,
  bool Function(WeeklyHabitSummary summary) test,
) {
  final matches = metrics.habitSummaries.where(test).toList()
    ..sort((a, b) {
      final byConsistency = b.consistencyOccurrences.compareTo(
        a.consistencyOccurrences,
      );
      if (byConsistency != 0) return byConsistency;
      return a.title.compareTo(b.title);
    });
  return matches.isEmpty ? null : matches.first;
}

bool _hasConsistencyGap(WeeklyHabitSummary summary) {
  return summary.consistencyOccurrences >= 2 &&
      summary.consistencyRate >= _highConsistencyThreshold &&
      summary.fullCompletions < summary.consistencyOccurrences;
}

WeeklyHabitSummary? _strongestHabit(WeeklyReviewMetrics metrics) {
  final scheduled = metrics.habitSummaries.where(
    (h) => h.scheduledOccurrences > 0,
  );
  if (scheduled.isEmpty) return null;
  return scheduled.reduce((a, b) {
    if (b.consistencyRate > a.consistencyRate) return b;
    if (b.consistencyRate < a.consistencyRate) return a;
    if (b.fullCompletions > a.fullCompletions) return b;
    if (b.fullCompletions < a.fullCompletions) return a;
    if (b.consistencyOccurrences > a.consistencyOccurrences) return b;
    if (b.consistencyOccurrences < a.consistencyOccurrences) return a;
    return a.title.compareTo(b.title) <= 0 ? a : b;
  });
}

String _plural(int count, String singular, String plural) =>
    count == 1 ? singular : plural;

String _formatNumber(double value) {
  if (value % 1 == 0) return value.toInt().toString();
  return value.toStringAsFixed(1);
}

String _quoted(String value) => "'$value'";

String _countWord(int count) {
  if (count == 2) return 'twice';
  return '$count times';
}

String _skipReasonPatternLabel(HabitSkipReason reason) {
  return switch (reason) {
    HabitSkipReason.noTime => 'Limited time',
    HabitSkipReason.forgot => 'Forgetting',
    HabitSkipReason.tooTired => 'Feeling too tired',
    HabitSkipReason.tooDifficult => 'Difficulty',
    HabitSkipReason.other => 'Other skip reasons',
  };
}

String _partialReasonPatternLabel(HabitPartialReason reason) {
  return switch (reason) {
    HabitPartialReason.noTime => 'Limited time',
    HabitPartialReason.tooTired => 'Feeling too tired',
    HabitPartialReason.targetTooDifficult => 'Target difficulty',
    HabitPartialReason.forgotToContinue => 'Forgetting to continue',
    HabitPartialReason.other => 'Other partial-progress reasons',
  };
}
