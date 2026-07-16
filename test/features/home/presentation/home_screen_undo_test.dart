import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_habit_coach/features/home/data/notification_service.dart';
import 'package:smart_habit_coach/features/home/domain/date_key.dart';
import 'package:smart_habit_coach/features/home/domain/habit.dart';
import 'package:smart_habit_coach/features/home/presentation/home_screen.dart';

import '../../../support/test_namespace.dart';

const _habitsKey = 'habits:$testNamespaceUid';

class _FakeNotificationService extends NotificationService {
  @override
  Future<void> initialize() async {}

  @override
  Future<void> scheduleHabitReminder(Habit habit) async {}

  @override
  Future<void> cancelHabitReminder(String habitId) async {}
}

Widget _homeScreen() => MaterialApp(
  home: HomeScreen(notificationService: _FakeNotificationService()),
);

Future<void> _pumpSnackBarVisible(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

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
      _habitsKey: jsonEncode([_binaryHabit]),
    });

    await tester.pumpWidget(_homeScreen());
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
      _habitsKey: jsonEncode([_binaryHabit]),
    });

    await tester.pumpWidget(_homeScreen());
    await tester.pumpAndSettle();

    // Toggle → completed.
    await tester.tap(find.byIcon(Icons.radio_button_unchecked));
    await _pumpSnackBarVisible(tester);
    expect(find.byIcon(Icons.circle), findsOneWidget);

    // Undo → back to uncompleted.
    await tester.tap(find.text('Undo'));
    await tester.pump();
    expect(find.byIcon(Icons.radio_button_unchecked), findsOneWidget);
  });

  // Test 19: dismissing snackbar without undo keeps the new state
  testWidgets('dismissing snackbar without Undo keeps new state', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      _habitsKey: jsonEncode([_binaryHabit]),
    });

    await tester.pumpWidget(_homeScreen());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.radio_button_unchecked));
    await tester.pump();

    // Let the snackbar time out naturally.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    // Still completed — undo was not tapped.
    expect(find.byIcon(Icons.circle), findsOneWidget);
  });

  // Test 20: adding a note shows "Note saved" snackbar
  testWidgets('adding a note shows Note saved snackbar', (tester) async {
    SharedPreferences.setMockInitialValues({
      _habitsKey: jsonEncode([_binaryHabit]),
    });

    await tester.pumpWidget(_homeScreen());
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add note'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Test note');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await _pumpSnackBarVisible(tester);

    expect(find.text('Note saved'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);
  });

  // Test 21: tapping Undo after note save removes the note
  testWidgets('tapping Undo after note save removes the note', (tester) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(800, 900);
    tester.view.devicePixelRatio = 1.0;

    SharedPreferences.setMockInitialValues({
      _habitsKey: jsonEncode([_binaryHabit]),
    });

    await tester.pumpWidget(_homeScreen());
    await tester.pumpAndSettle();

    // Add note.
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add note'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Temp note');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await _pumpSnackBarVisible(tester);

    expect(find.textContaining('Temp note'), findsOneWidget);

    // Undo → note preview disappears.
    await tester.tap(find.text('Undo'));
    await tester.pump();

    expect(find.textContaining('Temp note'), findsNothing);
  });

  // Test 22: a second action replaces the first undo snackbar
  testWidgets('second action replaces the first undo snackbar', (tester) async {
    SharedPreferences.setMockInitialValues({
      _habitsKey: jsonEncode([
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

    await tester.pumpWidget(_homeScreen());
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
      _habitsKey: jsonEncode([_binaryHabit]),
    });

    await tester.pumpWidget(_homeScreen());
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Why was it missed?'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Too tired'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await _pumpSnackBarVisible(tester);

    expect(find.text('Habit updated'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);
  });

  // Test 24: Undo after skip reason restores no reason
  testWidgets('Undo after skip reason removes the skip reason', (tester) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(800, 900);
    tester.view.devicePixelRatio = 1.0;

    SharedPreferences.setMockInitialValues({
      _habitsKey: jsonEncode([_binaryHabit]),
    });

    await tester.pumpWidget(_homeScreen());
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Why was it missed?'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Too tired'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await _pumpSnackBarVisible(tester);

    expect(find.textContaining('Too tired'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pump();

    expect(find.textContaining('Too tired'), findsNothing);
  });

  // Test 25: quantitative habit shows "Progress reset" when logging zero
  testWidgets(
    'logging zero on quantitative habit shows Progress reset snackbar',
    (tester) async {
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

      await tester.pumpWidget(_homeScreen());
      await tester.pumpAndSettle();

      // Tap log progress (habit is partial but not complete).
      await tester.tap(find.byTooltip('Log progress'));
      await tester.pumpAndSettle();

      // Clear the field and save 0.
      await tester.enterText(find.byType(TextField).first, '0');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await _pumpSnackBarVisible(tester);

      expect(find.text('Progress reset'), findsOneWidget);
    },
  );

  // Test 26: quantitative habit shows "Habit updated" when logging progress
  testWidgets('logging non-zero progress shows Habit updated snackbar', (
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
        },
      ]),
    });

    await tester.pumpWidget(_homeScreen());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Log progress'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '2');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await _pumpSnackBarVisible(tester);

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
        },
      ]),
    });

    await tester.pumpWidget(_homeScreen());
    await tester.pumpAndSettle();

    // Log 2 L.
    await tester.tap(find.byTooltip('Log progress'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '2');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await _pumpSnackBarVisible(tester);

    expect(find.textContaining('2'), findsWidgets);

    // Undo → progress removed, shows "Log progress" tooltip again.
    await tester.tap(find.text('Undo'));
    await tester.pump();

    expect(find.textContaining('2 / 3 L'), findsNothing);
  });

  // Test 28: minimum-version habit shows undo after picking status
  testWidgets('minimum-version habit shows Habit updated after status pick', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      _habitsKey: jsonEncode([
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

    await tester.pumpWidget(_homeScreen());
    await tester.pumpAndSettle();

    // Tap toggle — opens the minimum version picker.
    await tester.tap(find.byIcon(Icons.radio_button_unchecked));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Complete fully'));
    await _pumpSnackBarVisible(tester);

    expect(find.text('Habit updated'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);
  });

  // Test 29: Undo SnackBar has the configured 4 s duration
  // (The SnackBar.duration property is the source of truth; the timer itself
  // is a dart:async.Timer that does not fire during pump/pumpAndSettle in
  // widget tests, so we verify the property directly.)
  testWidgets('Undo SnackBar has a 4 s duration', (tester) async {
    SharedPreferences.setMockInitialValues({
      _habitsKey: jsonEncode([_binaryHabit]),
    });

    await tester.pumpWidget(_homeScreen());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.radio_button_unchecked));
    await tester.pump();

    expect(find.text('Undo'), findsOneWidget);
    final bar = tester.widget<SnackBar>(find.byType(SnackBar));
    expect(bar.duration, const Duration(seconds: 4));
  });

  // ── Lifecycle / timing tests ──────────────────────────────────────────────

  // Test 30: SnackBar is visible immediately after action
  testWidgets('SnackBar is visible immediately after toggling habit', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      _habitsKey: jsonEncode([_binaryHabit]),
    });

    await tester.pumpWidget(_homeScreen());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.radio_button_unchecked));
    await tester.pump();

    expect(find.text('Habit updated'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);
  });

  // Test 31: SnackBar is still visible well before the 4-second mark
  testWidgets('SnackBar is still visible at 3 s (before timeout)', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      _habitsKey: jsonEncode([_binaryHabit]),
    });

    await tester.pumpWidget(_homeScreen());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.radio_button_unchecked));
    await tester.pump(); // entry animation starts
    await tester.pump(const Duration(seconds: 3)); // well before 4-s timer

    expect(find.text('Undo'), findsOneWidget);
  });

  // Test 32: SnackBar auto-dismisses after the 4-second display period.
  //
  // Two bare pump() calls establish the Ticker's _startTime at FakeAsync t=0.
  // pump(300ms) completes the 250ms entry animation and creates the 4s display
  // timer. pump(4s+1ms) advances past the timer so it fires and starts the
  // 250ms exit animation. pump(300ms) completes the exit.
  testWidgets('SnackBar auto-dismisses after the 4 s display period', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      _habitsKey: jsonEncode([_binaryHabit]),
    });

    await tester.pumpWidget(_homeScreen());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.radio_button_unchecked));
    await tester.pump(); // handleDrawFrame: forward() called, Ticker registered
    await tester.pump(); // first Ticker tick: _startTime set, elapsed=0
    await tester.pump(const Duration(milliseconds: 300)); // entry done
    await tester.pump(
      const Duration(seconds: 4, milliseconds: 1),
    ); // timer fires
    await tester.pump(const Duration(milliseconds: 300)); // exit done

    expect(find.byType(SnackBar), findsNothing);
    expect(find.text('Undo'), findsNothing);
  });

  // Test 33: Undo still works when tapped before the timeout
  testWidgets('Undo before timeout restores previous state', (tester) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(800, 900);
    tester.view.devicePixelRatio = 1.0;

    SharedPreferences.setMockInitialValues({
      _habitsKey: jsonEncode([_binaryHabit]),
    });

    await tester.pumpWidget(_homeScreen());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.radio_button_unchecked));
    await _pumpSnackBarVisible(tester);
    expect(find.byIcon(Icons.circle), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pump();
    expect(find.byIcon(Icons.radio_button_unchecked), findsOneWidget);
  });

  // Test 34: After auto-dismiss, habit state remains in the toggled state
  // (undo was not applied — there is nothing to tap).
  testWidgets('habit stays toggled after SnackBar auto-dismisses', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(800, 900);
    tester.view.devicePixelRatio = 1.0;

    SharedPreferences.setMockInitialValues({
      _habitsKey: jsonEncode([_binaryHabit]),
    });

    await tester.pumpWidget(_homeScreen());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.radio_button_unchecked));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300)); // entry animation
    await tester.pump(
      const Duration(seconds: 4, milliseconds: 100),
    ); // timer fires
    await tester.pump(const Duration(milliseconds: 300)); // exit animation

    expect(find.text('Undo'), findsNothing);
    expect(find.byIcon(Icons.circle), findsOneWidget);
  });

  // Test 35: A second action replaces the first SnackBar
  testWidgets('second action replaces the first SnackBar', (tester) async {
    SharedPreferences.setMockInitialValues({
      _habitsKey: jsonEncode([
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

    await tester.pumpWidget(_homeScreen());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.radio_button_unchecked).first);
    await tester.pump();
    expect(find.text('Habit updated'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.radio_button_unchecked).last);
    await tester.pump();

    expect(find.text('Habit updated'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);
    expect(find.byType(SnackBar), findsOneWidget);
  });

  // Test 36: The second action remains undoable even though the first
  // SnackBar's .closed callback fires when it is hidden.
  // (Token guard: the stale callback must not clear the new undo state.)
  testWidgets('second action remains undoable after first SnackBar is hidden', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      _habitsKey: jsonEncode([
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

    await tester.pumpWidget(_homeScreen());
    await tester.pumpAndSettle();

    // Toggle first habit — SnackBar 1 appears.
    await tester.tap(find.byIcon(Icons.radio_button_unchecked).first);
    await tester.pump();
    expect(find.text('Undo'), findsOneWidget);

    // Toggle second habit — SnackBar 1 is hidden (SnackBarClosedReason.hide),
    // SnackBar 2 is queued.
    await tester.tap(find.byIcon(Icons.radio_button_unchecked).last);
    await tester.pump(); // SnackBar 1 begins exit; SnackBar 2 queued
    await tester.pump(
      const Duration(milliseconds: 50),
    ); // advance exit animation

    // Without the token guard, the stale .closed callback for SnackBar 1 would
    // have cleared _undoPrev, making undo do nothing. With the guard the undo
    // state for the second action is still intact.
    expect(find.text('Undo'), findsOneWidget);

    // Invoke undo directly: the button is in the render tree but its computed
    // centre can fall slightly outside the viewport with two habits rendered,
    // so we call onPressed() instead of using a position-based tap.
    tester
        .widget<TextButton>(find.widgetWithText(TextButton, 'Undo'))
        .onPressed
        ?.call();
    await tester.pump(); // process the undo setState

    // Only the second habit reverts to unchecked; the first stays checked.
    expect(find.byIcon(Icons.radio_button_unchecked), findsOneWidget);
  });

  // Test 37: SnackBar is not re-shown on subsequent rebuild frames.
  // (Verifies showSnackBar is not called inside build.)
  testWidgets('SnackBar is not re-shown on subsequent rebuild frames', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      _habitsKey: jsonEncode([_binaryHabit]),
    });

    await tester.pumpWidget(_homeScreen());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.radio_button_unchecked));
    await tester.pump();

    // Several more frames — would accumulate SnackBars if showSnackBar
    // were mistakenly called during build.
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text('Habit updated'), findsOneWidget);
  });
}
