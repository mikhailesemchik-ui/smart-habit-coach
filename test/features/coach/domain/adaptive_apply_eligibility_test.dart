import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_habit_coach/features/coach/domain/adaptive_apply_eligibility.dart';
import 'package:smart_habit_coach/features/coach/domain/adaptive_suggestion.dart';
import 'package:smart_habit_coach/features/home/domain/habit.dart';

final _now = DateTime(2026, 7, 2);
final _end = DateTime(2026, 7, 1);
final _start = _end.subtract(const Duration(days: 29));

Habit _quantHabit({
  double? targetValue = 10,
  String? unit = 'L',
  HabitStatus status = HabitStatus.active,
}) {
  return Habit(
    id: 'h1',
    title: 'Water',
    scheduledTime: '08:00 AM',
    icon: Icons.local_drink,
    trackingType: HabitTrackingType.quantitative,
    targetValue: targetValue,
    unit: unit,
    status: status,
  );
}

AdaptiveHabitSuggestion _validSuggestion({
  AdaptiveSuggestionType type = AdaptiveSuggestionType.reduceQuantitativeTarget,
  AdaptiveSuggestionStatus status = AdaptiveSuggestionStatus.pending,
  double? proposedTargetValue = 5.0,
  double? originalTargetValue = 10.0,
  String? originalUnit = 'L',
  Map<String, num> evidence = const {'hasUnitSnapshot': 1},
}) {
  return AdaptiveHabitSuggestion(
    id: 'h1-reduceQuantitativeTarget-2026-07-02',
    habitId: 'h1',
    type: type,
    status: status,
    createdAt: _now,
    analysisStart: _start,
    analysisEnd: _end,
    evidenceCode: 'repeated_target_too_difficult_reason',
    evidence: evidence,
    proposedTargetValue: proposedTargetValue,
    originalTargetValue: originalTargetValue,
    originalUnit: originalUnit,
  );
}

