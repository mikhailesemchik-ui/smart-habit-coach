/// User-facing failure when requesting or parsing an AI habit suggestion.
class AiHabitSetupException implements Exception {
  final String message;

  const AiHabitSetupException(this.message);

  @override
  String toString() => message;
}
