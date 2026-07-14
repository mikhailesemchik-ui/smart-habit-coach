import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_habit_coach/core/storage/local_namespace_resolver.dart';
import 'package:smart_habit_coach/core/sync/sync_metadata.dart';
import 'package:smart_habit_coach/core/sync/sync_metadata_storage.dart';

import '../../support/test_namespace.dart';

void main() {
  tearDown(() {
    LocalNamespaceResolver.debugUidOverride = testNamespaceUid;
  });

  group('SyncMetadataStorage', () {
    test('load returns empty defaults when nothing has been saved', () async {
      SharedPreferences.setMockInitialValues({});

      final metadata = await SyncMetadataStorage().load();

      expect(metadata.dirtyHabitIds, isEmpty);
      expect(metadata.preferencesDirty, isFalse);
    });

    test('save then load round-trips', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = SyncMetadataStorage();

      await storage.markHabitDirty('h1');
      final loaded = await storage.load();

      expect(loaded.dirtyHabitIds, {'h1'});
    });

    test('load falls back to empty defaults for malformed JSON', () async {
      SharedPreferences.setMockInitialValues({
        'sync_metadata:$testNamespaceUid': 'not valid json',
      });

      final metadata = await SyncMetadataStorage().load();

      expect(metadata.dirtyHabitIds, isEmpty);
    });

    test('namespaced isolation between two UIDs', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = SyncMetadataStorage();

      LocalNamespaceResolver.debugUidOverride = 'uid-a';
      await storage.markHabitDirty('a');

      LocalNamespaceResolver.debugUidOverride = 'uid-b';
      await storage.markHabitDirty('b');
      final bMeta = await storage.load();

      LocalNamespaceResolver.debugUidOverride = 'uid-a';
      final aMeta = await storage.load();

      expect(aMeta.dirtyHabitIds, {'a'});
      expect(bMeta.dirtyHabitIds, {'b'});
    });

    test('markHabitDirty adds one id without disturbing others', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = SyncMetadataStorage();

      await storage.markHabitDirty('h1');
      await storage.markHabitDirty('h2');
      final loaded = await storage.load();

      expect(loaded.dirtyHabitIds, {'h1', 'h2'});
    });

    test('markSuggestionDirty adds to dirtySuggestionIds', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = SyncMetadataStorage();

      await storage.markSuggestionDirty('s1');
      final loaded = await storage.load();

      expect(loaded.dirtySuggestionIds, {'s1'});
    });

    test('markPreferencesDirty sets the flag', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = SyncMetadataStorage();

      await storage.markPreferencesDirty();
      final loaded = await storage.load();

      expect(loaded.preferencesDirty, isTrue);
    });

    test(
      'recordSyncAttempt preserves an existing lastSuccessfulSyncAt',
      () async {
        SharedPreferences.setMockInitialValues({});
        final storage = SyncMetadataStorage();
        await storage.markHabitDirty('h1');

        await storage.recordSyncAttempt();
        final loaded = await storage.load();

        expect(loaded.dirtyHabitIds, {'h1'});
        expect(loaded.lastSyncAttemptAt, isNotNull);
      },
    );

    test(
      'two concurrent dirty marks (habit and suggestion) do not lose either id',
      () async {
        SharedPreferences.setMockInitialValues({});
        final storage = SyncMetadataStorage();

        final futureA = storage.markHabitDirty('h1');
        final futureB = storage.markSuggestionDirty('s1');
        await Future.wait([futureA, futureB]);

        final loaded = await storage.load();
        expect(loaded.dirtyHabitIds, {'h1'});
        expect(loaded.dirtySuggestionIds, {'s1'});
      },
    );

    test(
      'a failed write does not permanently block writes queued after it',
      () async {
        SharedPreferences.setMockInitialValues({});
        LocalNamespaceResolver.debugUidOverride = null;
        final storage = SyncMetadataStorage();

        await expectLater(storage.markHabitDirty('h1'), throwsStateError);

        LocalNamespaceResolver.debugUidOverride = 'uid-a';
        final loaded = await storage.markHabitDirty('h2');

        expect(loaded.dirtyHabitIds, {'h2'});
      },
    );

    test('clearHabitDirty removes only the given id', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = SyncMetadataStorage();
      await storage.markHabitDirty('h1');
      await storage.markHabitDirty('h2');

      final result = await storage.clearHabitDirty('h1');

      expect(result.dirtyHabitIds, {'h2'});
    });

    test('clearSuggestionDirty removes only the given id', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = SyncMetadataStorage();
      await storage.markSuggestionDirty('s1');
      await storage.markSuggestionDirty('s2');

      final result = await storage.clearSuggestionDirty('s1');

      expect(result.dirtySuggestionIds, {'s2'});
    });

    test('clearPreferencesDirty clears the flag', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = SyncMetadataStorage();
      await storage.markPreferencesDirty();

      final result = await storage.clearPreferencesDirty();

      expect(result.preferencesDirty, isFalse);
    });

    test('recordSyncResult sets lastSuccessfulSyncAt and clears the error code '
        'on success', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = SyncMetadataStorage();
      await storage.save(
        const SyncMetadata(lastSyncErrorCode: 'networkUnavailable'),
      );
      final now = DateTime.utc(2026, 1, 1);

      final result = await storage.recordSyncResult(successAt: now);

      expect(result.lastSuccessfulSyncAt, now);
      expect(result.lastSyncErrorCode, isNull);
    });

    test(
      'recordSyncResult on failure preserves the previous successful time',
      () async {
        SharedPreferences.setMockInitialValues({});
        final storage = SyncMetadataStorage();
        final previous = DateTime.utc(2025, 12, 1);
        await storage.recordSyncResult(successAt: previous);

        final result = await storage.recordSyncResult(
          errorCode: 'networkUnavailable',
        );

        expect(result.lastSuccessfulSyncAt, previous);
        expect(result.lastSyncErrorCode, 'networkUnavailable');
      },
    );
  });
}
