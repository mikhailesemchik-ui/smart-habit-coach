import 'package:flutter/foundation.dart';

import '../../../core/sync/sync_metadata_storage.dart';
import '../data/cloud_repositories.dart';
import '../data/sync_coordinator.dart';
import '../domain/sync_models.dart';

class SyncUiState {
  final bool isSyncing;
  final DateTime? lastSuccessfulSyncAt;
  final SyncSummary? lastSummary;
  final SyncFailure? lastFailure;

  const SyncUiState({
    required this.isSyncing,
    this.lastSuccessfulSyncAt,
    this.lastSummary,
    this.lastFailure,
  });

  SyncUiState copyWith({
    bool? isSyncing,
    DateTime? lastSuccessfulSyncAt,
    SyncSummary? lastSummary,
    SyncFailure? lastFailure,
    bool clearFailure = false,
  }) {
    return SyncUiState(
      isSyncing: isSyncing ?? this.isSyncing,
      lastSuccessfulSyncAt: lastSuccessfulSyncAt ?? this.lastSuccessfulSyncAt,
      lastSummary: lastSummary ?? this.lastSummary,
      lastFailure: clearFailure ? null : lastFailure ?? this.lastFailure,
    );
  }
}

/// Minimal "Sync now" UI controller. Only ever syncs when explicitly asked
/// (no startup/background sync, no polling).
class SyncController extends ChangeNotifier {
  final SyncCoordinator? _injectedCoordinator;
  final SyncMetadataStorage _syncMetadataStorage;
  SyncCoordinator? _lazyCoordinator;

  SyncUiState _state = const SyncUiState(isSyncing: false);

  SyncController({
    SyncCoordinator? coordinator,
    SyncMetadataStorage? syncMetadataStorage,
  }) : _injectedCoordinator = coordinator,
       _syncMetadataStorage = syncMetadataStorage ?? SyncMetadataStorage();

  SyncUiState get state => _state;

  void _emit(SyncUiState state) {
    _state = state;
    notifyListeners();
  }

  Future<void> loadStatus() async {
    final metadata = await _syncMetadataStorage.load();
    _emit(_state.copyWith(lastSuccessfulSyncAt: metadata.lastSuccessfulSyncAt));
  }

  /// Built lazily on first actual use (never in the constructor), so simply
  /// constructing a [SyncController] never touches the Supabase client —
  /// screens that show account/profile state before a session exists (or
  /// tests with no Supabase client at all) never crash just because this
  /// controller exists on screen. Returns `null` if the default cloud
  /// dependencies cannot be constructed (e.g. Supabase never initialized).
  SyncCoordinator? get _coordinator {
    final injected = _injectedCoordinator;
    if (injected != null) return injected;
    final existing = _lazyCoordinator;
    if (existing != null) return existing;
    try {
      final built = SyncCoordinator(
        sessionProvider: SupabaseCloudAuthSessionProvider(),
        habitCloudRepository: SupabaseHabitCloudRepository(),
        suggestionCloudRepository: SupabaseAdaptiveSuggestionCloudRepository(),
        settingsCloudRepository: SupabaseSettingsCloudRepository(),
        syncMetadataStorage: _syncMetadataStorage,
      );
      _lazyCoordinator = built;
      return built;
    } catch (_) {
      return null;
    }
  }

  /// Runs a sync. A second call while one is already in flight is a safe
  /// no-op — it awaits the same result rather than starting an overlapping
  /// sync.
  Future<void> syncNow({SyncMode mode = SyncMode.mergeNormally}) async {
    if (_state.isSyncing) return;
    final coordinator = _coordinator;
    if (coordinator == null) {
      _emit(
        _state.copyWith(
          lastFailure: const SyncFailure(
            SyncFailureCode.unknown,
            'Sync is not available right now.',
          ),
        ),
      );
      return;
    }

    _emit(_state.copyWith(isSyncing: true, clearFailure: true));

    final result = await coordinator.sync(mode: mode);

    _emit(
      _state.copyWith(
        isSyncing: false,
        lastSummary: result.summary,
        lastSuccessfulSyncAt: result.isSuccess
            ? result.summary.completedAt
            : _state.lastSuccessfulSyncAt,
        lastFailure: result.failure,
        clearFailure: result.isSuccess,
      ),
    );
  }
}

String syncFailureMessage(SyncFailure failure) {
  return switch (failure.code) {
    SyncFailureCode.unauthenticated =>
      'Your session is not ready. Please retry from startup.',
    SyncFailureCode.networkUnavailable =>
      'Could not connect. Check your connection and try again.',
    SyncFailureCode.permissionDenied => 'Cloud access was denied.',
    SyncFailureCode.malformedRemoteData => 'Cloud data was malformed.',
    SyncFailureCode.localStorageFailure => 'Local storage failed.',
    SyncFailureCode.cloudWriteFailure => 'Could not save to the cloud.',
    SyncFailureCode.cloudReadFailure => 'Could not read from the cloud.',
    SyncFailureCode.identityChanged =>
      'The active account changed during sync. Nothing was changed — try again.',
    SyncFailureCode.recoverySnapshotFailure =>
      'Could not create a local safety copy, so nothing was changed.',
    SyncFailureCode.alreadyRunning => 'A sync is already running.',
    SyncFailureCode.unknown => 'Something went wrong. Please try again.',
  };
}

String syncSummaryMessage(SyncSummary summary) {
  final parts = <String>[];
  final habits = summary.habitsUploaded + summary.habitsDownloaded;
  final suggestions =
      summary.suggestionsUploaded + summary.suggestionsDownloaded;
  if (habits > 0) parts.add('$habits habit${habits == 1 ? '' : 's'}');
  if (suggestions > 0) {
    parts.add('$suggestions suggestion${suggestions == 1 ? '' : 's'}');
  }
  if (parts.isEmpty) return 'Everything is already up to date.';
  return 'Synced ${parts.join(', ')}.';
}
