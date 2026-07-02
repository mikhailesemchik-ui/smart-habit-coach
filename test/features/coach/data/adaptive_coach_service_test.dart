import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_habit_coach/features/coach/data/adaptive_coach_service.dart';
import 'package:smart_habit_coach/features/coach/data/adaptive_suggestion_storage.dart';
import 'package:smart_habit_coach/features/coach/domain/adaptive_suggestion.dart';
import 'package:smart_habit_coach/features/home/domain/date_key.dart';
import 'package:smart_habit_coach/features/home/domain/habit.dart';

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
        'adaptive_suggestions',
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
}
