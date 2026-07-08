import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_habit_coach/features/coach/data/adaptive_coach_service.dart';
import 'package:smart_habit_coach/features/coach/data/adaptive_suggestion_storage.dart';
import 'package:smart_habit_coach/features/coach/domain/adaptive_suggestion.dart';
import 'package:smart_habit_coach/features/home/data/habit_storage.dart';
import 'package:smart_habit_coach/features/home/domain/date_key.dart';
import 'package:smart_habit_coach/features/home/domain/habit.dart';

import '../../../support/test_namespace.dart';

const _suggestionsKey = 'adaptive_suggestions:$testNamespaceUid';

final _now = DateTime(2026, 7, 2);
final _end = DateTime(2026, 7, 1);

List<DateTime> _lastDays(int count) =>
    List.generate(count, (i) => _end.subtract(Duration(days: i)));

List<DateTime> _spread(int count, {int span = 20}) {
  final days = _lastDays(span);
  if (count <= 1) return [days.last];
  final step = (days.length - 1) / (count - 1);
  return List.generate(count, (i) => days[(i * step).round()]);
}

Habit _habitWithEvidence({String id = 'h1', bool fillEngagement = true}) {
  final reasonDates = _spread(3);
  final reasonKeys = reasonDates.map(dateKey).toSet();
  final completed = fillEngagement
      ? _lastDays(35).map(dateKey).where((k) => !reasonKeys.contains(k)).toSet()
      : <String>{};
  return Habit(
    id: id,
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

class _ThrowingStorage extends AdaptiveSuggestionStorage {
  @override
  Future<List<AdaptiveHabitSuggestion>> loadSuggestions() =>
      Future.error(StateError('storage unavailable'));

  @override
  Future<void> saveSuggestions(List<AdaptiveHabitSuggestion> suggestions) =>
      Future.error(StateError('storage unavailable'));
}

class _ThrowingHabitStorage extends HabitStorage {
  @override
  Future<List<Habit>?> loadHabits() =>
      Future.error(StateError('habit storage unavailable'));

  @override
  Future<void> saveHabits(List<Habit> habits) =>
      Future.error(StateError('habit storage unavailable'));
}

Habit _quantitativeHabitWithEvidence({String id = 'h1'}) {
  final progressDays = _spread(10, span: 25);
  final reasonDays = _spread(3, span: 25);
  final reasonKeys = reasonDays.map(dateKey).toSet();
  final progressKeys = progressDays.map(dateKey).toSet();
  final filler = _lastDays(35)
      .map(dateKey)
      .where((k) => !reasonKeys.contains(k) && !progressKeys.contains(k))
      .toSet();
  return Habit(
    id: id,
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
    // Non-empty, unrelated fields to verify they survive an Apply
    // untouched (only targetValue should change).
    minimumVersion: 'Drink half a glass',
    completionNotes: {'2026-06-01': 'Felt great'},
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'no detected suggestion means resolvePendingSuggestion returns null',
    () async {
      final service = AdaptiveCoachService();
      final result = await service.resolvePendingSuggestion(
        habits: const [],
        now: _now,
      );
      expect(result, isNull);
    },
  );

  test('a detected suggestion is persisted pending and returned', () async {
    final service = AdaptiveCoachService();
    final habit = _habitWithEvidence();
    final result = await service.resolvePendingSuggestion(
      habits: [habit],
      now: _now,
    );
    expect(result, isNotNull);
    expect(result!.suggestion.status, AdaptiveSuggestionStatus.pending);
    expect(result.habit.id, habit.id);

    final stored = await AdaptiveSuggestionStorage().loadSuggestions();
    expect(stored, hasLength(1));
    expect(stored.first.status, AdaptiveSuggestionStatus.pending);
  });

  test(
    'reopening (a fresh service instance) shows the same pending suggestion',
    () async {
      final habit = _habitWithEvidence();
      final first = await AdaptiveCoachService().resolvePendingSuggestion(
        habits: [habit],
        now: _now,
      );
      final second = await AdaptiveCoachService().resolvePendingSuggestion(
        habits: [habit],
        now: _now,
      );
      expect(second!.suggestion.id, first!.suggestion.id);
    },
  );

  test('rebuild/retry does not duplicate the pending suggestion', () async {
    final habit = _habitWithEvidence();
    final service = AdaptiveCoachService();
    await service.resolvePendingSuggestion(habits: [habit], now: _now);
    await service.resolvePendingSuggestion(habits: [habit], now: _now);
    await service.resolvePendingSuggestion(habits: [habit], now: _now);

    final stored = await AdaptiveSuggestionStorage().loadSuggestions();
    expect(stored, hasLength(1));
  });

  test(
    'only one suggestion is created during the local week across habits',
    () async {
      final habitA = _habitWithEvidence(id: 'a');
      final habitB = _habitWithEvidence(id: 'b');
      final service = AdaptiveCoachService();
      await service.resolvePendingSuggestion(
        habits: [habitA, habitB],
        now: _now,
      );
      // A later call in the same week (even after handling) must not add one.
      await service.setStatus(
        (await AdaptiveSuggestionStorage().loadSuggestions()).first,
        AdaptiveSuggestionStatus.kept,
      );
      await service.resolvePendingSuggestion(
        habits: [habitA, habitB],
        now: _now,
      );

      final stored = await AdaptiveSuggestionStorage().loadSuggestions();
      expect(stored, hasLength(1));
    },
  );

  test(
    'a missing habit is not shown and is marked rejected as habit_unavailable',
    () async {
      final storage = AdaptiveSuggestionStorage();
      final orphan = AdaptiveHabitSuggestion(
        id: 'orphan-1',
        habitId: 'does-not-exist',
        type: AdaptiveSuggestionType.addMinimumVersion,
        createdAt: _now,
        analysisStart: _now.subtract(const Duration(days: 30)),
        analysisEnd: _end,
        evidenceCode: 'repeated_too_difficult',
      );
      await storage.saveSuggestions([orphan]);

      final result = await AdaptiveCoachService().resolvePendingSuggestion(
        habits: const [],
        now: _now,
      );
      expect(result, isNull);

      final stored = await storage.loadSuggestions();
      expect(stored.single.status, AdaptiveSuggestionStatus.rejected);
      expect(stored.single.evidenceCode, 'habit_unavailable');
    },
  );

  test('an archived habit is treated as unavailable', () async {
    final habit = _habitWithEvidence().copyWith(status: HabitStatus.archived);
    final storage = AdaptiveSuggestionStorage();
    final suggestion = AdaptiveHabitSuggestion(
      id: 's-1',
      habitId: habit.id,
      type: AdaptiveSuggestionType.addMinimumVersion,
      createdAt: _now,
      analysisStart: _now.subtract(const Duration(days: 30)),
      analysisEnd: _end,
      evidenceCode: 'repeated_too_difficult',
    );
    await storage.saveSuggestions([suggestion]);

    final result = await AdaptiveCoachService().resolvePendingSuggestion(
      habits: [habit],
      now: _now,
    );
    expect(result, isNull);
  });

  test(
    'malformed stored suggestions are ignored, valid ones still work',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _suggestionsKey,
        jsonEncode([
          {'id': 'broken'}, // missing required fields
          'not even a map',
        ]),
      );

      final habit = _habitWithEvidence();
      final result = await AdaptiveCoachService().resolvePendingSuggestion(
        habits: [habit],
        now: _now,
      );
      expect(result, isNotNull);
    },
  );

  test(
    'storage failure leaves the service usable (returns null, no throw)',
    () async {
      final service = AdaptiveCoachService(storage: _ThrowingStorage());
      final habit = _habitWithEvidence();
      final result = await service.resolvePendingSuggestion(
        habits: [habit],
        now: _now,
      );
      expect(result, isNull);

      final statusOk = await service.setStatus(
        AdaptiveHabitSuggestion(
          id: 'x',
          habitId: habit.id,
          type: AdaptiveSuggestionType.addMinimumVersion,
          createdAt: _now,
          analysisStart: _now.subtract(const Duration(days: 30)),
          analysisEnd: _end,
          evidenceCode: 'repeated_too_difficult',
        ),
        AdaptiveSuggestionStatus.kept,
      );
      expect(statusOk, isFalse);
    },
  );

  group('applySuggestion', () {
    test(
      'a successful apply changes only the target and marks applied',
      () async {
        final habit = _quantitativeHabitWithEvidence();
        final habitStorage = HabitStorage();
        await habitStorage.saveHabits([habit]);
        final service = AdaptiveCoachService(habitStorage: habitStorage);

        final pending = await service.resolvePendingSuggestion(
          habits: [habit],
          now: _now,
        );
        expect(pending, isNotNull);

        final outcome = await service.applySuggestion(
          suggestion: pending!.suggestion,
          currentHabit: pending.habit,
        );

        expect(outcome.result, AdaptiveApplyResult.applied);
        expect(outcome.habit!.targetValue, 5.0);
        expect(outcome.suggestion!.status, AdaptiveSuggestionStatus.applied);

        // Only targetValue changed; everything else is preserved exactly.
        expect(outcome.habit!.id, habit.id);
        expect(outcome.habit!.title, habit.title);
        expect(outcome.habit!.unit, habit.unit);
        expect(outcome.habit!.scheduledTime, habit.scheduledTime);
        expect(outcome.habit!.weekdays, habit.weekdays);
        expect(outcome.habit!.quantitativeProgress, habit.quantitativeProgress);
        expect(outcome.habit!.partialReasons, habit.partialReasons);
        expect(outcome.habit!.completionNotes, habit.completionNotes);
        expect(outcome.habit!.minimumVersion, habit.minimumVersion);
        expect(outcome.habit!.status, habit.status);

        final storedHabits = await habitStorage.loadHabits();
        expect(storedHabits!.single.targetValue, 5.0);
        final storedSuggestions = await AdaptiveSuggestionStorage()
            .loadSuggestions();
        expect(
          storedSuggestions.single.status,
          AdaptiveSuggestionStatus.applied,
        );
      },
    );

    test(
      'an ineligible suggestion returns stale without mutating anything',
      () async {
        final habit = _quantitativeHabitWithEvidence();
        final habitStorage = HabitStorage();
        await habitStorage.saveHabits([habit]);
        final service = AdaptiveCoachService(habitStorage: habitStorage);

        final pending = await service.resolvePendingSuggestion(
          habits: [habit],
          now: _now,
        );
        // Simulate the habit's target having already changed elsewhere.
        final changedHabit = habit.copyWith(targetValue: 3.0);

        final outcome = await service.applySuggestion(
          suggestion: pending!.suggestion,
          currentHabit: changedHabit,
        );

        expect(outcome.result, AdaptiveApplyResult.stale);
        // Nothing was ever written: the stored habit still has its original
        // (unchanged) target — the in-memory `changedHabit` used to trigger
        // staleness was never persisted.
        final storedHabits = await habitStorage.loadHabits();
        expect(storedHabits!.single.targetValue, 10.0);
        final storedSuggestions = await AdaptiveSuggestionStorage()
            .loadSuggestions();
        expect(
          storedSuggestions.single.status,
          AdaptiveSuggestionStatus.pending,
        );
      },
    );

    test('a non-quantitative-target suggestion returns unsupported', () async {
      final habit = _habitWithEvidence();
      final suggestion = AdaptiveHabitSuggestion(
        id: 'x',
        habitId: habit.id,
        type: AdaptiveSuggestionType.addMinimumVersion,
        createdAt: _now,
        analysisStart: _now.subtract(const Duration(days: 30)),
        analysisEnd: _end,
        evidenceCode: 'repeated_too_difficult',
      );
      final outcome = await AdaptiveCoachService().applySuggestion(
        suggestion: suggestion,
        currentHabit: habit,
      );
      expect(outcome.result, AdaptiveApplyResult.unsupported);
    });

    test(
      'habit save failure leaves the suggestion pending and reports habitSaveFailed',
      () async {
        final habit = _quantitativeHabitWithEvidence();
        final readService = AdaptiveCoachService();
        final pending = await readService.resolvePendingSuggestion(
          habits: [habit],
          now: _now,
        );

        final failingService = AdaptiveCoachService(
          habitStorage: _ThrowingHabitStorage(),
        );
        final outcome = await failingService.applySuggestion(
          suggestion: pending!.suggestion,
          currentHabit: pending.habit,
        );

        expect(outcome.result, AdaptiveApplyResult.habitSaveFailed);
        final storedSuggestions = await AdaptiveSuggestionStorage()
            .loadSuggestions();
        expect(
          storedSuggestions.single.status,
          AdaptiveSuggestionStatus.pending,
        );
      },
    );

    test(
      'suggestion status save failure after a successful habit save is a partial success',
      () async {
        final habit = _quantitativeHabitWithEvidence();
        final habitStorage = HabitStorage();
        await habitStorage.saveHabits([habit]);
        final readService = AdaptiveCoachService(habitStorage: habitStorage);
        final pending = await readService.resolvePendingSuggestion(
          habits: [habit],
          now: _now,
        );

        final service = AdaptiveCoachService(
          storage: _ThrowingStorage(),
          habitStorage: habitStorage,
        );
        final outcome = await service.applySuggestion(
          suggestion: pending!.suggestion,
          currentHabit: pending.habit,
        );

        expect(outcome.result, AdaptiveApplyResult.suggestionSaveFailed);
        // The habit itself was saved with the new target.
        expect(outcome.habit!.targetValue, 5.0);
        final storedHabits = await habitStorage.loadHabits();
        expect(storedHabits!.single.targetValue, 5.0);

        // Re-applying against the now-updated habit must not be eligible
        // (the target already matches the proposal), preventing a
        // duplicate write.
        final secondAttempt = await service.applySuggestion(
          suggestion: pending.suggestion,
          currentHabit: outcome.habit!,
        );
        expect(secondAttempt.result, AdaptiveApplyResult.stale);
      },
    );
  });
}
