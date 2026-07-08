import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_habit_coach/core/storage/local_namespace_resolver.dart';
import 'package:smart_habit_coach/core/sync/sync_metadata_storage.dart';
import 'package:smart_habit_coach/features/coach/data/adaptive_suggestion_storage.dart';
import 'package:smart_habit_coach/features/coach/domain/adaptive_suggestion.dart';

import '../../../support/fake_clock.dart';
import '../../../support/test_namespace.dart';

AdaptiveHabitSuggestion _suggestion(String id) {
  return AdaptiveHabitSuggestion(
    id: id,
    habitId: 'h1',
    type: AdaptiveSuggestionType.addMinimumVersion,
    createdAt: DateTime.utc(2026, 1, 1),
    analysisStart: DateTime.utc(2025, 12, 1),
    analysisEnd: DateTime.utc(2025, 12, 31),
    evidenceCode: 'code',
  );
}

void main() {
  tearDown(() {
    LocalNamespaceResolver.debugUidOverride = testNamespaceUid;
  });

  group('AdaptiveSuggestionStorage', () {
    test('loadSuggestions returns [] when nothing has been saved', () async {
      SharedPreferences.setMockInitialValues({});

      final result = await AdaptiveSuggestionStorage().loadSuggestions();

      expect(result, isEmpty);
    });

    test('saveSuggestions then loadSuggestions round-trips', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = AdaptiveSuggestionStorage();

      await storage.saveSuggestions([_suggestion('s1')]);
      final loaded = await storage.loadSuggestions();

      expect(loaded.single.id, 's1');
    });
  });

  group('AdaptiveSuggestionStorage namespacing', () {
    test('saves and loads under a namespaced key when a UID is set', () async {
      SharedPreferences.setMockInitialValues({});
      LocalNamespaceResolver.debugUidOverride = 'uid-a';
      final storage = AdaptiveSuggestionStorage();

      await storage.saveSuggestions([_suggestion('s1')]);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('adaptive_suggestions:uid-a'), isTrue);
      expect(prefs.containsKey('adaptive_suggestions'), isFalse);
    });

    test('two different UIDs read/write fully isolated data', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = AdaptiveSuggestionStorage();

      LocalNamespaceResolver.debugUidOverride = 'uid-a';
      await storage.saveSuggestions([_suggestion('a')]);

      LocalNamespaceResolver.debugUidOverride = 'uid-b';
      await storage.saveSuggestions([_suggestion('b')]);
      final bLoaded = await storage.loadSuggestions();

      LocalNamespaceResolver.debugUidOverride = 'uid-a';
      final aLoaded = await storage.loadSuggestions();

      expect(aLoaded.single.id, 'a');
      expect(bLoaded.single.id, 'b');
    });

    test('loadSuggestions returns [] when no UID is available', () async {
      SharedPreferences.setMockInitialValues({});
      LocalNamespaceResolver.debugUidOverride = null;

      final result = await AdaptiveSuggestionStorage().loadSuggestions();

      expect(result, isEmpty);
    });

    test('saveSuggestions throws when no UID is available', () async {
      SharedPreferences.setMockInitialValues({});
      LocalNamespaceResolver.debugUidOverride = null;

      expect(
        () => AdaptiveSuggestionStorage().saveSuggestions([_suggestion('s1')]),
        throwsStateError,
      );
    });
  });

  group(
    'AdaptiveSuggestionStorage.upsertSuggestion (Phase 1B centralized mutation)',
    () {
      test(
        'creating a suggestion preserves the detector-supplied createdAt and stamps updatedAt',
        () async {
          SharedPreferences.setMockInitialValues({});
          final clock = FakeClock(DateTime.utc(2026, 6, 1));
          final storage = AdaptiveSuggestionStorage(clock: clock);

          final stamped = await storage.upsertSuggestion(_suggestion('s1'));

          expect(stamped.createdAt, DateTime.utc(2026, 1, 1));
          expect(stamped.updatedAt, DateTime.utc(2026, 6, 1));
        },
      );

      test(
        'a status mutation advances updatedAt and preserves createdAt',
        () async {
          SharedPreferences.setMockInitialValues({});
          final clock = FakeClock(DateTime.utc(2026, 6, 1));
          final storage = AdaptiveSuggestionStorage(clock: clock);
          final created = await storage.upsertSuggestion(_suggestion('s1'));

          clock.value = DateTime.utc(2026, 6, 15);
          final applied = await storage.upsertSuggestion(
            created.copyWith(status: AdaptiveSuggestionStatus.applied),
          );

          expect(applied.createdAt, DateTime.utc(2026, 1, 1));
          expect(applied.updatedAt, DateTime.utc(2026, 6, 15));
          expect(applied.status, AdaptiveSuggestionStatus.applied);
        },
      );

      test(
        'deletedAt is preserved through an unrelated status mutation',
        () async {
          SharedPreferences.setMockInitialValues({});
          final storage = AdaptiveSuggestionStorage(
            clock: FakeClock(DateTime.utc(2026, 6, 1)),
          );
          final withDeletion = _suggestion(
            's1',
          ).copyWith(deletedAt: DateTime.utc(2026, 3, 1));
          final stamped = await storage.upsertSuggestion(withDeletion);

          expect(stamped.deletedAt, DateTime.utc(2026, 3, 1));
        },
      );

      test(
        'raw saveSuggestions still preserves supplied timestamps exactly',
        () async {
          SharedPreferences.setMockInitialValues({});
          final storage = AdaptiveSuggestionStorage();
          final suggestion = _suggestion(
            's1',
          ).copyWith(updatedAt: DateTime.utc(2021, 1, 1));

          await storage.saveSuggestions([suggestion]);
          final loaded = await storage.loadSuggestions();

          expect(loaded.single.createdAt, DateTime.utc(2026, 1, 1));
          expect(loaded.single.updatedAt, DateTime.utc(2021, 1, 1));
        },
      );

      test('upsertSuggestion throws when no UID is available', () async {
        SharedPreferences.setMockInitialValues({});
        LocalNamespaceResolver.debugUidOverride = null;

        // Writes are now queued behind `_writeQueue` (Phase 1B write-
        // serialization), so the "no UID" check runs on a later microtask,
        // not synchronously when this closure is invoked. The override
        // must therefore not be reset until this expectation has actually
        // settled — awaiting it here is required, not optional.
        await expectLater(
          AdaptiveSuggestionStorage().upsertSuggestion(_suggestion('s1')),
          throwsStateError,
        );
      });

      test(
        'upsertSuggestion keeps namespaced isolation between two UIDs',
        () async {
          SharedPreferences.setMockInitialValues({});
          final storage = AdaptiveSuggestionStorage();

          LocalNamespaceResolver.debugUidOverride = 'uid-a';
          await storage.upsertSuggestion(_suggestion('a'));

          LocalNamespaceResolver.debugUidOverride = 'uid-b';
          await storage.upsertSuggestion(_suggestion('b'));
          final bLoaded = await storage.loadSuggestions();

          LocalNamespaceResolver.debugUidOverride = 'uid-a';
          final aLoaded = await storage.loadSuggestions();

          expect(aLoaded.single.id, 'a');
          expect(bLoaded.single.id, 'b');
        },
      );

      test(
        'two near-simultaneous upserts for different suggestions do not lose either mutation',
        () async {
          SharedPreferences.setMockInitialValues({});
          final storage = AdaptiveSuggestionStorage(
            clock: FakeClock(DateTime.utc(2026, 1, 1)),
          );
          await storage.saveSuggestions([_suggestion('a'), _suggestion('b')]);

          final futureA = storage.upsertSuggestion(
            _suggestion('a').copyWith(status: AdaptiveSuggestionStatus.kept),
          );
          final futureB = storage.upsertSuggestion(
            _suggestion('b').copyWith(status: AdaptiveSuggestionStatus.applied),
          );
          await Future.wait([futureA, futureB]);

          final loaded = await storage.loadSuggestions();
          final a = loaded.firstWhere((s) => s.id == 'a');
          final b = loaded.firstWhere((s) => s.id == 'b');
          expect(a.status, AdaptiveSuggestionStatus.kept);
          expect(b.status, AdaptiveSuggestionStatus.applied);
        },
      );
    },
  );

  group('AdaptiveSuggestionStorage.tombstoneSuggestion (Phase 1C)', () {
    test(
      'normal load hides a tombstoned suggestion; raw load preserves it',
      () async {
        SharedPreferences.setMockInitialValues({});
        final storage = AdaptiveSuggestionStorage(
          clock: FakeClock(DateTime.utc(2026, 1, 1)),
        );
        final created = await storage.upsertSuggestion(_suggestion('s1'));

        await storage.tombstoneSuggestion(created);

        final visible = await storage.loadSuggestions();
        expect(visible, isEmpty);
        final raw = await storage.loadSuggestionsRaw();
        expect(raw.single.id, 's1');
        expect(raw.single.deletedAt, isNotNull);
      },
    );

    test(
      'createdAt is preserved; updatedAt and deletedAt share the same timestamp',
      () async {
        SharedPreferences.setMockInitialValues({});
        final clock = FakeClock(DateTime.utc(2026, 1, 1));
        final storage = AdaptiveSuggestionStorage(clock: clock);
        final created = await storage.upsertSuggestion(_suggestion('s1'));

        clock.value = DateTime.utc(2026, 6, 15);
        final tombstoned = await storage.tombstoneSuggestion(created);

        expect(tombstoned.createdAt, DateTime.utc(2026, 1, 1));
        expect(tombstoned.updatedAt, DateTime.utc(2026, 6, 15));
        expect(tombstoned.deletedAt, DateTime.utc(2026, 6, 15));
      },
    );

    test('marks dirtySuggestionIds', () async {
      SharedPreferences.setMockInitialValues({});
      final syncMetadataStorage = SyncMetadataStorage();
      final storage = AdaptiveSuggestionStorage(
        syncMetadataStorage: syncMetadataStorage,
      );
      final created = await storage.upsertSuggestion(_suggestion('s1'));

      await storage.tombstoneSuggestion(created);

      final metadata = await syncMetadataStorage.load();
      expect(metadata.dirtySuggestionIds, contains('s1'));
    });

    test(
      'status-only changes remain visible (not treated as deletion)',
      () async {
        SharedPreferences.setMockInitialValues({});
        final storage = AdaptiveSuggestionStorage();
        final created = await storage.upsertSuggestion(_suggestion('s1'));

        await storage.upsertSuggestion(
          created.copyWith(status: AdaptiveSuggestionStatus.applied),
        );

        final visible = await storage.loadSuggestions();
        expect(visible.single.status, AdaptiveSuggestionStatus.applied);
        expect(visible.single.deletedAt, isNull);
      },
    );

    test(
      'tombstoning a suggestion that was never persisted upserts it already deleted',
      () async {
        SharedPreferences.setMockInitialValues({});
        final storage = AdaptiveSuggestionStorage(
          clock: FakeClock(DateTime.utc(2026, 1, 1)),
        );

        final tombstoned = await storage.tombstoneSuggestion(_suggestion('s1'));

        expect(tombstoned.deletedAt, DateTime.utc(2026, 1, 1));
        final raw = await storage.loadSuggestionsRaw();
        expect(raw.single.id, 's1');
      },
    );
  });
}
