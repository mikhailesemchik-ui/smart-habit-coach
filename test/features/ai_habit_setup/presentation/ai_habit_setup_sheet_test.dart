import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_habit_coach/features/ai_habit_setup/domain/ai_habit_setup_exception.dart';
import 'package:smart_habit_coach/features/ai_habit_setup/domain/ai_habit_suggestion_source.dart';
import 'package:smart_habit_coach/features/ai_habit_setup/domain/habit_suggestion.dart';
import 'package:smart_habit_coach/features/ai_habit_setup/presentation/ai_habit_setup_sheet.dart';

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
