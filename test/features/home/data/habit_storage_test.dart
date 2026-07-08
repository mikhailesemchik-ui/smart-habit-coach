import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_habit_coach/core/storage/local_namespace_resolver.dart';
import 'package:smart_habit_coach/core/sync/recovery_snapshot_storage.dart';
import 'package:smart_habit_coach/core/sync/sync_metadata.dart';
import 'package:smart_habit_coach/core/sync/sync_metadata_storage.dart';
import 'package:smart_habit_coach/features/home/data/habit_storage.dart';
import 'package:smart_habit_coach/features/home/domain/date_key.dart';
import 'package:smart_habit_coach/features/home/domain/habit.dart';

import '../../../support/fake_clock.dart';
import '../../../support/test_namespace.dart';

const _habitsKey = 'habits:$testNamespaceUid';

/// Fails every data write while leaving metadata writes (which go through
/// a separate `SyncMetadataStorage` instance) unaffected — simulates
/// "metadata succeeds, data fails".
class _FailingWriteHabitStorage extends HabitStorage {
  _FailingWriteHabitStorage({super.syncMetadataStorage});

  @override
  Future<void> writeHabitsRaw(List<Habit> habits) =>
      Future.error(StateError('data write unavailable'));
}

/// Fails exactly once, then behaves normally — simulates a transient
/// failure followed by a successful retry, without permanently poisoning
/// the instance's write queue.
class _FailOnceHabitStorage extends HabitStorage {
  bool _failed = false;

  @override
  Future<void> writeHabitsRaw(List<Habit> habits) {
    if (!_failed) {
      _failed = true;
      return Future.error(StateError('transient failure'));
    }
    return super.writeHabitsRaw(habits);
  }
}

/// A SyncMetadataStorage whose every write fails — simulates "metadata
/// fails before the data write" when injected into a HabitStorage.
class _FailingSyncMetadataStorage extends SyncMetadataStorage {
  @override
  Future<SyncMetadata> markHabitDirty(String habitId) =>
      Future.error(StateError('metadata write unavailable'));
}

