import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_habit_coach/features/coach/domain/adaptive_suggestion.dart';
import 'package:smart_habit_coach/features/coach/presentation/adaptive_coach_card.dart';
import 'package:smart_habit_coach/features/home/domain/habit.dart';

final _now = DateTime(2026, 7, 2);
final _end = DateTime(2026, 7, 1);
final _start = _end.subtract(const Duration(days: 29));

Habit _habit({
  HabitTrackingType trackingType = HabitTrackingType.binary,
  double? targetValue,
}) {
  return Habit(
    id: 'h1',
    title: 'Read',
    scheduledTime: '08:00 AM',
    icon: Icons.book,
    trackingType: trackingType,
    targetValue: targetValue,
  );
}

AdaptiveHabitSuggestion _suggestion({
  required AdaptiveSuggestionType type,
  double? proposedTargetValue,
}) {
  return AdaptiveHabitSuggestion(
    id: 'h1-${type.name}',
    habitId: 'h1',
    type: type,
    createdAt: _now,
    analysisStart: _start,
    analysisEnd: _end,
    evidenceCode: 'x',
    proposedTargetValue: proposedTargetValue,
  );
}

void main() {
  testWidgets('shows Apply suggestion when onApply is provided', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdaptiveCoachCard(
            suggestion: _suggestion(
              type: AdaptiveSuggestionType.reduceQuantitativeTarget,
              proposedTargetValue: 5,
            ),
            habit: _habit(
              trackingType: HabitTrackingType.quantitative,
              targetValue: 10,
            ),
            onKeep: () {},
            onAdjust: () {},
            onApply: () {},
          ),
        ),
      ),
    );

    expect(find.text('Apply suggestion'), findsOneWidget);
    expect(find.text('Keep current plan'), findsOneWidget);
    expect(find.text('Adjust manually'), findsOneWidget);
  });

  testWidgets('omits Apply suggestion when onApply is null', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdaptiveCoachCard(
            suggestion: _suggestion(
              type: AdaptiveSuggestionType.addMinimumVersion,
            ),
            habit: _habit(),
            onKeep: () {},
            onAdjust: () {},
          ),
        ),
      ),
    );

    expect(find.text('Apply suggestion'), findsNothing);
    expect(find.text('Keep current plan'), findsOneWidget);
    expect(find.text('Adjust manually'), findsOneWidget);
  });
}
