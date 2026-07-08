import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/storage/local_namespace_resolver.dart';
import '../../../core/sync/recovery_snapshot_storage.dart';
import '../../../core/sync/sync_metadata_storage.dart';
import '../../../core/time/clock.dart';
import '../domain/adaptive_suggestion.dart';

/// Local persistence for [AdaptiveHabitSuggestion] metadata, mirroring the
/// habit storage pattern. Suggestion records are kept separate from habit
/// JSON so old habit storage stays valid unchanged.
class AdaptiveSuggestionStorage {
  static const _suggestionsBaseKey = 'adaptive_suggestions';

  final LocalNamespaceResolver _namespaceResolver;
  final Clock _clock;
  final SyncMetadataStorage _syncMetadataStorage;
  final RecoverySnapshotStorage? _recoverySnapshotStorageOverride;
  RecoverySnapshotStorage? _lazyRecoverySnapshotStorage;

  Future<void> _writeQueue = Future.value();

  AdaptiveSuggestionStorage({
    LocalNamespaceResolver? namespaceResolver,
    Clock? clock,
    SyncMetadataStorage? syncMetadataStorage,
    RecoverySnapshotStorage? recoverySnapshotStorage,
  }) : _namespaceResolver = namespaceResolver ?? const LocalNamespaceResolver(),
       _clock = clock ?? const SystemClock(),
       _syncMetadataStorage = syncMetadataStorage ?? SyncMetadataStorage(),
       _recoverySnapshotStorageOverride = recoverySnapshotStorage;

  // Lazy + reuses `this`, mirroring HabitStorage, so the two classes never
  // recurse into each other at construction time.
  RecoverySnapshotStorage get _recoverySnapshotStorage =>
      _recoverySnapshotStorageOverride ??
      (_lazyRecoverySnapshotStorage ??= RecoverySnapshotStorage(
        namespaceResolver: _namespaceResolver,
        clock: _clock,
        suggestionStorage: this,
      ));

  Future<T> _enqueueWrite<T>(Future<T> Function() action) {
    final result = _writeQueue.then((_) => action());
    _writeQueue = result.then((_) {}, onError: (_) {});
    return result;
  }

  /// **Visible read.** Used by all normal production call sites (Weekly
  /// Review, Coach Insights). Excludes tombstoned suggestions
  /// (`deletedAt != null`). Returns `[]` both when there is genuinely no
  /// saved data and when no local namespace is currently available —
  /// consistent with this method's existing "nothing to show" contract.
  Future<List<AdaptiveHabitSuggestion>> loadSuggestions() async {
    final all = await loadSuggestionsRaw();
    return all.where((s) => s.deletedAt == null).toList();
  }

