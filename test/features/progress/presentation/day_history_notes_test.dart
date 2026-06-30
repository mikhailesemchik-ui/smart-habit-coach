import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_habit_coach/features/home/domain/habit.dart';
import 'package:smart_habit_coach/features/progress/presentation/day_history_sheet.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // Test 14: DayHistorySheet shows "Add note" on each tile
  testWidgets('DayHistorySheet shows Add note button on binary tile', (
    tester,
  ) async {
    final day = DateTime(2026, 6, 27);
    final habit = Habit(
      id: '1',
      title: 'Read',
      scheduledTime: '08:00 AM',
      icon: Icons.book_outlined,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DayHistorySheet(
            day: day,
            habits: [habit],
            onHabitsChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Add note'), findsOneWidget);
  });

  testWidgets('DayHistorySheet shows Add note on quantitative tile', (
    tester,
  ) async {
    final day = DateTime(2026, 6, 27);
    final habit = Habit(
      id: '1',
      title: 'Water',
      scheduledTime: '08:00 AM',
      icon: Icons.local_drink_outlined,
      trackingType: HabitTrackingType.quantitative,
      targetValue: 3.0,
      unit: 'L',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DayHistorySheet(
            day: day,
            habits: [habit],
            onHabitsChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Add note'), findsOneWidget);
  });

  testWidgets('tapping Add note opens note sheet for that date', (
    tester,
  ) async {
    final day = DateTime(2026, 6, 27);
    final habit = Habit(
      id: '1',
      title: 'Read',
      scheduledTime: '08:00 AM',
      icon: Icons.book_outlined,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DayHistorySheet(
            day: day,
            habits: [habit],
            onHabitsChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add note'));
    await tester.pumpAndSettle();

    // Note sheet opened — shows title with the date and a Save button.
    // Use findsWidgets because the date also appears in the sheet header below.
    expect(find.textContaining('Saturday'), findsWidgets);
    expect(find.widgetWithText(FilledButton, 'Save'), findsOneWidget);
  });
}
