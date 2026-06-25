import 'package:flutter/material.dart';

enum StartOfWeek { monday, sunday }

class AppSettings {
  final String displayName;
  final ThemeMode themeMode;
  final StartOfWeek startOfWeek;

  const AppSettings({
    this.displayName = 'User',
    this.themeMode = ThemeMode.system,
    this.startOfWeek = StartOfWeek.monday,
  });

  static const defaults = AppSettings();

  AppSettings copyWith({
    String? displayName,
    ThemeMode? themeMode,
    StartOfWeek? startOfWeek,
  }) {
    return AppSettings(
      displayName: displayName ?? this.displayName,
      themeMode: themeMode ?? this.themeMode,
      startOfWeek: startOfWeek ?? this.startOfWeek,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'displayName': displayName,
      'themeMode': themeMode.name,
      'startOfWeek': startOfWeek.name,
    };
  }

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      displayName: _readDisplayName(json),
      themeMode: _readThemeMode(json),
      startOfWeek: _readStartOfWeek(json),
    );
  }

  static String _readDisplayName(Map<String, dynamic> json) {
    final value = json['displayName'];
    if (value is String && value.trim().isNotEmpty) return value;
    return defaults.displayName;
  }

  static ThemeMode _readThemeMode(Map<String, dynamic> json) {
    final value = json['themeMode'];
    if (value is String) {
      for (final mode in ThemeMode.values) {
        if (mode.name == value) return mode;
      }
    }
    return defaults.themeMode;
  }

  static StartOfWeek _readStartOfWeek(Map<String, dynamic> json) {
    final value = json['startOfWeek'];
    if (value is String) {
      for (final day in StartOfWeek.values) {
        if (day.name == value) return day;
      }
    }
    return defaults.startOfWeek;
  }
}