  /// **Raw/all-record read.** Includes tombstoned suggestions. Used by
  /// [upsertSuggestion]/[tombstoneSuggestion] (so re-saving never drops
  /// existing tombstones), [RecoverySnapshotStorage], and future
  /// sync/migration/tests.
  Future<List<AdaptiveHabitSuggestion>> loadSuggestionsRaw() async {
    final result = _namespaceResolver.resolveKey(_suggestionsBaseKey);
    if (!result.isAvailable) return [];

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(result.key!);
    if (raw == null) return [];

    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(AdaptiveHabitSuggestion.fromJson)
          .whereType<AdaptiveHabitSuggestion>()
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// **Normal mutation path.** Used by all production suggestion state
  /// changes (generation, Apply, Adjust, Keep, and any other status/
  /// evidence update).
  ///
  /// Loads the current namespaced collection (including tombstones, so
  /// none are dropped by the re-save), locates [suggestion] by id
  /// (appending it if not found), stamps `updatedAt` with the injected
  /// [Clock], and marks the id dirty in [SyncMetadataStorage]. Unlike
  /// `HabitStorage.upsertHabit`, `createdAt` is **not** re-derived from any
  /// existing stored record: a suggestion's `createdAt` is an intentional
  /// domain timestamp set once by the detector (the local calendar week it
  /// was generated in drives cooldown and weekly-limit logic), so it is
  /// always taken from [suggestion] as supplied — callers must never
  /// construct a suggestion with a changed `createdAt` for an existing id.
  /// `deletedAt` is likewise taken from [suggestion] as-is (use
  /// [tombstoneSuggestion] to delete).
  ///
  /// Throws a [StateError] if no local namespace is currently available.
  /// **Dirty-first ordering**: the id is marked dirty before the data
  /// write happens — see `HabitStorage.upsertHabit` for the full
  /// rationale (a spurious dirty id with no matching change is harmless;
  /// a persisted change with no dirty id is not recoverable without a
  /// full rescan).
  Future<AdaptiveHabitSuggestion> upsertSuggestion(
    AdaptiveHabitSuggestion suggestion,
  ) {
    return _enqueueWrite(() async {
      await _syncMetadataStorage.markSuggestionDirty(suggestion.id);

      final current = await loadSuggestionsRaw();
      final index = current.indexWhere((s) => s.id == suggestion.id);
      final stamped = suggestion.copyWith(updatedAt: _clock.now());

      if (index >= 0) {
        current[index] = stamped;
      } else {
        current.add(stamped);
      }

      await writeSuggestionsRaw(current);
      return stamped;
    });
  }

  /// **Tombstone delete.** No production call site tombstones a suggestion
  /// today (status transitions like Apply/Keep/Adjust/reject are handled
  /// by [upsertSuggestion] and are not deletions), but the primitive is
  /// built now for future use (e.g. a future "clear suggestion history"
  /// action). Creates a full-dataset [RecoverySnapshotStorage] snapshot
  /// first, then sets `deletedAt`/`updatedAt` to the same single [Clock]
  /// reading and marks the id dirty.
  ///
  /// Takes the full in-memory [suggestion] (not just its id), mirroring
  /// `HabitStorage.tombstoneHabit`: if a record with this id already
  /// exists in raw storage it is replaced; if not, [suggestion] is
  /// inserted already tombstoned. `createdAt` always comes from
  /// [suggestion] as supplied (same rule as [upsertSuggestion] — it is
  /// never re-derived from any existing stored record).
  ///
  /// Throws a [StateError] if no local namespace is available.
  /// Ordering: the recovery snapshot is taken first (true pre-mutation
  /// state), then the id is marked dirty, and only then is the data
  /// actually tombstoned — same dirty-first rationale as [upsertSuggestion].
  Future<AdaptiveHabitSuggestion> tombstoneSuggestion(
    AdaptiveHabitSuggestion suggestion,
  ) {
    return _enqueueWrite(() async {
      await _recoverySnapshotStorage.create(
        reason: 'beforeSuggestionTombstone',
      );
      await _syncMetadataStorage.markSuggestionDirty(suggestion.id);

      final current = await loadSuggestionsRaw();
      final index = current.indexWhere((s) => s.id == suggestion.id);
      final now = _clock.now();
      final tombstoned = suggestion.copyWith(deletedAt: now, updatedAt: now);

      if (index >= 0) {
        current[index] = tombstoned;
      } else {
        current.add(tombstoned);
      }

      await writeSuggestionsRaw(current);
      return tombstoned;
    });
  }

  /// **Raw/bulk persistence path.** Preserves every supplied timestamp
  /// exactly as given — never stamps `updatedAt`, never marks anything
  /// dirty. Reserved for migration, a future cloud-restore path, and tests
  /// that need exact timestamps. Production mutation call sites must use
  /// [upsertSuggestion]/[tombstoneSuggestion] instead.
  ///
  /// Throws a [StateError] if no local namespace is currently available, to
  /// avoid silently dropping a save.
  Future<void> saveSuggestions(List<AdaptiveHabitSuggestion> suggestions) {
    return _enqueueWrite(() => writeSuggestionsRaw(suggestions));
  }

  /// Actual unqueued write, shared by [saveSuggestions], [upsertSuggestion],
  /// and [tombstoneSuggestion]. Deliberately not private (and not queued
  /// itself) so test fakes can subclass and override this single choke
  /// point — see `HabitStorage.writeHabitsRaw` for the full rationale.
  Future<void> writeSuggestionsRaw(
    List<AdaptiveHabitSuggestion> suggestions,
  ) async {
    final result = _namespaceResolver.resolveKey(_suggestionsBaseKey);
    if (!result.isAvailable) {
      throw StateError(
        'AdaptiveSuggestionStorage.saveSuggestions: no local namespace available',
      );
    }
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(suggestions.map((s) => s.toJson()).toList());
    await prefs.setString(result.key!, encoded);
  }
}
