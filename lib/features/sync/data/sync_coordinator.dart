import '../../../core/sync/recovery_snapshot_storage.dart';
import '../../../core/sync/sync_metadata_storage.dart';
import '../../../core/time/clock.dart';
import '../../coach/data/adaptive_suggestion_storage.dart';
import '../../coach/domain/adaptive_suggestion.dart';
import '../../home/data/habit_storage.dart';
import '../../home/domain/habit.dart';
import '../../profile/data/settings_storage.dart';
import '../../profile/domain/app_settings.dart';
import '../domain/sync_models.dart';
import 'cloud_backend.dart';
import 'cloud_records.dart';
import 'cloud_repositories.dart';
import 'cloud_result.dart';
import 'sync_merge.dart';

T? _firstWhereOrNull<T>(Iterable<T> items, bool Function(T) test) {
  for (final item in items) {
    if (test(item)) return item;
  }
  return null;
}

/// Orchestrates one explicit sync attempt between the active UID's local
/// namespace and its Supabase cloud rows (habits, adaptive suggestions,
/// preferences). Never accesses Supabase directly — all cloud access goes
/// through the injected repositories, and the active UID always comes from
/// the injected [CloudAuthSessionProvider], never a caller-supplied value.
///
/// Sync is always explicit: nothing in this class schedules or triggers
/// itself. A caller (UI action) decides when [sync] runs.
///
/// See `sync_merge.dart` for the deterministic merge rule used by
/// [SyncMode.mergeNormally].
class SyncCoordinator {
  final CloudAuthSessionProvider sessionProvider;
  final HabitCloudRepository habitCloudRepository;
  final AdaptiveSuggestionCloudRepository suggestionCloudRepository;
  final SettingsCloudRepository settingsCloudRepository;
  final HabitStorage habitStorage;
  final AdaptiveSuggestionStorage suggestionStorage;
  final SettingsStorage settingsStorage;
  final SyncMetadataStorage syncMetadataStorage;
  final RecoverySnapshotStorage recoverySnapshotStorage;
  final Clock clock;

  /// Called after remote habit changes have been applied locally for the
  /// active UID (never for any other identity), with the resulting visible
  /// (non-tombstoned) habit list, so a caller can reconcile reminder
  /// scheduling. This is a narrow hook, not a `NotificationService`
  /// redesign — `SyncCoordinator` never touches notifications itself.
  final Future<void> Function(List<Habit> activeHabits)? onHabitsChanged;

  Future<SyncResult>? _inFlight;

  SyncCoordinator({
    required this.sessionProvider,
    required this.habitCloudRepository,
    required this.suggestionCloudRepository,
    required this.settingsCloudRepository,
    HabitStorage? habitStorage,
    AdaptiveSuggestionStorage? suggestionStorage,
    SettingsStorage? settingsStorage,
    SyncMetadataStorage? syncMetadataStorage,
    RecoverySnapshotStorage? recoverySnapshotStorage,
    Clock? clock,
    this.onHabitsChanged,
  }) : habitStorage = habitStorage ?? HabitStorage(),
       suggestionStorage = suggestionStorage ?? AdaptiveSuggestionStorage(),
       settingsStorage = settingsStorage ?? SettingsStorage(),
       syncMetadataStorage = syncMetadataStorage ?? SyncMetadataStorage(),
       recoverySnapshotStorage =
           recoverySnapshotStorage ?? RecoverySnapshotStorage(),
       clock = clock ?? const SystemClock();

  bool get isSyncing => _inFlight != null;

  /// Runs one sync attempt. If a sync is already running on this
  /// coordinator instance, returns the *same* in-flight [Future] rather
  /// than starting a second, overlapping one — duplicate "Sync now" taps
  /// are safe no-ops that just await the result already underway.
  Future<SyncResult> sync({SyncMode mode = SyncMode.mergeNormally}) {
    final existing = _inFlight;
    if (existing != null) return existing;
    final future = _runSync(mode);
    _inFlight = future;
    future.whenComplete(() => _inFlight = null);
    return future;
  }