void main() {
  group('HabitStorage', () {
    test('loadHabits returns null when no data has been saved', () async {
      SharedPreferences.setMockInitialValues({});

      final result = await HabitStorage().loadHabits();

      expect(result, isNull);
    });

    test('saveHabits then loadHabits returns the same habits', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = HabitStorage();
      final habits = [
        Habit(
          id: '1',
          title: 'Drink water',
          scheduledTime: '08:00 AM',
          icon: Icons.local_drink_outlined,
        ),
        Habit(
          id: '2',
          title: 'Evening walk',
          scheduledTime: '07:00 PM',
          icon: Icons.directions_walk_outlined,
          completedDates: {'2026-06-19'},
        ),
      ];

      await storage.saveHabits(habits);
      final loaded = await storage.loadHabits();

      expect(loaded, isNotNull);
      expect(loaded!.length, 2);
      expect(loaded[0].id, '1');
      expect(loaded[0].title, 'Drink water');
      expect(loaded[1].completedDates, {'2026-06-19'});
    });

    test(
      'saveHabits then loadHabits preserves today as a completion date',
      () async {
        SharedPreferences.setMockInitialValues({});
        final storage = HabitStorage();
        final today = todayKey();
        final habit = Habit(
          id: '1',
          title: 'Drink water',
          scheduledTime: '08:00 AM',
          icon: Icons.local_drink_outlined,
          completedDates: {today},
        );

        await storage.saveHabits([habit]);
        final loaded = await storage.loadHabits();

        expect(loaded, isNotNull);
        expect(loaded!.first.completedDates, contains(today));
        expect(loaded.first.isCompletedToday, isTrue);
      },
    );

    test('loadHabits returns null for corrupted saved data', () async {
      SharedPreferences.setMockInitialValues({_habitsKey: 'not valid json'});

      final result = await HabitStorage().loadHabits();

      expect(result, isNull);
    });

    test('loadHabits returns null when saved data is not a list', () async {
      SharedPreferences.setMockInitialValues({_habitsKey: '{"id": "1"}'});

      final result = await HabitStorage().loadHabits();

      expect(result, isNull);
    });

    test('loadHabits on corrupted data leaves storage unmodified', () async {
      const corrupt = 'not-valid-json{[}';
      SharedPreferences.setMockInitialValues({_habitsKey: corrupt});

      final result = await HabitStorage().loadHabits();

      expect(result, isNull);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(_habitsKey), corrupt);
    });
  });

  group('HabitStorage per-record tolerance', () {
    Map<String, dynamic> validRecord(String id) => {
      'id': id,
      'title': 'Habit $id',
      'scheduledTime': '08:00 AM',
      'iconId': 'water',
      'completedDates': <String>[],
    };

    const malformedRecord = {'title': 'missing id and scheduledTime'};

    test('all valid records load successfully', () async {
      SharedPreferences.setMockInitialValues({
        _habitsKey: jsonEncode([validRecord('1'), validRecord('2')]),
      });

      final result = await HabitStorage().loadHabits();

      expect(result, isNotNull);
      expect(result!.map((h) => h.id), ['1', '2']);
    });

    test('one malformed record between two valid ones is skipped', () async {
      SharedPreferences.setMockInitialValues({
        _habitsKey: jsonEncode([
          validRecord('1'),
          malformedRecord,
          validRecord('2'),
        ]),
      });

      final result = await HabitStorage().loadHabits();

      expect(result, isNotNull);
      expect(result!.map((h) => h.id), ['1', '2']);
    });

    test('malformed first record is skipped, valid ones remain', () async {
      SharedPreferences.setMockInitialValues({
        _habitsKey: jsonEncode([malformedRecord, validRecord('1')]),
      });

      final result = await HabitStorage().loadHabits();

      expect(result, isNotNull);
      expect(result!.map((h) => h.id), ['1']);
    });

    test('malformed last record is skipped, valid ones remain', () async {
      SharedPreferences.setMockInitialValues({
        _habitsKey: jsonEncode([validRecord('1'), malformedRecord]),
      });

      final result = await HabitStorage().loadHabits();

      expect(result, isNotNull);
      expect(result!.map((h) => h.id), ['1']);
    });

    test('all malformed records yields an empty (not null) list', () async {
      SharedPreferences.setMockInitialValues({
        _habitsKey: jsonEncode([malformedRecord, malformedRecord]),
      });

      final result = await HabitStorage().loadHabits();

      expect(result, isNotNull);
      expect(result, isEmpty);
    });

    test('non-map elements in the list are skipped', () async {
      SharedPreferences.setMockInitialValues({
        _habitsKey: jsonEncode([validRecord('1'), 'not-a-map', 42]),
      });

      final result = await HabitStorage().loadHabits();

      expect(result, isNotNull);
      expect(result!.map((h) => h.id), ['1']);
    });

    test('valid old-shape records without timestamps still load', () async {
      SharedPreferences.setMockInitialValues({
        _habitsKey: jsonEncode([validRecord('1')]),
      });

      final result = await HabitStorage().loadHabits();

      expect(result, isNotNull);
      expect(result!.first.createdAt, DateTime.utc(2000, 1, 1));
    });
  });

  group('HabitStorage namespacing', () {
    tearDown(() {
      LocalNamespaceResolver.debugUidOverride = testNamespaceUid;
    });

    test('saves and loads under a namespaced key when a UID is set', () async {
      SharedPreferences.setMockInitialValues({});
      LocalNamespaceResolver.debugUidOverride = 'uid-a';
      final storage = HabitStorage();
      final habit = Habit(
        id: '1',
        title: 'Drink water',
        scheduledTime: '08:00 AM',
        icon: Icons.local_drink_outlined,
      );

      await storage.saveHabits([habit]);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('habits:uid-a'), isTrue);
      expect(prefs.containsKey('habits'), isFalse);

      final loaded = await storage.loadHabits();
      expect(loaded!.single.id, '1');
    });

    test('two different UIDs read/write fully isolated data', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = HabitStorage();

      LocalNamespaceResolver.debugUidOverride = 'uid-a';
      await storage.saveHabits([
        Habit(
          id: 'a',
          title: 'A',
          scheduledTime: '08:00 AM',
          icon: Icons.local_drink_outlined,
        ),
      ]);

      LocalNamespaceResolver.debugUidOverride = 'uid-b';
      await storage.saveHabits([
        Habit(
          id: 'b',
          title: 'B',
          scheduledTime: '08:00 AM',
          icon: Icons.local_drink_outlined,
        ),
      ]);
      final bLoaded = await storage.loadHabits();

      LocalNamespaceResolver.debugUidOverride = 'uid-a';
      final aLoaded = await storage.loadHabits();

      expect(aLoaded!.single.id, 'a');
      expect(bLoaded!.single.id, 'b');
    });

    test('loadHabits returns null when no UID is available', () async {
      SharedPreferences.setMockInitialValues({});
      LocalNamespaceResolver.debugUidOverride = null;

      final result = await HabitStorage().loadHabits();

      expect(result, isNull);
    });

    test('saveHabits throws when no UID is available', () async {
      SharedPreferences.setMockInitialValues({});
      LocalNamespaceResolver.debugUidOverride = null;

      expect(
        () => HabitStorage().saveHabits([
          Habit(
            id: '1',
            title: 'Drink water',
            scheduledTime: '08:00 AM',
            icon: Icons.local_drink_outlined,
          ),
        ]),
        throwsStateError,
      );
    });
  });

  group('HabitStorage.upsertHabit (Phase 1B centralized mutation)', () {
    tearDown(() {
      LocalNamespaceResolver.debugUidOverride = testNamespaceUid;
    });

    Habit newHabit({String id = '1', Set<String> completedDates = const {}}) {
      return Habit(
        id: id,
        title: 'Drink water',
        scheduledTime: '08:00 AM',
        icon: Icons.local_drink_outlined,
        completedDates: completedDates,
      );
    }

    test(
      'creating a habit stamps createdAt == updatedAt == the fixed clock time',
      () async {
        SharedPreferences.setMockInitialValues({});
        final clock = FakeClock(DateTime.utc(2026, 1, 1));
        final storage = HabitStorage(clock: clock);

        final stamped = await storage.upsertHabit(newHabit());

        expect(stamped.createdAt, DateTime.utc(2026, 1, 1));
        expect(stamped.updatedAt, DateTime.utc(2026, 1, 1));
        final loaded = await storage.loadHabits();
        expect(loaded!.single.createdAt, DateTime.utc(2026, 1, 1));
        expect(loaded.single.updatedAt, DateTime.utc(2026, 1, 1));
      },
    );

    test(
      'updating an existing habit preserves createdAt and advances updatedAt',
      () async {
        SharedPreferences.setMockInitialValues({});
        final clock = FakeClock(DateTime.utc(2026, 1, 1));
        final storage = HabitStorage(clock: clock);
        await storage.upsertHabit(newHabit());

        clock.value = DateTime.utc(2026, 6, 1);
        final updated = await storage.upsertHabit(
          newHabit(completedDates: {'2026-06-01'}),
        );

        expect(updated.createdAt, DateTime.utc(2026, 1, 1));
        expect(updated.updatedAt, DateTime.utc(2026, 6, 1));
        expect(updated.completedDates, {'2026-06-01'});
      },
    );

    test(
      'deletedAt is preserved unless the caller explicitly changes it',
      () async {
        SharedPreferences.setMockInitialValues({});
        final clock = FakeClock(DateTime.utc(2026, 1, 1));
        final storage = HabitStorage(clock: clock);
        final habit = newHabit();
        await storage.upsertHabit(habit);

        final withDeletion = habit.copyWith(
          deletedAt: DateTime.utc(2026, 3, 1),
        );
        clock.value = DateTime.utc(2026, 6, 1);
        final stamped = await storage.upsertHabit(withDeletion);
        expect(stamped.deletedAt, DateTime.utc(2026, 3, 1));

        // A later, unrelated mutation that doesn't touch deletedAt preserves it.
        clock.value = DateTime.utc(2026, 7, 1);
        final again = await storage.upsertHabit(
          stamped.copyWith(completedDates: {'2026-07-01'}),
        );
        expect(again.deletedAt, DateTime.utc(2026, 3, 1));
      },
    );

    test(
      'caller-supplied legacy sentinel timestamps do not survive normal creation',
      () async {
        SharedPreferences.setMockInitialValues({});
        final clock = FakeClock(DateTime.utc(2026, 1, 1));
        final storage = HabitStorage(clock: clock);

        // Default-constructed Habit carries the legacy sentinel (2000-01-01)
        // unless explicitly given a createdAt — this is exactly the shape an
        // in-memory sample habit has before its first save.
        final sample = Habit(
          id: 'sample-1',
          title: 'Read',
          scheduledTime: '09:00 AM',
          icon: Icons.book,
        );
        expect(sample.createdAt, DateTime.utc(2000, 1, 1));

        final stamped = await storage.upsertHabit(sample);

        expect(stamped.createdAt, DateTime.utc(2026, 1, 1));
        expect(stamped.updatedAt, DateTime.utc(2026, 1, 1));
      },
    );

    test('upsertHabit throws when no UID is available', () async {
      SharedPreferences.setMockInitialValues({});
      LocalNamespaceResolver.debugUidOverride = null;

      expect(() => HabitStorage().upsertHabit(newHabit()), throwsStateError);
    });

    test('upsertHabit keeps namespaced isolation between two UIDs', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = HabitStorage();

      LocalNamespaceResolver.debugUidOverride = 'uid-a';
      await storage.upsertHabit(newHabit(id: 'a'));

      LocalNamespaceResolver.debugUidOverride = 'uid-b';
      await storage.upsertHabit(newHabit(id: 'b'));
      final bLoaded = await storage.loadHabits();

      LocalNamespaceResolver.debugUidOverride = 'uid-a';
      final aLoaded = await storage.loadHabits();

      expect(aLoaded!.single.id, 'a');
      expect(bLoaded!.single.id, 'b');
    });

    test(
      'raw saveHabits still preserves supplied timestamps exactly',
      () async {
        SharedPreferences.setMockInitialValues({});
        final storage = HabitStorage();
        final habit = Habit(
          id: '1',
          title: 'Drink water',
          scheduledTime: '08:00 AM',
          icon: Icons.local_drink_outlined,
          createdAt: DateTime.utc(2020, 1, 1),
          updatedAt: DateTime.utc(2021, 1, 1),
        );

        await storage.saveHabits([habit]);
        final loaded = await storage.loadHabits();

        expect(loaded!.single.createdAt, DateTime.utc(2020, 1, 1));
        expect(loaded.single.updatedAt, DateTime.utc(2021, 1, 1));
      },
    );

    test(
      'two near-simultaneous upserts for different habits do not lose either mutation',
      () async {
        SharedPreferences.setMockInitialValues({});
        final storage = HabitStorage(
          clock: FakeClock(DateTime.utc(2026, 1, 1)),
        );
        await storage.saveHabits([newHabit(id: 'a'), newHabit(id: 'b')]);

        // Neither call is awaited before the other starts — without
        // instance-level write serialization, one of these would load the
        // pre-mutation snapshot and silently clobber the other's save.
        final futureA = storage.upsertHabit(
          newHabit(id: 'a', completedDates: {'2026-01-01'}),
        );
        final futureB = storage.upsertHabit(
          newHabit(id: 'b', completedDates: {'2026-01-02'}),
        );
        await Future.wait([futureA, futureB]);

        final loaded = await storage.loadHabits();
        final a = loaded!.firstWhere((h) => h.id == 'a');
        final b = loaded.firstWhere((h) => h.id == 'b');
        expect(a.completedDates, {'2026-01-01'});
        expect(b.completedDates, {'2026-01-02'});
      },
    );

    test(
      'a failed write does not permanently block writes queued after it',
      () async {
        SharedPreferences.setMockInitialValues({});
        LocalNamespaceResolver.debugUidOverride = null;
        final storage = HabitStorage();

        await expectLater(
          storage.upsertHabit(newHabit(id: 'a')),
          throwsStateError,
        );

        LocalNamespaceResolver.debugUidOverride = 'uid-a';
        final stamped = await storage.upsertHabit(newHabit(id: 'b'));

        expect(stamped.id, 'b');
        final loaded = await storage.loadHabits();
        expect(loaded!.single.id, 'b');
      },
    );
  });

  group('HabitStorage.ensurePersisted (Phase 1C)', () {
    tearDown(() {
      LocalNamespaceResolver.debugUidOverride = testNamespaceUid;
    });

    Habit newHabit({String id = '1'}) => Habit(
      id: id,
      title: 'Drink water',
      scheduledTime: '08:00 AM',
      icon: Icons.local_drink_outlined,
    );

    test('persists habits not yet in raw storage', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = HabitStorage(clock: FakeClock(DateTime.utc(2026, 1, 1)));

      await storage.ensurePersisted([newHabit(id: '1'), newHabit(id: '2')]);

      final raw = await storage.loadHabitsRaw();
      expect(raw!.map((h) => h.id), containsAll(['1', '2']));
      expect(raw.first.createdAt, DateTime.utc(2026, 1, 1));
    });

    test('does not disturb a habit already persisted', () async {
      SharedPreferences.setMockInitialValues({});
      final clock = FakeClock(DateTime.utc(2026, 1, 1));
      final storage = HabitStorage(clock: clock);
      final existing = await storage.upsertHabit(newHabit(id: '1'));

      clock.value = DateTime.utc(2026, 6, 1);
      await storage.ensurePersisted([existing, newHabit(id: '2')]);

      final raw = await storage.loadHabitsRaw();
      final one = raw!.firstWhere((h) => h.id == '1');
      expect(one.updatedAt, DateTime.utc(2026, 1, 1));
    });

    test('does not disturb an existing tombstone', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = HabitStorage();
      final habit = await storage.upsertHabit(newHabit(id: '1'));
      await storage.tombstoneHabit(habit);

      await storage.ensurePersisted([newHabit(id: '2')]);

      final raw = await storage.loadHabitsRaw();
      final one = raw!.firstWhere((h) => h.id == '1');
      expect(one.deletedAt, isNotNull);
    });

    // Sample habits are real user-owned records once persisted (Habit
    // carries no "template"/local-only flag; they're edited, completed,
    // and deleted exactly like any user-created habit), so a future sync
    // engine must be able to see them. This means every id newly
    // persisted by ensurePersisted must land in dirtyHabitIds.
    test('every newly persisted habit is marked dirty', () async {
      SharedPreferences.setMockInitialValues({});
      final syncMetadataStorage = SyncMetadataStorage();
      final storage = HabitStorage(syncMetadataStorage: syncMetadataStorage);

      await storage.ensurePersisted([newHabit(id: '1'), newHabit(id: '2')]);

      final metadata = await syncMetadataStorage.load();
      expect(metadata.dirtyHabitIds, {'1', '2'});
    });

    test(
      'a repeated ensurePersisted call is a no-op: no restamp, no re-dirty',
      () async {
        SharedPreferences.setMockInitialValues({});
        final clock = FakeClock(DateTime.utc(2026, 1, 1));
        final syncMetadataStorage = SyncMetadataStorage();
        final storage = HabitStorage(
          clock: clock,
          syncMetadataStorage: syncMetadataStorage,
        );
        await storage.ensurePersisted([newHabit(id: '1')]);
        await syncMetadataStorage.save(SyncMetadata.empty);

        clock.value = DateTime.utc(2026, 6, 1);
        await storage.ensurePersisted([newHabit(id: '1')]);

        final raw = await storage.loadHabitsRaw();
        expect(raw!.single.updatedAt, DateTime.utc(2026, 1, 1));
        final metadata = await syncMetadataStorage.load();
        expect(metadata.dirtyHabitIds, isEmpty);
      },
    );

    test(
      'deleting one just-persisted sample does not make active siblings disappear',
      () async {
        SharedPreferences.setMockInitialValues({});
        final storage = HabitStorage();
        final samples = [
          newHabit(id: '1'),
          newHabit(id: '2'),
          newHabit(id: '3'),
        ];

        await storage.ensurePersisted(samples);
        await storage.tombstoneHabit(samples[0]);

        final visible = await storage.loadHabits();
        expect(visible!.map((h) => h.id), containsAll(['2', '3']));
        expect(visible, hasLength(2));
      },
    );

    test(
      'restart (fresh instance) preserves active siblings after a delete',
      () async {
        SharedPreferences.setMockInitialValues({});
        final samples = [newHabit(id: '1'), newHabit(id: '2')];
        await HabitStorage().ensurePersisted(samples);
        await HabitStorage().tombstoneHabit(samples[0]);

        // A brand-new instance, as a real app restart would create.
        final visible = await HabitStorage().loadHabits();

        expect(visible!.single.id, '2');
      },
    );

    test('two different UIDs keep ensurePersisted fully isolated', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = HabitStorage();

      LocalNamespaceResolver.debugUidOverride = 'uid-a';
      await storage.ensurePersisted([newHabit(id: '1')]);

      LocalNamespaceResolver.debugUidOverride = 'uid-b';
      final bVisible = await storage.loadHabits();

      LocalNamespaceResolver.debugUidOverride = 'uid-a';
      final aVisible = await storage.loadHabits();

      expect(aVisible!.single.id, '1');
      expect(bVisible, isNull);
    });
  });

  group('HabitStorage dirty-first atomicity (Phase 1C)', () {
    tearDown(() {
      LocalNamespaceResolver.debugUidOverride = testNamespaceUid;
    });

    Habit newHabit({String id = '1'}) => Habit(
      id: id,
      title: 'Drink water',
      scheduledTime: '08:00 AM',
      icon: Icons.local_drink_outlined,
    );

    test(
      'metadata succeeds, data write fails: the id is still dirty (recoverable), '
      'not silently lost',
      () async {
        SharedPreferences.setMockInitialValues({});
        final syncMetadataStorage = SyncMetadataStorage();
        final storage = _FailingWriteHabitStorage(
          syncMetadataStorage: syncMetadataStorage,
        );

        await expectLater(storage.upsertHabit(newHabit()), throwsStateError);

        final metadata = await syncMetadataStorage.load();
        expect(metadata.dirtyHabitIds, contains('1'));
        // The data write never happened, but that's the safe direction:
        // nothing was silently persisted without sync visibility.
        expect(await HabitStorage().loadHabitsRaw(), isNull);
      },
    );

    test('metadata fails before the data write: the whole mutation reports '
        'failure and nothing is silently half-applied', () async {
      SharedPreferences.setMockInitialValues({});
      final failingMetadata = _FailingSyncMetadataStorage();
      final storage = HabitStorage(syncMetadataStorage: failingMetadata);

      await expectLater(storage.upsertHabit(newHabit()), throwsStateError);

      expect(await HabitStorage().loadHabitsRaw(), isNull);
    });

    test(
      'a retried mutation after a failure succeeds and repairs the dirty id',
      () async {
        SharedPreferences.setMockInitialValues({});
        final syncMetadataStorage = SyncMetadataStorage();
        final storage = _FailingWriteHabitStorage(
          syncMetadataStorage: syncMetadataStorage,
        );

        await expectLater(storage.upsertHabit(newHabit()), throwsStateError);

        final retryStorage = HabitStorage(
          syncMetadataStorage: syncMetadataStorage,
        );
        final stamped = await retryStorage.upsertHabit(newHabit());

        final metadata = await syncMetadataStorage.load();
        expect(metadata.dirtyHabitIds, {'1'});
        expect(stamped.id, '1');
        final raw = await retryStorage.loadHabitsRaw();
        expect(raw!.single.id, '1');
      },
    );

    test('two concurrent mutations on different habits preserve both data '
        'changes and both dirty ids', () async {
      SharedPreferences.setMockInitialValues({});
      final syncMetadataStorage = SyncMetadataStorage();
      final storage = HabitStorage(syncMetadataStorage: syncMetadataStorage);

      final futureA = storage.upsertHabit(newHabit(id: 'a'));
      final futureB = storage.upsertHabit(newHabit(id: 'b'));
      await Future.wait([futureA, futureB]);

      final raw = await storage.loadHabitsRaw();
      expect(raw!.map((h) => h.id), containsAll(['a', 'b']));
      final metadata = await syncMetadataStorage.load();
      expect(metadata.dirtyHabitIds, {'a', 'b'});
    });

    test(
      'a failed operation does not poison the queue for later writes',
      () async {
        SharedPreferences.setMockInitialValues({});
        final storage = _FailOnceHabitStorage();

        await expectLater(storage.upsertHabit(newHabit()), throwsStateError);
        final stamped = await storage.upsertHabit(newHabit());

        expect(stamped.id, '1');
        final raw = await storage.loadHabitsRaw();
        expect(raw!.single.id, '1');
      },
    );
  });

  group('HabitStorage.tombstoneHabit (Phase 1C)', () {
    tearDown(() {
      LocalNamespaceResolver.debugUidOverride = testNamespaceUid;
    });

    Habit newHabit({String id = '1'}) => Habit(
      id: id,
      title: 'Drink water',
      scheduledTime: '08:00 AM',
      icon: Icons.local_drink_outlined,
    );

    test(
      'tombstone keeps the raw record but hides it from normal loads',
      () async {
        SharedPreferences.setMockInitialValues({});
        final storage = HabitStorage(
          clock: FakeClock(DateTime.utc(2026, 1, 1)),
        );
        final habit = await storage.upsertHabit(newHabit());

        await storage.tombstoneHabit(habit);

        final visible = await storage.loadHabits();
        expect(visible, isEmpty);
        final raw = await storage.loadHabitsRaw();
        expect(raw!.single.id, '1');
        expect(raw.single.deletedAt, isNotNull);
      },
    );

    test(
      'createdAt is preserved; updatedAt == deletedAt == the clock time',
      () async {
        SharedPreferences.setMockInitialValues({});
        final clock = FakeClock(DateTime.utc(2026, 1, 1));
        final storage = HabitStorage(clock: clock);
        final habit = await storage.upsertHabit(newHabit());

        clock.value = DateTime.utc(2026, 6, 1);
        final tombstoned = await storage.tombstoneHabit(habit);

        expect(tombstoned.createdAt, DateTime.utc(2026, 1, 1));
        expect(tombstoned.updatedAt, DateTime.utc(2026, 6, 1));
        expect(tombstoned.deletedAt, DateTime.utc(2026, 6, 1));
      },
    );

    test('marks the id dirty', () async {
      SharedPreferences.setMockInitialValues({});
      final syncMetadataStorage = SyncMetadataStorage();
      final storage = HabitStorage(syncMetadataStorage: syncMetadataStorage);
      final habit = await storage.upsertHabit(newHabit());

      await storage.tombstoneHabit(habit);

      final metadata = await syncMetadataStorage.load();
      expect(metadata.dirtyHabitIds, contains('1'));
    });

    test(
      'a second tombstone call is safe and re-stamps a later updatedAt',
      () async {
        SharedPreferences.setMockInitialValues({});
        final clock = FakeClock(DateTime.utc(2026, 1, 1));
        final storage = HabitStorage(clock: clock);
        final habit = await storage.upsertHabit(newHabit());
        final first = await storage.tombstoneHabit(habit);

        clock.value = DateTime.utc(2026, 6, 1);
        final again = await storage.tombstoneHabit(first);

        expect(again.deletedAt, DateTime.utc(2026, 6, 1));
        expect(again.updatedAt, DateTime.utc(2026, 6, 1));
      },
    );

    test(
      'tombstoning a habit that was never persisted upserts it already deleted '
      '(no pre-flush required)',
      () async {
        SharedPreferences.setMockInitialValues({});
        final storage = HabitStorage(
          clock: FakeClock(DateTime.utc(2026, 1, 1)),
        );

        final tombstoned = await storage.tombstoneHabit(newHabit());

        expect(tombstoned.createdAt, DateTime.utc(2026, 1, 1));
        expect(tombstoned.updatedAt, DateTime.utc(2026, 1, 1));
        expect(tombstoned.deletedAt, DateTime.utc(2026, 1, 1));
        final raw = await storage.loadHabitsRaw();
        expect(raw!.single.id, '1');
      },
    );

    test('creates a recovery snapshot before tombstoning', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = HabitStorage();
      final habit = await storage.upsertHabit(newHabit());

      await storage.tombstoneHabit(habit);

      final snapshot = await RecoverySnapshotStorage().read();
      expect(snapshot, isNotNull);
      expect(snapshot!.reason, 'beforeHabitTombstone');
      // Snapshot was taken before the tombstone, so it holds the
      // still-active record.
      expect(snapshot.habits.single['deletedAt'], isNull);
    });

    test('an all-tombstoned namespace does not regenerate sample habits '
        '(loadHabits returns an empty list, not null)', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = HabitStorage();
      final a = await storage.upsertHabit(newHabit(id: '1'));
      final b = await storage.upsertHabit(newHabit(id: '2'));

      await storage.tombstoneHabit(a);
      await storage.tombstoneHabit(b);

      final visible = await storage.loadHabits();
      expect(visible, isNotNull);
      expect(visible, isEmpty);
    });

    test(
      'a never-initialized namespace still returns null (first-load contract)',
      () async {
        SharedPreferences.setMockInitialValues({});

        final visible = await HabitStorage().loadHabits();

        expect(visible, isNull);
      },
    );

    test('a different UID gets its own correct first-use behavior', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = HabitStorage();

      LocalNamespaceResolver.debugUidOverride = 'uid-a';
      final habit = await storage.upsertHabit(newHabit());
      await storage.tombstoneHabit(habit);

      LocalNamespaceResolver.debugUidOverride = 'uid-b';
      final visible = await storage.loadHabits();

      expect(visible, isNull);
    });
  });
}
