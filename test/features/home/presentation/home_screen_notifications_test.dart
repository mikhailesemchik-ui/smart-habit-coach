import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_habit_coach/features/home/data/notification_service.dart';
import 'package:smart_habit_coach/features/home/domain/habit.dart';
import 'package:smart_habit_coach/features/home/presentation/home_screen.dart';

class FakeNotificationService extends NotificationService {
  final List<String> scheduledHabitIds = [];
  final List<Habit> scheduledHabits = [];
  final List<String> cancelledHabitIds = [];
  var initializeCallCount = 0;

  @override
  Future<void> initialize() async {
    initializeCallCount++;
  }

  @override
  Future<void> scheduleHabitReminder(Habit habit) async {
    scheduledHabitIds.add(habit.id);
    scheduledHabits.add(habit);
  }

  @override
  Future<void> cancelHabitReminder(String habitId) async {
    cancelledHabitIds.add(habitId);
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<FakeNotificationService> pumpHomeScreen(WidgetTester tester) async {
    final fake = FakeNotificationService();
    await tester.pumpWidget(
      MaterialApp(home: HomeScreen(notificationService: fake)),
    );
    await tester.pumpAndSettle();
    return fake;
  }

  testWidgets('initializes the notification service once on load', (
    tester,
  ) async {
    final fake = await pumpHomeScreen(tester);

    expect(fake.initializeCallCount, 1);
  });

  testWidgets('schedules a reminder after creating a habit', (tester) async {
    final fake = await pumpHomeScreen(tester);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Habit title'),
      'Stretch',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(fake.scheduledHabitIds.length, 1);
  });

  testWidgets('reschedules a reminder after editing a habit', (tester) async {
    final fake = await pumpHomeScreen(tester);

    await tester.tap(find.text('Drink water'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Edit habit'));
    await tester.tap(find.text('Edit habit'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Habit title'),
      'Drink more water',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(fake.scheduledHabitIds, ['1']);
  });

  testWidgets('cancels the reminder after deleting a habit', (tester) async {
    final fake = await pumpHomeScreen(tester);

    await tester.tap(find.text('Drink water'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.widgetWithText(OutlinedButton, 'Delete habit'),
    );
    await tester.tap(find.widgetWithText(OutlinedButton, 'Delete habit'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(fake.cancelledHabitIds, ['1']);
  });

  // Test 17: scheduleHabitReminder receives habit with selected weekdays.
  testWidgets(
    'schedules reminder with selected weekdays for a specific-days habit',
    (tester) async {
      final fake = await pumpHomeScreen(tester);

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Habit title'),
        'Gym',
      );

      // Switch to Specific days
      await tester.tap(find.text('Specific days'));
      await tester.pumpAndSettle();

      // Default: all 7 chips selected. Deselect everything except Mon (1).
      for (final label in ['Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']) {
        await tester.tap(find.widgetWithText(FilterChip, label));
        await tester.pump();
      }

      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(fake.scheduledHabits.length, 1);
      expect(fake.scheduledHabits.first.weekdays, [1]);
    },
  );

  // Test 18: editing replaces old schedule (scheduleHabitReminder called again).
  testWidgets('editing a habit triggers scheduleHabitReminder again', (
    tester,
  ) async {
    final fake = await pumpHomeScreen(tester);

    await tester.tap(find.text('Drink water'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Edit habit'));
    await tester.tap(find.text('Edit habit'));
    await tester.pumpAndSettle();

    // Switch from Every day to Specific days (Mon + Wed)
    await tester.tap(find.text('Specific days'));
    await tester.pumpAndSettle();

    for (final label in ['Tue', 'Thu', 'Fri', 'Sat', 'Sun']) {
      await tester.tap(find.widgetWithText(FilterChip, label));
      await tester.pump();
    }

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    // scheduleHabitReminder is called with updated weekdays
    expect(fake.scheduledHabits.last.weekdays, [1, 3]);
    expect(fake.scheduledHabitIds, ['1']);
  });

  // Test 19: deleting cancels the habit reminder (covered by existing test).
}
