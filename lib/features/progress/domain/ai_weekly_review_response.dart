import '../../home/domain/habit.dart';

import 'ai_weekly_review.dart';
import 'ai_weekly_review_exception.dart';
import 'weekly_review.dart';

const _genericParseError =
    "Couldn't understand the AI response. Please try again.";
const _maxObservationCount = 2;
const _maxPartialCount = 2;
const _maxPatternCount = 2;

AiWeeklyReviewException _invalid(
  String reason, {
  String? section,
  String? sentence,
  String? habitTitle,
}) {
  return AiWeeklyReviewException(
    _genericParseError,
    reason: reason,
    section: section,
    sentence: sentence,
    habitTitle: habitTitle,
  );
}

/// Parses and validates the JSON payload returned by the
/// `generate-weekly-review` edge function into an [AiWeeklyReview].
///
/// Throws [AiWeeklyReviewException] if [rawResponse] doesn't match the
/// expected shape.
AiWeeklyReview parseAiWeeklyReviewResponse(
  Object? rawResponse, {
  WeeklyReviewMetrics? metrics,
}) {
  if (rawResponse is! Map) {
    throw _invalid('invalid_response_shape');
  }

  if (rawResponse.containsKey('whatWentWell') ||
      rawResponse.containsKey('partialProgress') ||
      rawResponse.containsKey('patterns') ||
      rawResponse.containsKey('focusNextWeek')) {
    final whatWentWell = _readStringList(
      rawResponse['whatWentWell'],
      _maxObservationCount,
      allowEmpty: false,
    );
    final partialProgress = _readStringList(
      rawResponse['partialProgress'],
      _maxPartialCount,
      allowEmpty: true,
    );
    final patterns = _readStringList(
      rawResponse['patterns'],
      _maxPatternCount,
      allowEmpty: true,
    );
    final focusNextWeek = _readRequiredString(rawResponse['focusNextWeek']);

    if (whatWentWell == null ||
        partialProgress == null ||
        patterns == null ||
        focusNextWeek == null) {
      throw _invalid('malformed_structured_response');
    }

    _validateStructuredResponse(
      whatWentWell: whatWentWell,
      partialProgress: partialProgress,
      patterns: patterns,
      focusNextWeek: focusNextWeek,
      metrics: metrics,
    );

    return AiWeeklyReview(
      summary: whatWentWell.first,
      strongestInsight: whatWentWell.length > 1 ? whatWentWell[1] : '',
      weakestInsight: patterns.isEmpty ? '' : patterns.first,
      recommendation: focusNextWeek,
      whatWentWell: whatWentWell,
      partialProgress: partialProgress,
      patterns: patterns,
      focusNextWeek: focusNextWeek,
    );
  }

  final summary = _readRequiredString(rawResponse['summary']);
  final strongestInsight = _readRequiredString(rawResponse['strongestInsight']);
  final weakestInsight = _readRequiredString(rawResponse['weakestInsight']);
  final recommendation = _readRequiredString(rawResponse['recommendation']);

  if (summary == null ||
      strongestInsight == null ||
      weakestInsight == null ||
      recommendation == null) {
    throw _invalid('malformed_legacy_response');
  }

  _validateSafeWording([
    summary,
    strongestInsight,
    weakestInsight,
    recommendation,
  ], metrics: metrics);

  return AiWeeklyReview(
    summary: summary,
    strongestInsight: strongestInsight,
    weakestInsight: weakestInsight,
    recommendation: recommendation,
    whatWentWell: [
      summary,
      strongestInsight,
    ].take(_maxObservationCount).toList(),
    partialProgress: const [],
    patterns: [weakestInsight].take(_maxPatternCount).toList(),
    focusNextWeek: recommendation,
  );
}

String? _readRequiredString(Object? raw) {
  if (raw is! String) return null;
  final trimmed = raw.trim();
  return trimmed.isEmpty ? null : trimmed;
}

List<String>? _readStringList(
  Object? raw,
  int maxItems, {
  required bool allowEmpty,
}) {
  if (raw is! List) return null;
  if (!allowEmpty && raw.isEmpty) return null;
  final values = <String>[];
  for (final item in raw) {
    final value = _readRequiredString(item);
    if (value == null) return null;
    values.add(value);
  }
  return values.take(maxItems).toList();
}

