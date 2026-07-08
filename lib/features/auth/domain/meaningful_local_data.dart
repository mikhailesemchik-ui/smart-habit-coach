import '../../coach/data/adaptive_suggestion_storage.dart';
import '../../home/data/habit_storage.dart';
import '../../profile/data/settings_storage.dart';
import '../../../core/sync/recovery_snapshot_storage.dart';
import '../../../core/sync/sync_metadata_storage.dart';
import '../../profile/domain/app_settings.dart';

/// Decides whether the *currently active* local namespace holds
/// "meaningful" data — the S1/S2 split from the approved plan's
/// returning-user sign-in flow (Phase 2B UI, decision logic only here).
///
/// Deliberately conservative: empty/default-only structures never count,
/// but **any** trace of real user activity does, including tombstoned
/// (deleted) records and dirty-but-not-yet-synced metadata — a user who
/// created and then deleted a habit still made a real local decision that
/// must not be silently abandoned by a same-namespace-looks-empty check.
///
/// Must be called *before* switching the active session/namespace (i.e.
/// while the anonymous UID is still the one every storage class
/// resolves against).
Future<bool> hasMeaningfulLocalData({
  required HabitStorage habitStorage,
  required AdaptiveSuggestionStorage suggestionStorage,
  required SettingsStorage settingsStorage,
  required SyncMetadataStorage syncMetadataStorage,
  required RecoverySnapshotStorage recoverySnapshotStorage,
}) async {
  // Raw (not visible-only) reads: a tombstoned habit or suggestion is
  // still a real local decision the user made, even though it is hidden
  // from normal screens.
  final rawHabits = await habitStorage.loadHabitsRaw();
  if (rawHabits != null && rawHabits.isNotEmpty) return true;

  final rawSuggestions = await suggestionStorage.loadSuggestionsRaw();
  if (rawSuggestions.isNotEmpty) return true;

  final settings = await settingsStorage.loadSettings();
  if (_isNonDefaultSettings(settings)) return true;

  final syncMetadata = await syncMetadataStorage.load();
  if (syncMetadata.dirtyHabitIds.isNotEmpty ||
      syncMetadata.dirtySuggestionIds.isNotEmpty ||
      syncMetadata.preferencesDirty) {
    return true;
  }

  // A recovery snapshot is only ever written immediately before a
  // destructive mutation (Phase 1C), so its mere presence is itself
  // evidence a real, consequential local action already happened once.
  final snapshot = await recoverySnapshotStorage.read();
  if (snapshot != null) return true;

  return false;
}

// AppSettings has no value-equality override (it intentionally mirrors a
// hand-written JSON model, not a value object elsewhere in the app), so
// this compares the fields that represent actual user choices — not
// `updatedAt`, which is storage metadata, not user content.
bool _isNonDefaultSettings(AppSettings settings) {
  return settings.displayName != AppSettings.defaults.displayName ||
      settings.themeMode != AppSettings.defaults.themeMode ||
      settings.startOfWeek != AppSettings.defaults.startOfWeek;
}
