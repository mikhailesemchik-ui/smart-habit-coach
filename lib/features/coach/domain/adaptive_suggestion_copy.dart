import '../../home/domain/habit.dart';
import 'adaptive_suggestion.dart';

/// Deterministic, non-AI user-facing text for an [AdaptiveHabitSuggestion].
///
/// Every field is derived only from the suggestion's own evidence and the
/// referenced habit — never invented (no fabricated times, targets, or
/// weekday plans beyond what the suggestion already carries).
class AdaptiveSuggestionCopy {
  final String title;
  final String body;
  final String? suggestedTargetLine;

  const AdaptiveSuggestionCopy({
    required this.title,
    required this.body,
    this.suggestedTargetLine,
  });
}

int _count(AdaptiveHabitSuggestion suggestion, String key) =>
    (suggestion.evidence[key] ?? 0).round();

AdaptiveSuggestionCopy buildAdaptiveSuggestionCopy(
  AdaptiveHabitSuggestion suggestion,
  Habit habit,
) {
  switch (suggestion.type) {
    case AdaptiveSuggestionType.addMinimumVersion:
      return _addMinimumVersionCopy(suggestion, habit);
    case AdaptiveSuggestionType.reduceQuantitativeTarget:
      return _reduceQuantitativeTargetCopy(suggestion, habit);
    case AdaptiveSuggestionType.changeScheduledTime:
      return _changeScheduledTimeCopy(suggestion, habit);
    case AdaptiveSuggestionType.reviewSchedule:
      return _reviewScheduleCopy(suggestion, habit);
    case AdaptiveSuggestionType.reduceFrequency:
      return _reduceFrequencyCopy(suggestion, habit);
  }
}

AdaptiveSuggestionCopy _addMinimumVersionCopy(
  AdaptiveHabitSuggestion suggestion,
  Habit habit,
) {
  final title = 'Make "${habit.title}" easier on hard days';
  final body = suggestion.evidenceCode == 'repeated_no_time'
      ? 'You marked that you had no time ${_count(suggestion, 'noTimeCount')} '
            'times recently. A smaller Minimum Version may make the habit '
            'easier to complete on busy days.'
      : 'You marked this habit as too difficult '
            '${_count(suggestion, 'tooDifficultCount')} times recently. '
            'Adding a smaller Minimum Version may help you keep the routine '
            'going.';
  return AdaptiveSuggestionCopy(title: title, body: body);
}

AdaptiveSuggestionCopy _reduceQuantitativeTargetCopy(
  AdaptiveHabitSuggestion suggestion,
  Habit habit,
) {
  final partialCount = _count(suggestion, 'partialProgressCount');
  final reachedCount = _count(suggestion, 'reachedCount');
  final body =
      'You made progress on $partialCount scheduled days, but reached the '
      'full target on $reachedCount. A target closer to your recent '
      'activity may be more sustainable.';
  final proposedTarget = suggestion.proposedTargetValue;
  final suggestedTargetLine = proposedTarget == null
      ? null
      : 'Suggested target: ${habitProgressLabel(proposedTarget)}'
            '${habit.unit == null ? '' : ' ${habit.unit}'}';
  return AdaptiveSuggestionCopy(
    title: 'Review the target for "${habit.title}"',
    body: body,
    suggestedTargetLine: suggestedTargetLine,
  );
}

AdaptiveSuggestionCopy _changeScheduledTimeCopy(
  AdaptiveHabitSuggestion suggestion,
  Habit habit,
) {
  final body =
      'You marked yourself as too tired '
      '${_count(suggestion, 'tooTiredCount')} times recently. Reviewing '
      'when this habit is scheduled may help.';
  return AdaptiveSuggestionCopy(
    title: 'Try a different time for "${habit.title}"',
    body: body,
  );
}

AdaptiveSuggestionCopy _reviewScheduleCopy(
  AdaptiveHabitSuggestion suggestion,
  Habit habit,
) {
  final body =
      'You marked that you had no time '
      '${_count(suggestion, 'noTimeCount')} times recently. A different '
      'schedule may fit your week better.';
  return AdaptiveSuggestionCopy(
    title: 'Review the schedule for "${habit.title}"',
    body: body,
  );
}

AdaptiveSuggestionCopy _reduceFrequencyCopy(
  AdaptiveHabitSuggestion suggestion,
  Habit habit,
) {
  return AdaptiveSuggestionCopy(
    title: 'Review how often you do "${habit.title}"',
    body:
        'This habit had low engagement across three recent weeks. Reducing '
        'the weekly frequency may make the plan more realistic.',
  );
}
