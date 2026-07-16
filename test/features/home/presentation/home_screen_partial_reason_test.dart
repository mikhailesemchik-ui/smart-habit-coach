import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_habit_coach/features/home/domain/date_key.dart';
import 'package:smart_habit_coach/features/home/presentation/home_screen.dart';

import '../../../support/test_namespace.dart';

const _habitsKey = 'habits:$testNamespaceUid';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  // Test: Today card shows "Why wasn't the target reached?" when partial
  testWidgets('partial quantitative habit shows partial reason button', (
    tester,
  ) async {
    final today = todayKey();
    SharedPreferences.setMockInitialValues({
      _habitsKey: jsonEncode([
        {
          'id': '1',
          'title': 'Water',
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

    // Open the overflow menu to see which actions are available.
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();

    // The partial reason item is shown for partial progress.
    expect(find.text("Why wasn't the target reached?"), findsOneWidget);
    // The skip reason item is NOT shown (progress > 0).
    expect(find.text('Why was it missed?'), findsNothing);
  });

  // Test: Tapping partial reason button opens the partial reason sheet
  testWidgets('tapping partial reason button opens partial reason sheet', (
    tester,
  ) async {
    final today = todayKey();
    SharedPreferences.setMockInitialValues({
      _habitsKey: jsonEncode([
        {
          'id': '1',
          'title': 'Water',
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

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Why wasn't the target reached?"));
    await tester.pumpAndSettle();

    // Sheet title
    expect(find.text("Why wasn't the target reached?"), findsWidgets);
    // Reason options
    expect(find.text('No time'), findsOneWidget);
    expect(find.text('Too tired'), findsOneWidget);
    expect(find.text('Target too difficult'), findsOneWidget);
    expect(find.text('Forgot to continue'), findsOneWidget);
  });

  // Test: Saving partial reason shows label in subtitle
  testWidgets('saving partial reason shows compact label in card subtitle', (
    tester,
  ) async {
    final today = todayKey();
    SharedPreferences.setMockInitialValues({
      _habitsKey: jsonEncode([
        {
          'id': '1',
          'title': 'Water',
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

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Why wasn't the target reached?"));
    await tester.pumpAndSettle();
    await tester.tap(find.text('No time'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    // Subtitle now contains "Partial · No time"
    expect(find.textContaining('Partial'), findsWidgets);
    expect(find.textContaining('No time'), findsWidgets);
  });

  // Test: Skip reason shows at zero; partial reason shows at partial
  testWidgets('zero progress shows skip reason, not partial reason', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      _habitsKey: jsonEncode([
        {
          'id': '1',
          'title': 'Water',
          'scheduledTime': '08:00 AM',
          'iconId': 'water',
          'completedDates': <String>[],
          'weekdays': [1, 2, 3, 4, 5, 6, 7],
          'trackingType': 'quantitative',
          'targetValue': 3.0,
          'unit': 'L',
          'quantitativeProgress': <String, dynamic>{},
        },
      ]),
    });

    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pumpAndSettle();

    // Open the overflow menu to see which actions are available.
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();

    expect(find.text('Why was it missed?'), findsOneWidget);
    expect(find.text("Why wasn't the target reached?"), findsNothing);
  });
}
