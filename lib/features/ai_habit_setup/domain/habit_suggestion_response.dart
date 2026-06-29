import '../../home/domain/habit_icons.dart';
import 'ai_habit_setup_exception.dart';
import 'frequency_parser.dart';
import 'habit_suggestion.dart';

const _genericParseError =
    "Couldn't understand the AI response. Please try again.";

final _scheduledTimePattern = RegExp(r'^([01]\d|2[0-3]):([0-5]\d)$');

/// Parses the JSON payload from the `generate-habit` edge function into a
/// [HabitSuggestion]. [goalHint] is the original user prompt; it is used as a
/// deterministic fallback to extract a frequency count when the AI omits it.
///
/// Throws [AiHabitSetupException] when required fields are missing or invalid.
HabitSuggestion parseHabitSuggestionResponse(
  Object? rawResponse, {
  String goalHint = '',
}) {
  if (rawResponse is! Map) {
    throw const AiHabitSetupException(_genericParseError);
  }

  final title = rawResponse['title'];
  final reason = rawResponse['reason'];
  final scheduledTime = rawResponse['scheduledTime'];
  final iconId = rawResponse['iconId'];

  if (title is! String || title.trim().isEmpty) {
    throw const AiHabitSetupException(_genericParseError);
  }
  if (reason is! String || reason.trim().isEmpty) {
    throw const AiHabitSetupException(_genericParseError);
  }
  if (scheduledTime is! String ||
      !_scheduledTimePattern.hasMatch(scheduledTime)) {
    throw const AiHabitSetupException(_genericParseError);
  }
  if (iconId is! String || !habitIconOptions.containsKey(iconId)) {
    throw const AiHabitSetupException(_genericParseError);
  }

  final requiredDaysPerWeek = _readRequiredDays(
    rawResponse['requiredDaysPerWeek'],
    goalHint: goalHint,
  );

  // When a frequency count is present, keep any partial explicit days as-is
  // (may be empty) so the user can complete the selection.
  // When no count is present, normalize weekdays and fall back to all 7.
  final List<int> weekdays;
  if (requiredDaysPerWeek != null) {
    weekdays = _readWeekdays(rawResponse['weekdays'], allowEmpty: true);
  } else {
    weekdays = _readWeekdays(rawResponse['weekdays']);
  }

  return HabitSuggestion(
    title: title.trim(),
    reason: reason.trim(),
    scheduledTime: _to12HourClock(scheduledTime),
    icon: habitIconFromId(iconId),
    weekdays: weekdays,
    requiredDaysPerWeek: requiredDaysPerWeek,
    minimumVersion: _readOptionalString(rawResponse['minimumVersion']),
  );
}

String? _readOptionalString(Object? raw) {
  if (raw is! String) return null;
  final s = raw.trim();
  return s.isEmpty ? null : s;
}

int? _readRequiredDays(Object? raw, {required String goalHint}) {
  // AI-returned value takes priority.
  final n = raw is int ? raw : (raw is double ? raw.round() : null);
  if (n != null && n >= 1 && n <= 7) return n;
  // Deterministic local fallback from the original prompt.
  return parseFrequencyFromGoal(goalHint);
}

List<int> _readWeekdays(Object? raw, {bool allowEmpty = false}) {
  if (raw is! List) return allowEmpty ? const [] : const [1, 2, 3, 4, 5, 6, 7];
  final days =
      raw.whereType<int>().where((d) => d >= 1 && d <= 7).toSet().toList()
        ..sort();
  if (days.isNotEmpty) return days;
  return allowEmpty ? const [] : const [1, 2, 3, 4, 5, 6, 7];
}

String _to12HourClock(String twentyFourHour) {
  final match = _scheduledTimePattern.firstMatch(twentyFourHour)!;
  final hour24 = int.parse(match.group(1)!);
  final minute = match.group(2)!;
  final period = hour24 >= 12 ? 'PM' : 'AM';
  final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
  return '${hour12.toString().padLeft(2, '0')}:$minute $period';
}
