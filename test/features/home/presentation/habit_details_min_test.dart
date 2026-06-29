import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_habit_coach/features/home/domain/habit.dart';
import 'package:smart_habit_coach/features/home/presentation/habit_details_screen.dart';

// Fixed reference: Saturday 2026-06-27.
final _today = DateTime(2026, 6, 27);
const _todayKey = '2026-06-27';

Habit _habit({
  String? minimumVersion,
  Set<String> completedDates = const {},
  Set<String> minimumCompletedDates = const {},
}) => Habit(
  id: '1',
  title: 'Yoga',
  scheduledTime: '08:00 AM',
  icon: Icons.fitness_center_outlined,
  weekdays: const [1, 2, 3, 4, 5, 6, 7],
  completedDates: completedDates,
  minimumCompletedDates: minimumCompletedDates,
  minimumVersion: minimumVersion,
);

Widget _screen(Habit habit) => MaterialApp(
  home: HabitDetailsScreen(habit: habit, today: _today),
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  // ── Test 15: habit details calendar supports all three states ─────────────

  testWidgets(
    'calendar shows today as completed (full) when date is in completedDates',
    (tester) async {
      final habit = _habit(
        minimumVersion: 'Light stretch',
        completedDates: {_todayKey},
      );
      await tester.pumpWidget(_screen(habit));
      await tester.pumpAndSettle();

      expect(find.text('Completed'), findsOneWidget);
    },
  );

  testWidgets(
    'calendar shows today as minimum when date is in minimumCompletedDates',
    (tester) async {
      final habit = _habit(
        minimumVersion: 'Light stretch',
        minimumCompletedDates: {_todayKey},
      );
      await tester.pumpWidget(_screen(habit));
      await tester.pumpAndSettle();

      expect(find.text('Minimum'), findsOneWidget);
    },
  );

  testWidgets(
    'calendar cycles none to full to minimum to none on tap for min-version habit',
    (tester) async {
      final habit = _habit(minimumVersion: 'Light stretch');
      await tester.pumpWidget(_screen(habit));
      await tester.pumpAndSettle();

      expect(find.text('Not completed'), findsOneWidget);

      await tester.ensureVisible(find.text('27'));
      await tester.tap(find.text('27'));
      await tester.pumpAndSettle();

      expect(find.text('Completed'), findsOneWidget);

      await tester.ensureVisible(find.text('27'));
      await tester.tap(find.text('27'));
      await tester.pumpAndSettle();

      expect(find.text('Minimum'), findsOneWidget);

      await tester.ensureVisible(find.text('27'));
      await tester.tap(find.text('27'));
      await tester.pumpAndSettle();

      expect(find.text('Not completed'), findsOneWidget);
    },
  );

  testWidgets('habit without minimumVersion uses binary toggle in calendar', (
    tester,
  ) async {
    final habit = _habit();
    await tester.pumpWidget(_screen(habit));
    await tester.pumpAndSettle();

    expect(find.text('Not completed'), findsOneWidget);

    await tester.ensureVisible(find.text('27'));
    await tester.tap(find.text('27'));
    await tester.pumpAndSettle();

    expect(find.text('Completed'), findsOneWidget);
    expect(find.text('Minimum'), findsNothing);

    await tester.ensureVisible(find.text('27'));
    await tester.tap(find.text('27'));
    await tester.pumpAndSettle();

    expect(find.text('Not completed'), findsOneWidget);
  });
}
