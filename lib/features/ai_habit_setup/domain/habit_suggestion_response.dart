import '../../home/domain/habit_icons.dart';
import 'ai_habit_setup_exception.dart';
import 'habit_suggestion.dart';

const _genericParseError =
    "Couldn't understand the AI response. Please try again.";

final _scheduledTimePattern = RegExp(r'^([01]\d|2[0-3]):([0-5]\d)$');

/// Parses and validates the JSON payload returned by the `generate-habit`
/// edge function into a [HabitSuggestion].
///
/// Throws [AiHabitSetupException] if [rawResponse] doesn't match the
/// expected shape.
HabitSuggestion parseHabitSuggestionResponse(Object? rawResponse) {
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

  return HabitSuggestion(
    title: title.trim(),
    reason: reason.trim(),
    scheduledTime: _to12HourClock(scheduledTime),
    icon: habitIconFromId(iconId),
  );
}

/// Converts a 24-hour `HH:mm` time (as returned by the edge function) into
/// the `hh:mm AM/PM` format used elsewhere in the app.
String _to12HourClock(String twentyFourHour) {
  final match = _scheduledTimePattern.firstMatch(twentyFourHour)!;
  final hour24 = int.parse(match.group(1)!);
  final minute = match.group(2)!;
  final period = hour24 >= 12 ? 'PM' : 'AM';
  final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
  return '${hour12.toString().padLeft(2, '0')}:$minute $period';
}
