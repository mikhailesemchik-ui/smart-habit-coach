import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_habit_coach/core/sync/sync_metadata_storage.dart';
import 'package:smart_habit_coach/features/home/data/notification_service.dart';
import 'package:smart_habit_coach/features/home/domain/habit.dart';
import 'package:smart_habit_coach/features/home/presentation/archived_habits_screen.dart';
import 'package:smart_habit_coach/features/home/presentation/habit_details_screen.dart';

import '../../../support/test_namespace.dart';

const _habitsKey = 'habits:$testNamespaceUid';

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
      _habitsKey: _habitsJson([
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
      _habitsKey: _habitsJson([
        _habitJson(id: '1', title: 'Active run', status: 'active'),
      ]),
    });

    await _pump(tester);

    expect(find.text('No archived habits'), findsOneWidget);
  });

  testWidgets('shows empty message when no habits exist at all', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({_habitsKey: jsonEncode([])});

    await _pump(tester);

    expect(find.text('No archived habits'), findsOneWidget);
  });

  testWidgets('tapping an archived tile opens HabitDetailsScreen', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      _habitsKey: _habitsJson([
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
      _habitsKey: _habitsJson([
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

  // ── Direct restore action on the Archived Habits screen ───────────────────

  testWidgets('Restore button moves the habit back to active', (tester) async {
    final fake = _FakeNotifications();
    SharedPreferences.setMockInitialValues({
      _habitsKey: _habitsJson([
        _habitJson(id: '1', title: 'Old walk', status: 'archived'),
      ]),
    });

    await _pump(tester, ns: fake);
    expect(find.text('Old walk'), findsOneWidget);

    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();

    expect(find.text('Old walk'), findsNothing);
    expect(find.text('No archived habits'), findsOneWidget);
    expect(fake.scheduled, contains('1'));

    final raw = SharedPreferences.getInstance();
    final prefs = await raw;
    final stored = jsonDecode(prefs.getString(_habitsKey)!) as List<dynamic>;
    final habit = Habit.fromJson(stored.single as Map<String, dynamic>);
    expect(habit.status, HabitStatus.active);
  });

  // ── Direct permanent-delete (tombstone) action ─────────────────────────────

  testWidgets('Delete button shows a confirmation dialog', (tester) async {
    SharedPreferences.setMockInitialValues({
      _habitsKey: _habitsJson([
        _habitJson(id: '1', title: 'Old walk', status: 'archived'),
      ]),
    });

    await _pump(tester);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Delete habit'), findsOneWidget);
    expect(find.textContaining('cannot be undone'), findsOneWidget);
  });

  testWidgets('Cancel on delete confirmation leaves the habit unchanged', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      _habitsKey: _habitsJson([
        _habitJson(id: '1', title: 'Old walk', status: 'archived'),
      ]),
    });

    await _pump(tester);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Old walk'), findsOneWidget);
  });

  testWidgets(
    'Confirming delete tombstones the habit and removes it from the list',
    (tester) async {
      final fake = _FakeNotifications();
      SharedPreferences.setMockInitialValues({
        _habitsKey: _habitsJson([
          _habitJson(id: '1', title: 'Old walk', status: 'archived'),
        ]),
      });

      await _pump(tester, ns: fake);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();

      expect(find.text('Old walk'), findsNothing);
      expect(find.text('No archived habits'), findsOneWidget);
      expect(fake.cancelled, contains('1'));

      final prefs = await SharedPreferences.getInstance();
      final stored = jsonDecode(prefs.getString(_habitsKey)!) as List<dynamic>;
      final habit = Habit.fromJson(stored.single as Map<String, dynamic>);
      // Raw storage still contains the record — it is a tombstone, not a
      // physical delete.
      expect(habit.deletedAt, isNotNull);
      expect(habit.deletedAt, habit.updatedAt);
    },
  );

  testWidgets('Restore marks the habit dirty through storage metadata', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      _habitsKey: _habitsJson([
        _habitJson(id: '1', title: 'Old walk', status: 'archived'),
      ]),
    });

    await _pump(tester);
    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();

    final metadata = await SyncMetadataStorage().load();
    expect(metadata.dirtyHabitIds, contains('1'));
  });

  testWidgets('Delete marks the habit dirty through storage metadata', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      _habitsKey: _habitsJson([
        _habitJson(id: '1', title: 'Old walk', status: 'archived'),
      ]),
    });

    await _pump(tester);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();

    final metadata = await SyncMetadataStorage().load();
    expect(metadata.dirtyHabitIds, contains('1'));
  });

  testWidgets('duplicate Restore taps only reschedule the reminder once', (
    tester,
  ) async {
    final fake = _FakeNotifications();
    SharedPreferences.setMockInitialValues({
      _habitsKey: _habitsJson([
        _habitJson(id: '1', title: 'Old walk', status: 'archived'),
      ]),
    });

    await _pump(tester, ns: fake);
    await tester.tap(find.text('Restore'));
    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();

    expect(fake.scheduled.where((id) => id == '1').length, 1);
  });
}
