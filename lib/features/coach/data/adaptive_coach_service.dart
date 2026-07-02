import '../../home/domain/habit.dart';
import '../domain/adaptive_suggestion.dart';
import '../domain/adaptive_suggestion_detector.dart';
import '../domain/adaptive_suggestion_patterns.dart' show mondayOf;
import 'adaptive_suggestion_storage.dart';

/// A pending suggestion paired with the habit it refers to.
typedef PendingCoachSuggestion = ({
  AdaptiveHabitSuggestion suggestion,
  Habit habit,
});

/// Coordinates loading, generating, and updating Adaptive Coach suggestions
/// for Weekly Review. All detection stays local and deterministic (Phase 1);
/// this layer only adds persistence and habit-lookup around it.
///
/// Never throws: any storage or lookup failure results in no suggestion
/// being shown rather than a crash or a false success.
class AdaptiveCoachService {
  final AdaptiveSuggestionStorage _storage;

  AdaptiveCoachService({AdaptiveSuggestionStorage? storage})
    : _storage = storage ?? AdaptiveSuggestionStorage();

  /// Returns the single pending suggestion (and its habit) to show in
  /// Weekly Review, generating one if none exists yet for the current
  /// local week. Returns null when there is nothing to show.
  Future<PendingCoachSuggestion?> resolvePendingSuggestion({
    required List<Habit> habits,
    required DateTime now,
  }) async {
    try {
      final all = await _storage.loadSuggestions();
      final pending =
          _pendingForWeek(all, now) ?? await _maybeGenerate(all, habits, now);
      if (pending == null) return null;

      final habit = _findAvailableHabit(habits, pending.habitId);
      if (habit == null) {
        await _saveWithStatus(
          all,
          pending,
          AdaptiveSuggestionStatus.rejected,
          evidenceCode: 'habit_unavailable',
        );
        return null;
      }
      return (suggestion: pending, habit: habit);
    } catch (_) {
      return null;
    }
  }

  /// Persists [suggestion] with a new [status]. Returns true on success;
  /// false on any storage failure (caller should keep prior UI state).
  Future<bool> setStatus(
    AdaptiveHabitSuggestion suggestion,
    AdaptiveSuggestionStatus status,
  ) async {
    try {
      final all = await _storage.loadSuggestions();
      await _saveWithStatus(all, suggestion, status);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _saveWithStatus(
    List<AdaptiveHabitSuggestion> all,
    AdaptiveHabitSuggestion suggestion,
    AdaptiveSuggestionStatus status, {
    String? evidenceCode,
  }) async {
    final updated = suggestion.copyWith(
      status: status,
      evidenceCode: evidenceCode,
    );
    final index = all.indexWhere((s) => s.id == suggestion.id);
    final next = List<AdaptiveHabitSuggestion>.of(all);
    if (index >= 0) {
      next[index] = updated;
    } else {
      next.add(updated);
    }
    await _storage.saveSuggestions(next);
  }

  Future<AdaptiveHabitSuggestion?> _maybeGenerate(
    List<AdaptiveHabitSuggestion> all,
    List<Habit> habits,
    DateTime now,
  ) async {
    final detected = detectAdaptiveSuggestion(
      habits: habits,
      now: now,
      previousSuggestions: all,
    );
    if (detected == null) return null;
    await _storage.saveSuggestions([...all, detected]);
    return detected;
  }

  AdaptiveHabitSuggestion? _pendingForWeek(
    List<AdaptiveHabitSuggestion> all,
    DateTime now,
  ) {
    final weekStart = mondayOf(now);
    final weekEnd = weekStart.add(const Duration(days: 7));
    for (final s in all) {
      if (s.status != AdaptiveSuggestionStatus.pending) continue;
      final created = DateTime(
        s.createdAt.year,
        s.createdAt.month,
        s.createdAt.day,
      );
      if (!created.isBefore(weekStart) && created.isBefore(weekEnd)) {
        return s;
      }
    }
    return null;
  }

  Habit? _findAvailableHabit(List<Habit> habits, String habitId) {
    for (final h in habits) {
      if (h.id != habitId) continue;
      return h.status == HabitStatus.archived ? null : h;
    }
    return null;
  }
}
