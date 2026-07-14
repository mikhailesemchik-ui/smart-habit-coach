import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_habit_coach/core/storage/local_namespace_resolver.dart';
import 'package:smart_habit_coach/core/sync/recovery_snapshot_storage.dart';
import 'package:smart_habit_coach/core/sync/sync_metadata_storage.dart';
import 'package:smart_habit_coach/features/coach/data/adaptive_suggestion_storage.dart';
import 'package:smart_habit_coach/features/coach/domain/adaptive_suggestion.dart';
import 'package:smart_habit_coach/features/home/data/habit_storage.dart';
import 'package:smart_habit_coach/features/home/domain/habit.dart';
import 'package:smart_habit_coach/features/profile/data/settings_storage.dart';
import 'package:smart_habit_coach/features/profile/domain/app_settings.dart';
import 'package:smart_habit_coach/features/sync/data/cloud_backend.dart';
import 'package:smart_habit_coach/features/sync/data/cloud_records.dart';
import 'package:smart_habit_coach/features/sync/data/cloud_repositories.dart';
import 'package:smart_habit_coach/features/sync/data/cloud_result.dart';
import 'package:smart_habit_coach/features/sync/data/sync_coordinator.dart';
import 'package:smart_habit_coach/features/sync/domain/sync_models.dart';

import '../../../support/fake_clock.dart';
import '../../../support/test_namespace.dart';

class _FakeSessionProvider implements CloudAuthSessionProvider {
  String? uid;
  _FakeSessionProvider(this.uid);

  @override
  String? currentUid() => uid;
}

/// Returns [initial] on the first call, then a different value on every
/// call after that — used to simulate the active account changing partway
/// through a sync (after the coordinator has already captured its starting
/// uid).
class _MidSyncChangingSessionProvider implements CloudAuthSessionProvider {
  final String initial;
  int _calls = 0;
  _MidSyncChangingSessionProvider(this.initial);

  @override
  String? currentUid() {
    _calls++;
    return _calls == 1 ? initial : 'a-different-uid';
  }
}

class _FakeHabitCloudRepository implements HabitCloudRepository {
  final Map<String, CloudHabitRecord> rows = {};
  CloudFailure? fetchFailure;
  CloudFailure? upsertFailure;
  List<CloudHabitRecord> lastUpserted = [];

  @override
  Future<CloudResult<List<CloudHabitRecord>>> fetchAll() async {
    if (fetchFailure != null) return CloudResult.failure(fetchFailure!);
    return CloudResult.success(rows.values.toList());
  }

  @override
  Future<CloudResult<List<CloudHabitRecord>>> fetchUpdatedSince(
    DateTime updatedSince,
  ) => fetchAll();

  @override
  Future<CloudResult<void>> upsert(CloudHabitRecord record) =>
      upsertMany([record]);

  @override
  Future<CloudResult<void>> upsertMany(List<CloudHabitRecord> records) async {
    if (upsertFailure != null) return CloudResult.failure(upsertFailure!);
    lastUpserted = records;
    for (final r in records) {
      rows[r.habit.id] = r;
    }
    return CloudResult.success(null);
  }

  @override
  Future<CloudResult<void>> hardDelete(String id) async {
    rows.remove(id);
    return CloudResult.success(null);
  }
}

class _FakeSuggestionCloudRepository
    implements AdaptiveSuggestionCloudRepository {
  final Map<String, CloudAdaptiveSuggestionRecord> rows = {};
  CloudFailure? fetchFailure;
  CloudFailure? upsertFailure;

  @override
  Future<CloudResult<List<CloudAdaptiveSuggestionRecord>>> fetchAll() async {
    if (fetchFailure != null) return CloudResult.failure(fetchFailure!);
    return CloudResult.success(rows.values.toList());
  }

  @override
  Future<CloudResult<List<CloudAdaptiveSuggestionRecord>>> fetchUpdatedSince(
    DateTime updatedSince,
  ) => fetchAll();

  @override
  Future<CloudResult<void>> upsert(CloudAdaptiveSuggestionRecord record) =>
      upsertMany([record]);

  @override
  Future<CloudResult<void>> upsertMany(
    List<CloudAdaptiveSuggestionRecord> records,
  ) async {
    if (upsertFailure != null) return CloudResult.failure(upsertFailure!);
    for (final r in records) {
      rows[r.suggestion.id] = r;
    }
    return CloudResult.success(null);
  }

  @override
  Future<CloudResult<void>> hardDelete(String id) async {
    rows.remove(id);
    return CloudResult.success(null);
  }
}

