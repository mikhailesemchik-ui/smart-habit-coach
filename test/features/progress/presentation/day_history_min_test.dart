import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_habit_coach/features/home/domain/habit.dart';
import 'package:smart_habit_coach/features/progress/presentation/day_history_sheet.dart';

// Jan 15, 2026 is a Thursday (weekday 4).
final _day = DateTime(2026, 1, 15);
const _dateKey = '2026-01-15';

Habit _habit({
  String id = '1',
  String title = 'Run',
  String? minimumVersion,
  Set<String> completedDates = const {},
  Set<String> minimumCompletedDates = const {},
}) => Habit(
  id: id,
  title: title,
  scheduledTime: '08:00 AM',
  icon: Icons.fitness_center_outlined,
  weekdays: const [1, 2, 3, 4, 5, 6, 7],
  completedDates: completedDates,
  minimumCompletedDates: minimumCompletedDates,
  minimumVersion: minimumVersion,
);

Widget _sheet(List<Habit> habits) => MaterialApp(
  home: Scaffold(
    body: DayHistorySheet(day: _day, habits: habits, onHabitsChanged: (_) {}),
  ),
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  // ── Test 14: DayHistorySheet supports all three states ───────────────────────

  testWidgets('habit without minimumVersion renders CheckboxListTile', (
    tester,
  ) async {
    await tester.pumpWidget(_sheet([_habit()]));
    await tester.pump();

    expect(find.byType(CheckboxListTile), findsOneWidget);
    // No three-button row expected.
    expect(find.byIcon(Icons.adjust), findsNothing);
  });

  testWidgets('habit with minimumVersion renders three-state control', (
    tester,
  ) async {
    await tester.pumpWidget(_sheet([_habit(minimumVersion: 'Light jog')]));
    await tester.pump();

    expect(find.byType(CheckboxListTile), findsNothing);
    // Three status icons present.
    expect(find.byIcon(Icons.radio_button_unchecked), findsOneWidget);
    expect(find.byIcon(Icons.adjust), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
  });

  testWidgets('minimum state shows subtitle and adjust icon as selected', (
    tester,
  ) async {
    final habit = _habit(
      minimumVersion: 'Light jog',
      minimumCompletedDates: {_dateKey},
    );
    await tester.pumpWidget(_sheet([habit]));
    await tester.pump();

    expect(find.text('Minimum done'), findsOneWidget);
  });

  testWidgets('tapping full button in three-state tile updates to full', (
    tester,
  ) async {
    List<Habit>? received;
    final habit = _habit(minimumVersion: 'Light jog');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DayHistorySheet(
            day: _day,
            habits: [habit],
            onHabitsChanged: (h) => received = h,
          ),
        ),
      ),
    );
    await tester.pump();

    // Tap the full (check_circle) button.
    await tester.tap(find.byIcon(Icons.check_circle));
    await tester.pump();

    expect(received, isNotNull);
    expect(
      received!.first.completionStatusFor(_dateKey),
      HabitCompletionStatus.full,
    );
  });

  testWidgets('tapping minimum button in three-state tile updates to minimum', (
    tester,
  ) async {
    List<Habit>? received;
    final habit = _habit(minimumVersion: 'Light jog');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DayHistorySheet(
            day: _day,
            habits: [habit],
            onHabitsChanged: (h) => received = h,
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byIcon(Icons.adjust));
    await tester.pump();

    expect(received, isNotNull);
    expect(
      received!.first.completionStatusFor(_dateKey),
      HabitCompletionStatus.minimum,
    );
  });
}
