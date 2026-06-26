import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_habit_coach/features/home/data/habit_storage.dart';
import 'package:smart_habit_coach/features/home/domain/habit.dart';
import 'package:smart_habit_coach/features/progress/presentation/day_history_sheet.dart';

// Fixed past date used across all tests.
final _day = DateTime(2026, 1, 15); // Thursday, Jan 15 2026
const _dateKey = '2026-01-15';
const _priorDateKey = '2026-01-10';

Habit _habit(String id, String title, {Set<String> completedDates = const {}}) {
  return Habit(
    id: id,
    title: title,
    scheduledTime: '08:00 AM',
    icon: Icons.fitness_center_outlined,
    completedDates: completedDates,
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
}
