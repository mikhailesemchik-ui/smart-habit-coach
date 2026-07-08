import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_habit_coach/core/storage/local_namespace_resolver.dart';
import 'package:smart_habit_coach/features/profile/data/settings_storage.dart';
import 'package:smart_habit_coach/features/profile/domain/app_settings.dart';

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
      const settings = AppSettings(
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
      const settings = AppSettings(displayName: 'Jamie');

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
      await storage.saveSettings(const AppSettings(displayName: 'A'));

      LocalNamespaceResolver.debugUidOverride = 'uid-b';
      await storage.saveSettings(const AppSettings(displayName: 'B'));
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
}
