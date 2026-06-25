import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_habit_coach/features/home/data/notification_service.dart';
import 'package:smart_habit_coach/features/home/domain/habit.dart';
import 'package:smart_habit_coach/features/home/presentation/home_screen.dart';

class FakeNotificationService extends NotificationService {
  final List<String> scheduledHabitIds = [];
  final List<String> cancelledHabitIds = [];
  var initializeCallCount = 0;

  @override
  Future<void> initialize() async {
    initializeCallCount++;
  }

  @override
  Future<void> scheduleHabitReminder(Habit habit) async {
    scheduledHabitIds.add(habit.id);
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
    await tester.tap(find.widgetWithText(FilledButton, 'Edit'));
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
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(fake.cancelledHabitIds, ['1']);
  });
}