  Future<SyncResult> _runSync(SyncMode mode) async {
    final startedAt = clock.now();
    final summary = SyncSummary(startedAt: startedAt);

    final uid = sessionProvider.currentUid();
    if (uid == null || uid.trim().isEmpty) {
      return SyncResult.failure(
        const SyncFailure(
          SyncFailureCode.unauthenticated,
          'A signed-in user is required.',
        ),
        summary,
      );
    }

    await syncMetadataStorage.recordSyncAttempt();

    final localHabits = await habitStorage.loadHabitsRaw() ?? <Habit>[];
    final localSuggestions = await suggestionStorage.loadSuggestionsRaw();
    final localSettings = await settingsStorage.loadSettings();

    if (!_uidUnchanged(uid)) return _identityChangedFailure(summary);

    final habitsResult = await habitCloudRepository.fetchAll();
    if (!habitsResult.isSuccess) {
      return _cloudFailureResult(habitsResult.failure!, summary);
    }
    final suggestionsResult = await suggestionCloudRepository.fetchAll();
    if (!suggestionsResult.isSuccess) {
      return _cloudFailureResult(suggestionsResult.failure!, summary);
    }
    final settingsResult = await settingsCloudRepository.fetch();
    if (!settingsResult.isSuccess) {
      return _cloudFailureResult(settingsResult.failure!, summary);
    }

    if (!_uidUnchanged(uid)) return _identityChangedFailure(summary);

    final remoteHabits = habitsResult.value;
    final remoteSuggestions = suggestionsResult.value;
    final remoteSettings = settingsResult.value;

    // ---- Plan habits ----
    final habitUploadIds = <String>{};
    final habitApplyRemote = <String, Habit>{};
    final habitTombstonesToCreate = <Habit>[];
    var habitsUnchanged = 0;
    var habitTombUp = 0;
    var habitTombDown = 0;
    var habitConfLocal = 0;
    var habitConfRemote = 0;

    switch (mode) {
      case SyncMode.mergeNormally:
        final decision = planMerge<Habit, CloudHabitRecord>(
          local: localHabits,
          remote: remoteHabits,
          localId: (h) => h.id,
          localUpdatedAt: (h) => h.updatedAt,
          localIsTombstone: (h) => h.deletedAt != null,
          localJson: (h) => h.toJson(),
          remoteId: (r) => r.habit.id,
          remoteUpdatedAt: (r) => r.habit.updatedAt,
          remoteIsTombstone: (r) => r.habit.deletedAt != null,
          remoteJson: (r) => r.habit.toJson(),
        );
        habitUploadIds.addAll(decision.uploadIds);
        for (final entry in decision.applyRemote.entries) {
          habitApplyRemote[entry.key] = entry.value.habit;
        }
        habitsUnchanged = decision.unchangedCount;
        habitTombUp = decision.uploadedTombstoneCount;
        habitTombDown = decision.downloadedTombstoneCount;
        habitConfLocal = decision.conflictsResolvedLocal;
        habitConfRemote = decision.conflictsResolvedRemote;
      case SyncMode.useLocalDeviceData:
        habitUploadIds.addAll(localHabits.map((h) => h.id));
        final remoteOnly = remoteHabits.where(
          (r) => !habitUploadIds.contains(r.habit.id),
        );
        for (final r in remoteOnly) {
          final tombstoned = r.habit.copyWith(
            deletedAt: startedAt,
            updatedAt: startedAt,
          );
          habitTombstonesToCreate.add(tombstoned);
          habitUploadIds.add(tombstoned.id);
          habitTombUp++;
        }
      case SyncMode.useCloudData:
        for (final r in remoteHabits) {
          habitApplyRemote[r.habit.id] = r.habit;
          if (r.habit.deletedAt != null) habitTombDown++;
        }
    }

    // ---- Plan suggestions ----
    final suggestionUploadIds = <String>{};
    final suggestionApplyRemote = <String, AdaptiveHabitSuggestion>{};
    var suggestionsUnchanged = 0;
    var suggestionTombUp = 0;
    var suggestionTombDown = 0;
    var suggestionConfLocal = 0;
    var suggestionConfRemote = 0;

    switch (mode) {
      case SyncMode.mergeNormally:
        final decision =
            planMerge<AdaptiveHabitSuggestion, CloudAdaptiveSuggestionRecord>(
              local: localSuggestions,
              remote: remoteSuggestions,
              localId: (s) => s.id,
              localUpdatedAt: (s) => s.updatedAt,
              localIsTombstone: (s) => s.deletedAt != null,
              localJson: (s) => s.toJson(),
              remoteId: (r) => r.suggestion.id,
              remoteUpdatedAt: (r) => r.suggestion.updatedAt,
              remoteIsTombstone: (r) => r.suggestion.deletedAt != null,
              remoteJson: (r) => r.suggestion.toJson(),
            );
        suggestionUploadIds.addAll(decision.uploadIds);
        for (final entry in decision.applyRemote.entries) {
          suggestionApplyRemote[entry.key] = entry.value.suggestion;
        }
        suggestionsUnchanged = decision.unchangedCount;
        suggestionTombUp = decision.uploadedTombstoneCount;
        suggestionTombDown = decision.downloadedTombstoneCount;
        suggestionConfLocal = decision.conflictsResolvedLocal;
        suggestionConfRemote = decision.conflictsResolvedRemote;
      case SyncMode.useLocalDeviceData:
        suggestionUploadIds.addAll(localSuggestions.map((s) => s.id));
        final remoteOnly = remoteSuggestions.where(
          (r) => !suggestionUploadIds.contains(r.suggestion.id),
        );
        for (final r in remoteOnly) {
          final tombstoned = r.suggestion.copyWith(
            updatedAt: startedAt,
            deletedAt: startedAt,
          );
          suggestionApplyRemote[tombstoned.id] = tombstoned;
          suggestionUploadIds.add(tombstoned.id);
          suggestionTombUp++;
        }
      case SyncMode.useCloudData:
        for (final r in remoteSuggestions) {
          suggestionApplyRemote[r.suggestion.id] = r.suggestion;
          if (r.suggestion.deletedAt != null) suggestionTombDown++;
        }
    }

    // ---- Plan preferences ----
    String? preferencesAction; // 'upload' | 'download' | null
    switch (mode) {
      case SyncMode.mergeNormally:
        if (remoteSettings == null) {
          preferencesAction = 'upload';
        } else {
          final lu = localSettings.updatedAt;
          final ru = remoteSettings.settings.updatedAt;
          if (lu.isAfter(ru)) {
            preferencesAction = 'upload';
          } else if (ru.isAfter(lu)) {
            preferencesAction = 'download';
          } else {
            final lc = canonicalJson(localSettings.toJson());
            final rc = canonicalJson(remoteSettings.settings.toJson());
            if (lc != rc) {
              preferencesAction = rc.compareTo(lc) > 0 ? 'download' : 'upload';
            }
          }
        }
      case SyncMode.useLocalDeviceData:
        preferencesAction = 'upload';
      case SyncMode.useCloudData:
        if (remoteSettings != null) preferencesAction = 'download';
    }

    final needsLocalReplacement =
        habitApplyRemote.isNotEmpty ||
        habitTombstonesToCreate.isNotEmpty ||
        suggestionApplyRemote.isNotEmpty ||
        preferencesAction == 'download' ||
        mode == SyncMode.useCloudData;

    if (needsLocalReplacement) {
      try {
        await recoverySnapshotStorage.create(reason: _snapshotReason(mode));
      } catch (_) {
        return SyncResult.failure(
          const SyncFailure(
            SyncFailureCode.recoverySnapshotFailure,
            'Could not create a local safety snapshot before replacing local data.',
          ),
          summary.copyWith(completedAt: clock.now()),
        );
      }
    }

    SyncFailure? overallFailure;

    // ---- Push habits ----
    var habitsUploaded = 0;
    var habitsPushOk = true;
    final habitUploadedVersions = <String, DateTime>{};
    final habitsToUpload = <Habit>[
      for (final id in habitUploadIds)
        if (_firstWhereOrNull(localHabits, (h) => h.id == id) != null ||
            _firstWhereOrNull(habitTombstonesToCreate, (h) => h.id == id) !=
                null)
          _firstWhereOrNull(habitTombstonesToCreate, (h) => h.id == id) ??
              _firstWhereOrNull(localHabits, (h) => h.id == id)!,
    ];
    if (habitsToUpload.isNotEmpty) {
      final records = habitsToUpload
          .map((h) => CloudHabitRecord.fromHabit(userId: uid, habit: h))
          .toList();
      final pushResult = await habitCloudRepository.upsertMany(records);
      if (pushResult.isSuccess) {
        habitsUploaded = habitsToUpload.length;
        for (final h in habitsToUpload) {
          habitUploadedVersions[h.id] = h.updatedAt;
        }
      } else {
        habitsPushOk = false;
        overallFailure ??= _cloudFailure(pushResult.failure!);
      }
    }

    // ---- Push suggestions ----
    var suggestionsUploaded = 0;
    var suggestionsPushOk = true;
    final suggestionUploadedVersions = <String, DateTime>{};
    final suggestionsToUpload = <AdaptiveHabitSuggestion>[
      for (final id in suggestionUploadIds)
        _firstWhereOrNull(suggestionApplyRemote.values, (s) => s.id == id) ??
            _firstWhereOrNull(localSuggestions, (s) => s.id == id)!,
    ];
    if (suggestionsToUpload.isNotEmpty) {
      final records = suggestionsToUpload
          .map(
            (s) => CloudAdaptiveSuggestionRecord.fromSuggestion(
              userId: uid,
              suggestion: s,
            ),
          )
          .toList();
      final pushResult = await suggestionCloudRepository.upsertMany(records);
      if (pushResult.isSuccess) {
        suggestionsUploaded = suggestionsToUpload.length;
        for (final s in suggestionsToUpload) {
          suggestionUploadedVersions[s.id] = s.updatedAt;
        }
      } else {
        suggestionsPushOk = false;
        overallFailure ??= _cloudFailure(pushResult.failure!);
      }
    }

    // ---- Push preferences ----
    var preferencesPushOk = true;
    if (preferencesAction == 'upload') {
      final record = CloudSettingsRecord.fromSettings(
        userId: uid,
        settings: localSettings,
      );
      final pushResult = await settingsCloudRepository.upsert(record);
      if (!pushResult.isSuccess) {
        preferencesPushOk = false;
        overallFailure ??= _cloudFailure(pushResult.failure!);
      }
    }

    // ---- Apply local writes (raw, timestamp-preserving, never dirty) ----
    if (habitApplyRemote.isNotEmpty || habitTombstonesToCreate.isNotEmpty) {
      final updated = List<Habit>.of(localHabits);
      void upsertLocal(Habit habit) {
        final idx = updated.indexWhere((h) => h.id == habit.id);
        if (idx >= 0) {
          updated[idx] = habit;
        } else {
          updated.add(habit);
        }
      }

      for (final t in habitTombstonesToCreate) {
        upsertLocal(t);
      }
      for (final h in habitApplyRemote.values) {
        upsertLocal(h);
      }
      final finalHabits = mode == SyncMode.useCloudData
          ? remoteHabits.map((r) => r.habit).toList()
          : updated;
      await habitStorage.saveHabits(finalHabits);
    }

    if (suggestionApplyRemote.isNotEmpty) {
      final updated = List<AdaptiveHabitSuggestion>.of(localSuggestions);
      for (final s in suggestionApplyRemote.values) {
        final idx = updated.indexWhere((existing) => existing.id == s.id);
        if (idx >= 0) {
          updated[idx] = s;
        } else {
          updated.add(s);
        }
      }
      final finalSuggestions = mode == SyncMode.useCloudData
          ? remoteSuggestions.map((r) => r.suggestion).toList()
          : updated;
      await suggestionStorage.saveSuggestions(finalSuggestions);
    }

    AppSettings? appliedSettings;
    if (preferencesAction == 'download' && remoteSettings != null) {
      appliedSettings = remoteSettings.settings;
      await settingsStorage.saveSettings(appliedSettings);
    }

    if (!_uidUnchanged(uid)) return _identityChangedFailure(summary);

    // ---- Clear dirty markers for acknowledged records only ----
    if (habitsPushOk) {
      for (final entry in habitUploadedVersions.entries) {
        final current = await habitStorage.loadHabitsRaw() ?? [];
        final match = _firstWhereOrNull(current, (h) => h.id == entry.key);
        if (match != null && match.updatedAt == entry.value) {
          await syncMetadataStorage.clearHabitDirty(entry.key);
        }
      }
    }
    for (final id in habitApplyRemote.keys) {
      await syncMetadataStorage.clearHabitDirty(id);
    }

    if (suggestionsPushOk) {
      for (final entry in suggestionUploadedVersions.entries) {
        final current = await suggestionStorage.loadSuggestionsRaw();
        final match = _firstWhereOrNull(current, (s) => s.id == entry.key);
        if (match != null && match.updatedAt == entry.value) {
          await syncMetadataStorage.clearSuggestionDirty(entry.key);
        }
      }
    }
    for (final id in suggestionApplyRemote.keys) {
      await syncMetadataStorage.clearSuggestionDirty(id);
    }

    if (preferencesAction == 'upload' && preferencesPushOk) {
      final current = await settingsStorage.loadSettings();
      if (current.updatedAt == localSettings.updatedAt) {
        await syncMetadataStorage.clearPreferencesDirty();
      }
    } else if (preferencesAction == 'download') {
      await syncMetadataStorage.clearPreferencesDirty();
    }

    final overallSuccess =
        habitsPushOk && suggestionsPushOk && preferencesPushOk;
    await syncMetadataStorage.recordSyncResult(
      successAt: overallSuccess ? clock.now() : null,
      errorCode: overallSuccess
          ? null
          : (overallFailure?.code.name ?? SyncFailureCode.unknown.name),
    );

    final finalSummary = summary.copyWith(
      habitsUploaded: habitsUploaded,
      habitsDownloaded: habitApplyRemote.length,
      habitsUnchanged: habitsUnchanged,
      suggestionsUploaded: suggestionsUploaded,
      suggestionsDownloaded: suggestionApplyRemote.length,
      suggestionsUnchanged: suggestionsUnchanged,
      preferencesUploaded: preferencesAction == 'upload' && preferencesPushOk
          ? 1
          : 0,
      preferencesDownloaded: preferencesAction == 'download' ? 1 : 0,
      tombstonesUploaded: habitTombUp + suggestionTombUp,
      tombstonesDownloaded: habitTombDown + suggestionTombDown,
      conflictsResolvedLocal: habitConfLocal + suggestionConfLocal,
      conflictsResolvedRemote: habitConfRemote + suggestionConfRemote,
      completedAt: clock.now(),
    );

    if (habitApplyRemote.isNotEmpty || habitTombstonesToCreate.isNotEmpty) {
      final hook = onHabitsChanged;
      if (hook != null) {
        final activeHabits = await habitStorage.loadHabits() ?? [];
        await hook(activeHabits);
      }
    }

    if (overallSuccess) return SyncResult.success(finalSummary);
    return SyncResult.failure(
      overallFailure ??
          const SyncFailure(SyncFailureCode.unknown, 'Sync did not complete.'),
      finalSummary,
    );
  }

