import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_habit_coach/core/storage/local_namespace_resolver.dart';
import 'package:smart_habit_coach/core/sync/sync_metadata_storage.dart';
import 'package:smart_habit_coach/features/coach/data/adaptive_suggestion_storage.dart';
import 'package:smart_habit_coach/features/coach/domain/adaptive_suggestion.dart';
import 'package:smart_habit_coach/features/home/data/habit_storage.dart';
import 'package:smart_habit_coach/features/home/domain/habit.dart';
import 'package:smart_habit_coach/features/privacy/data/local_data_export_service.dart';
import 'package:smart_habit_coach/features/privacy/domain/export_result.dart';
import 'package:smart_habit_coach/features/profile/data/settings_storage.dart';
import 'package:smart_habit_coach/features/profile/domain/app_settings.dart';

import '../../../support/fake_clock.dart';
import '../../../support/test_namespace.dart';

Habit _habit({
  required String id,
  DateTime? deletedAt,
  DateTime? createdAt,
  DateTime? updatedAt,
}) => Habit(
  id: id,
  title: 'Habit $id',
  scheduledTime: '08:00 AM',
  icon: Icons.water_drop_outlined,
  createdAt: createdAt ?? DateTime.utc(2026, 1, 1),
  updatedAt: updatedAt ?? DateTime.utc(2026, 1, 1),
  deletedAt: deletedAt,
);

