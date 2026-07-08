import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_habit_coach/features/home/domain/date_key.dart';
import 'package:smart_habit_coach/features/home/presentation/home_screen.dart';

import '../../../support/test_namespace.dart';

const _habitsKey = 'habits:$testNamespaceUid';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // Test 12: tapping "Add note" in the overflow popup opens the note sheet
  testWidgets('tapping Add note in popup opens note sheet', (tester) async {
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

    await tester.tap(find.text('Add note'));
    await tester.pumpAndSettle();

    // Note sheet opens with a title and Save button.
    expect(find.text('Note for today'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Save'), findsOneWidget);
  });

  // Test 13: note preview appears in card subtitle after saving
  testWidgets('saved note preview appears in card subtitle', (tester) async {
    final today = todayKey();
    SharedPreferences.setMockInitialValues({
      _habitsKey: jsonEncode([
        {
          'id': '1',
          'title': 'Read',
          'scheduledTime': '08:00 AM',
          'iconId': 'book',
          'completedDates': <String>[],
          'weekdays': [1, 2, 3, 4, 5, 6, 7],
          'completionNotes': {today: 'Great session'},
        },
      ]),
    });

    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pumpAndSettle();

    // Italic note preview appears in the card subtitle.
    expect(find.textContaining('Great session'), findsOneWidget);
  });
}
