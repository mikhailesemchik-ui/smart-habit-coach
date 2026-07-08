import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_habit_coach/core/storage/local_namespace_resolver.dart';
import 'package:smart_habit_coach/features/home/data/habit_storage.dart';
import 'package:smart_habit_coach/features/home/domain/date_key.dart';
import 'package:smart_habit_coach/features/home/domain/habit.dart';

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
}
