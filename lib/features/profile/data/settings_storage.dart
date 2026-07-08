import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/storage/local_namespace_resolver.dart';
import '../domain/app_settings.dart';

class SettingsStorage {
  static const _settingsBaseKey = 'app_settings';

  final LocalNamespaceResolver _namespaceResolver;

  SettingsStorage({LocalNamespaceResolver? namespaceResolver})
    : _namespaceResolver = namespaceResolver ?? const LocalNamespaceResolver();

  /// Returns [AppSettings.defaults] both when there is no saved data and
  /// when no local namespace is currently available — consistent with this
  /// method's existing "nothing saved yet" contract.
  Future<AppSettings> loadSettings() async {
    final result = _namespaceResolver.resolveKey(_settingsBaseKey);
    if (!result.isAvailable) return AppSettings.defaults;

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(result.key!);
    if (raw == null) return AppSettings.defaults;

    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return AppSettings.fromJson(decoded);
    } catch (_) {
      return AppSettings.defaults;
    }
  }

  /// Persists [settings]. Throws a [StateError] if no local namespace is
  /// currently available — the same policy as [HabitStorage.saveHabits]
  /// and [AdaptiveSuggestionStorage.saveSuggestions], so no user-owned
  /// write is ever silently dropped. The startup identity gate ensures
  /// normal app UI (and therefore this call) is never reached before a
  /// real UID exists.
  Future<void> saveSettings(AppSettings settings) async {
    final result = _namespaceResolver.resolveKey(_settingsBaseKey);
    if (!result.isAvailable) {
      throw StateError(
        'SettingsStorage.saveSettings: no local namespace available',
      );
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(result.key!, jsonEncode(settings.toJson()));
  }
}
