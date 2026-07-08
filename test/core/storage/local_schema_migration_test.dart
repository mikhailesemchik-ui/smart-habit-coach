import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_habit_coach/core/storage/local_schema_migration.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('LocalSchemaMigrationRunner', () {
    test('runs a single step and records the new version', () async {
      final runner = LocalSchemaMigrationRunner(
        dataKey: 'data',
        versionKey: 'version',
        steps: [
          LocalSchemaMigrationStep(
            targetVersion: 1,
            migrate: (current) => {'migrated': true},
          ),
        ],
      );

      final version = await runner.run();

      expect(version, 1);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('version'), 1);
      expect(prefs.getString('data'), '{"migrated":true}');
    });

    test('runs multiple steps in order', () async {
      final applied = <int>[];
      final runner = LocalSchemaMigrationRunner(
        dataKey: 'data',
        versionKey: 'version',
        steps: [
          LocalSchemaMigrationStep(
            targetVersion: 1,
            migrate: (current) {
              applied.add(1);
              return {'step': 1};
            },
          ),
          LocalSchemaMigrationStep(
            targetVersion: 2,
            migrate: (current) {
              applied.add(2);
              return {'step': 2};
            },
          ),
        ],
      );

      final version = await runner.run();

      expect(version, 2);
      expect(applied, [1, 2]);
    });

    test(
      're-running is idempotent: already-applied steps are skipped',
      () async {
        var callCount = 0;
        final runner = LocalSchemaMigrationRunner(
          dataKey: 'data',
          versionKey: 'version',
          steps: [
            LocalSchemaMigrationStep(
              targetVersion: 1,
              migrate: (current) {
                callCount++;
                return {'runs': callCount};
              },
            ),
          ],
        );

        await runner.run();
        await runner.run();
        await runner.run();

        expect(callCount, 1);
      },
    );

    test('a failing step does not advance the recorded version', () async {
      final runner = LocalSchemaMigrationRunner(
        dataKey: 'data',
        versionKey: 'version',
        steps: [
          LocalSchemaMigrationStep(
            targetVersion: 1,
            migrate: (current) => throw StateError('boom'),
          ),
        ],
      );

      await expectLater(runner.run(), throwsStateError);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('version'), isNull);
    });

    test(
      'a failed step is retried on the next run and only counted once it succeeds',
      () async {
        var attempt = 0;
        final runner = LocalSchemaMigrationRunner(
          dataKey: 'data',
          versionKey: 'version',
          steps: [
            LocalSchemaMigrationStep(
              targetVersion: 1,
              migrate: (current) {
                attempt++;
                if (attempt == 1) throw StateError('boom');
                return {'ok': true};
              },
            ),
          ],
        );

        await expectLater(runner.run(), throwsStateError);
        final version = await runner.run();

        expect(version, 1);
        expect(attempt, 2);
      },
    );

    test('preserves prior data seen by the migrate function', () async {
      SharedPreferences.setMockInitialValues({'data': '{"existing":true}'});
      Object? seen;
      final runner = LocalSchemaMigrationRunner(
        dataKey: 'data',
        versionKey: 'version',
        steps: [
          LocalSchemaMigrationStep(
            targetVersion: 1,
            migrate: (current) {
              seen = current;
              return current;
            },
          ),
        ],
      );

      await runner.run();

      expect(seen, {'existing': true});
    });
  });
}
