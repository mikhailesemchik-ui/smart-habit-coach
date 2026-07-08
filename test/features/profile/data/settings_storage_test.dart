import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_habit_coach/core/storage/local_namespace_resolver.dart';
import 'package:smart_habit_coach/core/sync/sync_metadata_storage.dart';
import 'package:smart_habit_coach/features/profile/data/settings_storage.dart';
import 'package:smart_habit_coach/features/profile/domain/app_settings.dart';

import '../../../support/fake_clock.dart';
import '../../../support/test_namespace.dart';

const _settingsKey = 'app_settings:$testNamespaceUid';

void main() {
  group('SettingsStorage', () {
    test('loadSettings returns defaults when nothing has been saved', () async {
      SharedPreferences.setMockInitialValues({});

      final settings = await SettingsStorage().loadSettings();

      expect(settings.displayName, AppSettings.defaults.displayName);
      expect(settings.themeMode, AppSettings.defaults.themeMode);
      expect(settings.startOfWeek, AppSettings.defaults.startOfWeek);
    });

    test('saveSettings then loadSettings returns the same settings', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = SettingsStorage();
      final settings = AppSettings(
        displayName: 'Jamie',
        themeMode: ThemeMode.dark,
        startOfWeek: StartOfWeek.sunday,
      );

      await storage.saveSettings(settings);
      final loaded = await storage.loadSettings();

      expect(loaded.displayName, 'Jamie');
      expect(loaded.themeMode, ThemeMode.dark);
      expect(loaded.startOfWeek, StartOfWeek.sunday);
    });

    test('loadSettings returns defaults for corrupted saved data', () async {
      SharedPreferences.setMockInitialValues({_settingsKey: 'not valid json'});

      final settings = await SettingsStorage().loadSettings();

      expect(settings.displayName, AppSettings.defaults.displayName);
      expect(settings.themeMode, AppSettings.defaults.themeMode);
      expect(settings.startOfWeek, AppSettings.defaults.startOfWeek);
    });

    test(
      'loadSettings returns defaults when saved data is not a map',
      () async {
        SharedPreferences.setMockInitialValues({_settingsKey: '[1, 2, 3]'});

        final settings = await SettingsStorage().loadSettings();

        expect(settings.displayName, AppSettings.defaults.displayName);
      },
    );
  });

  group('SettingsStorage namespacing', () {
    tearDown(() {
      LocalNamespaceResolver.debugUidOverride = testNamespaceUid;
    });

    test('saves and loads under a namespaced key when a UID is set', () async {
      SharedPreferences.setMockInitialValues({});
      LocalNamespaceResolver.debugUidOverride = 'uid-a';
      final storage = SettingsStorage();
      final settings = AppSettings(displayName: 'Jamie');

      await storage.saveSettings(settings);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('app_settings:uid-a'), isTrue);
      expect(prefs.containsKey('app_settings'), isFalse);

      final loaded = await storage.loadSettings();
      expect(loaded.displayName, 'Jamie');
    });

    test('two different UIDs read/write fully isolated settings', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = SettingsStorage();

      LocalNamespaceResolver.debugUidOverride = 'uid-a';
      await storage.saveSettings(AppSettings(displayName: 'A'));

      LocalNamespaceResolver.debugUidOverride = 'uid-b';
      await storage.saveSettings(AppSettings(displayName: 'B'));
      final bLoaded = await storage.loadSettings();

      LocalNamespaceResolver.debugUidOverride = 'uid-a';
      final aLoaded = await storage.loadSettings();

      expect(aLoaded.displayName, 'A');
      expect(bLoaded.displayName, 'B');
    });

    test('loadSettings returns defaults when no UID is available', () async {
      SharedPreferences.setMockInitialValues({});
      LocalNamespaceResolver.debugUidOverride = null;

      final settings = await SettingsStorage().loadSettings();

      expect(settings.displayName, AppSettings.defaults.displayName);
    });

    test('saveSettings throws when no UID is available', () async {
      SharedPreferences.setMockInitialValues({});
      LocalNamespaceResolver.debugUidOverride = null;

      expect(
        () => SettingsStorage().saveSettings(AppSettings.defaults),
        throwsStateError,
      );
    });
  });

  group('SettingsStorage.updateSettings (Phase 1B centralized mutation)', () {
    tearDown(() {
      LocalNamespaceResolver.debugUidOverride = testNamespaceUid;
    });

    test(
      'a normal setting change stamps updatedAt via the injected Clock',
      () async {
        SharedPreferences.setMockInitialValues({});
        final clock = FakeClock(DateTime.utc(2026, 6, 1));
        final storage = SettingsStorage(clock: clock);

        final stamped = await storage.updateSettings(
          AppSettings(displayName: 'Jamie'),
        );

        expect(stamped.updatedAt, DateTime.utc(2026, 6, 1));
        final loaded = await storage.loadSettings();
        expect(loaded.displayName, 'Jamie');
        expect(loaded.updatedAt, DateTime.utc(2026, 6, 1));
      },
    );

    test('previous value is retained when only updatedAt changes', () async {
      SharedPreferences.setMockInitialValues({});
      final clock = FakeClock(DateTime.utc(2026, 6, 1));
      final storage = SettingsStorage(clock: clock);
      await storage.updateSettings(
        AppSettings(displayName: 'Jamie', themeMode: ThemeMode.dark),
      );

      clock.value = DateTime.utc(2026, 6, 15);
      final current = await storage.loadSettings();
      final updated = await storage.updateSettings(
        current.copyWith(themeMode: ThemeMode.light),
      );

      expect(updated.displayName, 'Jamie');
      expect(updated.themeMode, ThemeMode.light);
      expect(updated.updatedAt, DateTime.utc(2026, 6, 15));
    });

    test(
      'raw load of old settings without updatedAt remains compatible',
      () async {
        SharedPreferences.setMockInitialValues({
          _settingsKey:
              '{"displayName": "Jamie", "themeMode": "system", "startOfWeek": "monday"}',
        });

        final settings = await SettingsStorage().loadSettings();

        expect(settings.displayName, 'Jamie');
        expect(settings.updatedAt, DateTime.utc(2000, 1, 1));
      },
    );

    test('updateSettings throws when no UID is available', () async {
      SharedPreferences.setMockInitialValues({});
      LocalNamespaceResolver.debugUidOverride = null;

      // Dirty-first ordering means the "no UID" check now runs behind
      // SyncMetadataStorage's own write queue (a later microtask), not
      // synchronously — the override must not be reset until this
      // expectation has actually settled.
      await expectLater(
        SettingsStorage().updateSettings(AppSettings.defaults),
        throwsStateError,
      );
    });

    test(
      'updateSettings keeps namespaced isolation between two UIDs',
      () async {
        SharedPreferences.setMockInitialValues({});
        final storage = SettingsStorage(
          clock: FakeClock(DateTime.utc(2026, 1, 1)),
        );

        LocalNamespaceResolver.debugUidOverride = 'uid-a';
        await storage.updateSettings(AppSettings(displayName: 'A'));

        LocalNamespaceResolver.debugUidOverride = 'uid-b';
        await storage.updateSettings(AppSettings(displayName: 'B'));
        final bLoaded = await storage.loadSettings();

        LocalNamespaceResolver.debugUidOverride = 'uid-a';
        final aLoaded = await storage.loadSettings();

        expect(aLoaded.displayName, 'A');
        expect(bLoaded.displayName, 'B');
        LocalNamespaceResolver.debugUidOverride = testNamespaceUid;
      },
    );
  });

  group('SettingsStorage dirty tracking (Phase 1C)', () {
    test('updateSettings marks preferencesDirty', () async {
      SharedPreferences.setMockInitialValues({});
      final syncMetadataStorage = SyncMetadataStorage();
      final storage = SettingsStorage(syncMetadataStorage: syncMetadataStorage);

      await storage.updateSettings(AppSettings(displayName: 'Jamie'));

      final metadata = await syncMetadataStorage.load();
      expect(metadata.preferencesDirty, isTrue);
    });

    test('raw saveSettings does not mark preferencesDirty', () async {
      SharedPreferences.setMockInitialValues({});
      final syncMetadataStorage = SyncMetadataStorage();
      final storage = SettingsStorage(syncMetadataStorage: syncMetadataStorage);

      await storage.saveSettings(AppSettings(displayName: 'Jamie'));

      final metadata = await syncMetadataStorage.load();
      expect(metadata.preferencesDirty, isFalse);
    });
  });
}
