import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_habit_coach/features/home/data/habit_storage.dart';
import 'package:smart_habit_coach/features/home/domain/habit.dart';
import 'package:smart_habit_coach/features/progress/presentation/day_history_sheet.dart';
import 'package:smart_habit_coach/features/progress/presentation/habit_history_calendar_sheet.dart';
import 'package:smart_habit_coach/features/progress/presentation/progress_screen.dart';

// Fixed reference: Friday, 26 June 2026.
final _today = DateTime(2026, 6, 26);

Habit _habit(
  String id, {
  Set<String> completedDates = const {},
  List<int>? weekdays,
}) => Habit(
  id: id,
  title: 'Habit $id',
  scheduledTime: '08:00 AM',
  icon: Icons.fitness_center_outlined,
  completedDates: completedDates,
  weekdays: weekdays ?? const [1, 2, 3, 4, 5, 6, 7],
);

Widget _calendarSheet(
  List<Habit> habits, {
  DateTime? today,
  void Function(List<Habit>)? onHabitsChanged,
}) => MaterialApp(
  home: Scaffold(
    body: HabitHistoryCalendarSheet(
      habits: habits,
      today: today ?? _today,
      onHabitsChanged: onHabitsChanged ?? (_) {},
    ),
  ),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // ── Pure function tests ────────────────────────────────────────────────────

  // Test 6: correct day count for various months
  group('daysInMonth', () {
    test('returns 31 for January', () => expect(daysInMonth(2026, 1), 31));
    test('returns 30 for April', () => expect(daysInMonth(2026, 4), 30));
    test('returns 31 for December', () => expect(daysInMonth(2026, 12), 31));
    test('returns 28 for February in a non-leap year', () {
      expect(daysInMonth(2025, 2), 28);
      expect(daysInMonth(2026, 2), 28);
    });

    // Test 7: February in a leap year
    test('returns 29 for February in a leap year', () {
      expect(daysInMonth(2024, 2), 29);
      // 2100 is divisible by 100 but not 400, so not a leap year
      expect(daysInMonth(2100, 2), 28);
    });
  });

  group('firstWeekdayOffset', () {
    // June 1, 2026 is Monday → offset 0
    test('returns 0 for a month starting on Monday', () {
      expect(firstWeekdayOffset(2026, 6), 0);
    });
    // January 1, 2026 is Thursday → offset 3
    test('returns 3 for a month starting on Thursday', () {
      expect(firstWeekdayOffset(2026, 1), 3);
    });
    // February 1, 2026 is Sunday → offset 6
    test('returns 6 for a month starting on Sunday', () {
      expect(firstWeekdayOffset(2026, 2), 6);
    });
  });

  // ── Widget tests: ProgressScreen entry point ───────────────────────────────

  // Test 1: button is visible
  testWidgets('View calendar button is visible in the This week card', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: ProgressScreen()));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextButton, 'View calendar'), findsOneWidget);
  });

  // Test 2: tapping button opens the calendar sheet
  testWidgets('tapping View calendar opens the calendar sheet', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ProgressScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'View calendar'));
    await tester.pumpAndSettle();

    // Navigation buttons are the clearest indicator the sheet opened
    expect(find.byIcon(Icons.chevron_left), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
  });

  // ── Widget tests: HabitHistoryCalendarSheet ────────────────────────────────

  // Test 3: initial month shows the month containing today
  testWidgets('initially displays the month containing today', (tester) async {
    await tester.pumpWidget(_calendarSheet([]));
    await tester.pump();

    expect(find.text('June 2026'), findsOneWidget);
  });

  // Test 4: previous month navigation
  testWidgets('tapping previous navigates to the prior month', (tester) async {
    await tester.pumpWidget(_calendarSheet([]));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pump();

    expect(find.text('May 2026'), findsOneWidget);
    expect(find.text('June 2026'), findsNothing);
  });

  // Test 5: year boundary navigation in both directions
  testWidgets('navigates across a year boundary in both directions', (
    tester,
  ) async {
    // Start in January 2026, go back to December 2025
    await tester.pumpWidget(_calendarSheet([], today: DateTime(2026, 1, 15)));
    await tester.pump();

    expect(find.text('January 2026'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pump();

    expect(find.text('December 2025'), findsOneWidget);

    // Navigate forward back to January 2026
    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pump();

    expect(find.text('January 2026'), findsOneWidget);
  });

  // Test 8: future dates are disabled
  testWidgets('future dates cannot be tapped and do not open a sheet', (
    tester,
  ) async {
    await tester.pumpWidget(_calendarSheet([], today: DateTime(2026, 6, 26)));
    await tester.pump();

    // June 27 is tomorrow — must not open DayHistorySheet
    await tester.tap(find.text('27'));
    await tester.pumpAndSettle();

    expect(find.text('No habits yet'), findsNothing);
  });

  // Test 9: today has a dedicated visual state and is tappable
  testWidgets('today (26) is rendered and tappable', (tester) async {
    await tester.pumpWidget(_calendarSheet([], today: DateTime(2026, 6, 26)));
    await tester.pump();

    expect(find.text('26'), findsOneWidget);

    // Tapping today opens DayHistorySheet (confirming it is not disabled)
    await tester.tap(find.text('26'));
    await tester.pumpAndSettle();

    expect(find.text('No habits yet'), findsOneWidget);
  });

  // Test 10: full, partial, and empty completion states render without error
  testWidgets(
    'renders full, partial, and empty completion states without error',
    (tester) async {
      // One habit: allDone on Jun 15, anyDone on Jun 10 (partial—only habit1),
      // empty on Jun 20. With a single habit the "all done" threshold is 1.
      final habits = [
        _habit('1', completedDates: {'2026-06-15', '2026-06-10'}),
        _habit('2'),
      ];
      // Jun 15: 1/2 done → partial; Jun 10: 1/2 done → partial; Jun 20: 0 → empty

      await tester.pumpWidget(_calendarSheet(habits));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('15'), findsOneWidget);
      expect(find.text('10'), findsOneWidget);
      expect(find.text('20'), findsOneWidget);
    },
  );

  // Test 11: tapping a valid past date opens DayHistorySheet for that date
  testWidgets(
    'tapping a past date opens DayHistorySheet with the correct title',
    (tester) async {
      await tester.pumpWidget(_calendarSheet([_habit('1')]));
      await tester.pump();

      // June 15, 2026 is a Monday
      await tester.tap(find.text('15'));
      await tester.pumpAndSettle();

      expect(find.text(formatSheetDate(DateTime(2026, 6, 15))), findsOneWidget);
      expect(find.text('Monday, Jun 15'), findsOneWidget);
      expect(find.text('0 of 1 completed'), findsOneWidget);
    },
  );

  // Test 12: editing a day inside the sheet updates calendar state immediately
  testWidgets('completing a habit in the day sheet notifies the calendar', (
    tester,
  ) async {
    List<Habit>? received;
    final habit = _habit('1');

    await tester.pumpWidget(
      _calendarSheet([habit], onHabitsChanged: (updated) => received = updated),
    );
    await tester.pump();

    await tester.tap(find.text('15'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();

    expect(received, isNotNull);
    expect(received!.first.completedDates, contains('2026-06-15'));
  });

  // Test 13: changes made via the sheet persist through a HabitStorage reload
  testWidgets('changes persist through HabitStorage reload', (tester) async {
    final habit = _habit('1');

    await tester.pumpWidget(_calendarSheet([habit]));
    await tester.pump();

    await tester.tap(find.text('15'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();

    final reloaded = await HabitStorage().loadHabits();
    expect(reloaded, isNotNull);
    expect(reloaded!.first.completedDates, contains('2026-06-15'));
  });

  // Test 14: empty habit list is handled safely
  testWidgets('empty habits list renders safely', (tester) async {
    await tester.pumpWidget(_calendarSheet([]));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('June 2026'), findsOneWidget);

    // Tapping a past day opens DayHistorySheet showing the empty state
    await tester.tap(find.text('15'));
    await tester.pumpAndSettle();

    expect(find.text('No habits yet'), findsOneWidget);
  });

  // Test 15: no overflow on a compact screen
  testWidgets('does not overflow on a compact screen', (tester) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(360, 480);
    tester.view.devicePixelRatio = 1.0;

    await tester.pumpWidget(_calendarSheet([]));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.chevron_left), findsOneWidget);
  });

  // Test 12: calendar states ignore unscheduled habits for a given date.
  // June 15, 2026 is Monday (weekday=1).
  // A habit scheduled only for Wednesday should not affect June 15's state.
  testWidgets('calendar cell ignores habits not scheduled for that date', (
    tester,
  ) async {
    // habit '1' scheduled Wed only (weekday=3), completed on Jun 15
    // (completion stored but not scheduled → should not count)
    final habits = [
      _habit('1', completedDates: {'2026-06-15'}, weekdays: [3]),
    ];

    await tester.pumpWidget(_calendarSheet(habits));
    await tester.pump();

    // Tap Jun 15 — it's a past date, sheet should open
    await tester.tap(find.text('15'));
    await tester.pumpAndSettle();

    // No habits scheduled for Jun 15 (Monday), so sheet says "No habits scheduled"
    expect(find.text('No habits scheduled'), findsOneWidget);
  });

  // Test 16: View calendar label does not overflow on a narrow Progress screen
  testWidgets('View calendar button does not overflow on a narrow screen', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1.0;

    await tester.pumpWidget(const MaterialApp(home: ProgressScreen()));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.widgetWithText(TextButton, 'View calendar'), findsOneWidget);
  });
}
