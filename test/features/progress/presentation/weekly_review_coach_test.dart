import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_habit_coach/features/coach/data/adaptive_coach_service.dart';
import 'package:smart_habit_coach/features/coach/data/adaptive_suggestion_storage.dart';
import 'package:smart_habit_coach/features/coach/domain/adaptive_suggestion.dart';
import 'package:smart_habit_coach/features/coach/presentation/adaptive_coach_card.dart';
import 'package:smart_habit_coach/features/home/data/habit_storage.dart';
import 'package:smart_habit_coach/features/home/domain/date_key.dart';
import 'package:smart_habit_coach/features/home/domain/habit.dart';
import 'package:smart_habit_coach/features/home/presentation/add_habit_sheet.dart';
import 'package:smart_habit_coach/features/progress/domain/ai_weekly_review.dart';
import 'package:smart_habit_coach/features/progress/domain/ai_weekly_review_source.dart';
import 'package:smart_habit_coach/features/progress/domain/weekly_review.dart';
import 'package:smart_habit_coach/features/progress/presentation/weekly_review_sheet.dart';

// Anchored to the real clock (not a fixed calendar date): the production
// detector (`detectAdaptiveSuggestion`) always windows off `DateTime.now()`
// (see WeeklyReviewSheet's `now: DateTime.now()`), so seeded evidence must
// stay within `_windowDays` of whenever the suite actually runs rather than
// drifting out of range relative to a hardcoded past date.
final _now = DateTime.now();
final _end = _now.subtract(const Duration(days: 1));

List<DateTime> _lastDays(int count) =>
    List.generate(count, (i) => _end.subtract(Duration(days: i)));

List<DateTime> _spread(int count, {int span = 20}) {
  final days = _lastDays(span);
  if (count <= 1) return [days.last];
  final step = (days.length - 1) / (count - 1);
  return List.generate(count, (i) => days[(i * step).round()]);
}

Habit _habitWithEvidence() {
  final reasonDates = _spread(3);
  final reasonKeys = reasonDates.map(dateKey).toSet();
  final completed = _lastDays(
    35,
  ).map(dateKey).where((k) => !reasonKeys.contains(k)).toSet();
  return Habit(
    id: 'h1',
    title: 'Read',
    scheduledTime: '08:00 AM',
    icon: Icons.book,
    weekdays: const [1, 2, 3, 4, 5, 6, 7],
    completedDates: completed,
    skipReasons: {
      for (final d in reasonDates) dateKey(d): HabitSkipReason.tooDifficult,
    },
  );
}

Habit _quantitativeHabitWithEvidence() {
  final progressDays = _spread(10, span: 25);
  final reasonDays = _spread(3, span: 25);
  final reasonKeys = reasonDays.map(dateKey).toSet();
  final progressKeys = progressDays.map(dateKey).toSet();
  final filler = _lastDays(35)
      .map(dateKey)
      .where((k) => !reasonKeys.contains(k) && !progressKeys.contains(k))
      .toSet();
  return Habit(
    id: 'h1',
    title: 'Water',
    scheduledTime: '08:00 AM',
    icon: Icons.local_drink,
    weekdays: const [1, 2, 3, 4, 5, 6, 7],
    trackingType: HabitTrackingType.quantitative,
    targetValue: 10,
    unit: 'L',
    completedDates: filler,
    quantitativeProgress: {for (final d in progressDays) dateKey(d): 5.0},
    partialReasons: {
      for (final d in reasonDays)
        dateKey(d): HabitPartialReason.targetTooDifficult,
    },
  );
}

const _metrics = WeeklyReviewMetrics(
  completionRate: 0.5,
  currentStreak: 1,
  bestStreak: 2,
  strongestDay: null,
  weakestDay: null,
  completedCount: 1,
  minimumCompletedCount: 0,
  totalPossibleCount: 2,
);

const _localReview = WeeklyReview();

class _FakeAiSource implements AiWeeklyReviewSource {
  final AiWeeklyReview? review;
  final Object? error;
  const _FakeAiSource.success(this.review) : error = null;
  const _FakeAiSource.failure(this.error) : review = null;

  @override
  Future<AiWeeklyReview> generateReview(WeeklyReviewMetrics metrics) async {
    if (error != null) throw error!;
    return review!;
  }
}