AdaptiveHabitSuggestion _suggestion({
  required String id,
  DateTime? deletedAt,
}) => AdaptiveHabitSuggestion(
  id: id,
  habitId: 'h1',
  type: AdaptiveSuggestionType.addMinimumVersion,
  status: AdaptiveSuggestionStatus.pending,
  createdAt: DateTime.utc(2026, 1, 1),
  analysisStart: DateTime.utc(2025, 12, 25),
  analysisEnd: DateTime.utc(2026, 1, 1),
  evidenceCode: 'low_completion',
  evidence: const {'missedCount': 3},
  deletedAt: deletedAt,
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    LocalNamespaceResolver.debugUidOverride = testNamespaceUid;
  });
  tearDown(() {
    LocalNamespaceResolver.debugUidOverride = testNamespaceUid;
  });

  test('no active UID returns a typed failure', () async {
    LocalNamespaceResolver.debugUidOverride = null;
    final service = LocalDataExportService();

    final result = await service.export();

    expect(result.isSuccess, isFalse);
    expect(result.failure!.code, ExportFailureCode.noActiveIdentity);
  });

  test('export includes the active UID', () async {
    final service = LocalDataExportService();

    final result = await service.export();

    expect(result.isSuccess, isTrue);
    expect(result.export!.activeUid, testNamespaceUid);
  });

  test('export includes habits, including tombstones', () async {
    final habitStorage = HabitStorage();
    await habitStorage.saveHabits([
      _habit(id: 'active-1'),
      _habit(id: 'deleted-1', deletedAt: DateTime.utc(2026, 1, 2)),
    ]);
    final service = LocalDataExportService(habitStorage: habitStorage);

    final result = await service.export();

    final ids = result.export!.habitsRaw.map((h) => h['id']).toSet();
    expect(ids, {'active-1', 'deleted-1'});
    final deleted = result.export!.habitsRaw.firstWhere(
      (h) => h['id'] == 'deleted-1',
    );
    expect(deleted['deletedAt'], isNotNull);
  });

  test('export includes suggestions, including tombstones', () async {
    final suggestionStorage = AdaptiveSuggestionStorage();
    await suggestionStorage.saveSuggestions([
      _suggestion(id: 's1'),
      _suggestion(id: 's2', deletedAt: DateTime.utc(2026, 1, 2)),
    ]);
    final service = LocalDataExportService(
      suggestionStorage: suggestionStorage,
    );

    final result = await service.export();

    final ids = result.export!.adaptiveSuggestionsRaw
        .map((s) => s['id'])
        .toSet();
    expect(ids, {'s1', 's2'});
  });

  test('export includes settings', () async {
    final settingsStorage = SettingsStorage();
    await settingsStorage.updateSettings(
      AppSettings.defaults.copyWith(displayName: 'Jamie'),
    );
    final service = LocalDataExportService(settingsStorage: settingsStorage);

    final result = await service.export();

    expect(result.export!.appSettings['displayName'], 'Jamie');
  });

  test('export includes sync metadata', () async {
    final syncMetadataStorage = SyncMetadataStorage();
    await syncMetadataStorage.markHabitDirty('h1');
    final service = LocalDataExportService(
      syncMetadataStorage: syncMetadataStorage,
    );

    final result = await service.export();

    expect(result.export!.syncMetadata['dirtyHabitIds'], contains('h1'));
  });

  test(
    'export includes the latest recovery snapshot when one exists',
    () async {
      final habitStorage = HabitStorage();
      await habitStorage.saveHabits([_habit(id: 'h1')]);
      // tombstoneHabit creates a recovery snapshot as a side effect.
      await habitStorage.tombstoneHabit(_habit(id: 'h1'));
      final service = LocalDataExportService(habitStorage: habitStorage);

      final result = await service.export();

      expect(result.export!.recoverySnapshot, isNotNull);
    },
  );

  test('export has no recovery snapshot when none was ever created', () async {
    final service = LocalDataExportService();

    final result = await service.export();

    expect(result.export!.recoverySnapshot, isNull);
  });

  test('generatedAt uses the injected Clock', () async {
    final fixed = DateTime.utc(2026, 3, 4, 5, 6);
    final service = LocalDataExportService(clock: FakeClock(fixed));

    final result = await service.export();

    expect(result.export!.generatedAt, fixed);
  });

  test('habits and suggestions are sorted by id in the JSON output', () async {
    final habitStorage = HabitStorage();
    await habitStorage.saveHabits([_habit(id: 'b'), _habit(id: 'a')]);
    final service = LocalDataExportService(habitStorage: habitStorage);

    final result = await service.export();

    final decoded = jsonDecode(result.jsonString!) as Map<String, dynamic>;
    final ids = (decoded['habits'] as List)
        .map((h) => (h as Map)['id'] as String)
        .toList();
    expect(ids, ['a', 'b']);
  });

  test(
    'running the export twice with unchanged data produces identical JSON',
    () async {
      final fixed = DateTime.utc(2026, 1, 1);
      final habitStorage = HabitStorage();
      await habitStorage.saveHabits([_habit(id: 'h1')]);
      final service = LocalDataExportService(
        habitStorage: habitStorage,
        clock: FakeClock(fixed),
      );

      final first = await service.export();
      final second = await service.export();

      expect(first.jsonString, second.jsonString);
    },
  );

  test('export JSON contains no auth/session/API secret fields', () async {
    final habitStorage = HabitStorage();
    await habitStorage.saveHabits([_habit(id: 'h1')]);
    final service = LocalDataExportService(habitStorage: habitStorage);

    final result = await service.export();
    final json = result.jsonString!;

    for (final forbidden in [
      'access_token',
      'refresh_token',
      'service_role',
      'SUPABASE_SERVICE_ROLE',
      'OPENAI_API_KEY',
      'apikey',
      'password',
    ]) {
      expect(json.toLowerCase(), isNot(contains(forbidden.toLowerCase())));
    }
  });

  test('export does not mutate dirty metadata', () async {
    final syncMetadataStorage = SyncMetadataStorage();
    final before = await syncMetadataStorage.load();
    final service = LocalDataExportService(
      syncMetadataStorage: syncMetadataStorage,
    );

    await service.export();

    final after = await syncMetadataStorage.load();
    expect(after.dirtyHabitIds, before.dirtyHabitIds);
    expect(after.preferencesDirty, before.preferencesDirty);
  });

  test('export does not write to local storage', () async {
    final habitStorage = HabitStorage();
    await habitStorage.saveHabits([_habit(id: 'h1')]);
    final before = await habitStorage.loadHabitsRaw();
    final service = LocalDataExportService(habitStorage: habitStorage);

    await service.export();

    final after = await habitStorage.loadHabitsRaw();
    expect(after!.map((h) => h.updatedAt), before!.map((h) => h.updatedAt));
  });
}
