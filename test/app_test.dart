import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_habit_coach/app.dart';
import 'package:smart_habit_coach/features/home/presentation/habit_details_sheet.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'onboarding_completed': true});
  });

  testWidgets('Today screen displays habits and updates progress on toggle', (
    tester,
  ) async {
    await tester.pumpWidget(const SmartHabitCoachApp());
    await tester.pumpAndSettle();

    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('Today')),
      findsOneWidget,
    );
    expect(find.text('Drink water'), findsOneWidget);
    expect(find.text('Read 20 minutes'), findsOneWidget);
    expect(find.text('Evening walk'), findsOneWidget);
    expect(find.text('0 of 3 habits completed (0%)'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.radio_button_unchecked).first);
    await tester.pump();

    expect(find.text('1 of 3 habits completed (33%)'), findsOneWidget);
  });

  testWidgets('Adding a habit updates the list and progress summary', (
    tester,
  ) async {
    await tester.pumpWidget(const SmartHabitCoachApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    expect(find.text('Add habit'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Habit title'),
      'Stretch',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.text('Add habit'), findsNothing);
    expect(find.text('0 of 4 habits completed (0%)'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Stretch'), 200);
    expect(find.text('Stretch'), findsOneWidget);
  });

  testWidgets('Saving with an empty title shows a validation error', (
    tester,
  ) async {
    await tester.pumpWidget(const SmartHabitCoachApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pump();

    expect(find.text('Title cannot be empty'), findsOneWidget);
    expect(find.text('Add habit'), findsOneWidget);
  });

  testWidgets('Cancel closes the form without adding a habit', (tester) async {
    await tester.pumpWidget(const SmartHabitCoachApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Add habit'), findsNothing);
    expect(find.text('0 of 3 habits completed (0%)'), findsOneWidget);
  });

  testWidgets('Tapping a habit opens its details', (tester) async {
    await tester.pumpWidget(const SmartHabitCoachApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Drink water'));
    await tester.pumpAndSettle();

    final details = find.byType(HabitDetailsSheet);
    expect(details, findsOneWidget);
    expect(
      find.descendant(of: details, matching: find.text('Drink water')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: details, matching: find.text('08:00 AM')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: details, matching: find.text('Not completed')),
      findsOneWidget,
    );
  });

  testWidgets('Editing a habit updates it in the list', (tester) async {
    await tester.pumpWidget(const SmartHabitCoachApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Drink water'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Edit'));
    await tester.pumpAndSettle();

    expect(find.text('Edit habit'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Habit title'),
      'Drink more water',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.text('Drink more water'), findsOneWidget);
    expect(find.text('Drink water'), findsNothing);
  });

  testWidgets('Canceling an edit keeps the original habit unchanged', (
    tester,
  ) async {
    await tester.pumpWidget(const SmartHabitCoachApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Drink water'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Edit'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Habit title'),
      'Should not save',
    );
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Drink water'), findsOneWidget);
    expect(find.text('Should not save'), findsNothing);
  });

  testWidgets(
    'Canceling delete keeps the habit; confirming removes it and updates progress',
    (tester) async {
      await tester.pumpWidget(const SmartHabitCoachApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Evening walk'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Evening walk'), findsOneWidget);
      expect(find.text('0 of 3 habits completed (0%)'), findsOneWidget);

      await tester.tap(find.text('Evening walk'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(find.text('Evening walk'), findsNothing);
      expect(find.text('0 of 2 habits completed (0%)'), findsOneWidget);
    },
  );
}
