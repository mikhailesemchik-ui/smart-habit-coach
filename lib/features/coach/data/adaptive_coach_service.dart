import '../../home/data/habit_storage.dart';
import '../../home/domain/habit.dart';
import '../domain/adaptive_apply_eligibility.dart';
import '../domain/adaptive_suggestion.dart';
import '../domain/adaptive_suggestion_detector.dart';
import '../domain/adaptive_suggestion_patterns.dart' show mondayOf;
import 'adaptive_suggestion_storage.dart';

/// A pending suggestion paired with the habit it refers to.
typedef PendingCoachSuggestion = ({
  AdaptiveHabitSuggestion suggestion,
  Habit habit,
});

/// Outcome states for [AdaptiveCoachService.applySuggestion]. Expected
/// (non-exceptional) results only — storage/validation failures are
/// reported here rather than thrown.
enum AdaptiveApplyResult {
  applied,
  stale,
  habitSaveFailed,
  suggestionSaveFailed,
  unsupported,
}

/// Result of a direct-apply attempt.
///
/// [habit] carries the up-to-date habit whenever the habit save itself
/// succeeded (i.e. for [AdaptiveApplyResult.applied] and
/// [AdaptiveApplyResult.suggestionSaveFailed]), so the caller can update
/// its in-memory state even on partial failure. [suggestion] is only set
/// for a fully successful apply.
class AdaptiveApplyOutcome {
  final AdaptiveApplyResult result;
  final Habit? habit;
  final AdaptiveHabitSuggestion? suggestion;

  const AdaptiveApplyOutcome({
    required this.result,
    this.habit,
    this.suggestion,
  });
}

/// Coordinates loading, generating, and updating Adaptive Coach suggestions
/// for Weekly Review. All detection stays local and deterministic (Phase 1);
/// this layer only adds persistence and habit-lookup around it.
///
/// Never throws: any storage or lookup failure results in no suggestion
/// being shown rather than a crash or a false success.
class AdaptiveCoachService {
  final AdaptiveSuggestionStorage _storage;
  final HabitStorage _habitStorage;

  AdaptiveCoachService({
    AdaptiveSuggestionStorage? storage,
    HabitStorage? habitStorage,
  }) : _storage = storage ?? AdaptiveSuggestionStorage(),
       _habitStorage = habitStorage ?? HabitStorage();

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
      await _saveWithStatus(suggestion, status);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Directly applies a fully-specified, still-eligible [suggestion] to
  /// [currentHabit] (Phase 3: only [AdaptiveSuggestionType
  /// .reduceQuantitativeTarget]). Re-validates eligibility against
  /// [currentHabit] before doing anything, then persists in order:
  /// habit first, suggestion status second — see [AdaptiveApplyResult] for
  /// what each partial-failure outcome means for the caller.
  Future<AdaptiveApplyOutcome> applySuggestion({
    required AdaptiveHabitSuggestion suggestion,
    required Habit currentHabit,
  }) async {
    final eligibility = evaluateApplyEligibility(
      suggestion: suggestion,
      habit: currentHabit,
    );
    if (eligibility != AdaptiveApplyEligibility.eligible) {
      if (suggestion.type != AdaptiveSuggestionType.reduceQuantitativeTarget) {
        return const AdaptiveApplyOutcome(
          result: AdaptiveApplyResult.unsupported,
        );
      }
      return AdaptiveApplyOutcome(
        result: AdaptiveApplyResult.stale,
        habit: currentHabit,
      );
    }

    final proposedHabit = currentHabit.copyWith(
      targetValue: suggestion.proposedTargetValue,
    );

    final savedHabit = await _saveHabit(proposedHabit);
    if (savedHabit == null) {
      return const AdaptiveApplyOutcome(
        result: AdaptiveApplyResult.habitSaveFailed,
      );
    }

    final statusSaved = await setStatus(
      suggestion,
      AdaptiveSuggestionStatus.applied,
    );
    if (!statusSaved) {
      // Partial success: the habit is already saved with the new target,
      // so re-evaluating eligibility against it will naturally return
      // targetChanged/proposalNotLower and hide Apply, preventing a
      // duplicate write without any extra flag.
      return AdaptiveApplyOutcome(
        result: AdaptiveApplyResult.suggestionSaveFailed,
        habit: savedHabit,
      );
    }

    return AdaptiveApplyOutcome(
      result: AdaptiveApplyResult.applied,
      habit: savedHabit,
      suggestion: suggestion.copyWith(status: AdaptiveSuggestionStatus.applied),
    );
  }

  /// Returns the actually-persisted (stamped) habit on success, so callers
  /// reflect real storage state rather than the pre-persist in-memory copy.
  Future<Habit?> _saveHabit(Habit habit) async {
    try {
      return await _habitStorage.upsertHabit(habit);
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveWithStatus(
    AdaptiveHabitSuggestion suggestion,
    AdaptiveSuggestionStatus status, {
    String? evidenceCode,
  }) async {
    final updated = suggestion.copyWith(
      status: status,
      evidenceCode: evidenceCode,
    );
    await _storage.upsertSuggestion(updated);
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
    await _storage.upsertSuggestion(detected);
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
