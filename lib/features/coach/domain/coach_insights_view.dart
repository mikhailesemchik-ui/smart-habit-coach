import '../../home/domain/habit.dart';
import 'adaptive_suggestion.dart';

const _fallbackHabitTitle = 'Habit no longer available';

/// Resolves the best available display title for [suggestion]'s habit.
///
/// Priority: 1) the current habit's title if it still exists (including
/// archived — a habit only becomes fully unresolvable once deleted),
/// 2) the title snapshot recorded when the suggestion was created,
/// 3) a neutral fallback. Never mutates the suggestion or the habit list.
String resolveHabitDisplayTitle(
  AdaptiveHabitSuggestion suggestion,
  List<Habit> habits,
) {
  for (final habit in habits) {
    if (habit.id == suggestion.habitId) return habit.title;
  }
  final snapshot = suggestion.habitTitleSnapshot;
  if (snapshot != null && snapshot.trim().isNotEmpty) return snapshot;
  return _fallbackHabitTitle;
}

/// True when [suggestion]'s habit could not be resolved by id at all (not
/// even a snapshot title survives) — used only for display, never to
/// mutate or drop the record.
bool isHabitUnavailableForDisplay(
  AdaptiveHabitSuggestion suggestion,
  List<Habit> habits,
) => resolveHabitDisplayTitle(suggestion, habits) == _fallbackHabitTitle;

/// Display order for Coach Insights status groups.
const List<AdaptiveSuggestionStatus> coachInsightsStatusOrder = [
  AdaptiveSuggestionStatus.pending,
  AdaptiveSuggestionStatus.applied,
  AdaptiveSuggestionStatus.adjusted,
  AdaptiveSuggestionStatus.kept,
  AdaptiveSuggestionStatus.rejected,
];

/// One non-empty status section, sorted newest-first.
class CoachInsightsGroup {
  final AdaptiveSuggestionStatus status;
  final List<AdaptiveHabitSuggestion> suggestions;

  const CoachInsightsGroup({required this.status, required this.suggestions});
}

/// Groups [suggestions] by status in [coachInsightsStatusOrder], each
/// sorted by createdAt descending. Empty groups are omitted entirely.
/// Pure: never touches storage or mutates its input.
List<CoachInsightsGroup> groupSuggestionsForInsights(
  List<AdaptiveHabitSuggestion> suggestions,
) {
  final groups = <CoachInsightsGroup>[];
  for (final status in coachInsightsStatusOrder) {
    final matching = suggestions.where((s) => s.status == status).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (matching.isEmpty) continue;
    groups.add(CoachInsightsGroup(status: status, suggestions: matching));
  }
  return groups;
}
