import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_habit_coach/features/coach/data/adaptive_suggestion_storage.dart';
import 'package:smart_habit_coach/features/coach/data/coach_insights_service.dart';
import 'package:smart_habit_coach/features/coach/domain/adaptive_suggestion.dart';
import 'package:smart_habit_coach/features/coach/presentation/coach_insights_screen.dart';

final _now = DateTime(2026, 7, 2);
final _end = DateTime(2026, 7, 1);

class _ThrowingSuggestionStorage extends AdaptiveSuggestionStorage {
  @override
  Future<List<AdaptiveHabitSuggestion>> loadSuggestions() =>
      Future.error(StateError('unavailable'));
}

/// Finds a status *section header* Text with [label], as opposed to a
/// status chip inside a suggestion card that might carry the same text
/// (e.g. both render "Pending"). Section headers are direct ListView
/// children and are never inside a Card, so excluding any match with a
/// Card ancestor disambiguates the two without relying on theme styling.
Finder _sectionHeaderFinder(String label) {
  return find.byElementPredicate((element) {
    final widget = element.widget;
    if (widget is! Text || widget.data != label) return false;
    var insideCard = false;
    element.visitAncestorElements((ancestor) {
      if (ancestor.widget is Card) {
        insideCard = true;
        return false;
      }
      return true;
    });
    return !insideCard;
  });
}

AdaptiveHabitSuggestion _suggestion({
  required String id,
  AdaptiveSuggestionStatus status = AdaptiveSuggestionStatus.pending,
  DateTime? createdAt,
  String? habitTitleSnapshot,
}) {
  return AdaptiveHabitSuggestion(
    id: id,
    habitId: 'h1',
    type: AdaptiveSuggestionType.addMinimumVersion,
    status: status,
    createdAt: createdAt ?? _now,
    analysisStart: _now.subtract(const Duration(days: 30)),
    analysisEnd: _end,
    evidenceCode: 'repeated_too_difficult',
    evidence: const {'tooDifficultCount': 4},
    habitTitleSnapshot: habitTitleSnapshot,
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('shows the empty state when there are no records', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: CoachInsightsScreen()));
    await tester.pumpAndSettle();

    expect(find.text('No coach insights yet'), findsOneWidget);
    expect(
      find.textContaining('Adaptive Coach suggestions will appear here'),
      findsOneWidget,
    );
  });

  testWidgets('shows a retryable error state on storage failure', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CoachInsightsScreen(
          service: CoachInsightsService(
            suggestionStorage: _ThrowingSuggestionStorage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text("Couldn't load coach insights."), findsOneWidget);
    final retry = find.text('Try again');
    expect(retry, findsOneWidget);

    await tester.tap(retry);
    await tester.pumpAndSettle();
    // Still failing storage → error state persists rather than crashing.
    expect(find.text("Couldn't load coach insights."), findsOneWidget);
  });

  testWidgets('records display newest first within a status group', (
    tester,
  ) async {
    final storage = AdaptiveSuggestionStorage();
    await storage.saveSuggestions([
      _suggestion(id: 'old', createdAt: DateTime(2026, 6, 1)),
      _suggestion(id: 'new', createdAt: DateTime(2026, 7, 1)),
    ]);

    await tester.pumpWidget(const MaterialApp(home: CoachInsightsScreen()));
    await tester.pumpAndSettle();

    final dates = tester
        .widgetList<Text>(find.textContaining(', 2026'))
        .map((t) => t.data)
        .toList();
    expect(dates.first, contains('Jul 1'));
    expect(dates.last, contains('Jun 1'));
  });

  testWidgets(
    'status groups appear in the required order and hide empty ones',
    (tester) async {
      final storage = AdaptiveSuggestionStorage();
      await storage.saveSuggestions([
        _suggestion(id: 'k', status: AdaptiveSuggestionStatus.kept),
        _suggestion(id: 'p', status: AdaptiveSuggestionStatus.pending),
      ]);

      await tester.pumpWidget(const MaterialApp(home: CoachInsightsScreen()));
      await tester.pumpAndSettle();

      // Only pending and kept records exist: the other three status
      // headers must never render at all, in a lazy list or otherwise.
      // Scoped to section headers (excluding Card-nested status chips) so
      // this stays correct even if a chip happens to share the same text.
      expect(_sectionHeaderFinder('Applied'), findsNothing);
      expect(_sectionHeaderFinder('Adjusted'), findsNothing);
      expect(_sectionHeaderFinder('Rejected'), findsNothing);

      // Pending is the first non-empty section and renders without
      // scrolling. "Pending" also appears as the status chip on the
      // pending suggestion's card, so the finder must target the section
      // header specifically, not just any matching text.
      expect(_sectionHeaderFinder('Pending'), findsOneWidget);

      // Scroll down through the Coach Insights list to reach Kept further
      // down, confirming it renders in sequence after Pending rather than
      // assuming both sections are mounted simultaneously.
      await tester.scrollUntilVisible(
        _sectionHeaderFinder('Kept'),
        200,
        scrollable: find.byType(Scrollable),
      );
      expect(_sectionHeaderFinder('Kept'), findsOneWidget);
    },
  );

  testWidgets('no action buttons appear on historical cards', (tester) async {
    final storage = AdaptiveSuggestionStorage();
    await storage.saveSuggestions([_suggestion(id: 'p')]);

    await tester.pumpWidget(const MaterialApp(home: CoachInsightsScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Apply suggestion'), findsNothing);
    expect(find.text('Adjust manually'), findsNothing);
    expect(find.text('Keep current plan'), findsNothing);
    expect(find.byType(FilledButton), findsNothing);
    expect(find.byType(OutlinedButton), findsNothing);
  });

  testWidgets('no AI wording or attribution is shown', (tester) async {
    final storage = AdaptiveSuggestionStorage();
    await storage.saveSuggestions([_suggestion(id: 'p')]);

    await tester.pumpWidget(const MaterialApp(home: CoachInsightsScreen()));
    await tester.pumpAndSettle();

    expect(find.textContaining('AI'), findsNothing);
    expect(find.textContaining('artificial intelligence'), findsNothing);
  });

  testWidgets('opening the screen does not mutate suggestion status', (
    tester,
  ) async {
    final storage = AdaptiveSuggestionStorage();
    await storage.saveSuggestions([_suggestion(id: 'p')]);

    await tester.pumpWidget(const MaterialApp(home: CoachInsightsScreen()));
    await tester.pumpAndSettle();

    final stored = await storage.loadSuggestions();
    expect(stored.single.status, AdaptiveSuggestionStatus.pending);
  });

  testWidgets('a missing habit record remains visible with a fallback title', (
    tester,
  ) async {
    final storage = AdaptiveSuggestionStorage();
    await storage.saveSuggestions([_suggestion(id: 'orphan')]);

    await tester.pumpWidget(const MaterialApp(home: CoachInsightsScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Habit no longer available'), findsOneWidget);
  });

  testWidgets('the title snapshot is used after habit deletion', (
    tester,
  ) async {
    final storage = AdaptiveSuggestionStorage();
    await storage.saveSuggestions([
      _suggestion(id: 'deleted', habitTitleSnapshot: 'Morning Run'),
    ]);

    await tester.pumpWidget(const MaterialApp(home: CoachInsightsScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Morning Run'), findsOneWidget);
  });
}
