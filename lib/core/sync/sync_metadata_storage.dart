import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../storage/local_namespace_resolver.dart';
import '../time/clock.dart';
import 'sync_metadata.dart';

/// Local persistence for [SyncMetadata], namespaced per UID like the other
/// user-owned storage classes. Local-only in Phase 1C — no network calls,
/// no cloud table.
class SyncMetadataStorage {
  static const _baseKey = 'sync_metadata';

  final LocalNamespaceResolver _namespaceResolver;
  final Clock _clock;

  /// Serializes every write through this instance — same pattern as
  /// `HabitStorage`/`AdaptiveSuggestionStorage`: a load→modify→save
  /// mutation must not interleave with another one on the same instance.
  Future<void> _writeQueue = Future.value();

  SyncMetadataStorage({LocalNamespaceResolver? namespaceResolver, Clock? clock})
    : _namespaceResolver = namespaceResolver ?? const LocalNamespaceResolver(),
      _clock = clock ?? const SystemClock();

  Future<T> _enqueueWrite<T>(Future<T> Function() action) {
    final result = _writeQueue.then((_) => action());
    _writeQueue = result.then((_) {}, onError: (_) {});
    return result;
  }

  /// Loads the current metadata, or [SyncMetadata.empty] if nothing has
  /// been saved yet, the data is malformed, or no namespace is available
  /// (never another identity's data — an unavailable namespace always
  /// yields safe, empty defaults, never a fallback read of another UID).
  Future<SyncMetadata> load() async {
    final result = _namespaceResolver.resolveKey(_baseKey);
    if (!result.isAvailable) return SyncMetadata.empty;

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(result.key!);
    if (raw == null) return SyncMetadata.empty;

    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return SyncMetadata.fromJson(decoded);
    } catch (_) {
      return SyncMetadata.empty;
    }
  }

  /// Raw/bulk persistence: saves [metadata] exactly as given, queued behind
  /// any other in-flight write on this instance. Throws a [StateError] if
  /// no namespace is available.
  Future<void> save(SyncMetadata metadata) {
    return _enqueueWrite(() => _saveUnqueued(metadata));
  }

  Future<void> _saveUnqueued(SyncMetadata metadata) async {
    final result = _namespaceResolver.resolveKey(_baseKey);
    if (!result.isAvailable) {
      throw StateError(
        'SyncMetadataStorage.save: no local namespace available',
      );
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(result.key!, jsonEncode(metadata.toJson()));
  }

  Future<SyncMetadata> _update(
    SyncMetadata Function(SyncMetadata current) transform,
  ) {
    return _enqueueWrite(() async {
      final current = await load();
      final updated = transform(current);
      await _saveUnqueued(updated);
      return updated;
    });
  }

  /// Marks [habitId] dirty. Idempotent — adding an id already present is a
  /// no-op change.
  Future<SyncMetadata> markHabitDirty(String habitId) {
    return _update(
      (current) =>
          current.copyWith(dirtyHabitIds: {...current.dirtyHabitIds, habitId}),
    );
  }

  /// Marks [suggestionId] dirty. Idempotent.
  Future<SyncMetadata> markSuggestionDirty(String suggestionId) {
    return _update(
      (current) => current.copyWith(
        dirtySuggestionIds: {...current.dirtySuggestionIds, suggestionId},
      ),
    );
  }

  /// Marks preferences dirty. Idempotent.
  Future<SyncMetadata> markPreferencesDirty() {
    return _update((current) => current.copyWith(preferencesDirty: true));
  }

  /// Records that a sync attempt just started, using the injected [Clock].
  /// Not used by anything in Phase 1C (no sync exists yet) — exposed for
  /// the future sync engine to call.
  Future<SyncMetadata> recordSyncAttempt() {
    return _update(
      (current) => current.copyWith(lastSyncAttemptAt: _clock.now()),
    );
  }
}
