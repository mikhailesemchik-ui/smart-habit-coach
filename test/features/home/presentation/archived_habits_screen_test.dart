import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_habit_coach/features/home/data/notification_service.dart';
import 'package:smart_habit_coach/features/home/domain/habit.dart';
import 'package:smart_habit_coach/features/home/presentation/archived_habits_screen.dart';
import 'package:smart_habit_coach/features/home/presentation/habit_details_screen.dart';

class _FakeNotifications extends NotificationService {
  final List<String> scheduled = [];
  final List<String> cancelled = [];

  @override
  Future<void> initialize() async {}

  @override
  Future<void> scheduleHabitReminder(Habit habit) async {
    scheduled.add(habit.id);
  }

  @override
  Future<void> cancelHabitReminder(String habitId) async {
    cancelled.add(habitId);
  }
}

String _habitsJson(List<Map<String, dynamic>> habits) => jsonEncode(habits);

Map<String, dynamic> _habitJson({
  required String id,
  required String title,
  String status = 'archived',
  String? pausedFromDate,
}) => {
  'id': id,
  'title': title,
  'scheduledTime': '08:00 AM',
  'iconId': 'water',
  'completedDates': <String>[],
  'weekdays': [1, 2, 3, 4, 5, 6, 7],
  'status': status,
  'pausedFromDate': pausedFromDate,
};

Future<void> _pump(WidgetTester tester, {NotificationService? ns}) async {
  await tester.pumpWidget(
    MaterialApp(home: ArchivedHabitsScreen(notificationService: ns)),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // ── Test 20: archived habits list shows archived items only ───────────────
  testWidgets('shows only archived habits, not active ones', (tester) async {
    SharedPreferences.setMockInitialValues({
      'habits': _habitsJson([
        _habitJson(id: '1', title: 'Old walk', status: 'archived'),
        _habitJson(id: '2', title: 'Active run', status: 'active'),
        _habitJson(id: '3', title: 'Old swim', status: 'archived'),
      ]),
    });

    await _pump(tester);

    expect(find.text('Old walk'), findsOneWidget);
    expect(find.text('Old swim'), findsOneWidget);
    expect(find.text('Active run'), findsNothing);
  });

  testWidgets('shows empty message when no archived habits exist', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'habits': _habitsJson([
        _habitJson(id: '1', title: 'Active run', status: 'active'),
      ]),
    });

    await _pump(tester);

    expect(find.text('No archived habits'), findsOneWidget);
  });

  testWidgets('shows empty message when no habits exist at all', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'habits': jsonEncode([])});

    await _pump(tester);

    expect(find.text('No archived habits'), findsOneWidget);
  });

  testWidgets('tapping an archived tile opens HabitDetailsScreen', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'habits': _habitsJson([
        _habitJson(id: '1', title: 'Old walk', status: 'archived'),
      ]),
    });

    await _pump(tester);

    await tester.tap(find.text('Old walk'));
    await tester.pumpAndSettle();

    expect(find.byType(HabitDetailsScreen), findsOneWidget);
  });

  // ── Test 21: restored habit disappears from archived list ─────────────────
  testWidgets('restoring a habit removes it from the archived list', (
    tester,
  ) async {
    final fake = _FakeNotifications();
    SharedPreferences.setMockInitialValues({
      'habits': _habitsJson([
        _habitJson(
          id: '1',
          title: 'Old walk',
          status: 'archived',
          pausedFromDate: '2026-06-25',
        ),
      ]),
    });

    await _pump(tester, ns: fake);

    expect(find.text('Old walk'), findsOneWidget);

    // Open details.
    await tester.tap(find.text('Old walk'));
    await tester.pumpAndSettle();

    // Restore.
    await tester.ensureVisible(find.text('Restore habit'));
    await tester.tap(find.text('Restore habit'));
    await tester.pumpAndSettle();

    // Pop back to the archived list.
    await tester.pageBack();
    await tester.pumpAndSettle();

    // Habit is no longer archived → list is empty.
    expect(find.text('Old walk'), findsNothing);
    expect(find.text('No archived habits'), findsOneWidget);
  });
}