void main() {
  test('a fully valid suggestion is eligible', () {
    expect(
      evaluateApplyEligibility(
        suggestion: _validSuggestion(),
        habit: _quantHabit(),
      ),
      AdaptiveApplyEligibility.eligible,
    );
  });

  test('every non-reduceQuantitativeTarget type is unsupportedType', () {
    for (final type in AdaptiveSuggestionType.values) {
      if (type == AdaptiveSuggestionType.reduceQuantitativeTarget) continue;
      expect(
        evaluateApplyEligibility(
          suggestion: _validSuggestion(type: type),
          habit: _quantHabit(),
        ),
        AdaptiveApplyEligibility.unsupportedType,
        reason: 'type=$type',
      );
    }
  });

  test('a non-pending suggestion is notPending', () {
    for (final status in AdaptiveSuggestionStatus.values) {
      if (status == AdaptiveSuggestionStatus.pending) continue;
      expect(
        evaluateApplyEligibility(
          suggestion: _validSuggestion(status: status),
          habit: _quantHabit(),
        ),
        AdaptiveApplyEligibility.notPending,
      );
    }
  });

  test('a missing habit is missingHabit', () {
    expect(
      evaluateApplyEligibility(suggestion: _validSuggestion(), habit: null),
      AdaptiveApplyEligibility.missingHabit,
    );
  });

  test('an archived habit is missingHabit', () {
    expect(
      evaluateApplyEligibility(
        suggestion: _validSuggestion(),
        habit: _quantHabit(status: HabitStatus.archived),
      ),
      AdaptiveApplyEligibility.missingHabit,
    );
  });

  test('a binary habit is wrongHabitType', () {
    final habit = Habit(
      id: 'h1',
      title: 'Read',
      scheduledTime: '08:00 AM',
      icon: Icons.book,
    );
    expect(
      evaluateApplyEligibility(suggestion: _validSuggestion(), habit: habit),
      AdaptiveApplyEligibility.wrongHabitType,
    );
  });

  test(
    'a null/NaN/infinite/non-positive current target is invalidCurrentTarget',
    () {
      for (final target in [null, double.nan, double.infinity, 0.0, -1.0]) {
        expect(
          evaluateApplyEligibility(
            suggestion: _validSuggestion(originalTargetValue: target),
            habit: _quantHabit(targetValue: target),
          ),
          AdaptiveApplyEligibility.invalidCurrentTarget,
          reason: 'target=$target',
        );
      }
    },
  );

  test(
    'a null/NaN/infinite/non-positive proposal is invalidProposedTarget',
    () {
      for (final proposal in [null, double.nan, double.infinity, 0.0, -1.0]) {
        expect(
          evaluateApplyEligibility(
            suggestion: _validSuggestion(proposedTargetValue: proposal),
            habit: _quantHabit(),
          ),
          AdaptiveApplyEligibility.invalidProposedTarget,
          reason: 'proposal=$proposal',
        );
      }
    },
  );

  test('a proposal equal to the current target is proposalNotLower', () {
    expect(
      evaluateApplyEligibility(
        suggestion: _validSuggestion(proposedTargetValue: 10.0),
        habit: _quantHabit(targetValue: 10),
      ),
      AdaptiveApplyEligibility.proposalNotLower,
    );
  });

  test('a proposal above the current target is proposalNotLower', () {
    expect(
      evaluateApplyEligibility(
        suggestion: _validSuggestion(proposedTargetValue: 12.0),
        habit: _quantHabit(targetValue: 10),
      ),
      AdaptiveApplyEligibility.proposalNotLower,
    );
  });

  test('a proposal below the 50% floor is proposalBelowSafetyFloor', () {
    expect(
      evaluateApplyEligibility(
        suggestion: _validSuggestion(proposedTargetValue: 4.9),
        habit: _quantHabit(targetValue: 10),
      ),
      AdaptiveApplyEligibility.proposalBelowSafetyFloor,
    );
  });

  test('a suggestion without an originalTargetValue snapshot cannot apply', () {
    // Simulates an old, pre-Phase-3 stored suggestion.
    expect(
      evaluateApplyEligibility(
        suggestion: _validSuggestion(
          originalTargetValue: null,
          evidence: const {},
        ),
        habit: _quantHabit(),
      ),
      AdaptiveApplyEligibility.missingSnapshot,
    );
  });

  test('a suggestion without a unit-snapshot marker cannot apply', () {
    // originalTargetValue is present, but the evidence never recorded
    // that a unit snapshot was captured — also treated as incomplete.
    expect(
      evaluateApplyEligibility(
        suggestion: _validSuggestion(evidence: const {}),
        habit: _quantHabit(),
      ),
      AdaptiveApplyEligibility.missingSnapshot,
    );
  });

  test('a malformed unit-snapshot marker is malformedEvidence', () {
    expect(
      evaluateApplyEligibility(
        suggestion: _validSuggestion(evidence: const {'hasUnitSnapshot': 0}),
        habit: _quantHabit(),
      ),
      AdaptiveApplyEligibility.malformedEvidence,
    );
  });

  test('a changed current target makes the suggestion targetChanged', () {
    expect(
      evaluateApplyEligibility(
        suggestion: _validSuggestion(originalTargetValue: 10.0),
        habit: _quantHabit(targetValue: 8),
      ),
      AdaptiveApplyEligibility.targetChanged,
    );
  });

  test('a changed unit makes the suggestion unitChanged', () {
    expect(
      evaluateApplyEligibility(
        suggestion: _validSuggestion(originalUnit: 'L'),
        habit: _quantHabit(unit: 'min'),
      ),
      AdaptiveApplyEligibility.unitChanged,
    );
  });

  test('a habit that lost its unit makes the suggestion unitChanged', () {
    expect(
      evaluateApplyEligibility(
        suggestion: _validSuggestion(originalUnit: 'L'),
        habit: _quantHabit(unit: null),
      ),
      AdaptiveApplyEligibility.unitChanged,
    );
  });

  test('a habit that became non-quantitative is wrongHabitType (stale)', () {
    final habit = Habit(
      id: 'h1',
      title: 'Water',
      scheduledTime: '08:00 AM',
      icon: Icons.local_drink,
    );
    expect(
      evaluateApplyEligibility(suggestion: _validSuggestion(), habit: habit),
      AdaptiveApplyEligibility.wrongHabitType,
    );
  });
}
