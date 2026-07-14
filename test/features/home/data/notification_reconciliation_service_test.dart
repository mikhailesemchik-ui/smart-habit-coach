import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_habit_coach/core/storage/local_namespace_resolver.dart';
import 'package:smart_habit_coach/features/home/data/habit_storage.dart';
import 'package:smart_habit_coach/features/home/data/notification_reconciliation_service.dart';
import 'package:smart_habit_coach/features/home/data/notification_service.dart';
import 'package:smart_habit_coach/features/home/domain/habit.dart';

import '../../../support/test_namespace.dart';

const _habitsKey = 'habits:$testNamespaceUid';

class _FakeNotifications extends NotificationService {
  final List<String> scheduled = [];
  bool cancelAllCalled = false;

  @override
  Future<void> scheduleHabitReminder(Habit habit) async {
    scheduled.add(habit.id);
  }

  @override
  Future<void> cancelAll() async {
    cancelAllCalled = true;
  }
}

Habit _habit({
  required String id,
  HabitStatus status = HabitStatus.active,
  DateTime? deletedAt,
}) => Habit(
  id: id,
  title: 'Habit $id',
  scheduledTime: '08:00 AM',
  icon: Icons.water_drop_outlined,
  status: status,
  deletedAt: deletedAt,
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    LocalNamespaceResolver.debugUidOverride = testNamespaceUid;
  });
  tearDown(() {
    LocalNamespaceResolver.debugUidOverride = testNamespaceUid;
  });

  test('cancels everything before rescheduling', () async {
    final fake = _FakeNotifications();
    final storage = HabitStorage();
    await storage.saveHabits([_habit(id: '1')]);

    await NotificationReconciliationService(
      storage: storage,
      notifications: fake,
    ).reconcile();

    expect(fake.cancelAllCalled, isTrue);
  });

  test('schedules only active, non-archived, non-tombstoned habits', () async {
    final fake = _FakeNotifications();
    final storage = HabitStorage();
    await storage.saveHabits([
      _habit(id: 'active', status: HabitStatus.active),
      _habit(id: 'paused', status: HabitStatus.paused),
      _habit(id: 'archived', status: HabitStatus.archived),
      _habit(
        id: 'deleted',
        status: HabitStatus.active,
        deletedAt: DateTime.utc(2026, 1, 1),
      ),
    ]);

    await NotificationReconciliationService(
      storage: storage,
      notifications: fake,
    ).reconcile();

    expect(fake.scheduled, ['active']);
  });

  test('a restored habit becomes eligible for scheduling again', () async {
    final fake = _FakeNotifications();
    final storage = HabitStorage();
    await storage.saveHabits([_habit(id: '1', status: HabitStatus.archived)]);

    await NotificationReconciliationService(
      storage: storage,
      notifications: fake,
    ).reconcile();
    expect(fake.scheduled, isEmpty);

    await storage.upsertHabit(_habit(id: '1', status: HabitStatus.active));
    await NotificationReconciliationService(
      storage: storage,
      notifications: fake,
    ).reconcile();
    expect(fake.scheduled, ['1']);
  });

  test(
    'reconciling after a UID switch only schedules the new UID\'s habits',
    () async {
      // Old UID has an active habit; new UID (after the switch) has none.
      SharedPreferences.setMockInitialValues({
        _habitsKey: jsonEncode([_habit(id: 'old-uid-habit').toJson()]),
      });
      final fake = _FakeNotifications();
      final storage = HabitStorage();

      LocalNamespaceResolver.debugUidOverride = 'a-different-uid';
      await NotificationReconciliationService(
        storage: storage,
        notifications: fake,
      ).reconcile();

      expect(fake.cancelAllCalled, isTrue);
      expect(fake.scheduled, isEmpty);
    },
  );
}
