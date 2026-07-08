import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_habit_coach/core/storage/legacy_migration_runner.dart';
import 'package:smart_habit_coach/core/storage/local_namespace_resolver.dart';

import '../../support/test_namespace.dart';

void main() {
  tearDown(() {
    LocalNamespaceResolver.debugUidOverride = testNamespaceUid;
  });

  LegacyMigrationRunner runnerFor(String uid) {
    LocalNamespaceResolver.debugUidOverride = uid;
    return LegacyMigrationRunner(resolver: const LocalNamespaceResolver());
  }

  group('LegacyMigrationRunner', () {
    test('postpones with no writes when no UID is available', () async {
      SharedPreferences.setMockInitialValues({
        'habits': jsonEncode([
          {'id': '1'},
        ]),
      });
      LocalNamespaceResolver.debugUidOverride = null;
      final runner = LegacyMigrationRunner(
        resolver: const LocalNamespaceResolver(),
      );
      // Force "no UID": resolver.currentUid is null only when Supabase is
      // also uninitialized, which is the case in this test environment.

      final result = await runner.run();

      expect(result, LegacyMigrationResult.postponedNoUid);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(LegacyMigrationRunner.completedKey), isNull);
    });

    test('no-op when there is no legacy data', () async {
      SharedPreferences.setMockInitialValues({});
      final runner = runnerFor('uid-a');

      final result = await runner.run();

      expect(result, LegacyMigrationResult.noLegacyData);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(LegacyMigrationRunner.completedKey), isNull);
    });

    test('an empty legacy habits list is not meaningful data', () async {
      SharedPreferences.setMockInitialValues({'habits': jsonEncode([])});
      final runner = runnerFor('uid-a');

      final result = await runner.run();

      expect(result, LegacyMigrationResult.noLegacyData);
    });

    test(
      'successfully migrates legacy habits into the active UID namespace',
      () async {
        final legacyHabits = jsonEncode([
          {'id': '1', 'title': 'Drink water'},
        ]);
        SharedPreferences.setMockInitialValues({'habits': legacyHabits});
        final runner = runnerFor('uid-a');

        final result = await runner.run();

        expect(result, LegacyMigrationResult.migrated);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('habits:uid-a'), legacyHabits);
        // Old unscoped key is preserved, never deleted.
        expect(prefs.getString('habits'), legacyHabits);
        expect(prefs.getBool(LegacyMigrationRunner.completedKey), isTrue);
        expect(
          prefs.getString(LegacyMigrationRunner.migratedToUidKey),
          'uid-a',
        );
        expect(prefs.getString(LegacyMigrationRunner.migratedAtKey), isNotNull);
      },
    );

    test(
      'migrates partial legacy categories (habits only, no suggestions/settings)',
      () async {
        final legacyHabits = jsonEncode([
          {'id': '1'},
        ]);
        SharedPreferences.setMockInitialValues({'habits': legacyHabits});
        final runner = runnerFor('uid-a');

        final result = await runner.run();

        expect(result, LegacyMigrationResult.migrated);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.containsKey('adaptive_suggestions:uid-a'), isFalse);
        expect(prefs.containsKey('app_settings:uid-a'), isFalse);
      },
    );

    test('migrates legacy settings even with no habits/suggestions', () async {
      SharedPreferences.setMockInitialValues({
        'app_settings': jsonEncode({'displayName': 'Jamie'}),
      });
      final runner = runnerFor('uid-a');

      final result = await runner.run();

      expect(result, LegacyMigrationResult.migrated);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('app_settings:uid-a'), isNotNull);
    });

    test(
      'second run under the same UID is a no-op (already completed)',
      () async {
        final legacyHabits = jsonEncode([
          {'id': '1'},
        ]);
        SharedPreferences.setMockInitialValues({'habits': legacyHabits});
        final runner = runnerFor('uid-a');
        await runner.run();

        final second = await runnerFor('uid-a').run();

        expect(second, LegacyMigrationResult.alreadyCompleted);
      },
    );

    test(
      'cross-identity import is impossible: a later run under a different UID never imports',
      () async {
        final legacyHabits = jsonEncode([
          {'id': '1'},
        ]);
        SharedPreferences.setMockInitialValues({'habits': legacyHabits});
        await runnerFor('uid-a').run();

        final result = await runnerFor('uid-b').run();

        expect(result, LegacyMigrationResult.alreadyCompleted);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.containsKey('habits:uid-b'), isFalse);
        expect(
          prefs.getString(LegacyMigrationRunner.migratedToUidKey),
          'uid-a',
        );
      },
    );

    test(
      'destination already populated with no completion marker records a conflict, '
      'never overwrites or merges',
      () async {
        final legacyHabits = jsonEncode([
          {'id': '1'},
        ]);
        final destHabits = jsonEncode([
          {'id': '2'},
        ]);
        SharedPreferences.setMockInitialValues({
          'habits': legacyHabits,
          'habits:uid-a': destHabits,
        });
        final runner = runnerFor('uid-a');

        final result = await runner.run();

        expect(result, LegacyMigrationResult.conflict);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('habits:uid-a'), destHabits);
        expect(prefs.getString('habits'), legacyHabits);
        expect(prefs.getBool(LegacyMigrationRunner.completedKey), isNull);
        final conflictRaw = prefs.getString(LegacyMigrationRunner.conflictKey);
        expect(conflictRaw, isNotNull);
        final conflict = jsonDecode(conflictRaw!) as Map<String, dynamic>;
        expect(conflict['uid'], 'uid-a');
        expect(conflict['legacyCategories'], contains('habits'));
        expect(conflict['destinationCategories'], contains('habits'));
        // Diagnostic metadata must never contain full record contents.
        expect(conflictRaw, isNot(contains('Drink water')));
      },
    );

    test(
      'old unscoped keys still exist after a successful migration',
      () async {
        final legacyHabits = jsonEncode([
          {'id': '1'},
        ]);
        SharedPreferences.setMockInitialValues({'habits': legacyHabits});
        await runnerFor('uid-a').run();

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('habits'), legacyHabits);
      },
    );
  });
}
