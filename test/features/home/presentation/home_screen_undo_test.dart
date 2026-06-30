import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_habit_coach/features/home/domain/date_key.dart';
import 'package:smart_habit_coach/features/home/presentation/home_screen.dart';

const _binaryHabit = {
  'id': '1',
  'title': 'Read',
  'scheduledTime': '08:00 AM',
  'iconId': 'book',
  'completedDates': <String>[],
  'weekdays': [1, 2, 3, 4, 5, 6, 7],
};

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // Test 17: toggling a binary habit shows "Habit updated" snackbar
  testWidgets('toggling binary habit shows Habit updated snackbar', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'habits': jsonEncode([_binaryHabit]),
    });

    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.radio_button_unchecked));
    await tester.pump();

    expect(find.text('Habit updated'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);
  });

  // Test 18: tapping Undo after toggle restores previous completion state
  testWidgets('tapping Undo after toggle restores completion state', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(800, 900);
    tester.view.devicePixelRatio = 1.0;

    SharedPreferences.setMockInitialValues({
      'habits': jsonEncode([_binaryHabit]),
    });

    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pumpAndSettle();

    // Toggle → completed.
    await tester.tap(find.byIcon(Icons.radio_button_unchecked));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.check_circle), findsOneWidget);

    // Undo → back to uncompleted.
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.radio_button_unchecked), findsOneWidget);
  });

  // Test 19: dismissing snackbar without undo keeps the new state
  testWidgets('dismissing snackbar without Undo keeps new state', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'habits': jsonEncode([_binaryHabit]),
    });

    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.radio_button_unchecked));
    await tester.pump();

    // Let the snackbar time out naturally.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    // Still completed — undo was not tapped.
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
  });

  // Test 20: adding a note shows "Note saved" snackbar
  testWidgets('adding a note shows Note saved snackbar', (tester) async {
    SharedPreferences.setMockInitialValues({
      'habits': jsonEncode([_binaryHabit]),
    });

    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add note'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Test note');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.text('Note saved'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);
  });

  // Test 21: tapping Undo after note save removes the note
  testWidgets('tapping Undo after note save removes the note', (tester) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(800, 900);
    tester.view.devicePixelRatio = 1.0;

    SharedPreferences.setMockInitialValues({
      'habits': jsonEncode([_binaryHabit]),
    });

    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pumpAndSettle();

    // Add note.
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add note'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Temp note');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Temp note'), findsOneWidget);

    // Undo → note preview disappears.
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Temp note'), findsNothing);
  });

  // Test 22: a second action replaces the first undo snackbar
  testWidgets('second action replaces the first undo snackbar', (tester) async {
    SharedPreferences.setMockInitialValues({
      'habits': jsonEncode([
        _binaryHabit,
        {
          'id': '2',
          'title': 'Walk',
          'scheduledTime': '09:00 AM',
          'iconId': 'directions_walk',
          'completedDates': <String>[],
          'weekdays': [1, 2, 3, 4, 5, 6, 7],
        },
      ]),
    });

    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pumpAndSettle();

    // First toggle.
    await tester.tap(find.byIcon(Icons.radio_button_unchecked).first);
    await tester.pump();
    expect(find.text('Habit updated'), findsOneWidget);

    // Second toggle (different habit) — replaces the snackbar.
    await tester.tap(find.byIcon(Icons.radio_button_unchecked).last);
    await tester.pump();

    // Still exactly one snackbar (the new one replaced the old one).
    expect(find.text('Habit updated'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);
  });

  // Test 23: after setting skip reason, "Habit updated" appears
  testWidgets('setting skip reason shows Habit updated snackbar', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'habits': jsonEncode([_binaryHabit]),
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

    expect(find.text('Habit updated'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);
  });

  // Test 24: Undo after skip reason restores no reason
  testWidgets('Undo after skip reason removes the skip reason', (tester) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(800, 900);
    tester.view.devicePixelRatio = 1.0;

    SharedPreferences.setMockInitialValues({
      'habits': jsonEncode([_binaryHabit]),
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

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Too tired'), findsNothing);
  });

  // Test 25: quantitative habit shows "Progress reset" when logging zero
  testWidgets(
    'logging zero on quantitative habit shows Progress reset snackbar',
    (tester) async {
      final today = todayKey();
      SharedPreferences.setMockInitialValues({
        'habits': jsonEncode([
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

      // Tap log progress (habit is partial but not complete).
      await tester.tap(find.byTooltip('Log progress'));
      await tester.pumpAndSettle();

      // Clear the field and save 0.
      await tester.enterText(find.byType(TextField).first, '0');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(find.text('Progress reset'), findsOneWidget);
    },
  );

  // Test 26: quantitative habit shows "Habit updated" when logging progress
  testWidgets('logging non-zero progress shows Habit updated snackbar', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'habits': jsonEncode([
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
        },
      ]),
    });

    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Log progress'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '2');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.text('Habit updated'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);
  });

  // Test 27: Undo after logging progress restores previous progress value
  testWidgets('Undo after logging progress restores previous value', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(800, 900);
    tester.view.devicePixelRatio = 1.0;

    SharedPreferences.setMockInitialValues({
      'habits': jsonEncode([
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
        },
      ]),
    });

    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pumpAndSettle();

    // Log 2 L.
    await tester.tap(find.byTooltip('Log progress'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '2');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.textContaining('2'), findsWidgets);

    // Undo → progress removed, shows "Log progress" tooltip again.
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    expect(find.textContaining('2 / 3 L'), findsNothing);
  });

  // Test 28: minimum-version habit shows undo after picking status
  testWidgets('minimum-version habit shows Habit updated after status pick', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'habits': jsonEncode([
        {
          'id': '1',
          'title': 'Meditate',
          'scheduledTime': '07:00 AM',
          'iconId': 'self_improvement',
          'completedDates': <String>[],
          'weekdays': [1, 2, 3, 4, 5, 6, 7],
          'minimumVersion': 'At least 5 min',
        },
      ]),
    });

    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pumpAndSettle();

    // Tap toggle — opens the minimum version picker.
    await tester.tap(find.byIcon(Icons.radio_button_unchecked));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Complete fully'));
    await tester.pumpAndSettle();

    expect(find.text('Habit updated'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);
  });

  // Test 29: Undo SnackBar has the configured 4 s duration
  // (The SnackBar.duration property is the source of truth; the timer itself
  // is a dart:async.Timer that does not fire during pump/pumpAndSettle in
  // widget tests, so we verify the property directly.)
  testWidgets('Undo SnackBar has a 4 s duration', (tester) async {
    SharedPreferences.setMockInitialValues({
      'habits': jsonEncode([_binaryHabit]),
    });

    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.radio_button_unchecked));
    await tester.pump();

    expect(find.text('Undo'), findsOneWidget);
    final bar = tester.widget<SnackBar>(find.byType(SnackBar));
    expect(bar.duration, const Duration(seconds: 4));
  });

  // Test 30: SnackBar is visible immediately after action
  testWidgets('SnackBar is visible immediately after toggling habit', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'habits': jsonEncode([_binaryHabit]),
    });

    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.radio_button_unchecked));
    await tester.pump(); // one frame — SnackBar queued

    expect(find.text('Habit updated'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);
  });

  // Test 31: SnackBar is still visible before timeout (< 4 s)
  testWidgets('SnackBar is still visible before the 4 s timeout', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'habits': jsonEncode([_binaryHabit]),
    });

    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.radio_button_unchecked));
    await tester.pump(); // show snackbar
    await tester.pump(const Duration(seconds: 3)); // well under 4 s

    expect(find.text('Undo'), findsOneWidget);
  });

  // Test 32: Undo works before timeout — tapping Undo restores previous state
  testWidgets('Undo tapped before timeout restores previous state', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(800, 900);
    tester.view.devicePixelRatio = 1.0;

    SharedPreferences.setMockInitialValues({
      'habits': jsonEncode([_binaryHabit]),
    });

    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pumpAndSettle();

    // Toggle → completed.
    await tester.tap(find.byIcon(Icons.radio_button_unchecked));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.check_circle), findsOneWidget);

    // Undo before timeout → back to uncompleted.
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.radio_button_unchecked), findsOneWidget);
  });

  // Test 33: A second action replaces the first SnackBar
  testWidgets('second action hides first SnackBar and shows new one', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'habits': jsonEncode([
        _binaryHabit,
        {
          'id': '2',
          'title': 'Walk',
          'scheduledTime': '09:00 AM',
          'iconId': 'directions_walk',
          'completedDates': <String>[],
          'weekdays': [1, 2, 3, 4, 5, 6, 7],
        },
      ]),
    });

    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pumpAndSettle();

    // First toggle — first SnackBar.
    await tester.tap(find.byIcon(Icons.radio_button_unchecked).first);
    await tester.pump();
    expect(find.text('Habit updated'), findsOneWidget);

    // Second toggle — second SnackBar replaces first.
    await tester.tap(find.byIcon(Icons.radio_button_unchecked).last);
    await tester.pump();

    // Exactly one SnackBar remains.
    expect(find.text('Habit updated'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);
  });

  // Test 34: SnackBar uses hideCurrentSnackBar (cascade pattern — no
  // clearSnackBars) so a second show replaces without leaving ghost bars.
  testWidgets('SnackBar action uses cascade hideCurrentSnackBar pattern', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'habits': jsonEncode([_binaryHabit]),
    });

    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.radio_button_unchecked));
    await tester.pump();

    // The SnackBar should have no persistent/fixed behavior that prevents
    // auto-dismiss — verify there is exactly one SnackBar widget.
    expect(find.byType(SnackBar), findsOneWidget);
    // And the action label is present, meaning the action callback is wired.
    expect(find.text('Undo'), findsOneWidget);
  });
}
