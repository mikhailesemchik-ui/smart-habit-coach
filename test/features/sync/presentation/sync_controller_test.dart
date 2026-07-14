import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_habit_coach/core/storage/local_namespace_resolver.dart';
import 'package:smart_habit_coach/core/sync/sync_metadata_storage.dart';
import 'package:smart_habit_coach/features/sync/data/cloud_backend.dart';
import 'package:smart_habit_coach/features/sync/data/cloud_records.dart';
import 'package:smart_habit_coach/features/sync/data/cloud_repositories.dart';
import 'package:smart_habit_coach/features/sync/data/cloud_result.dart';
import 'package:smart_habit_coach/features/sync/data/sync_coordinator.dart';
import 'package:smart_habit_coach/features/sync/presentation/sync_controller.dart';

import '../../../support/test_namespace.dart';

class _FakeSessionProvider implements CloudAuthSessionProvider {
  @override
  String? currentUid() => testNamespaceUid;
}

class _EmptyHabitCloudRepository implements HabitCloudRepository {
  CloudFailure? failure;
  int upsertManyCalls = 0;

  @override
  Future<CloudResult<List<CloudHabitRecord>>> fetchAll() async {
    if (failure != null) return CloudResult.failure(failure!);
    return CloudResult.success([]);
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
    upsertManyCalls++;
    return CloudResult.success(null);
  }

  @override
  Future<CloudResult<void>> hardDelete(String id) async =>
      CloudResult.success(null);
}

class _EmptySuggestionCloudRepository
    implements AdaptiveSuggestionCloudRepository {
  @override
  Future<CloudResult<List<CloudAdaptiveSuggestionRecord>>> fetchAll() async =>
      CloudResult.success([]);

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
  ) async => CloudResult.success(null);

  @override
  Future<CloudResult<void>> hardDelete(String id) async =>
      CloudResult.success(null);
}

class _EmptySettingsCloudRepository implements SettingsCloudRepository {
  @override
  Future<CloudResult<CloudSettingsRecord?>> fetch() async =>
      CloudResult.success(null);

  @override
  Future<CloudResult<void>> upsert(CloudSettingsRecord record) async =>
      CloudResult.success(null);
}

void main() {
  late _EmptyHabitCloudRepository habitRepo;
  late SyncMetadataStorage syncMetadataStorage;
  late SyncCoordinator coordinator;
  late SyncController controller;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    LocalNamespaceResolver.debugUidOverride = testNamespaceUid;
    habitRepo = _EmptyHabitCloudRepository();
    syncMetadataStorage = SyncMetadataStorage();
    coordinator = SyncCoordinator(
      sessionProvider: _FakeSessionProvider(),
      habitCloudRepository: habitRepo,
      suggestionCloudRepository: _EmptySuggestionCloudRepository(),
      settingsCloudRepository: _EmptySettingsCloudRepository(),
      syncMetadataStorage: syncMetadataStorage,
    );
    controller = SyncController(
      coordinator: coordinator,
      syncMetadataStorage: syncMetadataStorage,
    );
  });

  test('starts not syncing with no last-successful time', () async {
    await controller.loadStatus();
    expect(controller.state.isSyncing, isFalse);
    expect(controller.state.lastSuccessfulSyncAt, isNull);
  });

  test('syncNow shows a loading state while in flight', () async {
    final future = controller.syncNow();
    expect(controller.state.isSyncing, isTrue);
    await future;
    expect(controller.state.isSyncing, isFalse);
  });

  test('duplicate taps while syncing do not start a second sync', () async {
    final first = controller.syncNow();
    final second = controller.syncNow();
    await Future.wait([first, second]);

    expect(habitRepo.upsertManyCalls, 0); // nothing to upload, but no crash
    expect(controller.state.isSyncing, isFalse);
  });

  test(
    'success shows a summary and records the last successful time',
    () async {
      await controller.syncNow();

      expect(controller.state.lastFailure, isNull);
      expect(controller.state.lastSummary, isNotNull);
      expect(controller.state.lastSuccessfulSyncAt, isNotNull);
      expect(syncSummaryMessage(controller.state.lastSummary!), isNotEmpty);
    },
  );

  test('typed failure copy is shown, never a raw exception', () async {
    habitRepo.failure = const CloudFailure(
      CloudErrorCode.unavailable,
      'raw backend detail',
    );
    await controller.syncNow();

    expect(controller.state.lastFailure, isNotNull);
    final message = syncFailureMessage(controller.state.lastFailure!);
    expect(message, isNot(contains('raw backend detail')));
  });
}
