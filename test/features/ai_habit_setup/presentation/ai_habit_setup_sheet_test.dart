import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_habit_coach/features/ai_habit_setup/data/ai_habit_setup_service.dart';
import 'package:smart_habit_coach/features/ai_habit_setup/domain/ai_habit_setup_exception.dart';
import 'package:smart_habit_coach/features/ai_habit_setup/domain/ai_habit_suggestion_source.dart';
import 'package:smart_habit_coach/features/ai_habit_setup/domain/habit_suggestion.dart';
import 'package:smart_habit_coach/features/ai_habit_setup/presentation/ai_habit_setup_sheet.dart';
import 'package:smart_habit_coach/features/home/presentation/add_habit_sheet.dart';

class _FakeAiHabitSuggestionSource implements AiHabitSuggestionSource {
  final HabitSuggestion? suggestion;
  final AiHabitSetupException? error;
  final Completer<void>? delay;
  var callCount = 0;

  _FakeAiHabitSuggestionSource.success(this.suggestion)
    : error = null,
      delay = null;

  _FakeAiHabitSuggestionSource.failure(this.error)
    : suggestion = null,
      delay = null;

  _FakeAiHabitSuggestionSource.pending(this.delay)
    : suggestion = null,
      error = null;

  @override
  Future<HabitSuggestion> generateSuggestion(String goal) async {
    callCount++;
    if (delay != null) {
      await delay!.future;
    }
    if (error != null) throw error!;
    return suggestion!;
  }
}

