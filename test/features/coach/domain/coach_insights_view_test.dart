import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_habit_coach/features/coach/domain/adaptive_suggestion.dart';
import 'package:smart_habit_coach/features/coach/domain/coach_insights_view.dart';
import 'package:smart_habit_coach/features/home/domain/habit.dart';

final _now = DateTime(2026, 7, 2);
final _end = DateTime(2026, 7, 1);
final _start = _end.subtract(const Duration(days: 29));

Habit _habit({String id = 'h1', String title = 'Read'}) {
  return Habit(
    id: id,
    title: title,
    scheduledTime: '08:00 AM',
    icon: Icons.book,
  );
}

AdaptiveHabitSuggestion _suggestion({
  String id = 's1',
  String habitId = 'h1',
  AdaptiveSuggestionStatus status = AdaptiveSuggestionStatus.pending,
  DateTime? createdAt,
  String? habitTitleSnapshot,
}) {
  return AdaptiveHabitSuggestion(
    id: id,
    habitId: habitId,
    type: AdaptiveSuggestionType.addMinimumVersion,
    status: status,
    createdAt: createdAt ?? _now,
    analysisStart: _start,
    analysisEnd: _end,
    evidenceCode: 'repeated_too_difficult',
    habitTitleSnapshot: habitTitleSnapshot,
  );
}

void main() {
  group('resolveHabitDisplayTitle', () {
    test('prefers the current habit title when the habit still exists', () {
      final habit = _habit(title: 'Read daily');
      final suggestion = _suggestion(habitTitleSnapshot: 'Old title');
      expect(resolveHabitDisplayTitle(suggestion, [habit]), 'Read daily');
    });

    test('falls back to the title snapshot after the habit is deleted', () {
      final suggestion = _suggestion(habitTitleSnapshot: 'Old title');
      expect(resolveHabitDisplayTitle(suggestion, const []), 'Old title');
    });

    test('falls back to "Habit no longer available" with no snapshot', () {
      final suggestion = _suggestion();
      expect(
        resolveHabitDisplayTitle(suggestion, const []),
        'Habit no longer available',
      );
      expect(isHabitUnavailableForDisplay(suggestion, const []), isTrue);
    });

    test('an archived habit still supplies its current title', () {
      final habit = _habit(
        title: 'Read daily',
      ).copyWith(status: HabitStatus.archived);
      final suggestion = _suggestion(habitTitleSnapshot: 'Old title');
      expect(resolveHabitDisplayTitle(suggestion, [habit]), 'Read daily');
    });
  });

  group('groupSuggestionsForInsights', () {
    test(
      'groups appear in Pending, Applied, Adjusted, Kept, Rejected order',
      () {
        final suggestions = [
          _suggestion(id: 'r', status: AdaptiveSuggestionStatus.rejected),
          _suggestion(id: 'k', status: AdaptiveSuggestionStatus.kept),
          _suggestion(id: 'a2', status: AdaptiveSuggestionStatus.adjusted),
          _suggestion(id: 'a1', status: AdaptiveSuggestionStatus.applied),
          _suggestion(id: 'p', status: AdaptiveSuggestionStatus.pending),
        ];
        final groups = groupSuggestionsForInsights(suggestions);
        expect(groups.map((g) => g.status).toList(), [
          AdaptiveSuggestionStatus.pending,
          AdaptiveSuggestionStatus.applied,
          AdaptiveSuggestionStatus.adjusted,
          AdaptiveSuggestionStatus.kept,
          AdaptiveSuggestionStatus.rejected,
        ]);
      },
    );

    test('empty status groups are omitted', () {
      final suggestions = [
        _suggestion(status: AdaptiveSuggestionStatus.pending),
      ];
      final groups = groupSuggestionsForInsights(suggestions);
      expect(groups, hasLength(1));
      expect(groups.single.status, AdaptiveSuggestionStatus.pending);
    });

    test('within a group, records are sorted newest first', () {
      final oldest = _suggestion(id: 'old', createdAt: DateTime(2026, 6, 1));
      final newest = _suggestion(id: 'new', createdAt: DateTime(2026, 7, 1));
      final middle = _suggestion(id: 'mid', createdAt: DateTime(2026, 6, 15));
      final groups = groupSuggestionsForInsights([oldest, newest, middle]);
      expect(groups.single.suggestions.map((s) => s.id).toList(), [
        'new',
        'mid',
        'old',
      ]);
    });

    test('an empty list produces no groups', () {
      expect(groupSuggestionsForInsights(const []), isEmpty);
    });
  });
}
