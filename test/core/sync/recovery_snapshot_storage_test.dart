import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_habit_coach/core/storage/local_namespace_resolver.dart';
import 'package:smart_habit_coach/core/sync/recovery_snapshot_storage.dart';
import 'package:smart_habit_coach/features/home/data/habit_storage.dart';
import 'package:smart_habit_coach/features/home/domain/habit.dart';

import '../../support/test_namespace.dart';

void main() {
  tearDown(() {
    LocalNamespaceResolver.debugUidOverride = testNamespaceUid;
  });

  group('RecoverySnapshotStorage', () {
    test('create then read round-trips', () async {
      SharedPreferences.setMockInitialValues({});
      final habitStorage = HabitStorage();
      await habitStorage.upsertHabit(
        Habit(
          id: '1',
          title: 'Drink water',
          scheduledTime: '08:00 AM',
          icon: Icons.local_drink_outlined,
        ),
      );
      final storage = RecoverySnapshotStorage(habitStorage: habitStorage);

      await storage.create(reason: 'beforeHabitTombstone');
      final snapshot = await storage.read();

      expect(snapshot, isNotNull);
      expect(snapshot!.reason, 'beforeHabitTombstone');
      expect(snapshot.habits.single['id'], '1');
    });

    test('includes tombstoned records', () async {
      SharedPreferences.setMockInitialValues({});
      final habitStorage = HabitStorage();
      final habit = await habitStorage.upsertHabit(
        Habit(
          id: '1',
          title: 'Drink water',
          scheduledTime: '08:00 AM',
          icon: Icons.local_drink_outlined,
        ),
      );
      await habitStorage.tombstoneHabit(habit);
      final storage = RecoverySnapshotStorage(habitStorage: habitStorage);

      await storage.create(reason: 'test');
      final snapshot = await storage.read();

      expect(snapshot!.habits.single['deletedAt'], isNotNull);
    });

    test('preserves timestamps exactly (does not stamp anything)', () async {
      SharedPreferences.setMockInitialValues({});
      final habitStorage = HabitStorage();
      final habit = Habit(
        id: '1',
        title: 'Drink water',
        scheduledTime: '08:00 AM',
        icon: Icons.local_drink_outlined,
        createdAt: DateTime.utc(2020, 1, 1),
        updatedAt: DateTime.utc(2021, 1, 1),
      );
      await habitStorage.saveHabits([habit]);
      final storage = RecoverySnapshotStorage(habitStorage: habitStorage);

      await storage.create(reason: 'test');
      final snapshot = await storage.read();

      expect(snapshot!.habits.single['createdAt'], '2020-01-01T00:00:00.000Z');
      expect(snapshot.habits.single['updatedAt'], '2021-01-01T00:00:00.000Z');
    });

    test('read returns null when nothing has been created', () async {
      SharedPreferences.setMockInitialValues({});

      final snapshot = await RecoverySnapshotStorage().read();

      expect(snapshot, isNull);
    });

    test('read returns null for malformed data', () async {
      SharedPreferences.setMockInitialValues({
        'recovery_snapshot:$testNamespaceUid': 'not valid json',
      });

      final snapshot = await RecoverySnapshotStorage().read();

      expect(snapshot, isNull);
    });

    test('clear removes the snapshot', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = RecoverySnapshotStorage();
      await storage.create(reason: 'test');

      await storage.clear();
      final snapshot = await storage.read();

      expect(snapshot, isNull);
    });

    test('creating a new snapshot replaces the previous one', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = RecoverySnapshotStorage();

      await storage.create(reason: 'first');
      await storage.create(reason: 'second');
      final snapshot = await storage.read();

      expect(snapshot!.reason, 'second');
    });

    test(
      'namespaced isolation between two UIDs: no cross-UID restore',
      () async {
        SharedPreferences.setMockInitialValues({});
        final storage = RecoverySnapshotStorage();

        LocalNamespaceResolver.debugUidOverride = 'uid-a';
        await storage.create(reason: 'uid-a-snapshot');

        LocalNamespaceResolver.debugUidOverride = 'uid-b';
        final bSnapshot = await storage.read();

        expect(bSnapshot, isNull);
      },
    );
  });
}
