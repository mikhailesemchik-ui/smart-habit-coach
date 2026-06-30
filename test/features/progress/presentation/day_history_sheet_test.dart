import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_habit_coach/features/home/data/habit_storage.dart';
import 'package:smart_habit_coach/features/home/domain/habit.dart';
import 'package:smart_habit_coach/features/progress/presentation/day_history_sheet.dart';

// Fixed past date used across all tests.
// Jan 15, 2026 is a Thursday (weekday = 4).
final _day = DateTime(2026, 1, 15);
const _dateKey = '2026-01-15';
const _priorDateKey = '2026-01-10';

Habit _habit(
  String id,
  String title, {
  Set<String> completedDates = const {},
  List<int>? weekdays,
}) {
  return Habit(
    id: id,
    title: title,
    scheduledTime: '08:00 AM',
    icon: Icons.fitness_center_outlined,
    completedDates: completedDates,
    weekdays: weekdays ?? const [1, 2, 3, 4, 5, 6, 7],
  );
}

Widget _sheet(
  List<Habit> habits, {
  void Function(List<Habit>)? onHabitsChanged,
}) {
  return MaterialApp(
    home: Scaffold(
      body: DayHistorySheet(
        day: _day,
        habits: habits,
        onHabitsChanged: onHabitsChanged ?? (_) {},
      ),
    ),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  // Test 2: existing completion state shown correctly
  testWidgets(
    'shows checked state for habits already completed on selected date',
    (tester) async {
      final habits = [
        _habit('1', 'Run', completedDates: {_dateKey}),
        _habit('2', 'Read'),
      ];

      await tester.pumpWidget(_sheet(habits));
      await tester.pump();

      final checkboxes = tester
          .widgetList<Checkbox>(find.byType(Checkbox))
          .toList();
      expect(checkboxes[0].value, isTrue);
      expect(checkboxes[1].value, isFalse);
    },
  );

  // Test 3: marking a past date complete adds only that normalized date
  testWidgets(
    'checking a habit adds only the selected date to completedDates',
    (tester) async {
      List<Habit>? captured;
      final habits = [_habit('1', 'Run')];

      await tester.pumpWidget(
        _sheet(habits, onHabitsChanged: (updated) => captured = updated),
      );
      await tester.pump();

      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();

      expect(captured, isNotNull);
      expect(captured!.first.completedDates, {_dateKey});
      expect(captured!.first.completedDates.length, 1);
    },
  );

  // Test 4: unchecking removes only that date and preserves other dates
  testWidgets(
    'unchecking removes only the selected date and keeps prior dates',
    (tester) async {
      List<Habit>? captured;
      final habits = [
        _habit('1', 'Run', completedDates: {_priorDateKey, _dateKey}),
      ];

      await tester.pumpWidget(
        _sheet(habits, onHabitsChanged: (updated) => captured = updated),
      );
      await tester.pump();

      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();

      expect(captured!.first.completedDates, {_priorDateKey});
      expect(captured!.first.completedDates, isNot(contains(_dateKey)));
    },
  );

  // Test 5: changes persist after reloading HabitStorage
  testWidgets('toggling a habit persists through a HabitStorage reload', (
    tester,
  ) async {
    final habits = [_habit('1', 'Run')];

    await tester.pumpWidget(_sheet(habits));
    await tester.pump();

    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();

    final loaded = await HabitStorage().loadHabits();
    expect(loaded, isNotNull);
    expect(loaded!.first.completedDates, contains(_dateKey));
    expect(loaded.first.completedDates.length, 1);
  });

  // Test 9: empty habits state handled safely
  testWidgets('shows "No habits yet" when the habit list is empty', (
    tester,
  ) async {
    await tester.pumpWidget(_sheet([]));
    await tester.pump();

    expect(find.text('No habits yet'), findsOneWidget);
    expect(find.byType(CheckboxListTile), findsNothing);
  });

  // Test 10: DayHistorySheet filters by scheduled date.
  // _day = Thursday (weekday=4). A Mon-only habit must not appear.
  testWidgets('shows only habits scheduled for the selected date', (
    tester,
  ) async {
    final habits = [
      _habit('1', 'Thursday habit', weekdays: [4]), // Thu = weekday 4
      _habit('2', 'Monday habit', weekdays: [1]), // Mon = weekday 1
    ];

    await tester.pumpWidget(_sheet(habits));
    await tester.pump();

    expect(find.text('Thursday habit'), findsOneWidget);
    expect(find.text('Monday habit'), findsNothing);
  });

  // Test 11: no-scheduled-habits shows dedicated message.
  testWidgets(
    'shows "No habits scheduled" when habits exist but none for date',
    (tester) async {
      // _day is Thursday (weekday=4); schedule only for Monday
      final habits = [
        _habit('1', 'Gym', weekdays: [1]),
      ];

      await tester.pumpWidget(_sheet(habits));
      await tester.pump();

      expect(find.text('No habits scheduled'), findsOneWidget);
      expect(find.text('No habits yet'), findsNothing);
      expect(find.byType(CheckboxListTile), findsNothing);
    },
  );

  // toggling an unscheduled habit's sibling updates the full list.
  testWidgets('toggling a scheduled habit updates the full habit list', (
    tester,
  ) async {
    List<Habit>? captured;
    // habit '1' is for Thu (shown), habit '2' is for Mon (hidden)
    final habits = [
      _habit('1', 'Run', weekdays: [4]),
      _habit('2', 'Read', weekdays: [1]),
    ];

    await tester.pumpWidget(
      _sheet(habits, onHabitsChanged: (updated) => captured = updated),
    );
    await tester.pump();

    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();

    // Callback provides the FULL list (both habits), not just scheduled
    expect(captured, isNotNull);
    expect(captured!.length, 2);
    expect(captured!.first.completedDates, contains(_dateKey));
  });

  // Test 10: scrollable and does not overflow on a compact screen
  testWidgets('does not overflow on a compact screen with many habits', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(360, 480);
    tester.view.devicePixelRatio = 1.0;
    tester.view.padding = const FakeViewPadding(bottom: 48);

    final habits = List.generate(12, (i) => _habit('$i', 'Habit number $i'));

    await tester.pumpWidget(_sheet(habits));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Habit number 0'), findsOneWidget);
  });

  testWidgets('title shows the formatted date', (tester) async {
    await tester.pumpWidget(_sheet([_habit('1', 'Run')]));
    await tester.pump();

    expect(find.text(formatSheetDate(_day)), findsOneWidget);
    // Thursday, Jan 15
    expect(find.text('Thursday, Jan 15'), findsOneWidget);
  });

  testWidgets('subtitle shows correct completed count', (tester) async {
    final habits = [
      _habit('1', 'Run', completedDates: {_dateKey}),
      _habit('2', 'Read'),
      _habit('3', 'Walk'),
    ];

    await tester.pumpWidget(_sheet(habits));
    await tester.pump();

    expect(find.text('1 of 3 completed'), findsOneWidget);
  });

  // Test 17: DayHistory shows quantitative tile
  testWidgets('shows quantitative habit tile with Log button', (tester) async {
    final habit = Habit(
      id: 'q',
      title: 'Water',
      scheduledTime: '08:00 AM',
      icon: Icons.local_drink_outlined,
      trackingType: HabitTrackingType.quantitative,
      targetValue: 3.0,
      unit: 'L',
      weekdays: const [1, 2, 3, 4, 5, 6, 7],
    );

    await tester.pumpWidget(_sheet([habit]));
    await tester.pump();

    expect(find.text('Water'), findsOneWidget);
    // Log button confirms quantitative tile rendered
    expect(find.text('Log'), findsOneWidget);
    // No checkbox for quantitative
    expect(find.byType(CheckboxListTile), findsNothing);
  });

  // Test 17b: quantitative edit saves to storage
  testWidgets('quantitative progress saves to storage', (tester) async {
    final habit = Habit(
      id: 'q',
      title: 'Water',
      scheduledTime: '08:00 AM',
      icon: Icons.local_drink_outlined,
      trackingType: HabitTrackingType.quantitative,
      targetValue: 3.0,
      unit: 'L',
      weekdays: const [1, 2, 3, 4, 5, 6, 7],
    );

    await tester.pumpWidget(_sheet([habit]));
    await tester.pump();

    // Tap Log button
    await tester.tap(find.text('Log'));
    await tester.pumpAndSettle();

    // Enter value in progress entry sheet
    await tester.enterText(find.byType(TextField).first, '2.5');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    final loaded = await HabitStorage().loadHabits();
    expect(loaded, isNotNull);
    expect(loaded!.first.progressFor(_day), closeTo(2.5, 0.001));
  });

  testWidgets('DayHistorySheet supports adding and clearing skip reasons', (
    tester,
  ) async {
    List<Habit>? captured;
    final habits = [_habit('1', 'Run')];

    await tester.pumpWidget(
      _sheet(habits, onHabitsChanged: (updated) => captured = updated),
    );
    await tester.pump();

    await tester.tap(find.text('Why was it missed?'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Too difficult'));
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(captured!.first.skipReasonFor(_day), HabitSkipReason.tooDifficult);
    expect(find.textContaining('Too difficult'), findsOneWidget);

    await tester.tap(find.text('Why was it missed?'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Clear reason'));
    await tester.pumpAndSettle();

    expect(captured!.first.skipReasonFor(_day), isNull);
  });

  // Test: DayHistory shows partial reason button for partial quantitative habit
  testWidgets(
    'partial quantitative habit shows "Why wasn\'t the target reached?" button',
    (tester) async {
      final habit = Habit(
        id: '1',
        title: 'Water',
        scheduledTime: '08:00 AM',
        icon: Icons.local_drink_outlined,
        weekdays: const [1, 2, 3, 4, 5, 6, 7],
        trackingType: HabitTrackingType.quantitative,
        targetValue: 3.0,
        unit: 'L',
        quantitativeProgress: const {_dateKey: 1.5},
      );

      await tester.pumpWidget(_sheet([habit]));
      await tester.pump();

      expect(find.text("Why wasn't the target reached?"), findsOneWidget);
      expect(find.text('Why was it missed?'), findsNothing);
    },
  );

  // Test: DayHistory saves partial reason and shows label in subtitle
  testWidgets(
    'saves partial reason and shows compact label in DayHistory tile subtitle',
    (tester) async {
      List<Habit>? captured;
      final habit = Habit(
        id: '1',
        title: 'Water',
        scheduledTime: '08:00 AM',
        icon: Icons.local_drink_outlined,
        weekdays: const [1, 2, 3, 4, 5, 6, 7],
        trackingType: HabitTrackingType.quantitative,
        targetValue: 3.0,
        unit: 'L',
        quantitativeProgress: const {_dateKey: 1.5},
      );

      await tester.pumpWidget(
        _sheet([habit], onHabitsChanged: (updated) => captured = updated),
      );
      await tester.pump();

      await tester.tap(find.text("Why wasn't the target reached?"));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Too tired'));
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(
        captured!.first.partialReasonFor(_day),
        HabitPartialReason.tooTired,
      );
      expect(find.textContaining('Too tired'), findsOneWidget);
    },
  );
}