Widget _harness({
  required List<Habit> habits,
  AiWeeklyReviewSource? service,
  AdaptiveCoachService? coachService,
  HabitStorage? habitStorage,
  ValueChanged<Habit>? onHabitUpdated,
}) {
  return MaterialApp(
    home: Scaffold(
      body: WeeklyReviewSheet(
        localReview: _localReview,
        metrics: _metrics,
        habits: habits,
        service: service ?? const _FakeAiSource.success(AiWeeklyReview()),
        coachService: coachService,
        habitStorage: habitStorage,
        onHabitUpdated: onHabitUpdated,
      ),
    ),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('no detected suggestion means no coach card', (tester) async {
    await tester.pumpWidget(_harness(habits: const []));
    await tester.pumpAndSettle();
    expect(find.byType(AdaptiveCoachCard), findsNothing);
  });

  testWidgets('a detected suggestion is persisted pending and shown', (
    tester,
  ) async {
    final habit = _habitWithEvidence();
    await tester.pumpWidget(_harness(habits: [habit]));
    await tester.pumpAndSettle();

    expect(find.byType(AdaptiveCoachCard), findsOneWidget);
    expect(find.text('Adaptive Coach'), findsOneWidget);
    expect(find.text('Based on your recent habit history'), findsOneWidget);

    final stored = await AdaptiveSuggestionStorage().loadSuggestions();
    expect(stored, hasLength(1));
    expect(stored.first.status, AdaptiveSuggestionStatus.pending);
  });

  testWidgets(
    'Keep current plan marks kept, removes the card, does not mutate the habit',
    (tester) async {
      final habit = _habitWithEvidence();
      final habitStorage = HabitStorage();
      await habitStorage.saveHabits([habit]);

      await tester.pumpWidget(
        _harness(habits: [habit], habitStorage: habitStorage),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Keep current plan'));
      // Let the async status update settle, then let the SnackBar's entry
      // animation complete without advancing past its display timer.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(AdaptiveCoachCard), findsNothing);
      expect(find.text('Current plan kept'), findsOneWidget);

      final stored = await AdaptiveSuggestionStorage().loadSuggestions();
      expect(stored.single.status, AdaptiveSuggestionStatus.kept);

      final habits = await habitStorage.loadHabits();
      expect(habits!.single.skipReasons, habit.skipReasons);
      expect(habits.single.minimumVersion, habit.minimumVersion);
    },
  );

  testWidgets(
    'Adjust manually opens the existing edit flow; cancel keeps the suggestion pending',
    (tester) async {
      final habit = _habitWithEvidence();
      final habitStorage = HabitStorage();
      await habitStorage.saveHabits([habit]);

      await tester.pumpWidget(
        _harness(habits: [habit], habitStorage: habitStorage),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Adjust manually'));
      await tester.pumpAndSettle();
      expect(find.byType(AddHabitSheet), findsOneWidget);

      // Cancel by popping the sheet without a result.
      Navigator.of(tester.element(find.byType(AddHabitSheet))).pop();
      await tester.pumpAndSettle();

      expect(find.byType(AdaptiveCoachCard), findsOneWidget);
      final stored = await AdaptiveSuggestionStorage().loadSuggestions();
      expect(stored.single.status, AdaptiveSuggestionStatus.pending);
    },
  );

  testWidgets(
    'a successful edit marks the suggestion adjusted and removes the card',
    (tester) async {
      final habit = _habitWithEvidence();
      final habitStorage = HabitStorage();
      await habitStorage.saveHabits([habit]);

      await tester.pumpWidget(
        _harness(habits: [habit], habitStorage: habitStorage),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Adjust manually'));
      await tester.pumpAndSettle();

      final saveButton = find.widgetWithText(FilledButton, 'Save');
      await tester.ensureVisible(saveButton);
      await tester.pump();
      await tester.tap(saveButton);
      await tester.pumpAndSettle();

      expect(find.byType(AdaptiveCoachCard), findsNothing);
      expect(find.text('Habit plan updated'), findsOneWidget);

      final stored = await AdaptiveSuggestionStorage().loadSuggestions();
      expect(stored.single.status, AdaptiveSuggestionStatus.adjusted);
    },
  );

  testWidgets(
    'Apply suggestion is offered for reduceQuantitativeTarget and updates the target directly',
    (tester) async {
      final habit = _quantitativeHabitWithEvidence();
      final habitStorage = HabitStorage();
      await habitStorage.saveHabits([habit]);
      Habit? reportedHabit;

      await tester.pumpWidget(
        _harness(
          habits: [habit],
          habitStorage: habitStorage,
          onHabitUpdated: (h) => reportedHabit = h,
        ),
      );
      await tester.pumpAndSettle();

      final applyButton = find.text('Apply suggestion');
      await tester.ensureVisible(applyButton);
      await tester.pump();
      await tester.tap(applyButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(AdaptiveCoachCard), findsNothing);
      expect(find.text('Suggested target applied'), findsOneWidget);

      final stored = await AdaptiveSuggestionStorage().loadSuggestions();
      expect(stored.single.status, AdaptiveSuggestionStatus.applied);

      final habits = await habitStorage.loadHabits();
      expect(habits!.single.targetValue, 5.0);
      // Unrelated fields survive untouched.
      expect(habits.single.quantitativeProgress, habit.quantitativeProgress);
      expect(habits.single.unit, habit.unit);

      // ProgressScreen-style state propagation happens immediately.
      expect(reportedHabit, isNotNull);
      expect(reportedHabit!.targetValue, 5.0);
    },
  );

  testWidgets(
    'double-tapping Apply suggestion causes only one apply operation',
    (tester) async {
      final habit = _quantitativeHabitWithEvidence();
      final habitStorage = HabitStorage();
      await habitStorage.saveHabits([habit]);
      var updateCount = 0;

      await tester.pumpWidget(
        _harness(
          habits: [habit],
          habitStorage: habitStorage,
          onHabitUpdated: (_) => updateCount++,
        ),
      );
      await tester.pumpAndSettle();

      final applyButton = find.text('Apply suggestion');
      await tester.ensureVisible(applyButton);
      await tester.pump();
      // Two rapid taps before the first async apply completes.
      await tester.tap(applyButton);
      await tester.tap(applyButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(updateCount, 1);
      final stored = await AdaptiveSuggestionStorage().loadSuggestions();
      expect(stored, hasLength(1));
      expect(stored.single.status, AdaptiveSuggestionStatus.applied);
    },
  );

  testWidgets(
    'a successful Adjust manually edit also propagates the habit immediately',
    (tester) async {
      final habit = _habitWithEvidence();
      final habitStorage = HabitStorage();
      await habitStorage.saveHabits([habit]);
      Habit? reportedHabit;

      await tester.pumpWidget(
        _harness(
          habits: [habit],
          habitStorage: habitStorage,
          onHabitUpdated: (h) => reportedHabit = h,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Adjust manually'));
      await tester.pumpAndSettle();

      final saveButton = find.widgetWithText(FilledButton, 'Save');
      await tester.ensureVisible(saveButton);
      await tester.pump();
      await tester.tap(saveButton);
      await tester.pumpAndSettle();

      expect(reportedHabit, isNotNull);
      expect(reportedHabit!.id, habit.id);
    },
  );

  testWidgets(
    'Apply suggestion is not offered for suggestion types other than reduceQuantitativeTarget',
    (tester) async {
      final habit = _habitWithEvidence();
      await tester.pumpWidget(_harness(habits: [habit]));
      await tester.pumpAndSettle();

      expect(find.byType(AdaptiveCoachCard), findsOneWidget);
      expect(find.text('Apply suggestion'), findsNothing);
      expect(find.text('Keep current plan'), findsOneWidget);
      expect(find.text('Adjust manually'), findsOneWidget);
    },
  );

  testWidgets('a missing habit does not crash and does not display a card', (
    tester,
  ) async {
    final storage = AdaptiveSuggestionStorage();
    await storage.saveSuggestions([
      AdaptiveHabitSuggestion(
        id: 'orphan',
        habitId: 'gone',
        type: AdaptiveSuggestionType.addMinimumVersion,
        createdAt: _now,
        analysisStart: _now.subtract(const Duration(days: 30)),
        analysisEnd: _end,
        evidenceCode: 'repeated_too_difficult',
      ),
    ]);

    await tester.pumpWidget(_harness(habits: const []));
    await tester.pumpAndSettle();

    expect(find.byType(AdaptiveCoachCard), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'AI review failure does not prevent the local coach card from showing',
    (tester) async {
      final habit = _habitWithEvidence();
      await tester.pumpWidget(
        _harness(habits: [habit], service: const _FakeAiSource.failure('boom')),
      );
      await tester.pumpAndSettle();

      expect(find.byType(AdaptiveCoachCard), findsOneWidget);
      // The AI fallback notice is shown independently; it must not block
      // or be confused with the coach card.
      expect(
        find.textContaining("Showing your local weekly review"),
        findsOneWidget,
      );
    },
  );

  testWidgets('Weekly Review Retry does not create a second suggestion', (
    tester,
  ) async {
    final habit = _habitWithEvidence();
    await tester.pumpWidget(
      _harness(habits: [habit], service: const _FakeAiSource.failure('boom')),
    );
    await tester.pumpAndSettle();

    final firstStored = await AdaptiveSuggestionStorage().loadSuggestions();
    expect(firstStored, hasLength(1));

    final retryButton = find.text('Retry');
    await tester.ensureVisible(retryButton);
    await tester.pump();
    await tester.tap(retryButton);
    await tester.pumpAndSettle();

    final secondStored = await AdaptiveSuggestionStorage().loadSuggestions();
    expect(secondStored, hasLength(1));
    expect(secondStored.first.id, firstStored.first.id);
  });
}
