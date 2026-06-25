import 'habit_suggestion.dart';

/// Abstraction over anything that can turn a free-form goal description
/// into a structured [HabitSuggestion]. Allows the real Supabase-backed
/// implementation to be swapped for a test double.
abstract class AiHabitSuggestionSource {
  Future<HabitSuggestion> generateSuggestion(String goal);
}