void _validateSafeWording(
  List<String> values, {
  WeeklyReviewMetrics? metrics,
  String? section,
}) {
  final signals = metrics == null ? null : weeklyReviewFocusSignals(metrics);
  for (final value in values) {
    final normalized = value.toLowerCase();
    if (normalized.contains('partial completion')) {
      throw _invalid(
        'partial_completion_wording',
        section: section,
        sentence: value,
      );
    }
    if (signals != null &&
        !signals.repeatedForgot &&
        !signals.repeatedForgotToContinue &&
        _containsReminderAdvice(normalized)) {
      throw _invalid(
        'unsupported_reminder_advice',
        section: section,
        sentence: value,
      );
    }
  }
}

void _validateStructuredResponse({
  required List<String> whatWentWell,
  required List<String> partialProgress,
  required List<String> patterns,
  required String focusNextWeek,
  required WeeklyReviewMetrics? metrics,
}) {
  _validateSafeWording(whatWentWell, metrics: metrics, section: 'whatWentWell');
  _validateSafeWording(
    partialProgress,
    metrics: metrics,
    section: 'partialProgress',
  );
  _validateSafeWording(patterns, metrics: metrics, section: 'patterns');
  _validateSafeWording(
    [focusNextWeek],
    metrics: metrics,
    section: 'focusNextWeek',
  );
  _rejectDuplicateSectionFacts(
    whatWentWell,
    partialProgress,
    patterns,
    focusNextWeek,
  );

  final titles = _knownHabitTitles(metrics);
  if (titles.isEmpty) return;

  final normalizedFocus = focusNextWeek.toLowerCase();
  if (_containsGenericFocus(normalizedFocus)) {
    throw _invalid(
      'generic_focus',
      section: 'focusNextWeek',
      sentence: focusNextWeek,
    );
  }
  if (!_containsKnownHabitTitle(focusNextWeek, titles)) {
    throw _invalid(
      'focus_missing_habit_title',
      section: 'focusNextWeek',
      sentence: focusNextWeek,
    );
  }

  _rejectBelowTargetQuantitativeWhatWentWell(whatWentWell, metrics);
  _rejectPartialProgressAsMissedFocus(
    focusNextWeek,
    metrics,
    partialProgress: partialProgress,
    patterns: patterns,
  );
  _rejectUnknownFocusNumbers(focusNextWeek, metrics);

  for (final pattern in patterns) {
    if (_knownHabitTitleCount(pattern, titles) > 1) {
      throw _invalid(
        'multi_habit_pattern',
        section: 'patterns',
        sentence: pattern,
      );
    }
  }
}

void _rejectDuplicateSectionFacts(
  List<String> whatWentWell,
  List<String> partialProgress,
  List<String> patterns,
  String focusNextWeek,
) {
  final seen = <String>{};
  for (final value in [
    ...whatWentWell,
    ...partialProgress,
    ...patterns,
    focusNextWeek,
  ]) {
    final normalized = _normalizeSentence(value);
    if (normalized.isEmpty) continue;
    if (!seen.add(normalized)) {
      throw _invalid('duplicate_section_observation', sentence: value);
    }
  }
}

List<String> _knownHabitTitles(WeeklyReviewMetrics? metrics) {
  if (metrics == null) return const [];
  return metrics.habitSummaries
      .where((summary) => summary.scheduledOccurrences > 0)
      .map((summary) => summary.title.trim())
      .where((title) => title.isNotEmpty)
      .toList();
}

bool _containsKnownHabitTitle(String value, List<String> titles) {
  return _knownHabitTitleCount(value, titles) > 0;
}

int _knownHabitTitleCount(String value, List<String> titles) {
  var normalized = value.toLowerCase();
  var count = 0;
  final orderedTitles = [...titles]
    ..sort((a, b) => b.length.compareTo(a.length));
  for (final title in orderedTitles) {
    final normalizedTitle = title.toLowerCase();
    if (normalized.contains(normalizedTitle)) {
      count++;
      normalized = normalized.replaceAll(normalizedTitle, ' ');
    }
  }
  return count;
}

void _rejectBelowTargetQuantitativeWhatWentWell(
  List<String> whatWentWell,
  WeeklyReviewMetrics? metrics,
) {
  if (metrics == null) return;
  for (final line in whatWentWell) {
    final normalized = line.toLowerCase();
    for (final summary in metrics.habitSummaries) {
      if (summary.trackingType != HabitTrackingType.quantitative) continue;
      if (!_containsKnownHabitTitle(line, [summary.title])) continue;
      final reportsRawPartialProgress =
          summary.partialOccurrences > 0 &&
          !_describesConsistency(normalized) &&
          !_describesTargetReach(normalized);
      final rawProgressWording =
          normalized.contains('made progress') ||
          normalized.contains('logged progress') ||
          normalized.contains('total') ||
          normalized.contains('logged');
      if (reportsRawPartialProgress && rawProgressWording) {
        throw _invalid(
          'below_target_progress_in_what_went_well',
          section: 'whatWentWell',
          sentence: line,
          habitTitle: summary.title,
        );
      }
    }
  }
}

