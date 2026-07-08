import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/storage/local_namespace_resolver.dart';
import '../../../core/sync/sync_metadata_storage.dart';
import '../../../core/time/clock.dart';
import '../domain/app_settings.dart';

class SettingsStorage {
  static const _settingsBaseKey = 'app_settings';

  final LocalNamespaceResolver _namespaceResolver;
  final Clock _clock;
  final SyncMetadataStorage _syncMetadataStorage;

  SettingsStorage({
    LocalNamespaceResolver? namespaceResolver,
    Clock? clock,
    SyncMetadataStorage? syncMetadataStorage,
  }) : _namespaceResolver = namespaceResolver ?? const LocalNamespaceResolver(),
       _clock = clock ?? const SystemClock(),
       _syncMetadataStorage = syncMetadataStorage ?? SyncMetadataStorage();

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

  /// **Normal mutation path.** Used by every production settings change
  /// (theme, display name, start-of-week, ...). Stamps `updatedAt` with
  /// the injected [Clock] and persists through [saveSettings].
  ///
  /// **Dirty-first ordering**: `preferencesDirty` is set *before* the data
  /// write happens, not after — see `HabitStorage.upsertHabit` for the
  /// full rationale (a spuriously-set dirty flag is harmless; a persisted
  /// change with no dirty flag is not recoverable without a full rescan).
  Future<AppSettings> updateSettings(AppSettings settings) async {
    await _syncMetadataStorage.markPreferencesDirty();
    final stamped = settings.copyWith(updatedAt: _clock.now());
    await saveSettings(stamped);
    return stamped;
  }

  /// **Raw/bulk persistence path.** Preserves the supplied `updatedAt`
  /// exactly — never stamps it. Reserved for migration, a future
  /// cloud-restore path, and tests that need exact timestamps. Production
  /// mutation call sites must use [updateSettings] instead.
  ///
  /// Throws a [StateError] if no local namespace is currently available —
  /// the same policy as `HabitStorage.upsertHabit` /
  /// `AdaptiveSuggestionStorage.upsertSuggestion`, so no user-owned write
  /// is ever silently dropped. The startup identity gate ensures normal
  /// app UI (and therefore this call) is never reached before a real UID
  /// exists.
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
