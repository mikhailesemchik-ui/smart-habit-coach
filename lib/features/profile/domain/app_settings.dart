import 'package:flutter/material.dart';

enum StartOfWeek { monday, sunday }

class AppSettings {
  final String displayName;
  final ThemeMode themeMode;
  final StartOfWeek startOfWeek;

  /// When these settings were last modified. Defaults to [_legacyTimestamp]
  /// for settings that predate this field (Phase 1B) — a fixed, documented
  /// sentinel rather than [DateTime.now], so repeated loads of the same
  /// legacy settings never produce a changing value. Centralized stamping
  /// happens in `SettingsStorage.updateSettings`, not here.
  final DateTime updatedAt;

  /// Deterministic fallback for [updatedAt] on settings that predate this
  /// field. `DateTime` has no const constructor in Dart, so this cannot be
  /// a compile-time constant; `static final` still gives a single,
  /// process-lifetime-stable instance. This is also why [AppSettings]'s
  /// constructor is no longer `const`.
  static final DateTime _legacyTimestamp = DateTime.utc(2000, 1, 1);

  AppSettings({
    this.displayName = 'User',
    this.themeMode = ThemeMode.system,
    this.startOfWeek = StartOfWeek.monday,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? _legacyTimestamp;

  static final defaults = AppSettings();

  AppSettings copyWith({
    String? displayName,
    ThemeMode? themeMode,
    StartOfWeek? startOfWeek,
    DateTime? updatedAt,
  }) {
    return AppSettings(
      displayName: displayName ?? this.displayName,
      themeMode: themeMode ?? this.themeMode,
      startOfWeek: startOfWeek ?? this.startOfWeek,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'displayName': displayName,
      'themeMode': themeMode.name,
      'startOfWeek': startOfWeek.name,
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      displayName: _readDisplayName(json),
      themeMode: _readThemeMode(json),
      startOfWeek: _readStartOfWeek(json),
      updatedAt: _readUpdatedAt(json),
    );
  }

  static DateTime _readUpdatedAt(Map<String, dynamic> json) {
    final raw = json['updatedAt'];
    if (raw is! String) return _legacyTimestamp;
    return DateTime.tryParse(raw) ?? _legacyTimestamp;
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