void _rejectPartialProgressAsMissedFocus(
  String focusNextWeek,
  WeeklyReviewMetrics? metrics, {
  required List<String> partialProgress,
  required List<String> patterns,
}) {
  if (metrics == null) return;
  final summary = _focusHabitSummary(focusNextWeek, metrics);
  if (summary == null || summary.partialOccurrences < 2) return;
  final groundedInPartialProgress = [...partialProgress, ...patterns].any((
    value,
  ) {
    final normalized = value.toLowerCase();
    return _containsKnownHabitTitle(value, [summary.title]) &&
        normalized.contains('partial progress');
  });
  if (!groundedInPartialProgress) return;
  final normalized = focusNextWeek.toLowerCase();
  const forbidden = [
    'missed day',
    'missed days',
    'skipped day',
    'skipped days',
    'failed',
    'failure',
    'incomplete day',
    'incomplete days',
  ];
  if (forbidden.any(normalized.contains)) {
    throw _invalid(
      'partial_progress_called_missed',
      section: 'focusNextWeek',
      sentence: focusNextWeek,
      habitTitle: summary.title,
    );
  }
}

void _rejectUnknownFocusNumbers(
  String focusNextWeek,
  WeeklyReviewMetrics? metrics,
) {
  if (metrics == null) return;
  final summary = _focusHabitSummary(focusNextWeek, metrics);
  if (summary == null) return;
  final numbers = _numericMatches(focusNextWeek);
  if (numbers.isEmpty) return;
  final known = _knownNumbersForHabit(summary);
  for (final number in numbers) {
    if (!known.contains(number)) {
      throw _invalid(
        'invented_numeric_target',
        section: 'focusNextWeek',
        sentence: focusNextWeek,
        habitTitle: summary.title,
      );
    }
  }
}

WeeklyHabitSummary? _focusHabitSummary(
  String focusNextWeek,
  WeeklyReviewMetrics metrics,
) {
  final matches = metrics.habitSummaries.where(
    (summary) => _containsKnownHabitTitle(focusNextWeek, [summary.title]),
  );
  return matches.isEmpty ? null : matches.first;
}

bool _describesConsistency(String normalized) {
  return normalized.contains('engaged with') ||
      normalized.contains('scheduled day') ||
      normalized.contains('scheduled days');
}

bool _describesTargetReach(String normalized) {
  return normalized.contains('reached') ||
      normalized.contains('reach the') ||
      normalized.contains('target reached') ||
      normalized.contains('completed the target');
}

Set<String> _knownNumbersForHabit(WeeklyHabitSummary summary) {
  final values = <String>{};
  void add(num value) {
    values.add(_normalizeNumber(value.toString()));
    if (value % 1 == 0) {
      values.add(_normalizeNumber(value.toInt().toString()));
    } else {
      values.add(_normalizeNumber(value.toStringAsFixed(1)));
      values.add(_normalizeNumber(value.toStringAsFixed(2)));
    }
  }

  add(summary.scheduledOccurrences);
  add(summary.fullCompletions);
  add(summary.minimumCompletions);
  add(summary.partialOccurrences);
  add(summary.missedOccurrences);
  add(summary.consistencyOccurrences);
  add(summary.currentStreak);
  add(summary.bestStreak);
  add(summary.totalLogged);
  add(summary.averageProgress);
  add(summary.averageLoggedAmount);
  final target = summary.targetValue;
  if (target != null) add(target);
  return values;
}

List<String> _numericMatches(String value) {
  return RegExp(r'\d[\d,]*(?:\.\d+)?')
      .allMatches(value)
      .map((match) => _normalizeNumber(match.group(0)!))
      .toList();
}

String _normalizeNumber(String value) {
  var normalized = value.replaceAll(',', '');
  if (normalized.endsWith('.0')) {
    normalized = normalized.substring(0, normalized.length - 2);
  }
  return normalized;
}

String _normalizeSentence(String value) {
  return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}

bool _containsGenericFocus(String normalized) {
  const forbidden = [
    'all scheduled habits',
    'all habits',
    'improve completion rates',
    'improve your habits',
    'be more consistent',
    'completion rates',
    'habits you want to prioritize',
  ];
  return forbidden.any(normalized.contains);
}

bool _containsReminderAdvice(String normalized) {
  return normalized.contains('reminder') ||
      normalized.contains('remind ') ||
      normalized.contains('remind yourself') ||
      normalized.contains('notification');
}
