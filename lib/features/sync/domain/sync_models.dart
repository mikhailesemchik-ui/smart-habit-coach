/// Stable, UI-safe failure categories for a sync attempt. Never exposes a
/// raw backend/storage exception to callers.
enum SyncFailureCode {
  unauthenticated,
  networkUnavailable,
  permissionDenied,
  malformedRemoteData,
  localStorageFailure,
  cloudWriteFailure,
  cloudReadFailure,

  /// The active UID changed partway through the sync (e.g. the user signed
  /// out or switched accounts while a sync was in flight). The sync is
  /// aborted; no dirty state is cleared and no other identity's data is
  /// ever applied to the namespace that was active when the sync started.
  identityChanged,

  recoverySnapshotFailure,

  /// Another sync for the same coordinator instance is already running.
  alreadyRunning,

  unknown,
}

class SyncFailure {
  final SyncFailureCode code;
  final String message;

  const SyncFailure(this.code, this.message);

  @override
  String toString() => 'SyncFailure($code)';
}

/// Counts of what a sync attempt actually did. Always populated, even on a
/// partial or failed sync, so a caller can show "3 of 5 habits synced"
/// rather than an all-or-nothing result.
class SyncSummary {
  final int habitsUploaded;
  final int habitsDownloaded;
  final int habitsUnchanged;
  final int suggestionsUploaded;
  final int suggestionsDownloaded;
  final int suggestionsUnchanged;
  final int preferencesUploaded;
  final int preferencesDownloaded;
  final int tombstonesUploaded;
  final int tombstonesDownloaded;
  final int conflictsResolvedLocal;
  final int conflictsResolvedRemote;
  final DateTime startedAt;
  final DateTime? completedAt;

  const SyncSummary({
    this.habitsUploaded = 0,
    this.habitsDownloaded = 0,
    this.habitsUnchanged = 0,
    this.suggestionsUploaded = 0,
    this.suggestionsDownloaded = 0,
    this.suggestionsUnchanged = 0,
    this.preferencesUploaded = 0,
    this.preferencesDownloaded = 0,
    this.tombstonesUploaded = 0,
    this.tombstonesDownloaded = 0,
    this.conflictsResolvedLocal = 0,
    this.conflictsResolvedRemote = 0,
    required this.startedAt,
    this.completedAt,
  });

  SyncSummary copyWith({
    int? habitsUploaded,
    int? habitsDownloaded,
    int? habitsUnchanged,
    int? suggestionsUploaded,
    int? suggestionsDownloaded,
    int? suggestionsUnchanged,
    int? preferencesUploaded,
    int? preferencesDownloaded,
    int? tombstonesUploaded,
    int? tombstonesDownloaded,
    int? conflictsResolvedLocal,
    int? conflictsResolvedRemote,
    DateTime? completedAt,
  }) {
    return SyncSummary(
      habitsUploaded: habitsUploaded ?? this.habitsUploaded,
      habitsDownloaded: habitsDownloaded ?? this.habitsDownloaded,
      habitsUnchanged: habitsUnchanged ?? this.habitsUnchanged,
      suggestionsUploaded: suggestionsUploaded ?? this.suggestionsUploaded,
      suggestionsDownloaded:
          suggestionsDownloaded ?? this.suggestionsDownloaded,
      suggestionsUnchanged: suggestionsUnchanged ?? this.suggestionsUnchanged,
      preferencesUploaded: preferencesUploaded ?? this.preferencesUploaded,
      preferencesDownloaded:
          preferencesDownloaded ?? this.preferencesDownloaded,
      tombstonesUploaded: tombstonesUploaded ?? this.tombstonesUploaded,
      tombstonesDownloaded: tombstonesDownloaded ?? this.tombstonesDownloaded,
      conflictsResolvedLocal:
          conflictsResolvedLocal ?? this.conflictsResolvedLocal,
      conflictsResolvedRemote:
          conflictsResolvedRemote ?? this.conflictsResolvedRemote,
      startedAt: startedAt,
      completedAt: completedAt ?? this.completedAt,
    );
  }
}

/// Explicit sync modes. Only ever triggered by an explicit user action —
/// never chosen or run automatically.
enum SyncMode {
  /// Timestamp-based deterministic merge (see [SyncCoordinator] doc).
  mergeNormally,

  /// The user explicitly chose "use the data on this device": every local
  /// row is pushed as authoritative, and every remote-only row is
  /// tombstoned (never left in place, or it would reappear on the next
  /// pull).
  useLocalDeviceData,

  /// The user explicitly chose "use the cloud backup": local raw datasets
  /// are replaced with the remote ones. Internal/tested option; not wired
  /// to a dedicated conflict-resolution UI in Phase 4.
  useCloudData,
}

class SyncResult {
  final bool isSuccess;
  final SyncSummary summary;
  final SyncFailure? failure;

  const SyncResult({
    required this.isSuccess,
    required this.summary,
    this.failure,
  });

  factory SyncResult.success(SyncSummary summary) =>
      SyncResult(isSuccess: true, summary: summary);

  factory SyncResult.failure(SyncFailure failure, SyncSummary summary) =>
      SyncResult(isSuccess: false, summary: summary, failure: failure);
}
