import '../../home/data/habit_storage.dart';
import '../../home/domain/habit.dart';
import '../domain/adaptive_suggestion.dart';
import 'adaptive_suggestion_storage.dart';

/// Result of loading data for the read-only Coach Insights screen.
class CoachInsightsLoadResult {
  final List<AdaptiveHabitSuggestion> suggestions;
  final List<Habit> habits;
  final bool hasError;

  const CoachInsightsLoadResult({
    required this.suggestions,
    required this.habits,
    required this.hasError,
  });
}

/// Loads suggestion history and current habits for Coach Insights.
///
/// Read-only: never writes to storage, never changes a suggestion's
/// status, and never crashes — any storage failure is reported through
/// [CoachInsightsLoadResult.hasError] instead of throwing.
class CoachInsightsService {
  final AdaptiveSuggestionStorage _suggestionStorage;
  final HabitStorage _habitStorage;

  CoachInsightsService({
    AdaptiveSuggestionStorage? suggestionStorage,
    HabitStorage? habitStorage,
  }) : _suggestionStorage = suggestionStorage ?? AdaptiveSuggestionStorage(),
       _habitStorage = habitStorage ?? HabitStorage();

  Future<CoachInsightsLoadResult> load() async {
    try {
      final suggestions = await _suggestionStorage.loadSuggestions();
      final habits = await _habitStorage.loadHabits() ?? const [];
      return CoachInsightsLoadResult(
        suggestions: suggestions,
        habits: habits,
        hasError: false,
      );
    } catch (_) {
      return const CoachInsightsLoadResult(
        suggestions: [],
        habits: [],
        hasError: true,
      );
    }
  }
}
