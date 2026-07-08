import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_habit_coach/core/storage/local_namespace_resolver.dart';
import 'package:smart_habit_coach/core/sync/recovery_snapshot_storage.dart';
import 'package:smart_habit_coach/core/sync/sync_metadata_storage.dart';
import 'package:smart_habit_coach/features/auth/domain/meaningful_local_data.dart';
import 'package:smart_habit_coach/features/coach/data/adaptive_suggestion_storage.dart';
import 'package:smart_habit_coach/features/coach/domain/adaptive_suggestion.dart';
import 'package:smart_habit_coach/features/home/data/habit_storage.dart';
import 'package:smart_habit_coach/features/home/domain/habit.dart';
import 'package:smart_habit_coach/features/profile/data/settings_storage.dart';
import 'package:smart_habit_coach/features/profile/domain/app_settings.dart';

import '../../../support/test_namespace.dart';

Future<bool> _check({
  HabitStorage? habitStorage,
  AdaptiveSuggestionStorage? suggestionStorage,
  SettingsStorage? settingsStorage,
  SyncMetadataStorage? syncMetadataStorage,
  RecoverySnapshotStorage? recoverySnapshotStorage,
}) {
  return hasMeaningfulLocalData(
    habitStorage: habitStorage ?? HabitStorage(),
    suggestionStorage: suggestionStorage ?? AdaptiveSuggestionStorage(),
    settingsStorage: settingsStorage ?? SettingsStorage(),
    syncMetadataStorage: syncMetadataStorage ?? SyncMetadataStorage(),
    recoverySnapshotStorage:
        recoverySnapshotStorage ?? RecoverySnapshotStorage(),
  );
}

AdaptiveHabitSuggestion _suggestion({String id = 's1'}) {
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
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() {
    LocalNamespaceResolver.debugUidOverride = testNamespaceUid;
  });

  test('an empty namespace is not meaningful', () async {
    expect(await _check(), isFalse);
  });

  test('a namespace with at least one habit is meaningful', () async {
    final habitStorage = HabitStorage();
    await habitStorage.upsertHabit(
      Habit(
        id: '1',
        title: 'Drink water',
        scheduledTime: '08:00 AM',
        icon: Icons.local_drink_outlined,
      ),
    );

    expect(await _check(habitStorage: habitStorage), isTrue);
  });

  test('persisted sample habits are meaningful', () async {
    final habitStorage = HabitStorage();
    await habitStorage.upsertHabit(
      Habit(
        id: 'sample-water',
        title: 'Drink water',
        scheduledTime: '08:00 AM',
        icon: Icons.local_drink_outlined,
      ),
    );

    expect(await _check(habitStorage: habitStorage), isTrue);
  });

  test(
    'a namespace with only a tombstoned habit is still meaningful',
    () async {
      final habitStorage = HabitStorage();
      final habit = await habitStorage.upsertHabit(
        Habit(
          id: '1',
          title: 'Drink water',
          scheduledTime: '08:00 AM',
          icon: Icons.local_drink_outlined,
        ),
      );
      await habitStorage.tombstoneHabit(habit);

      expect(await _check(habitStorage: habitStorage), isTrue);
    },
  );

  test('a namespace with an adaptive suggestion is meaningful', () async {
    final suggestionStorage = AdaptiveSuggestionStorage();
    await suggestionStorage.upsertSuggestion(_suggestion());

    expect(await _check(suggestionStorage: suggestionStorage), isTrue);
  });

  test('a namespace with only a tombstoned suggestion is meaningful', () async {
    final suggestionStorage = AdaptiveSuggestionStorage();
    await suggestionStorage.saveSuggestions([
      _suggestion().copyWith(deletedAt: DateTime.utc(2026, 1, 2)),
    ]);

    expect(await _check(suggestionStorage: suggestionStorage), isTrue);
  });

  test('non-default settings are meaningful', () async {
    final settingsStorage = SettingsStorage();
    await settingsStorage.updateSettings(AppSettings(displayName: 'Jamie'));

    expect(await _check(settingsStorage: settingsStorage), isTrue);
  });

  test('default-only settings are not meaningful', () async {
    final settingsStorage = SettingsStorage();
    await settingsStorage.saveSettings(AppSettings.defaults);

    expect(await _check(settingsStorage: settingsStorage), isFalse);
  });

  test('dirty habit metadata alone is meaningful', () async {
    final syncMetadataStorage = SyncMetadataStorage();
    await syncMetadataStorage.markHabitDirty('h1');

    expect(await _check(syncMetadataStorage: syncMetadataStorage), isTrue);
  });

  test('dirty suggestion metadata alone is meaningful', () async {
    final syncMetadataStorage = SyncMetadataStorage();
    await syncMetadataStorage.markSuggestionDirty('s1');

    expect(await _check(syncMetadataStorage: syncMetadataStorage), isTrue);
  });

  test('preferencesDirty alone is meaningful', () async {
    final syncMetadataStorage = SyncMetadataStorage();
    await syncMetadataStorage.markPreferencesDirty();

    expect(await _check(syncMetadataStorage: syncMetadataStorage), isTrue);
  });

  test('an existing recovery snapshot alone is meaningful', () async {
    final recoverySnapshotStorage = RecoverySnapshotStorage();
    await recoverySnapshotStorage.create(reason: 'test');

    expect(
      await _check(recoverySnapshotStorage: recoverySnapshotStorage),
      isTrue,
    );
  });

  test('meaningful-data checks are isolated by uid namespace', () async {
    final habitStorage = HabitStorage();

    LocalNamespaceResolver.debugUidOverride = 'uid-a';
    await habitStorage.upsertHabit(
      Habit(
        id: 'a-habit',
        title: 'Drink water',
        scheduledTime: '08:00 AM',
        icon: Icons.local_drink_outlined,
      ),
    );
    expect(await _check(habitStorage: habitStorage), isTrue);

    LocalNamespaceResolver.debugUidOverride = 'uid-b';
    expect(await _check(habitStorage: habitStorage), isFalse);

    LocalNamespaceResolver.debugUidOverride = 'uid-a';
    expect(await _check(habitStorage: habitStorage), isTrue);
  });
}