  bool _uidUnchanged(String capturedUid) =>
      sessionProvider.currentUid() == capturedUid;

  SyncResult _identityChangedFailure(SyncSummary summary) => SyncResult.failure(
    const SyncFailure(
      SyncFailureCode.identityChanged,
      'The active account changed during sync.',
    ),
    summary.copyWith(completedAt: clock.now()),
  );

  SyncResult _cloudFailureResult(CloudFailure failure, SyncSummary summary) =>
      SyncResult.failure(
        _cloudFailure(failure),
        summary.copyWith(completedAt: clock.now()),
      );

  SyncFailure _cloudFailure(CloudFailure failure) {
    final code = switch (failure.code) {
      CloudErrorCode.unauthenticated => SyncFailureCode.unauthenticated,
      CloudErrorCode.networkUnavailable => SyncFailureCode.networkUnavailable,
      CloudErrorCode.permissionDenied => SyncFailureCode.permissionDenied,
      CloudErrorCode.malformedResponse => SyncFailureCode.malformedRemoteData,
      CloudErrorCode.constraintViolation => SyncFailureCode.cloudWriteFailure,
      CloudErrorCode.rateLimited => SyncFailureCode.networkUnavailable,
      CloudErrorCode.unavailable => SyncFailureCode.cloudReadFailure,
      CloudErrorCode.unknown => SyncFailureCode.unknown,
    };
    return SyncFailure(code, 'Cloud sync failed.');
  }

  String _snapshotReason(SyncMode mode) => switch (mode) {
    SyncMode.mergeNormally => 'beforeSyncMerge',
    SyncMode.useLocalDeviceData => 'beforeUseLocalDeviceData',
    SyncMode.useCloudData => 'beforeUseCloudData',
  };
}
