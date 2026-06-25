import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_habit_coach/features/profile/data/settings_storage.dart';
import 'package:smart_habit_coach/features/profile/domain/app_settings.dart';

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
      SharedPreferences.setMockInitialValues({
        'app_settings': 'not valid json',
      });

      final settings = await SettingsStorage().loadSettings();

      expect(settings.displayName, AppSettings.defaults.displayName);
      expect(settings.themeMode, AppSettings.defaults.themeMode);
      expect(settings.startOfWeek, AppSettings.defaults.startOfWeek);
    });

    test(
      'loadSettings returns defaults when saved data is not a map',
      () async {
        SharedPreferences.setMockInitialValues({'app_settings': '[1, 2, 3]'});

        final settings = await SettingsStorage().loadSettings();

        expect(settings.displayName, AppSettings.defaults.displayName);
      },
    );
  });
}
