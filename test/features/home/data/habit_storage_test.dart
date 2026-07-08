import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_habit_coach/core/storage/local_namespace_resolver.dart';
import 'package:smart_habit_coach/features/home/data/habit_storage.dart';
import 'package:smart_habit_coach/features/home/domain/date_key.dart';
import 'package:smart_habit_coach/features/home/domain/habit.dart';

import '../../../support/fake_clock.dart';
import '../../../support/test_namespace.dart';

const _habitsKey = 'habits:$testNamespaceUid';

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
}
