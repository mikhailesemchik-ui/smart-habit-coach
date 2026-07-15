import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_habit_coach/features/home/data/habit_storage.dart';
import 'package:smart_habit_coach/features/home/domain/date_key.dart';
import 'package:smart_habit_coach/features/home/domain/habit.dart';
import 'package:smart_habit_coach/features/home/presentation/home_screen.dart';

import '../../../support/test_namespace.dart';

const _habitsKey = 'habits:$testNamespaceUid';

void main() {
  group('HomeScreen persistence', () {
    testWidgets(
      'editing title and time does not erase existing completion dates',
      (tester) async {
        final today = todayKey();
        SharedPreferences.setMockInitialValues({
          _habitsKey: jsonEncode([
            {
              'id': '1',
              'title': 'Drink water',
              'scheduledTime': '08:00 AM',
              'iconId': 'water',
              'completedDates': [today],
            },
          ]),
        });

        await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Drink water'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Edit habit'));
        await tester.tap(find.text('Edit habit'));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.widgetWithText(TextFormField, 'Habit title'),
          'Drink more water',
        );
        await tester.ensureVisible(find.widgetWithText(FilledButton, 'Save'));
        await tester.tap(find.widgetWithText(FilledButton, 'Save'));
        await tester.pumpAndSettle();

        final loaded = await HabitStorage().loadHabits();

        expect(loaded, isNotNull);
        expect(loaded!.first.title, 'Drink more water');
        expect(loaded.first.completedDates, contains(today));
        expect(loaded.first.isCompletedToday, isTrue);
      },
    );

    testWidgets(
      'completion history survives widget recreation via mocked SharedPreferences',
      (tester) async {
        SharedPreferences.setMockInitialValues({});

        await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.radio_button_unchecked).first);
        await tester.pump();

        expect(find.byIcon(Icons.circle), findsOneWidget);

        // Force a fresh HomeScreen state (simulates re-navigating or hot restart).
        await tester.pumpWidget(
          const MaterialApp(home: HomeScreen(key: ValueKey('reload'))),
        );
        await tester.pumpAndSettle();

        expect(find.byIcon(Icons.circle), findsOneWidget);
      },
    );
  });

  testWidgets('Today adds, changes, clears, and displays a skip reason', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      _habitsKey: jsonEncode([
        {
          'id': '1',
          'title': 'Read',
          'scheduledTime': '08:00 AM',
          'iconId': 'book',
          'completedDates': <String>[],
          'weekdays': [1, 2, 3, 4, 5, 6, 7],
        },
      ]),
    });

    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Why was it missed?'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Too tired'));
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Too tired'), findsOneWidget);

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Why was it missed?'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Forgot'));
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Forgot'), findsOneWidget);

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Why was it missed?'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Clear reason'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Forgot'), findsNothing);
  });

  // Test 14: Today shows quantitative current/target
  testWidgets('Today shows quantitative habit with progress bar', (
    tester,
  ) async {
    final today = todayKey();
    SharedPreferences.setMockInitialValues({
      _habitsKey: jsonEncode([
        {
          'id': '1',
          'title': 'Drink water',
          'scheduledTime': '08:00 AM',
          'iconId': 'water',
          'completedDates': <String>[],
          'weekdays': [1, 2, 3, 4, 5, 6, 7],
          'trackingType': 'quantitative',
          'targetValue': 3.0,
          'unit': 'L',
          'quantitativeProgress': {today: 1.5},
        },
      ]),
    });

    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pumpAndSettle();

    // Shows progress bar
    expect(find.byType(LinearProgressIndicator), findsWidgets);
    // Shows partial progress text (e.g. "08:00 AM · 1.5 / 3 L")
    expect(find.textContaining('1.5'), findsOneWidget);
    expect(find.textContaining('3 L'), findsOneWidget);
  });

  // Test 16: Aggregate score uses progress ratio
  testWidgets('progress card shows ratio-based progress score', (tester) async {
    final today = todayKey();
    SharedPreferences.setMockInitialValues({
      _habitsKey: jsonEncode([
        {
          'id': '1',
          'title': 'Drink water',
          'scheduledTime': '08:00 AM',
          'iconId': 'water',
          'completedDates': <String>[],
          'weekdays': [1, 2, 3, 4, 5, 6, 7],
          'trackingType': 'quantitative',
          'targetValue': 2.0,
          'unit': 'L',
          'quantitativeProgress': {today: 1.0}, // ratio = 0.5
        },
      ]),
    });

    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pumpAndSettle();

    // 50% progress score
    expect(find.text('50% progress score'), findsOneWidget);
  });

  testWidgets('Other skip reason note survives reload from storage', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      _habitsKey: jsonEncode([
        {
          'id': '1',
          'title': 'Read',
          'scheduledTime': '08:00 AM',
          'iconId': 'book',
          'completedDates': <String>[],
          'weekdays': [1, 2, 3, 4, 5, 6, 7],
        },
      ]),
    });

    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Why was it missed?'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Other'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Optional note'),
      'Travel',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    final loaded = await HabitStorage().loadHabits();
    expect(loaded!.first.skipReasonFor(DateTime.now()), HabitSkipReason.other);
    expect(loaded.first.skipReasonNoteFor(DateTime.now()), 'Travel');
  });
}
