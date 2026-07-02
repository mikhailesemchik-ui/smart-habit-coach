import '../../home/domain/habit.dart';
import 'adaptive_suggestion.dart';

/// Structured reason a suggestion can or cannot be applied directly.
///
/// Only [eligible] means the direct Apply action may be shown/executed.
/// Every other value is a specific, testable reason it must not be.
enum AdaptiveApplyEligibility {
  eligible,
  unsupportedType,
  notPending,
  missingHabit,
  wrongHabitType,
  invalidCurrentTarget,
  invalidProposedTarget,
  proposalNotLower,
  proposalBelowSafetyFloor,
  missingSnapshot,
  targetChanged,
  unitChanged,
  malformedEvidence,
}

bool _isValidPositiveFinite(double? value) =>
    value != null && value.isFinite && !value.isNaN && value > 0;

/// Pure, deterministic eligibility check for directly applying [suggestion]
/// to [habit] (`null` when the habit could not be found/loaded).
///
/// This is the single source of truth for whether the "Apply suggestion"
/// action may be offered or executed — both the card (display) and the
/// apply flow (execution) must call this rather than duplicating checks.
AdaptiveApplyEligibility evaluateApplyEligibility({
  required AdaptiveHabitSuggestion suggestion,
  required Habit? habit,
}) {
  if (suggestion.type != AdaptiveSuggestionType.reduceQuantitativeTarget) {
    return AdaptiveApplyEligibility.unsupportedType;
  }
  if (suggestion.status != AdaptiveSuggestionStatus.pending) {
    return AdaptiveApplyEligibility.notPending;
  }
  if (habit == null || habit.status == HabitStatus.archived) {
    return AdaptiveApplyEligibility.missingHabit;
  }
  if (!habit.isQuantitative) {
    return AdaptiveApplyEligibility.wrongHabitType;
  }

  final currentTarget = habit.targetValue;
  if (!_isValidPositiveFinite(currentTarget)) {
    return AdaptiveApplyEligibility.invalidCurrentTarget;
  }

  final proposedTarget = suggestion.proposedTargetValue;
  if (!_isValidPositiveFinite(proposedTarget)) {
    return AdaptiveApplyEligibility.invalidProposedTarget;
  }

  if (proposedTarget! >= currentTarget!) {
    return AdaptiveApplyEligibility.proposalNotLower;
  }
  if (proposedTarget < currentTarget * 0.5) {
    return AdaptiveApplyEligibility.proposalBelowSafetyFloor;
  }

  // Snapshot presence: both the numeric target snapshot and an explicit
  // marker that a unit snapshot was captured must exist. Suggestions
  // created before Phase 3 have neither, and remain loadable but
  // ineligible for direct Apply.
  final originalTarget = suggestion.originalTargetValue;
  if (!_isValidPositiveFinite(originalTarget)) {
    return AdaptiveApplyEligibility.missingSnapshot;
  }
  final unitSnapshotMarker = suggestion.evidence['hasUnitSnapshot'];
  if (unitSnapshotMarker == null) {
    return AdaptiveApplyEligibility.missingSnapshot;
  }
  if (unitSnapshotMarker != 1) {
    return AdaptiveApplyEligibility.malformedEvidence;
  }

  if (currentTarget != originalTarget) {
    return AdaptiveApplyEligibility.targetChanged;
  }
  if (habit.unit != suggestion.originalUnit) {
    return AdaptiveApplyEligibility.unitChanged;
  }

  return AdaptiveApplyEligibility.eligible;
}

bool isApplyEligible({
  required AdaptiveHabitSuggestion suggestion,
  required Habit? habit,
}) =>
    evaluateApplyEligibility(suggestion: suggestion, habit: habit) ==
    AdaptiveApplyEligibility.eligible;
