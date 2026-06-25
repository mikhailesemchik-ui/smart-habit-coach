import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_habit_coach/features/profile/domain/app_settings.dart';

void main() {
  group('AppSettings.fromJson defaults', () {
    test('uses all defaults when json is empty', () {
      final settings = AppSettings.fromJson({});

      expect(settings.displayName, 'User');
      expect(settings.themeMode, ThemeMode.system);
      expect(settings.startOfWeek, StartOfWeek.monday);
    });

    test('falls back to default display name when blank or missing type', () {
      expect(AppSettings.fromJson({'displayName': '   '}).displayName, 'User');
      expect(AppSettings.fromJson({'displayName': 7}).displayName, 'User');
    });

    test('falls back to default theme mode for unknown or missing value', () {
      expect(
        AppSettings.fromJson({'themeMode': 'not_a_mode'}).themeMode,
        ThemeMode.system,
      );
      expect(AppSettings.fromJson({}).themeMode, ThemeMode.system);
    });

    test(
      'falls back to default start of week for unknown or missing value',
      () {
        expect(
          AppSettings.fromJson({'startOfWeek': 'tuesday'}).startOfWeek,
          StartOfWeek.monday,
        );
        expect(AppSettings.fromJson({}).startOfWeek, StartOfWeek.monday);
      },
    );
  });

  test('toJson/fromJson round trip preserves all fields', () {
    const settings = AppSettings(
      displayName: 'Alex',
      themeMode: ThemeMode.dark,
      startOfWeek: StartOfWeek.sunday,
    );

    final restored = AppSettings.fromJson(settings.toJson());

    expect(restored.displayName, settings.displayName);
    expect(restored.themeMode, settings.themeMode);
    expect(restored.startOfWeek, settings.startOfWeek);
  });

  test('copyWith only changes the given fields', () {
    const settings = AppSettings(displayName: 'Alex');

    final updated = settings.copyWith(themeMode: ThemeMode.light);

    expect(updated.displayName, 'Alex');
    expect(updated.themeMode, ThemeMode.light);
    expect(updated.startOfWeek, StartOfWeek.monday);
  });
}