void main() {
  const suggestion = HabitSuggestion(
    title: 'Drink more water',
    reason: 'Staying hydrated boosts energy and focus throughout the day.',
    scheduledTime: '09:00 AM',
    icon: Icons.local_drink_outlined,
  );

  Future<void> pumpSheet(
    WidgetTester tester,
    AiHabitSuggestionSource service,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AiHabitSetupSheet(service: service)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Generating a plan shows a loading indicator', (tester) async {
    final delay = Completer<void>();
    final service = _FakeAiHabitSuggestionSource.pending(delay);
    await pumpSheet(tester, service);

    await tester.tap(find.widgetWithText(FilledButton, 'Generate plan'));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Generate plan'), findsNothing);

    delay.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('Tapping Generate plan twice only sends one request', (
    tester,
  ) async {
    final delay = Completer<void>();
    final service = _FakeAiHabitSuggestionSource.pending(delay);
    await pumpSheet(tester, service);

    await tester.tap(find.widgetWithText(FilledButton, 'Generate plan'));
    await tester.tap(find.widgetWithText(FilledButton, 'Generate plan'));
    await tester.pump();

    expect(service.callCount, 1);

    delay.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('A successful response shows the suggestion preview', (
    tester,
  ) async {
    final service = _FakeAiHabitSuggestionSource.success(suggestion);
    await pumpSheet(tester, service);

    await tester.tap(find.widgetWithText(FilledButton, 'Generate plan'));
    await tester.pumpAndSettle();

    expect(find.text('Drink more water'), findsOneWidget);
    expect(find.text('Suggested time: 09:00 AM'), findsOneWidget);
  });

  testWidgets('Accepting a suggestion pops with the result', (tester) async {
    final service = _FakeAiHabitSuggestionSource.success(suggestion);
    await pumpSheet(tester, service);

    await tester.tap(find.widgetWithText(FilledButton, 'Generate plan'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Add habit'));
    await tester.pumpAndSettle();

    expect(find.byType(AiHabitSetupSheet), findsNothing);
  });

  testWidgets('Editing a suggestion pops with openForEditing true', (
    tester,
  ) async {
    AiHabitSetupResult? capturedResult;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                capturedResult = await showModalBottomSheet<AiHabitSetupResult>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => AiHabitSetupSheet(
                    service: _FakeAiHabitSuggestionSource.success(suggestion),
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Generate plan'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'Edit'));
    await tester.pumpAndSettle();

    expect(capturedResult, isNotNull);
    expect(capturedResult!.openForEditing, isTrue);
    expect(capturedResult!.habit.title, 'Drink more water');
  });

  testWidgets('Cancel before generating closes without changes', (
    tester,
  ) async {
    final service = _FakeAiHabitSuggestionSource.success(suggestion);
    await pumpSheet(tester, service);

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(find.byType(AiHabitSetupSheet), findsNothing);
    expect(service.callCount, 0);
  });

  testWidgets('Cancel after generating a suggestion discards it', (
    tester,
  ) async {
    final service = _FakeAiHabitSuggestionSource.success(suggestion);
    await pumpSheet(tester, service);

    await tester.tap(find.widgetWithText(FilledButton, 'Generate plan'));
    await tester.pumpAndSettle();

    expect(find.text('Drink more water'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(find.byType(AiHabitSetupSheet), findsNothing);
  });

  testWidgets('A failed request shows a user-friendly error with Retry', (
    tester,
  ) async {
    final service = _FakeAiHabitSuggestionSource.failure(
      const AiHabitSetupException('Network unavailable, try again.'),
    );
    await pumpSheet(tester, service);

    await tester.tap(find.widgetWithText(FilledButton, 'Generate plan'));
    await tester.pumpAndSettle();

    expect(find.text('Network unavailable, try again.'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Retry'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('A quota failure shows the daily AI habit limit message', (
    tester,
  ) async {
    final service = _FakeAiHabitSuggestionSource.failure(
      const AiHabitSetupException(aiHabitSetupQuotaMessage),
    );
    await pumpSheet(tester, service);

    await tester.tap(find.widgetWithText(FilledButton, 'Generate plan'));
    await tester.pumpAndSettle();

    expect(find.text(aiHabitSetupQuotaMessage), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Retry'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'No overflow and all actions reachable at 360×640 with keyboard inset',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.reset);

      final service = _FakeAiHabitSuggestionSource.success(suggestion);
      await pumpSheet(tester, service);

      await tester.tap(find.widgetWithText(FilledButton, 'Generate plan'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Drink more water'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Cancel'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Edit'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Add habit'), findsOneWidget);
    },
  );

  // Test 10: preview displays the proposed repeat schedule.
  testWidgets('preview shows Repeat: Mon, Wed, Fri for weekdays [1,3,5]', (
    tester,
  ) async {
    const weekdaySuggestion = HabitSuggestion(
      title: 'Work out',
      reason: 'Strength.',
      scheduledTime: '07:00 AM',
      icon: Icons.fitness_center_outlined,
      weekdays: [1, 3, 5],
    );
    final service = _FakeAiHabitSuggestionSource.success(weekdaySuggestion);
    await pumpSheet(tester, service);

    await tester.tap(find.widgetWithText(FilledButton, 'Generate plan'));
    await tester.pumpAndSettle();

    expect(find.text('Repeat: Mon, Wed, Fri'), findsOneWidget);
  });

  testWidgets('preview shows Repeat: Every day for all-week suggestion', (
    tester,
  ) async {
    // Default `suggestion` constant has weekdays = [1,2,3,4,5,6,7].
    final service = _FakeAiHabitSuggestionSource.success(suggestion);
    await pumpSheet(tester, service);

    await tester.tap(find.widgetWithText(FilledButton, 'Generate plan'));
    await tester.pumpAndSettle();

    expect(find.text('Repeat: Every day'), findsOneWidget);
  });

  // Test 12: compact screen with weekday schedule does not overflow.
  testWidgets(
    'preview with weekday schedule does not overflow on a compact screen',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.reset);

      const weekdaySuggestion = HabitSuggestion(
        title: 'Meditate',
        reason: 'Calm the mind.',
        scheduledTime: '07:00 AM',
        icon: Icons.self_improvement_outlined,
        weekdays: [2, 4],
      );
      final service = _FakeAiHabitSuggestionSource.success(weekdaySuggestion);
      await pumpSheet(tester, service);

      await tester.tap(find.widgetWithText(FilledButton, 'Generate plan'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Repeat: Tue, Thu'), findsOneWidget);
    },
  );

  testWidgets('Retry after a failure can succeed', (tester) async {
    var attempt = 0;
    final service = _RetryingFakeSource(
      suggestion: suggestion,
      attempt: () {
        attempt++;
        return attempt == 1;
      },
    );
    await pumpSheet(tester, service);

    await tester.tap(find.widgetWithText(FilledButton, 'Generate plan'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(FilledButton, 'Retry'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Retry'));
    await tester.pumpAndSettle();

    expect(find.text('Drink more water'), findsOneWidget);
  });

  // ── Unresolved-frequency tests (11–14) ────────────────────────────────────

  // Test 11: preview displays "Choose N days" for unresolved suggestions.
  testWidgets('preview shows Repeat: Choose 2 days for unresolved suggestion', (
    tester,
  ) async {
    const unresolvedSuggestion = HabitSuggestion(
      title: 'Gym',
      reason: 'Get fit.',
      scheduledTime: '07:00 AM',
      icon: Icons.fitness_center_outlined,
      weekdays: [],
      requiredDaysPerWeek: 2,
    );
    final service = _FakeAiHabitSuggestionSource.success(unresolvedSuggestion);
    await pumpSheet(tester, service);

    await tester.tap(find.widgetWithText(FilledButton, 'Generate plan'));
    await tester.pumpAndSettle();

    expect(find.text('Repeat: Choose 2 days'), findsOneWidget);
  });

  // Test 12: Add habit disabled when unresolved.
  testWidgets('Add habit is disabled while suggestion is unresolved', (
    tester,
  ) async {
    const unresolvedSuggestion = HabitSuggestion(
      title: 'Gym',
      reason: 'Get fit.',
      scheduledTime: '07:00 AM',
      icon: Icons.fitness_center_outlined,
      weekdays: [],
      requiredDaysPerWeek: 2,
    );
    final service = _FakeAiHabitSuggestionSource.success(unresolvedSuggestion);
    await pumpSheet(tester, service);

    await tester.tap(find.widgetWithText(FilledButton, 'Generate plan'));
    await tester.pumpAndSettle();

    final btn = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Add habit'),
    );
    expect(btn.onPressed, isNull);
  });

  // Test 13: selecting exactly N weekdays enables Add habit.
  testWidgets('selecting exactly N weekdays through Edit enables Add habit', (
    tester,
  ) async {
    const unresolvedSuggestion = HabitSuggestion(
      title: 'Gym',
      reason: 'Get fit.',
      scheduledTime: '07:00 AM',
      icon: Icons.fitness_center_outlined,
      weekdays: [],
      requiredDaysPerWeek: 2,
    );
    final service = _FakeAiHabitSuggestionSource.success(unresolvedSuggestion);
    await pumpSheet(tester, service);

    await tester.tap(find.widgetWithText(FilledButton, 'Generate plan'));
    await tester.pumpAndSettle();

    // Open the day picker via Edit.
    await tester.tap(find.widgetWithText(TextButton, 'Edit'));
    await tester.pumpAndSettle();

    // AddHabitSheet is now shown as a nested modal.
    expect(find.byType(AddHabitSheet), findsOneWidget);

    // Select Mon and Wed (2 days as required).
    await tester.ensureVisible(find.widgetWithText(FilterChip, 'Mon'));
    await tester.tap(find.widgetWithText(FilterChip, 'Mon'));
    await tester.pump();
    await tester.ensureVisible(find.widgetWithText(FilterChip, 'Wed'));
    await tester.tap(find.widgetWithText(FilterChip, 'Wed'));
    await tester.pump();

    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Save'));
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    // AddHabitSheet closed; AI sheet shows resolved suggestion.
    expect(find.byType(AddHabitSheet), findsNothing);
    expect(find.text('Gym'), findsOneWidget);
    expect(find.text('Repeat: Mon, Wed'), findsOneWidget);

    final btn = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Add habit'),
    );
    expect(btn.onPressed, isNotNull);
  });

  // Test 14: saving with wrong count blocks close and shows error.
  testWidgets(
    'saving with wrong weekday count shows error and keeps modal open',
    (tester) async {
      const unresolvedSuggestion = HabitSuggestion(
        title: 'Gym',
        reason: 'Get fit.',
        scheduledTime: '07:00 AM',
        icon: Icons.fitness_center_outlined,
        weekdays: [],
        requiredDaysPerWeek: 2,
      );
      final service = _FakeAiHabitSuggestionSource.success(
        unresolvedSuggestion,
      );
      await pumpSheet(tester, service);

      await tester.tap(find.widgetWithText(FilledButton, 'Generate plan'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, 'Edit'));
      await tester.pumpAndSettle();

      // Select only 1 day (not 2).
      await tester.tap(find.widgetWithText(FilterChip, 'Mon'));
      await tester.pump();

      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      // Modal stays open; the error text appears (hint + error = 2 instances).
      expect(find.byType(AddHabitSheet), findsOneWidget);
      expect(find.text('Select exactly 2 days'), findsWidgets);
    },
  );

  // ── Stale-prompt tests (17–26) ────────────────────────────────────────────

  // Test 17: editing the prompt marks the suggestion stale.
  testWidgets('editing prompt after generation marks suggestion stale', (
    tester,
  ) async {
    final service = _FakeAiHabitSuggestionSource.success(suggestion);
    await pumpSheet(tester, service);

    await tester.enterText(find.byType(TextField), 'initial prompt');
    await tester.tap(find.widgetWithText(FilledButton, 'Generate plan'));
    await tester.pumpAndSettle();

    expect(find.text('Drink more water'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'different prompt');
    await tester.pump();

    expect(
      find.text('Generate again to update the suggestion.'),
      findsOneWidget,
    );
  });

  // Test 18: stale suggestion cannot be added.
  testWidgets('Add habit is not available when suggestion is stale', (
    tester,
  ) async {
    final service = _FakeAiHabitSuggestionSource.success(suggestion);
    await pumpSheet(tester, service);

    await tester.enterText(find.byType(TextField), 'initial prompt');
    await tester.tap(find.widgetWithText(FilledButton, 'Generate plan'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'different prompt');
    await tester.pump();

    expect(find.widgetWithText(FilledButton, 'Add habit'), findsNothing);
  });

  // Test 19: primary action changes to Generate again when stale.
  testWidgets('primary action changes to Generate again when stale', (
    tester,
  ) async {
    final service = _FakeAiHabitSuggestionSource.success(suggestion);
    await pumpSheet(tester, service);

    await tester.enterText(find.byType(TextField), 'initial prompt');
    await tester.tap(find.widgetWithText(FilledButton, 'Generate plan'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'different prompt');
    await tester.pump();

    expect(find.widgetWithText(FilledButton, 'Generate again'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Add habit'), findsNothing);
  });

  // Test 20: editing text alone does not call the AI service.
  testWidgets('editing text alone does not trigger a new AI call', (
    tester,
  ) async {
    final service = _FakeAiHabitSuggestionSource.success(suggestion);
    await pumpSheet(tester, service);

    await tester.enterText(find.byType(TextField), 'initial prompt');
    await tester.tap(find.widgetWithText(FilledButton, 'Generate plan'));
    await tester.pumpAndSettle();
    expect(service.callCount, 1);

    await tester.enterText(find.byType(TextField), 'different prompt');
    await tester.pump();

    expect(service.callCount, 1);
  });

  // Test 21: Generate again makes exactly one new AI call.
  testWidgets('Generate again makes exactly one additional AI call', (
    tester,
  ) async {
    final service = _FakeAiHabitSuggestionSource.success(suggestion);
    await pumpSheet(tester, service);

    await tester.enterText(find.byType(TextField), 'initial prompt');
    await tester.tap(find.widgetWithText(FilledButton, 'Generate plan'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'different prompt');
    await tester.pump();

    await tester.tap(find.widgetWithText(FilledButton, 'Generate again'));
    await tester.pumpAndSettle();

    expect(service.callCount, 2);
  });

  // Test 22: successful regeneration replaces the old suggestion.
  testWidgets('successful regeneration clears stale state', (tester) async {
    final service = _FakeAiHabitSuggestionSource.success(suggestion);
    await pumpSheet(tester, service);

    await tester.enterText(find.byType(TextField), 'initial prompt');
    await tester.tap(find.widgetWithText(FilledButton, 'Generate plan'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'different prompt');
    await tester.pump();

    await tester.tap(find.widgetWithText(FilledButton, 'Generate again'));
    await tester.pumpAndSettle();

    expect(find.text('Generate again to update the suggestion.'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Add habit'), findsOneWidget);
  });

  // Test 23: failed regeneration keeps the old suggestion stale.
  testWidgets('failed regeneration keeps old result stale', (tester) async {
    const failMessage = 'Connection failed.';
    final service = _SequenceFakeSource([
      suggestion,
      const AiHabitSetupException(failMessage),
    ]);
    await pumpSheet(tester, service);

    await tester.enterText(find.byType(TextField), 'initial prompt');
    await tester.tap(find.widgetWithText(FilledButton, 'Generate plan'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'different prompt');
    await tester.pump();

    await tester.tap(find.widgetWithText(FilledButton, 'Generate again'));
    await tester.pumpAndSettle();

    expect(find.text(failMessage), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Add habit'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Generate again'), findsOneWidget);
  });

  // Test 24: changing prompt back to generated value restores valid state.
  testWidgets('changing prompt back to generated text restores Add habit', (
    tester,
  ) async {
    final service = _FakeAiHabitSuggestionSource.success(suggestion);
    await pumpSheet(tester, service);

    await tester.enterText(find.byType(TextField), 'initial prompt');
    await tester.tap(find.widgetWithText(FilledButton, 'Generate plan'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'different prompt');
    await tester.pump();
    expect(find.widgetWithText(FilledButton, 'Add habit'), findsNothing);

    await tester.enterText(find.byType(TextField), 'initial prompt');
    await tester.pump();

    expect(find.widgetWithText(FilledButton, 'Add habit'), findsOneWidget);
    expect(find.text('Generate again to update the suggestion.'), findsNothing);
  });

  // Test 25: manual Edit does not mark the prompt stale.
  testWidgets(
    'tapping Edit in stale state does not make an additional AI call',
    (tester) async {
      AiHabitSetupResult? captured;
      final service = _FakeAiHabitSuggestionSource.success(suggestion);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  captured = await showModalBottomSheet<AiHabitSetupResult>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => AiHabitSetupSheet(service: service),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'initial prompt');
      await tester.tap(find.widgetWithText(FilledButton, 'Generate plan'));
      await tester.pumpAndSettle();

      // Make it stale.
      await tester.enterText(find.byType(TextField), 'different prompt');
      await tester.pump();
      expect(
        find.text('Generate again to update the suggestion.'),
        findsOneWidget,
      );

      // Click Edit — pops the AI sheet (resolved suggestion).
      await tester.tap(find.widgetWithText(TextButton, 'Edit'));
      await tester.pumpAndSettle();

      expect(service.callCount, 1);
      expect(captured?.openForEditing, isTrue);
    },
  );

  // Test 26: compact screen shows no overflow in stale state.
  testWidgets('no overflow in stale state on a compact screen', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.reset);

    final service = _FakeAiHabitSuggestionSource.success(suggestion);
    await pumpSheet(tester, service);

    await tester.enterText(find.byType(TextField), 'initial prompt');
    await tester.tap(find.widgetWithText(FilledButton, 'Generate plan'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'different prompt');
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.widgetWithText(FilledButton, 'Generate again'), findsOneWidget);
  });
}

class _RetryingFakeSource implements AiHabitSuggestionSource {
  final HabitSuggestion suggestion;
  final bool Function() attempt;

  _RetryingFakeSource({required this.suggestion, required this.attempt});

  @override
  Future<HabitSuggestion> generateSuggestion(String goal) async {
    if (attempt()) {
      throw const AiHabitSetupException('Temporary failure.');
    }
    return suggestion;
  }
}

/// Returns outcomes in sequence; each element is either a [HabitSuggestion]
/// (success) or an [AiHabitSetupException] (failure).
class _SequenceFakeSource implements AiHabitSuggestionSource {
  final List<dynamic> _outcomes;
  var _index = 0;

  _SequenceFakeSource(this._outcomes);

  @override
  Future<HabitSuggestion> generateSuggestion(String goal) async {
    final outcome = _outcomes[_index++];
    if (outcome is AiHabitSetupException) throw outcome;
    return outcome as HabitSuggestion;
  }
}
