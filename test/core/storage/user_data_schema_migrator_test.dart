import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_habit_coach/core/storage/local_namespace_resolver.dart';
import 'package:smart_habit_coach/core/storage/user_data_schema_migrator.dart';

import '../../support/test_namespace.dart';

void main() {
  tearDown(() {
    LocalNamespaceResolver.debugUidOverride = testNamespaceUid;
  });

  group('LocalUserDataSchemaMigrator', () {
    test('version key is namespaced per UID', () async {
      SharedPreferences.setMockInitialValues({});
      LocalNamespaceResolver.debugUidOverride = 'uid-a';

      await LocalUserDataSchemaMigrator().run();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('local_schema_version:uid-a'), 1);
    });

    test(
      'migrates old-shape namespaced habits, backfilling createdAt/updatedAt',
      () async {
        LocalNamespaceResolver.debugUidOverride = 'uid-a';
        SharedPreferences.setMockInitialValues({
          'habits:uid-a': jsonEncode([
            {'id': '1', 'title': 'Old habit'},
          ]),
        });

        final ok = await LocalUserDataSchemaMigrator(
          clock: () => DateTime.utc(2026, 7, 1),
        ).run();

        expect(ok, isTrue);
        final prefs = await SharedPreferences.getInstance();
        final decoded = jsonDecode(prefs.getString('habits:uid-a')!) as List;
        final record = decoded.single as Map;
        expect(record['id'], '1');
        expect(record['title'], 'Old habit');
        expect(record['createdAt'], '2026-07-01T00:00:00.000Z');
        expect(record['updatedAt'], '2026-07-01T00:00:00.000Z');
        expect(record.containsKey('deletedAt'), isFalse);
      },
    );

    test('migrates old-shape namespaced suggestions the same way', () async {
      LocalNamespaceResolver.debugUidOverride = 'uid-a';
      SharedPreferences.setMockInitialValues({
        'adaptive_suggestions:uid-a': jsonEncode([
          {'id': 's1', 'habitId': 'h1'},
        ]),
      });

      final ok = await LocalUserDataSchemaMigrator(
        clock: () => DateTime.utc(2026, 7, 1),
      ).run();

      expect(ok, isTrue);
      final prefs = await SharedPreferences.getInstance();
      final decoded =
          jsonDecode(prefs.getString('adaptive_suggestions:uid-a')!) as List;
      final record = decoded.single as Map;
      expect(record['createdAt'], '2026-07-01T00:00:00.000Z');
      expect(record['updatedAt'], '2026-07-01T00:00:00.000Z');
    });

    test(
      'every migrated record in one run receives the same timestamp',
      () async {
        LocalNamespaceResolver.debugUidOverride = 'uid-a';
        SharedPreferences.setMockInitialValues({
          'habits:uid-a': jsonEncode([
            {'id': '1'},
            {'id': '2'},
          ]),
        });
        var calls = 0;
        DateTime clock() {
          calls++;
          return DateTime.utc(2026, 7, 1);
        }

        await LocalUserDataSchemaMigrator(clock: clock).run();

        final prefs = await SharedPreferences.getInstance();
        final decoded = jsonDecode(prefs.getString('habits:uid-a')!) as List;
        expect(decoded[0]['createdAt'], decoded[1]['createdAt']);
        // Clock is called exactly once for the whole migration run, never
        // once per record or per data category.
        expect(calls, 1);
      },
    );

    test(
      'existing timestamps on a record are preserved, not overwritten',
      () async {
        LocalNamespaceResolver.debugUidOverride = 'uid-a';
        SharedPreferences.setMockInitialValues({
          'habits:uid-a': jsonEncode([
            {
              'id': '1',
              'createdAt': '2020-01-01T00:00:00.000Z',
              'updatedAt': '2020-06-01T00:00:00.000Z',
            },
          ]),
        });

        await LocalUserDataSchemaMigrator(
          clock: () => DateTime.utc(2026, 7, 1),
        ).run();

        final prefs = await SharedPreferences.getInstance();
        final record =
            (jsonDecode(prefs.getString('habits:uid-a')!) as List).single
                as Map;
        expect(record['createdAt'], '2020-01-01T00:00:00.000Z');
        expect(record['updatedAt'], '2020-06-01T00:00:00.000Z');
      },
    );

    test('deletedAt remains absent unless already present', () async {
      LocalNamespaceResolver.debugUidOverride = 'uid-a';
      SharedPreferences.setMockInitialValues({
        'habits:uid-a': jsonEncode([
          {'id': '1'},
          {'id': '2', 'deletedAt': '2026-06-01T00:00:00.000Z'},
        ]),
      });

      await LocalUserDataSchemaMigrator(
        clock: () => DateTime.utc(2026, 7, 1),
      ).run();

      final prefs = await SharedPreferences.getInstance();
      final decoded = jsonDecode(prefs.getString('habits:uid-a')!) as List;
      expect((decoded[0] as Map).containsKey('deletedAt'), isFalse);
      expect(decoded[1]['deletedAt'], '2026-06-01T00:00:00.000Z');
    });

    test('unknown fields on existing records are preserved', () async {
      LocalNamespaceResolver.debugUidOverride = 'uid-a';
      SharedPreferences.setMockInitialValues({
        'habits:uid-a': jsonEncode([
          {'id': '1', 'someFutureField': 'keep-me'},
        ]),
      });

      await LocalUserDataSchemaMigrator(
        clock: () => DateTime.utc(2026, 7, 1),
      ).run();

      final prefs = await SharedPreferences.getInstance();
      final record =
          (jsonDecode(prefs.getString('habits:uid-a')!) as List).single as Map;
      expect(record['someFutureField'], 'keep-me');
    });

    test(
      'malformed (non-map) records are preserved verbatim, not dropped',
      () async {
        LocalNamespaceResolver.debugUidOverride = 'uid-a';
        SharedPreferences.setMockInitialValues({
          'habits:uid-a': jsonEncode([
            {'id': '1'},
            'not-a-map',
          ]),
        });

        await LocalUserDataSchemaMigrator(
          clock: () => DateTime.utc(2026, 7, 1),
        ).run();

        final prefs = await SharedPreferences.getInstance();
        final decoded = jsonDecode(prefs.getString('habits:uid-a')!) as List;
        expect(decoded.length, 2);
        expect(decoded[1], 'not-a-map');
      },
    );

    test('unparseable top-level JSON is left completely untouched', () async {
      LocalNamespaceResolver.debugUidOverride = 'uid-a';
      SharedPreferences.setMockInitialValues({
        'habits:uid-a': 'not valid json',
      });

      final ok = await LocalUserDataSchemaMigrator(
        clock: () => DateTime.utc(2026, 7, 1),
      ).run();

      expect(ok, isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('habits:uid-a'), 'not valid json');
    });

    test('second run is a no-op: already-migrated data is untouched', () async {
      LocalNamespaceResolver.debugUidOverride = 'uid-a';
      SharedPreferences.setMockInitialValues({
        'habits:uid-a': jsonEncode([
          {'id': '1'},
        ]),
      });

      await LocalUserDataSchemaMigrator(
        clock: () => DateTime.utc(2026, 7, 1),
      ).run();
      var secondClockCalled = false;
      final ok = await LocalUserDataSchemaMigrator(
        clock: () {
          secondClockCalled = true;
          return DateTime.utc(2099, 1, 1);
        },
      ).run();

      expect(ok, isTrue);
      expect(secondClockCalled, isFalse);
    });

    test(
      'returns false and does not advance version when no UID is available',
      () async {
        LocalNamespaceResolver.debugUidOverride = null;
        SharedPreferences.setMockInitialValues({});

        final ok = await LocalUserDataSchemaMigrator().run();

        expect(ok, isFalse);
        final prefs = await SharedPreferences.getInstance();
        expect(
          prefs.getKeys().where((k) => k.startsWith('local_schema_version')),
          isEmpty,
        );
      },
    );

    test('works on data already namespaced after a legacy copy', () async {
      LocalNamespaceResolver.debugUidOverride = 'uid-a';
      // Simulates the state right after LegacyMigrationRunner copied
      // unscoped legacy data into the active UID's namespace.
      SharedPreferences.setMockInitialValues({
        'habits': jsonEncode([
          {'id': '1'},
        ]),
        'habits:uid-a': jsonEncode([
          {'id': '1'},
        ]),
      });

      final ok = await LocalUserDataSchemaMigrator(
        clock: () => DateTime.utc(2026, 7, 1),
      ).run();

      expect(ok, isTrue);
      final prefs = await SharedPreferences.getInstance();
      final migrated =
          (jsonDecode(prefs.getString('habits:uid-a')!) as List).single as Map;
      expect(migrated['createdAt'], '2026-07-01T00:00:00.000Z');
      // The old unscoped legacy key is untouched by schema migration.
      final legacy =
          (jsonDecode(prefs.getString('habits')!) as List).single as Map;
      expect(legacy.containsKey('createdAt'), isFalse);
    });
  });
}
