import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_habit_coach/features/home/domain/habit.dart';
import 'package:smart_habit_coach/features/home/presentation/habit_details_screen.dart';

final _today = DateTime(2026, 6, 27);

Habit _dailyHabit({String id = '1', String title = 'Walk'}) => Habit(
  id: id,
  title: title,
  scheduledTime: '07:00 AM',
  icon: Icons.directions_walk_outlined,
);

String _prefs(Habit h) => jsonEncode([h.toJson()]);

Future<void> _pump(WidgetTester tester, Habit habit) async {
  SharedPreferences.setMockInitialValues({'habits': _prefs(habit)});
  await tester.pumpWidget(
    MaterialApp(
      home: HabitDetailsScreen(habit: habit, today: _today),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // Test 15: date action sheet includes "Add note" item for binary habits
  testWidgets('binary date action sheet includes Add note item', (
    tester,
  ) async {
    await _pump(tester, _dailyHabit());

    // Open the date action sheet for today (Jun 27).
    await tester.ensureVisible(find.text('27'));
    await tester.tap(find.text('27'));
    await tester.pumpAndSettle();

    expect(find.text('Add note'), findsOneWidget);
  });

  // Test 16: tapping "Add note" for a calendar date opens the note sheet
  testWidgets('tapping Add note in date action sheet opens note sheet', (
    tester,
  ) async {
    await _pump(tester, _dailyHabit());

    await tester.ensureVisible(find.text('27'));
    await tester.tap(find.text('27'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add note'));
    await tester.pumpAndSettle();

    // Note sheet opened — shows Save button and a TextField.
    expect(find.widgetWithText(FilledButton, 'Save'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });
}
