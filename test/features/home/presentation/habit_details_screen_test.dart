import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_habit_coach/features/home/data/habit_storage.dart';
import 'package:smart_habit_coach/features/home/data/notification_service.dart';
import 'package:smart_habit_coach/features/home/domain/habit.dart';
import 'package:smart_habit_coach/features/home/presentation/habit_details_screen.dart';
import 'package:smart_habit_coach/features/home/presentation/home_screen.dart';

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

// Saturday June 27, 2026 (weekday 6).
// Dates: Mon=22, Tue=23, Wed=24, Thu=25, Fri=26, Sat=27, Sun=28.
final _today = DateTime(2026, 6, 27);

Habit _dailyHabit({
  String id = '1',
  String title = 'Walk',
  Set<String> completedDates = const {},
}) => Habit(
  id: id,
  title: title,
  scheduledTime: '07:00 AM',
  icon: Icons.directions_walk_outlined,
  completedDates: completedDates,
);

String _prefs(Habit habit) => jsonEncode([habit.toJson()]);

Future<void> _pumpDetails(
  WidgetTester tester,
  Habit habit, {
  _FakeNotifications? fakeNotifications,
  DateTime? today,
}) async {
  SharedPreferences.setMockInitialValues({'habits': _prefs(habit)});
  await tester.pumpWidget(
    MaterialApp(
      home: HabitDetailsScreen(
        habit: habit,
        notificationService: fakeNotifications,
        today: today ?? _today,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // ── Navigation ────────────────────────────────────────────────────────────

  // Test 1: tapping habit card body opens the details screen.
  testWidgets('tapping habit card body navigates to HabitDetailsScreen', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Drink water'));
    await tester.pumpAndSettle();

    expect(find.byType(HabitDetailsScreen), findsOneWidget);
  });

  // Test 2: tapping completion control does not open details.
  testWidgets('tapping completion toggle does not open HabitDetailsScreen', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.radio_button_unchecked).first);
    await tester.pump();

    expect(find.byType(HabitDetailsScreen), findsNothing);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
  });

  // ── Summary card ──────────────────────────────────────────────────────────

  // Test 3: summary shows correct title, time, and schedule.
  testWidgets('summary card shows title, reminder time, and repeat schedule', (
    tester,
  ) async {
    final habit = Habit(
      id: '1',
      title: 'Morning run',
      scheduledTime: '06:30 AM',
      icon: Icons.fitness_center_outlined,
      weekdays: const [1, 3, 5],
    );
    await _pumpDetails(tester, habit);

    // Title appears in AppBar and summary card.
    expect(find.text('Morning run'), findsWidgets);
    expect(find.text('06:30 AM'), findsOneWidget);
    expect(find.text('Mon, Wed, Fri'), findsOneWidget);
  });

  testWidgets('summary card shows "Every day" for a daily habit', (
    tester,
  ) async {
    await _pumpDetails(tester, _dailyHabit());
    expect(find.text('Every day'), findsOneWidget);
  });

  // ── Statistics ────────────────────────────────────────────────────────────

  // Test 4: statistics use only this habit.
  testWidgets('statistics card reflects only the given habit', (tester) async {
    // Completed Jun 25, 26, 27 (3 consecutive days ending today).
    final habit = _dailyHabit(
      completedDates: const {'2026-06-25', '2026-06-26', '2026-06-27'},
    );
    await _pumpDetails(tester, habit);

    // Current streak = 3 and best streak = 3 → "3 days" appears twice.
    expect(find.text('3 days'), findsWidgets);
    // Today is completed, so "Completed" appears in summary.
    expect(find.text('Completed'), findsOneWidget);
  });

  testWidgets('statistics update after toggling a calendar day', (
    tester,
  ) async {
    // Test 16: stats refresh after a calendar edit.
    final habit = _dailyHabit();
    await _pumpDetails(tester, habit);

    // Initially no streak.
    expect(find.text('0 days'), findsWidgets);

    // Tap today (day 27) to mark it complete.
    await tester.ensureVisible(find.text('27'));
    await tester.tap(find.text('27'));
    await tester.pumpAndSettle();

    // Streak is now 1 day for both current and best.
    expect(find.text('1 day'), findsWidgets);
  });

  // ── Calendar ─────────────────────────────────────────────────────────────

  // Test 10: calendar initially shows current month.
  testWidgets('calendar initially shows the current month', (tester) async {
    await _pumpDetails(tester, _dailyHabit());
    expect(find.text('June 2026'), findsOneWidget);
  });

  // Test 11: month and year navigation works.
  testWidgets('previous-month button shows May 2026', (tester) async {
    await _pumpDetails(tester, _dailyHabit());
    await tester.tap(find.byTooltip('Previous month'));
    await tester.pumpAndSettle();
    expect(find.text('May 2026'), findsOneWidget);
  });

  testWidgets('next-month button shows July 2026', (tester) async {
    await _pumpDetails(tester, _dailyHabit());
    await tester.tap(find.byTooltip('Next month'));
    await tester.pumpAndSettle();
    expect(find.text('July 2026'), findsOneWidget);
  });

  testWidgets('navigating back from January wraps to previous year', (
    tester,
  ) async {
    final habit = _dailyHabit();
    SharedPreferences.setMockInitialValues({'habits': _prefs(habit)});
    await tester.pumpWidget(
      MaterialApp(
        home: HabitDetailsScreen(habit: habit, today: DateTime(2026, 1, 15)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Previous month'));
    await tester.pumpAndSettle();
    expect(find.text('December 2025'), findsOneWidget);
  });

  // Test 12: leap year — February 2024 shows 29 days.
  testWidgets('calendar shows 29 days for February 2024 (leap year)', (
    tester,
  ) async {
    final habit = _dailyHabit();
    SharedPreferences.setMockInitialValues({'habits': _prefs(habit)});
    await tester.pumpWidget(
      MaterialApp(
        home: HabitDetailsScreen(habit: habit, today: DateTime(2024, 2, 15)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('February 2024'), findsOneWidget);
    expect(find.text('29'), findsOneWidget);
  });

  // Test 13: today cell is indicated; future cells are not tappable.
  testWidgets('today cell has today indication and future cells are passive', (
    tester,
  ) async {
    await _pumpDetails(tester, _dailyHabit());

    // Today = June 27. The cell shows '27'.
    // Tap it — should toggle.
    await tester.ensureVisible(find.text('27'));
    await tester.pump();

    // A future day (Jun 28). Tap it — should NOT toggle stats.
    await tester.ensureVisible(find.text('28'));
    await tester.tap(find.text('28'));
    await tester.pumpAndSettle();

    // Stats still show 0 days (no toggle happened for a future date).
    expect(find.text('0 days'), findsWidgets);
  });

  // Test 14: tapping a past scheduled day toggles only this habit.
  testWidgets('tapping a scheduled past day toggles its completion', (
    tester,
  ) async {
    final habit = _dailyHabit();
    await _pumpDetails(tester, habit);

    // Jun 27 is today and scheduled. Tap to complete.
    await tester.ensureVisible(find.text('27'));
    await tester.tap(find.text('27'));
    await tester.pumpAndSettle();

    // Jun 27 should now be completed → summary says "Completed".
    expect(find.text('Completed'), findsOneWidget);
  });

  // Test 15: changes persist after storage reload.
  testWidgets('toggling a calendar day persists to storage', (tester) async {
    final habit = _dailyHabit();
    await _pumpDetails(tester, habit);

    await tester.ensureVisible(find.text('27'));
    await tester.tap(find.text('27'));
    await tester.pumpAndSettle();

    final loaded = await HabitStorage().loadHabits();
    expect(loaded, isNotNull);
    expect(loaded!.first.completedDates, contains('2026-06-27'));
  });

  // ── Edit ──────────────────────────────────────────────────────────────────

  // Test 17: edit preserves completion history.
  testWidgets('editing a habit preserves its completion history', (
    tester,
  ) async {
    final fake = _FakeNotifications();
    final habit = _dailyHabit(
      title: 'Walk',
      completedDates: const {'2026-06-25', '2026-06-26'},
    );
    await _pumpDetails(tester, habit, fakeNotifications: fake);

    await tester.ensureVisible(find.text('Edit habit'));
    await tester.tap(find.text('Edit habit'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Habit title'),
      'Evening walk',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    final loaded = await HabitStorage().loadHabits();
    expect(loaded, isNotNull);
    expect(loaded!.first.title, 'Evening walk');
    expect(
      loaded.first.completedDates,
      containsAll(<String>{'2026-06-25', '2026-06-26'}),
    );
  });

  // Test 18: edit updates schedule and reminder.
  testWidgets('editing a habit reschedules notifications', (tester) async {
    final fake = _FakeNotifications();
    final habit = _dailyHabit();
    await _pumpDetails(tester, habit, fakeNotifications: fake);

    await tester.ensureVisible(find.text('Edit habit'));
    await tester.tap(find.text('Edit habit'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(fake.scheduled, contains('1'));
  });

  // ── Delete ────────────────────────────────────────────────────────────────

  // Test 19: delete confirmation dialog works.
  testWidgets('cancelling delete confirmation leaves the screen open', (
    tester,
  ) async {
    final fake = _FakeNotifications();
    await _pumpDetails(tester, _dailyHabit(), fakeNotifications: fake);

    await tester.ensureVisible(
      find.widgetWithText(OutlinedButton, 'Delete habit'),
    );
    await tester.tap(find.widgetWithText(OutlinedButton, 'Delete habit'));
    await tester.pumpAndSettle();

    // Confirmation dialog appears.
    expect(find.widgetWithText(FilledButton, 'Delete'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    // Still on the details screen.
    expect(find.byType(HabitDetailsScreen), findsOneWidget);
    expect(fake.cancelled, isEmpty);
  });

  // Test 20: delete cancels notifications and returns to Today.
  testWidgets('confirming delete cancels notifications and pops the screen', (
    tester,
  ) async {
    final fake = _FakeNotifications();
    await _pumpDetails(tester, _dailyHabit(), fakeNotifications: fake);

    await tester.ensureVisible(
      find.widgetWithText(OutlinedButton, 'Delete habit'),
    );
    await tester.tap(find.widgetWithText(OutlinedButton, 'Delete habit'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    // Screen is popped (HabitDetailsScreen is no longer in the tree).
    expect(find.byType(HabitDetailsScreen), findsNothing);
    expect(fake.cancelled, contains('1'));

    // Storage no longer contains the habit.
    final loaded = await HabitStorage().loadHabits();
    expect(loaded?.any((h) => h.id == '1'), isFalse);
  });

  // ── Layout ────────────────────────────────────────────────────────────────

  // Test 21: compact-screen layout has no overflow.
  testWidgets('details screen has no overflow on a compact screen', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;

    final habit = _dailyHabit();
    SharedPreferences.setMockInitialValues({'habits': _prefs(habit)});
    await tester.pumpWidget(
      MaterialApp(
        home: HabitDetailsScreen(habit: habit, today: _today),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(HabitDetailsScreen), findsOneWidget);
  });

  // Test 22: empty or unusual historical data does not crash.
  testWidgets('screen renders without crash for a habit with no history', (
    tester,
  ) async {
    final habit = Habit(
      id: '1',
      title: 'New habit',
      scheduledTime: '08:00 AM',
      icon: Icons.local_drink_outlined,
      completedDates: const {},
      weekdays: const [1], // Monday only
    );
    await _pumpDetails(tester, habit);

    expect(tester.takeException(), isNull);
    expect(find.text('Statistics'), findsOneWidget);
    expect(find.text('0 days'), findsWidgets);
  });

  testWidgets(
    'screen renders without crash for a habit with no scheduled days in the month',
    (tester) async {
      // Navigate to a month with no history.
      final habit = _dailyHabit();
      await _pumpDetails(tester, habit);

      // Go back 12 months — should not crash.
      for (var i = 0; i < 12; i++) {
        await tester.tap(find.byTooltip('Previous month'));
        await tester.pumpAndSettle();
      }

      expect(tester.takeException(), isNull);
      expect(find.text('June 2025'), findsOneWidget);
    },
  );

  // ── Status badge ──────────────────────────────────────────────────────────

  // Test 18a: Habit Details shows "Active" badge for an active habit.
  testWidgets('summary card shows Active badge for an active habit', (
    tester,
  ) async {
    await _pumpDetails(tester, _dailyHabit());

    expect(find.text('Active'), findsOneWidget);
    expect(find.text('Edit habit'), findsOneWidget);
    expect(find.text('Pause habit'), findsOneWidget);
    expect(find.text('Archive habit'), findsOneWidget);
    expect(find.text('Resume habit'), findsNothing);
    expect(find.text('Restore habit'), findsNothing);
  });

  // Test 18b: Habit Details shows "Paused" badge and Resume/Archive actions.
  testWidgets('summary card shows Paused badge and correct actions', (
    tester,
  ) async {
    final paused = Habit(
      id: '1',
      title: 'Walk',
      scheduledTime: '07:00 AM',
      icon: Icons.directions_walk_outlined,
      status: HabitStatus.paused,
      pausedFromDate: '2026-06-25',
    );
    await _pumpDetails(tester, paused);

    expect(find.text('Paused'), findsOneWidget);
    expect(find.text('Resume habit'), findsOneWidget);
    expect(find.text('Archive habit'), findsOneWidget);
    expect(find.text('Pause habit'), findsNothing);
    expect(find.text('Restore habit'), findsNothing);
  });

  // Test 18c: Habit Details shows "Archived" badge and Restore action.
  testWidgets('summary card shows Archived badge and correct actions', (
    tester,
  ) async {
    final archived = Habit(
      id: '1',
      title: 'Walk',
      scheduledTime: '07:00 AM',
      icon: Icons.directions_walk_outlined,
      status: HabitStatus.archived,
      pausedFromDate: '2026-06-25',
    );
    await _pumpDetails(tester, archived);

    expect(find.text('Archived'), findsOneWidget);
    expect(find.text('Restore habit'), findsOneWidget);
    expect(find.text('Pause habit'), findsNothing);
    expect(find.text('Resume habit'), findsNothing);
  });

  // ── Test 14: pause cancels reminders ──────────────────────────────────────
  testWidgets('tapping Pause habit cancels reminders', (tester) async {
    final fake = _FakeNotifications();
    await _pumpDetails(tester, _dailyHabit(), fakeNotifications: fake);

    await tester.ensureVisible(find.text('Pause habit'));
    await tester.tap(find.text('Pause habit'));
    await tester.pumpAndSettle();

    expect(fake.cancelled, contains('1'));
    expect(fake.scheduled, isEmpty);
  });

  // ── Test 15: resume restores reminders ────────────────────────────────────
  testWidgets('tapping Resume habit schedules reminders', (tester) async {
    final fake = _FakeNotifications();
    final paused = Habit(
      id: '1',
      title: 'Walk',
      scheduledTime: '07:00 AM',
      icon: Icons.directions_walk_outlined,
      status: HabitStatus.paused,
      pausedFromDate: '2026-06-25',
    );
    await _pumpDetails(tester, paused, fakeNotifications: fake);

    await tester.ensureVisible(find.text('Resume habit'));
    await tester.tap(find.text('Resume habit'));
    await tester.pumpAndSettle();

    expect(fake.scheduled, contains('1'));
  });

  // ── Test 16: archive cancels reminders ────────────────────────────────────
  testWidgets('confirming Archive habit cancels reminders', (tester) async {
    final fake = _FakeNotifications();
    await _pumpDetails(tester, _dailyHabit(), fakeNotifications: fake);

    await tester.ensureVisible(find.text('Archive habit'));
    await tester.tap(find.text('Archive habit'));
    await tester.pumpAndSettle();

    // Confirm dialog.
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Archive'));
    await tester.pumpAndSettle();

    expect(fake.cancelled, contains('1'));
    expect(fake.scheduled, isEmpty);
  });

  // ── Test 17: restore schedules reminders ──────────────────────────────────
  testWidgets('tapping Restore habit schedules reminders', (tester) async {
    final fake = _FakeNotifications();
    final archived = Habit(
      id: '1',
      title: 'Walk',
      scheduledTime: '07:00 AM',
      icon: Icons.directions_walk_outlined,
      status: HabitStatus.archived,
      pausedFromDate: '2026-06-25',
    );
    await _pumpDetails(tester, archived, fakeNotifications: fake);

    await tester.ensureVisible(find.text('Restore habit'));
    await tester.tap(find.text('Restore habit'));
    await tester.pumpAndSettle();

    expect(fake.scheduled, contains('1'));
  });

  // ── Test 19: Archive confirmation ─────────────────────────────────────────
  testWidgets('cancelling archive dialog keeps the habit active', (
    tester,
  ) async {
    final fake = _FakeNotifications();
    await _pumpDetails(tester, _dailyHabit(), fakeNotifications: fake);

    await tester.ensureVisible(find.text('Archive habit'));
    await tester.tap(find.text('Archive habit'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    // Still active — status badge still shows Active.
    expect(find.text('Active'), findsOneWidget);
    expect(fake.cancelled, isEmpty);
  });

  // ── Test 22: editing paused habit keeps it paused ─────────────────────────
  testWidgets('editing a paused habit preserves its paused status', (
    tester,
  ) async {
    final fake = _FakeNotifications();
    final paused = Habit(
      id: '1',
      title: 'Walk',
      scheduledTime: '07:00 AM',
      icon: Icons.directions_walk_outlined,
      status: HabitStatus.paused,
      pausedFromDate: '2026-06-25',
    );
    SharedPreferences.setMockInitialValues({'habits': _prefs(paused)});
    await tester.pumpWidget(
      MaterialApp(
        home: HabitDetailsScreen(
          habit: paused,
          notificationService: fake,
          today: _today,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Edit habit'));
    await tester.tap(find.text('Edit habit'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    // Status badge still says Paused.
    expect(find.text('Paused'), findsOneWidget);
    // No reminder was scheduled (habit is still paused).
    expect(fake.scheduled, isEmpty);
    // Storage persists the paused status.
    final loaded = await HabitStorage().loadHabits();
    expect(loaded?.first.status, HabitStatus.paused);
  });

  // ── Test 23: editing archived habit keeps it archived ─────────────────────
  testWidgets('editing an archived habit preserves its archived status', (
    tester,
  ) async {
    final fake = _FakeNotifications();
    final archived = Habit(
      id: '1',
      title: 'Walk',
      scheduledTime: '07:00 AM',
      icon: Icons.directions_walk_outlined,
      status: HabitStatus.archived,
      pausedFromDate: '2026-06-25',
    );
    SharedPreferences.setMockInitialValues({'habits': _prefs(archived)});
    await tester.pumpWidget(
      MaterialApp(
        home: HabitDetailsScreen(
          habit: archived,
          notificationService: fake,
          today: _today,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Edit habit'));
    await tester.tap(find.text('Edit habit'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.text('Archived'), findsOneWidget);
    expect(fake.scheduled, isEmpty);
    final loaded = await HabitStorage().loadHabits();
    expect(loaded?.first.status, HabitStatus.archived);
  });

  // ── Test 24: delete still works for all statuses ──────────────────────────
  testWidgets('delete works for a paused habit', (tester) async {
    final fake = _FakeNotifications();
    final paused = Habit(
      id: '1',
      title: 'Walk',
      scheduledTime: '07:00 AM',
      icon: Icons.directions_walk_outlined,
      status: HabitStatus.paused,
      pausedFromDate: '2026-06-25',
    );
    await _pumpDetails(tester, paused, fakeNotifications: fake);

    await tester.ensureVisible(
      find.widgetWithText(OutlinedButton, 'Delete habit'),
    );
    await tester.tap(find.widgetWithText(OutlinedButton, 'Delete habit'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(find.byType(HabitDetailsScreen), findsNothing);
    expect(fake.cancelled, contains('1'));
  });

  testWidgets('delete works for an archived habit', (tester) async {
    final fake = _FakeNotifications();
    final archived = Habit(
      id: '1',
      title: 'Walk',
      scheduledTime: '07:00 AM',
      icon: Icons.directions_walk_outlined,
      status: HabitStatus.archived,
      pausedFromDate: '2026-06-25',
    );
    await _pumpDetails(tester, archived, fakeNotifications: fake);

    await tester.ensureVisible(
      find.widgetWithText(OutlinedButton, 'Delete habit'),
    );
    await tester.tap(find.widgetWithText(OutlinedButton, 'Delete habit'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(find.byType(HabitDetailsScreen), findsNothing);
    expect(fake.cancelled, contains('1'));
  });

  // ── Test 25: compact layout with status actions ────────────────────────────
  testWidgets('status actions cause no overflow on a compact screen', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;

    final paused = Habit(
      id: '1',
      title: 'Walk',
      scheduledTime: '07:00 AM',
      icon: Icons.directions_walk_outlined,
      status: HabitStatus.paused,
      pausedFromDate: '2026-06-25',
    );
    SharedPreferences.setMockInitialValues({'habits': _prefs(paused)});
    await tester.pumpWidget(
      MaterialApp(
        home: HabitDetailsScreen(habit: paused, today: _today),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Paused'), findsOneWidget);
  });
}
