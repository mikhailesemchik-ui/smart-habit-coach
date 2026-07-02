import 'adaptive_suggestion.dart';

/// User-facing label for [AdaptiveSuggestionType]. Never expose the enum
/// name directly in the UI.
String adaptiveSuggestionTypeLabel(AdaptiveSuggestionType type) {
  switch (type) {
    case AdaptiveSuggestionType.addMinimumVersion:
      return 'Add a Minimum Version';
    case AdaptiveSuggestionType.reduceQuantitativeTarget:
      return 'Reduce the target';
    case AdaptiveSuggestionType.changeScheduledTime:
      return 'Review the scheduled time';
    case AdaptiveSuggestionType.reviewSchedule:
      return 'Review the schedule';
    case AdaptiveSuggestionType.reduceFrequency:
      return 'Reduce weekly frequency';
  }
}

/// User-facing label for [AdaptiveSuggestionStatus]. Never expose the enum
/// name directly in the UI.
String adaptiveSuggestionStatusLabel(AdaptiveSuggestionStatus status) {
  switch (status) {
    case AdaptiveSuggestionStatus.pending:
      return 'Pending';
    case AdaptiveSuggestionStatus.applied:
      return 'Applied';
    case AdaptiveSuggestionStatus.adjusted:
      return 'Adjusted manually';
    case AdaptiveSuggestionStatus.kept:
      return 'Current plan kept';
    case AdaptiveSuggestionStatus.rejected:
      return 'No longer available';
  }
}

int _count(AdaptiveHabitSuggestion suggestion, String key) =>
    (suggestion.evidence[key] ?? 0).round();

bool _isValidPositiveFinite(double? value) =>
    value != null && value.isFinite && !value.isNaN && value > 0;

/// A conservative, deterministic, non-AI explanation of the evidence behind
/// a suggestion, written for historical review (Coach Insights) rather than
/// the actionable Weekly Review card. Never exposes raw evidence map keys
/// and never invents a time, target, or frequency that wasn't recorded.
String buildAdaptiveSuggestionEvidenceText(AdaptiveHabitSuggestion suggestion) {
  switch (suggestion.type) {
    case AdaptiveSuggestionType.addMinimumVersion:
      return _addMinimumVersionEvidence(suggestion);
    case AdaptiveSuggestionType.reduceQuantitativeTarget:
      return _reduceQuantitativeTargetEvidence(suggestion);
    case AdaptiveSuggestionType.changeScheduledTime:
      return _changeScheduledTimeEvidence(suggestion);
    case AdaptiveSuggestionType.reviewSchedule:
      return _reviewScheduleEvidence(suggestion);
    case AdaptiveSuggestionType.reduceFrequency:
      return _reduceFrequencyEvidence(suggestion);
  }
}

String _addMinimumVersionEvidence(AdaptiveHabitSuggestion suggestion) {
  if (suggestion.evidenceCode == 'repeated_no_time') {
    return 'You marked that you had no time ${_count(suggestion, 'noTimeCount')} times.';
  }
  final tooDifficultCount = _count(suggestion, 'tooDifficultCount');
  if (tooDifficultCount > 0) {
    return 'You marked this habit as too difficult $tooDifficultCount times.';
  }
  final minimumUsedCount = _count(suggestion, 'minimumUsedCount');
  return 'You used the Minimum Version $minimumUsedCount times.';
}

/// Optional suggested-target line for a [AdaptiveSuggestionType
/// .reduceQuantitativeTarget] suggestion. Null when there is no valid
/// proposed value to show (never invented).
String? adaptiveSuggestionTargetLine(
  AdaptiveHabitSuggestion suggestion,
  String? unitLabel,
) {
  if (suggestion.type != AdaptiveSuggestionType.reduceQuantitativeTarget) {
    return null;
  }
  final value = suggestion.proposedTargetValue;
  if (!_isValidPositiveFinite(value)) return null;

  final formatted = value! % 1 == 0
      ? value.toInt().toString()
      : value.toStringAsFixed(1);
  final withUnit = unitLabel == null ? formatted : '$formatted $unitLabel';

  final wasResolved =
      suggestion.status == AdaptiveSuggestionStatus.applied ||
      suggestion.status == AdaptiveSuggestionStatus.adjusted;
  return wasResolved
      ? 'Suggested target at the time: $withUnit'
      : 'Suggested target: $withUnit';
}

String _reduceQuantitativeTargetEvidence(AdaptiveHabitSuggestion suggestion) {
  final partialCount = _count(suggestion, 'partialProgressCount');
  final reachedCount = _count(suggestion, 'reachedCount');
  return 'You made partial progress on $partialCount scheduled days and '
      'reached the full target on $reachedCount days.';
}

String _changeScheduledTimeEvidence(AdaptiveHabitSuggestion suggestion) {
  return 'You marked yourself as too tired ${_count(suggestion, 'tooTiredCount')} times.';
}

String _reviewScheduleEvidence(AdaptiveHabitSuggestion suggestion) {
  return 'You marked that you had no time ${_count(suggestion, 'noTimeCount')} times.';
}

String _reduceFrequencyEvidence(AdaptiveHabitSuggestion suggestion) {
  return 'Low engagement was detected across three recent weeks.';
}