class _FakeSettingsCloudRepository implements SettingsCloudRepository {
  CloudSettingsRecord? row;
  CloudFailure? fetchFailure;
  CloudFailure? upsertFailure;

  @override
  Future<CloudResult<CloudSettingsRecord?>> fetch() async {
    if (fetchFailure != null) return CloudResult.failure(fetchFailure!);
    return CloudResult.success(row);
  }

  @override
  Future<CloudResult<void>> upsert(CloudSettingsRecord record) async {
    if (upsertFailure != null) return CloudResult.failure(upsertFailure!);
    row = record;
    return CloudResult.success(null);
  }
}

void main() {
  const uid = testNamespaceUid;

  late _FakeSessionProvider sessionProvider;
  late _FakeHabitCloudRepository habitRepo;
  late _FakeSuggestionCloudRepository suggestionRepo;
  late _FakeSettingsCloudRepository settingsRepo;
  late FakeClock clock;
  late HabitStorage habitStorage;
  late AdaptiveSuggestionStorage suggestionStorage;
  late SettingsStorage settingsStorage;
  late SyncMetadataStorage syncMetadataStorage;
  late RecoverySnapshotStorage recoverySnapshotStorage;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    LocalNamespaceResolver.debugUidOverride = uid;
    sessionProvider = _FakeSessionProvider(uid);
    habitRepo = _FakeHabitCloudRepository();
    suggestionRepo = _FakeSuggestionCloudRepository();
    settingsRepo = _FakeSettingsCloudRepository();
    clock = FakeClock(DateTime.utc(2026, 3, 1));
    syncMetadataStorage = SyncMetadataStorage(clock: clock);
    habitStorage = HabitStorage(
      clock: clock,
      syncMetadataStorage: syncMetadataStorage,
    );
    suggestionStorage = AdaptiveSuggestionStorage(
      clock: clock,
      syncMetadataStorage: syncMetadataStorage,
    );
    settingsStorage = SettingsStorage(
      clock: clock,
      syncMetadataStorage: syncMetadataStorage,
    );
    recoverySnapshotStorage = RecoverySnapshotStorage(
      clock: clock,
      habitStorage: habitStorage,
      suggestionStorage: suggestionStorage,
      settingsStorage: settingsStorage,
      syncMetadataStorage: syncMetadataStorage,
    );
  });

  SyncCoordinator coordinator({
    Future<void> Function(List<Habit>)? onHabitsChanged,
  }) {
    return SyncCoordinator(
      sessionProvider: sessionProvider,
      habitCloudRepository: habitRepo,
      suggestionCloudRepository: suggestionRepo,
      settingsCloudRepository: settingsRepo,
      habitStorage: habitStorage,
      suggestionStorage: suggestionStorage,
      settingsStorage: settingsStorage,
      syncMetadataStorage: syncMetadataStorage,
      recoverySnapshotStorage: recoverySnapshotStorage,
      clock: clock,
      onHabitsChanged: onHabitsChanged,
    );
  }

  Habit habit(String id, {DateTime? updatedAt, DateTime? deletedAt}) => Habit(
    id: id,
    title: 'Habit $id',
    scheduledTime: '08:00 AM',
    icon: Icons.check,
    createdAt: DateTime.utc(2026, 1, 1),
    updatedAt: updatedAt ?? DateTime.utc(2026, 1, 2),
    deletedAt: deletedAt,
  );

  void putRemoteHabit(Habit h) {
    habitRepo.rows[h.id] = CloudHabitRecord.fromHabit(userId: uid, habit: h);
  }

  group('UID safety', () {
    test(
      'unauthenticated (no session) fails before any storage access',
      () async {
        sessionProvider.uid = null;
        final result = await coordinator().sync();

        expect(result.isSuccess, isFalse);
        expect(result.failure!.code, SyncFailureCode.unauthenticated);
        expect(habitRepo.rows, isEmpty);
      },
    );

    test('blank uid fails', () async {
      sessionProvider.uid = '   ';
      final result = await coordinator().sync();

      expect(result.failure!.code, SyncFailureCode.unauthenticated);
    });

    test('UID changing mid-sync aborts without clearing dirty state', () async {
      await habitStorage.upsertHabit(habit('h1'));
      // Returns the original uid on the coordinator's very first read, then
      // a different uid on every subsequent read — simulating the active
      // account changing (e.g. sign-out) after the sync has already
      // captured its starting identity and loaded the local snapshot.
      final changingProvider = _MidSyncChangingSessionProvider(uid);
      final c = SyncCoordinator(
        sessionProvider: changingProvider,
        habitCloudRepository: habitRepo,
        suggestionCloudRepository: suggestionRepo,
        settingsCloudRepository: settingsRepo,
        habitStorage: habitStorage,
        suggestionStorage: suggestionStorage,
        settingsStorage: settingsStorage,
        syncMetadataStorage: syncMetadataStorage,
        recoverySnapshotStorage: recoverySnapshotStorage,
        clock: clock,
      );
      final result = await c.sync();

      expect(result.failure!.code, SyncFailureCode.identityChanged);
      expect(habitRepo.rows, isEmpty);
      final metadata = await syncMetadataStorage.load();
      expect(metadata.dirtyHabitIds, contains('h1'));
    });
  });

  group('Merge engine — habits', () {
    test('local-only dirty habit uploads', () async {
      await habitStorage.upsertHabit(habit('h1'));
      final result = await coordinator().sync();

      expect(result.isSuccess, isTrue);
      expect(result.summary.habitsUploaded, 1);
      expect(habitRepo.rows.containsKey('h1'), isTrue);
      final metadata = await syncMetadataStorage.load();
      expect(metadata.dirtyHabitIds, isEmpty);
    });

    test('remote-only habit downloads and is not marked dirty', () async {
      putRemoteHabit(habit('remote-1', updatedAt: DateTime.utc(2026, 2, 1)));
      final result = await coordinator().sync();

      expect(result.isSuccess, isTrue);
      expect(result.summary.habitsDownloaded, 1);
      final local = await habitStorage.loadHabits();
      expect(local!.single.id, 'remote-1');
      final metadata = await syncMetadataStorage.load();
      expect(metadata.dirtyHabitIds, isNot(contains('remote-1')));
    });

    test('local newer wins over remote', () async {
      putRemoteHabit(habit('h1', updatedAt: DateTime.utc(2026, 1, 1)));
      await habitStorage.saveHabits([
        habit('h1', updatedAt: DateTime.utc(2026, 2, 1)),
      ]);
      final result = await coordinator().sync();

      expect(habitRepo.rows['h1']!.habit.updatedAt, DateTime.utc(2026, 2, 1));
      expect(result.summary.conflictsResolvedLocal, 1);
    });

    test('remote newer wins over local', () async {
      putRemoteHabit(habit('h1', updatedAt: DateTime.utc(2026, 3, 5)));
      await habitStorage.saveHabits([
        habit('h1', updatedAt: DateTime.utc(2026, 1, 1)),
      ]);
      final result = await coordinator().sync();

      final local = await habitStorage.loadHabits();
      expect(local!.single.updatedAt, DateTime.utc(2026, 3, 5));
      expect(result.summary.conflictsResolvedRemote, 1);
    });

    test('equal timestamp, identical payload: unchanged', () async {
      final h = habit('h1', updatedAt: DateTime.utc(2026, 1, 1));
      putRemoteHabit(h);
      await habitStorage.saveHabits([h]);
      final result = await coordinator().sync();

      expect(result.summary.habitsUnchanged, 1);
      expect(result.summary.habitsUploaded, 0);
      expect(result.summary.habitsDownloaded, 0);
    });

    test('exact-tie tombstone wins over non-tombstone', () async {
      final tie = DateTime.utc(2026, 1, 1);
      putRemoteHabit(habit('h1', updatedAt: tie, deletedAt: tie));
      await habitStorage.saveHabits([habit('h1', updatedAt: tie)]);
      final result = await coordinator().sync();

      final local = await habitStorage.loadHabitsRaw();
      expect(local!.single.deletedAt, tie);
      expect(result.summary.conflictsResolvedRemote, 1);
    });
  });

  group('Preferences', () {
    test('local dirty settings upload', () async {
      await settingsStorage.updateSettings(AppSettings(displayName: 'Jamie'));
      final result = await coordinator().sync();

      expect(result.summary.preferencesUploaded, 1);
      expect(settingsRepo.row!.settings.displayName, 'Jamie');
      final metadata = await syncMetadataStorage.load();
      expect(metadata.preferencesDirty, isFalse);
    });

    test('remote newer settings download and are not marked dirty', () async {
      settingsRepo.row = CloudSettingsRecord.fromSettings(
        userId: uid,
        settings: AppSettings(
          displayName: 'Remote',
          updatedAt: DateTime.utc(2026, 5, 1),
        ),
      );
      final result = await coordinator().sync();

      expect(result.summary.preferencesDownloaded, 1);
      final local = await settingsStorage.loadSettings();
      expect(local.displayName, 'Remote');
      final metadata = await syncMetadataStorage.load();
      expect(metadata.preferencesDirty, isFalse);
    });
  });

  group('Dirty acknowledgement', () {
    test('local mutation during sync keeps the id dirty', () async {
      await habitStorage.upsertHabit(habit('h1'));
      // Simulate a user edit racing with the in-flight upload: the fake
      // repository "mutates" local storage the moment the push arrives,
      // exactly like a real concurrent edit landing mid-network-call.
      habitRepo.upsertFailure = null;
      final originalUpsertMany = habitRepo.upsertMany;
      var mutated = false;
      Future<CloudResult<void>> interceptingUpsertMany(
        List<CloudHabitRecord> records,
      ) async {
        if (!mutated) {
          mutated = true;
          clock.value = clock.value.add(const Duration(minutes: 1));
          await habitStorage.upsertHabit(habit('h1'));
        }
        return originalUpsertMany(records);
      }

      final c = SyncCoordinator(
        sessionProvider: sessionProvider,
        habitCloudRepository: _InterceptingHabitRepo(
          habitRepo,
          interceptingUpsertMany,
        ),
        suggestionCloudRepository: suggestionRepo,
        settingsCloudRepository: settingsRepo,
        habitStorage: habitStorage,
        suggestionStorage: suggestionStorage,
        settingsStorage: settingsStorage,
        syncMetadataStorage: syncMetadataStorage,
        recoverySnapshotStorage: recoverySnapshotStorage,
        clock: clock,
      );
      await c.sync();

      final metadata = await syncMetadataStorage.load();
      expect(metadata.dirtyHabitIds, contains('h1'));
    });

    test('failed upload keeps the id dirty', () async {
      await habitStorage.upsertHabit(habit('h1'));
      habitRepo.upsertFailure = const CloudFailure(
        CloudErrorCode.unavailable,
        'down',
      );
      final result = await coordinator().sync();

      expect(result.isSuccess, isFalse);
      final metadata = await syncMetadataStorage.load();
      expect(metadata.dirtyHabitIds, contains('h1'));
    });

    test('partial success clears only the acknowledged entity type', () async {
      await habitStorage.upsertHabit(habit('h1'));
      await suggestionStorage.upsertSuggestion(
        AdaptiveHabitSuggestion(
          id: 's1',
          habitId: 'h1',
          type: AdaptiveSuggestionType.reviewSchedule,
          createdAt: clock.now(),
          analysisStart: clock.now(),
          analysisEnd: clock.now(),
          evidenceCode: 'x',
        ),
      );
      suggestionRepo.upsertFailure = const CloudFailure(
        CloudErrorCode.unavailable,
        'down',
      );
      final result = await coordinator().sync();

      expect(result.isSuccess, isFalse);
      final metadata = await syncMetadataStorage.load();
      expect(metadata.dirtyHabitIds, isEmpty);
      expect(metadata.dirtySuggestionIds, contains('s1'));
    });

    test('retry after a failure is idempotent', () async {
      await habitStorage.upsertHabit(habit('h1'));
      habitRepo.upsertFailure = const CloudFailure(
        CloudErrorCode.unavailable,
        'down',
      );
      await coordinator().sync();
      habitRepo.upsertFailure = null;
      final result = await coordinator().sync();

      expect(result.isSuccess, isTrue);
      expect(habitRepo.rows.length, 1);
    });
  });

  group('Recovery snapshot', () {
    test(
      'snapshot is created before a remote-wins local replacement',
      () async {
        putRemoteHabit(habit('h1', updatedAt: DateTime.utc(2026, 6, 1)));
        await habitStorage.saveHabits([
          habit('h1', updatedAt: DateTime.utc(2026, 1, 1)),
        ]);
        await coordinator().sync();

        final snapshot = await recoverySnapshotStorage.read();
        expect(snapshot, isNotNull);
        expect(snapshot!.reason, 'beforeSyncMerge');
      },
    );

    test('no local replacement needed: no snapshot is created', () async {
      await habitStorage.upsertHabit(habit('h1'));
      await coordinator().sync();

      final snapshot = await recoverySnapshotStorage.read();
      expect(snapshot, isNull);
    });
  });

  group('UseLocalDeviceData', () {
    test(
      'local rows uploaded and remote-only rows are tombstoned, not left in place',
      () async {
        await habitStorage.upsertHabit(habit('local-1'));
        putRemoteHabit(
          habit('remote-only', updatedAt: DateTime.utc(2026, 1, 1)),
        );
        final result = await coordinator().sync(
          mode: SyncMode.useLocalDeviceData,
        );

        expect(result.isSuccess, isTrue);
        expect(habitRepo.rows['local-1'], isNotNull);
        expect(habitRepo.rows['remote-only']!.habit.deletedAt, isNotNull);
        final localTombstone = await habitStorage.loadHabitsRaw();
        final tombstoned = localTombstone!.firstWhere(
          (h) => h.id == 'remote-only',
        );
        expect(tombstoned.deletedAt, isNotNull);
      },
    );

    test(
      'a subsequent merge does not resurrect the tombstoned remote-only row',
      () async {
        await habitStorage.upsertHabit(habit('local-1'));
        putRemoteHabit(
          habit('remote-only', updatedAt: DateTime.utc(2026, 1, 1)),
        );
        await coordinator().sync(mode: SyncMode.useLocalDeviceData);

        final second = await coordinator().sync();

        expect(second.isSuccess, isTrue);
        final local = await habitStorage.loadHabits();
        expect(local!.where((h) => h.id == 'remote-only'), isEmpty);
        expect(habitRepo.rows['remote-only']!.habit.deletedAt, isNotNull);
      },
    );

    test('preferences are uploaded as authoritative', () async {
      await settingsStorage.updateSettings(AppSettings(displayName: 'Local'));
      settingsRepo.row = CloudSettingsRecord.fromSettings(
        userId: uid,
        settings: AppSettings(
          displayName: 'Cloud',
          updatedAt: DateTime.utc(2026, 6, 1),
        ),
      );
      await coordinator().sync(mode: SyncMode.useLocalDeviceData);

      expect(settingsRepo.row!.settings.displayName, 'Local');
    });
  });

  group('Concurrency', () {
    test('duplicate sync requests do not overlap', () async {
      await habitStorage.upsertHabit(habit('h1'));
      final c = coordinator();
      final first = c.sync();
      final second = c.sync();

      expect(identical(first, second), isTrue);
      await first;
    });

    test('a failed sync does not poison the next attempt', () async {
      await habitStorage.upsertHabit(habit('h1'));
      habitRepo.upsertFailure = const CloudFailure(
        CloudErrorCode.unavailable,
        'down',
      );
      final c = coordinator();
      await c.sync();
      expect(c.isSyncing, isFalse);

      habitRepo.upsertFailure = null;
      final result = await c.sync();
      expect(result.isSuccess, isTrue);
    });
  });
}

/// Wraps a [_FakeHabitCloudRepository] so a test can inject side effects
/// exactly at the moment `upsertMany` is called, simulating a concurrent
/// local mutation racing with the in-flight network call.
class _InterceptingHabitRepo implements HabitCloudRepository {
  final _FakeHabitCloudRepository delegate;
  final Future<CloudResult<void>> Function(List<CloudHabitRecord>) onUpsertMany;

  _InterceptingHabitRepo(this.delegate, this.onUpsertMany);

  @override
  Future<CloudResult<List<CloudHabitRecord>>> fetchAll() => delegate.fetchAll();

  @override
  Future<CloudResult<List<CloudHabitRecord>>> fetchUpdatedSince(
    DateTime updatedSince,
  ) => delegate.fetchUpdatedSince(updatedSince);

  @override
  Future<CloudResult<void>> upsert(CloudHabitRecord record) =>
      upsertMany([record]);

  @override
  Future<CloudResult<void>> upsertMany(List<CloudHabitRecord> records) =>
      onUpsertMany(records);

  @override
  Future<CloudResult<void>> hardDelete(String id) => delegate.hardDelete(id);
}
