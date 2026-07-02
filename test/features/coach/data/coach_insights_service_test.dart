import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_habit_coach/features/coach/data/adaptive_suggestion_storage.dart';
import 'package:smart_habit_coach/features/coach/data/coach_insights_service.dart';
import 'package:smart_habit_coach/features/coach/domain/adaptive_suggestion.dart';
import 'package:smart_habit_coach/features/home/data/habit_storage.dart';
import 'package:smart_habit_coach/features/home/domain/habit.dart';

final _now = DateTime(2026, 7, 2);
final _end = DateTime(2026, 7, 1);

class _ThrowingSuggestionStorage extends AdaptiveSuggestionStorage {
  @override
  Future<List<AdaptiveHabitSuggestion>> loadSuggestions() =>
      Future.error(StateError('unavailable'));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('malformed stored records are ignored', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'adaptive_suggestions',
      jsonEncode([
        {'id': 'broken'},
        AdaptiveHabitSuggestion(
          id: 'valid',
          habitId: 'h1',
          type: AdaptiveSuggestionType.addMinimumVersion,
          createdAt: _now,
          analysisStart: _now.subtract(const Duration(days: 30)),
          analysisEnd: _end,
          evidenceCode: 'repeated_too_difficult',
        ).toJson(),
      ]),
    );

    final result = await CoachInsightsService().load();
    expect(result.hasError, isFalse);
    expect(result.suggestions, hasLength(1));
    expect(result.suggestions.single.id, 'valid');
  });

  test('storage failure is reported as an error, never thrown', () async {
    final service = CoachInsightsService(
      suggestionStorage: _ThrowingSuggestionStorage(),
    );
    final result = await service.load();
    expect(result.hasError, isTrue);
    expect(result.suggestions, isEmpty);
  });

  test('loading never mutates a suggestion status', () async {
    final storage = AdaptiveSuggestionStorage();
    await storage.saveSuggestions([
      AdaptiveHabitSuggestion(
        id: 'p1',
        habitId: 'h1',
        type: AdaptiveSuggestionType.addMinimumVersion,
        createdAt: _now,
        analysisStart: _now.subtract(const Duration(days: 30)),
        analysisEnd: _end,
        evidenceCode: 'repeated_too_difficult',
      ),
    ]);

    await CoachInsightsService().load();
    await CoachInsightsService().load();

    final stored = await storage.loadSuggestions();
    expect(stored.single.status, AdaptiveSuggestionStatus.pending);
  });

  test('a suggestion referencing a missing habit remains visible', () async {
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
        habitTitleSnapshot: 'Old Habit',
      ),
    ]);

    final result = await CoachInsightsService().load();
    expect(result.suggestions, hasLength(1));
    expect(result.suggestions.single.status, AdaptiveSuggestionStatus.pending);
  });

  test('an old record without a title snapshot still loads', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'adaptive_suggestions',
      jsonEncode([
        {
          'id': 'legacy',
          'habitId': 'h1',
          'type': 'addMinimumVersion',
          'status': 'pending',
          'createdAt': _now.toIso8601String(),
          'analysisStart': _now.toIso8601String(),
          'analysisEnd': _now.toIso8601String(),
          'evidenceCode': 'repeated_too_difficult',
          // No habitTitleSnapshot key at all.
        },
      ]),
    );

    final result = await CoachInsightsService().load();
    expect(result.suggestions, hasLength(1));
    expect(result.suggestions.single.habitTitleSnapshot, isNull);
  });

  test('current habits are also loaded alongside suggestions', () async {
    final habitStorage = HabitStorage();
    final habit = Habit(
      id: 'h1',
      title: 'Read',
      scheduledTime: '08:00 AM',
      icon: Icons.book,
    );
    await habitStorage.saveHabits([habit]);

    final result = await CoachInsightsService(
      habitStorage: habitStorage,
    ).load();
    expect(result.habits, hasLength(1));
    expect(result.habits.single.id, 'h1');
  });
}
