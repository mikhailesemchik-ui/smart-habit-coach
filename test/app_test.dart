import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_habit_coach/app.dart';
import 'package:smart_habit_coach/features/home/presentation/habit_details_screen.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'onboarding_completed': true});
  });

  testWidgets('Today screen displays habits and updates progress on toggle', (
    tester,
  ) async {
    await tester.pumpWidget(SmartHabitCoachApp());
    await tester.pumpAndSettle();

    expect(
      find.descendant(of: find.byType(ListView), matching: find.text('Today')),
      findsOneWidget,
    );
    expect(find.text('Drink water'), findsOneWidget);
    expect(find.text('Read 20 minutes'), findsOneWidget);
    expect(find.text('Evening walk'), findsOneWidget);
    expect(find.text('0 complete · 3 remaining'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.radio_button_unchecked).first);
    await tester.pump();

    expect(find.text('1 complete · 2 remaining'), findsOneWidget);
  });

  testWidgets('Adding a habit updates the list and progress summary', (
    tester,
  ) async {
    await tester.pumpWidget(SmartHabitCoachApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    expect(find.text('Add habit'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Habit title'),
      'Stretch',
    );
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Save'));
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.text('Add habit'), findsNothing);
    expect(find.text('0 complete · 4 remaining'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Stretch'), 200);
    expect(find.text('Stretch'), findsOneWidget);
  });

  testWidgets('Saving with an empty title shows a validation error', (
    tester,
  ) async {
    await tester.pumpWidget(SmartHabitCoachApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Save'));
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pump();

    expect(find.text('Title cannot be empty'), findsOneWidget);
    expect(find.text('Add habit'), findsOneWidget);
  });

  testWidgets('Cancel closes the form without adding a habit', (tester) async {
    await tester.pumpWidget(SmartHabitCoachApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.widgetWithText(TextButton, 'Cancel'));
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Add habit'), findsNothing);
    expect(find.text('0 complete · 3 remaining'), findsOneWidget);
  });

  testWidgets('Tapping a habit opens its details', (tester) async {
    await tester.pumpWidget(SmartHabitCoachApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Drink water'));
    await tester.pumpAndSettle();

    expect(find.byType(HabitDetailsScreen), findsOneWidget);
    expect(find.text('08:00 AM'), findsOneWidget);
    expect(find.text('Not completed'), findsOneWidget);
  });

  testWidgets('Editing a habit updates it in the list', (tester) async {
    await tester.pumpWidget(SmartHabitCoachApp());
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

    // Pop back to the home screen.
    await tester.ensureVisible(find.byType(BackButton));
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(find.text('Drink more water'), findsOneWidget);
    expect(find.text('Drink water'), findsNothing);
  });

  testWidgets('Canceling an edit keeps the original habit unchanged', (
    tester,
  ) async {
    await tester.pumpWidget(SmartHabitCoachApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Drink water'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Edit habit'));
    await tester.tap(find.text('Edit habit'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Habit title'),
      'Should not save',
    );
    await tester.ensureVisible(find.widgetWithText(TextButton, 'Cancel'));
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    // Pop back to the home screen.
    await tester.ensureVisible(find.byType(BackButton));
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(find.text('Drink water'), findsOneWidget);
    expect(find.text('Should not save'), findsNothing);
  });

  testWidgets(
    'Canceling delete keeps the habit; confirming removes it and updates progress',
    (tester) async {
      await tester.pumpWidget(SmartHabitCoachApp());
      await tester.pumpAndSettle();

      // Open details and cancel the delete.
      await tester.tap(find.text('Evening walk'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.widgetWithText(OutlinedButton, 'Delete habit'),
      );
      await tester.tap(find.widgetWithText(OutlinedButton, 'Delete habit'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      // Back to home screen after canceling.
      await tester.ensureVisible(find.byType(BackButton));
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(find.text('Evening walk'), findsOneWidget);
      expect(find.text('0 complete · 3 remaining'), findsOneWidget);

      // Open details again and confirm the delete.
      await tester.tap(find.text('Evening walk'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.widgetWithText(OutlinedButton, 'Delete habit'),
      );
      await tester.tap(find.widgetWithText(OutlinedButton, 'Delete habit'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      // _deleteHabit pops the screen automatically; home screen reloads.
      expect(find.text('Evening walk'), findsNothing);
      expect(find.text('0 complete · 2 remaining'), findsOneWidget);
    },
  );
}
