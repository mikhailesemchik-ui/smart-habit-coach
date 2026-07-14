import 'dart:convert';

import '../../../core/storage/local_namespace_resolver.dart';
import '../../../core/sync/recovery_snapshot.dart';
import '../../../core/sync/recovery_snapshot_storage.dart';
import '../../../core/sync/sync_metadata.dart';
import '../../../core/sync/sync_metadata_storage.dart';
import '../../../core/time/clock.dart';
import '../../coach/data/adaptive_suggestion_storage.dart';
import '../../coach/domain/adaptive_suggestion.dart';
import '../../home/data/habit_storage.dart';
import '../../home/domain/habit.dart';
import '../../profile/data/settings_storage.dart';
import '../../profile/domain/app_settings.dart';
import '../domain/export_result.dart';
import '../domain/local_data_export.dart';

/// Builds a personal-backup JSON export of the active UID's local data.
///
/// Read-only: never mutates habits/suggestions/settings, never marks
/// anything dirty, never touches the network, never triggers a sync. Only
/// ever reads the currently-active local namespace — there is no way for
/// this service to read another UID's data, since every storage class it
/// depends on is itself namespaced by [LocalNamespaceResolver].
class LocalDataExportService {
  final LocalNamespaceResolver _namespaceResolver;
  final HabitStorage _habitStorage;
  final AdaptiveSuggestionStorage _suggestionStorage;
  final SettingsStorage _settingsStorage;
  final SyncMetadataStorage _syncMetadataStorage;
  final RecoverySnapshotStorage _recoverySnapshotStorage;
  final Clock _clock;

  LocalDataExportService({
    LocalNamespaceResolver? namespaceResolver,
    HabitStorage? habitStorage,
    AdaptiveSuggestionStorage? suggestionStorage,
    SettingsStorage? settingsStorage,
    SyncMetadataStorage? syncMetadataStorage,
    RecoverySnapshotStorage? recoverySnapshotStorage,
    Clock? clock,
  }) : _namespaceResolver = namespaceResolver ?? const LocalNamespaceResolver(),
       _habitStorage = habitStorage ?? HabitStorage(),
       _suggestionStorage = suggestionStorage ?? AdaptiveSuggestionStorage(),
       _settingsStorage = settingsStorage ?? SettingsStorage(),
       _syncMetadataStorage = syncMetadataStorage ?? SyncMetadataStorage(),
       _recoverySnapshotStorage =
           recoverySnapshotStorage ?? RecoverySnapshotStorage(),
       _clock = clock ?? const SystemClock();

  Future<ExportResult> export() async {
    final uid = _namespaceResolver.currentUid;
    if (uid == null) {
      return ExportResult.failure(
        const ExportFailure(
          ExportFailureCode.noActiveIdentity,
          'No active identity — nothing to export yet.',
        ),
      );
    }

    final List<Habit> habits;
    final List<AdaptiveHabitSuggestion> suggestions;
    final AppSettings settings;
    final SyncMetadata syncMetadata;
    final RecoverySnapshot? recoverySnapshot;
    try {
      habits = await _habitStorage.loadHabitsRaw() ?? [];
      suggestions = await _suggestionStorage.loadSuggestionsRaw();
      settings = await _settingsStorage.loadSettings();
      syncMetadata = await _syncMetadataStorage.load();
      recoverySnapshot = await _recoverySnapshotStorage.read();
    } catch (_) {
      return ExportResult.failure(
        const ExportFailure(
          ExportFailureCode.localReadFailure,
          'Could not read your local data.',
        ),
      );
    }

    try {
      final export = LocalDataExport(
        generatedAt: _clock.now(),
        activeUid: uid,
        habitsRaw: habits.map((h) => h.toJson()).toList(),
        adaptiveSuggestionsRaw: suggestions.map((s) => s.toJson()).toList(),
        appSettings: settings.toJson(),
        syncMetadata: syncMetadata.toJson(),
        recoverySnapshot: recoverySnapshot?.toJson(),
      );
      const encoder = JsonEncoder.withIndent('  ');
      final jsonString = encoder.convert(export.toJson());
      return ExportResult.success(export, jsonString);
    } catch (_) {
      return ExportResult.failure(
        const ExportFailure(
          ExportFailureCode.serializationFailure,
          'Could not build the export file.',
        ),
      );
    }
  }
}
