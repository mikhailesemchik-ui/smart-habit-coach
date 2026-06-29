import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_habit_coach/features/home/data/notification_service.dart';
import 'package:smart_habit_coach/features/home/domain/habit.dart';
import 'package:smart_habit_coach/features/home/presentation/habit_details_screen.dart';
import 'package:smart_habit_coach/features/home/presentation/home_screen.dart';
import 'package:smart_habit_coach/features/navigation/presentation/main_navigation_screen.dart';
import 'package:smart_habit_coach/features/profile/domain/app_settings.dart';

class _FakeNotifications extends NotificationService {
  final List<String> scheduled = [];

  @override
  Future<void> initialize() async {}

  @override
  Future<void> scheduleHabitReminder(Habit habit) async {
    scheduled.add(habit.id);
  }

  @override
  Future<void> cancelHabitReminder(String habitId) async {}
}

// Saturday 2026-06-27 (weekday 6) — used only for HabitDetailsScreen injection.
final _saturday = DateTime(2026, 6, 27);

String _encode(List<Map<String, dynamic>> habits) => jsonEncode(habits);

Map<String, dynamic> _archivedJson({
  String id = '1',
  String title = 'Yoga',
  List<int> weekdays = const [1, 2, 3, 4, 5, 6, 7],
}) => {
  'id': id,
  'title': title,
  'scheduledTime': '08:00 AM',
  'iconId': 'fitness',
  'weekdays': weekdays,
  'completedDates': <String>[],
  'minimumCompletedDates': <String>[],
  'status': 'archived',
};

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  // ── Test 9: restore persists after app restart ────────────────────────────
  testWidgets('restored habit appears in Today after a fresh HomeScreen load', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'habits': _encode([
        {
          'id': '1',
          'title': 'Yoga',
          'scheduledTime': '08:00 AM',
          'iconId': 'fitness',
          'weekdays': [1, 2, 3, 4, 5, 6, 7],
          'completedDates': <String>[],
          'minimumCompletedDates': <String>[],
          'status': 'active',
        },
      ]),
    });

    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Yoga'), findsOneWidget);
  });

  // ── Test 7: restored habit appears only if scheduled today ───────────────
  testWidgets('restored habit scheduled today appears in Today list', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'habits': _encode([
        {
          'id': '1',
          'title': 'Yoga',
          'scheduledTime': '08:00 AM',
          'iconId': 'fitness',
          'weekdays': [1, 2, 3, 4, 5, 6, 7], // every day
          'completedDates': <String>[],
          'minimumCompletedDates': <String>[],
          'status': 'active',
        },
      ]),
    });

    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Yoga'), findsOneWidget);
  });

  // ── Test 8: restored habit absent if not scheduled today ─────────────────
  testWidgets('restored habit not scheduled today does not appear in Today', (
    tester,
  ) async {
    // Dynamically exclude today's weekday so the test is not day-sensitive.
    final todayWd = DateTime.now().weekday;
    final notTodayWd = todayWd == 1 ? 7 : 1; // If Mon→Sun; otherwise Mon.
    SharedPreferences.setMockInitialValues({
      'habits': _encode([
        {
          'id': '1',
          'title': 'Yoga',
          'scheduledTime': '08:00 AM',
          'iconId': 'fitness',
          'weekdays': [notTodayWd],
          'completedDates': <String>[],
          'minimumCompletedDates': <String>[],
          'status': 'active',
        },
      ]),
    });

    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Yoga'), findsNothing);
    expect(find.text('No habits scheduled for today'), findsOneWidget);
  });

  // ── Test 10: restore reschedules notifications ────────────────────────────
  testWidgets('restoring an archived habit schedules its notification', (
    tester,
  ) async {
    final fake = _FakeNotifications();
    final habit = Habit(
      id: 'h1',
      title: 'Yoga',
      scheduledTime: '08:00 AM',
      icon: Icons.fitness_center_outlined,
      weekdays: const [1, 2, 3, 4, 5, 6, 7],
      status: HabitStatus.archived,
    );

    SharedPreferences.setMockInitialValues({
      'habits': _encode([habit.toJson()]),
    });

    await tester.pumpWidget(
      MaterialApp(
        home: HabitDetailsScreen(
          habit: habit,
          notificationService: fake,
          today: _saturday,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Restore habit'));
    await tester.tap(find.text('Restore habit'));
    await tester.pumpAndSettle();

    expect(fake.scheduled, contains('h1'));
  });

  // ── Test 6: restoring refreshes Today immediately (via tab switch) ────────
  testWidgets(
    'switching to Today tab after a restore shows the habit without restart',
    (tester) async {
      // Start with an archived habit.
      SharedPreferences.setMockInitialValues({
        'habits': _encode([_archivedJson()]),
        'onboarding_completed': true,
      });

      await tester.pumpWidget(
        MaterialApp(
          home: MainNavigationScreen(
            settings: const AppSettings(),
            onSettingsChanged: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Today tab: habit is archived so not shown.
      expect(find.text('Yoga'), findsNothing);

      // Switch to Profile tab.
      await tester.tap(find.byIcon(Icons.person_outline));
      await tester.pumpAndSettle();

      // Simulate a restore by writing the active version directly to storage.
      // This mirrors what HabitDetailsScreen._restoreHabit() + _persistHabit() does.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'habits',
        _encode([
          {..._archivedJson(), 'status': 'active'},
        ]),
      );

      // Switch back to Today tab → _homeRefreshToken increments → HomeScreen
      // is recreated with a new key and reloads from storage.
      await tester.tap(find.byIcon(Icons.today_outlined));
      await tester.pumpAndSettle();

      expect(find.text('Yoga'), findsOneWidget);
    },
  );
}
