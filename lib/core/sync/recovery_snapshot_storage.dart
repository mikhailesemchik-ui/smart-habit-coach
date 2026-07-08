import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../features/coach/data/adaptive_suggestion_storage.dart';
import '../../features/home/data/habit_storage.dart';
import '../../features/profile/data/settings_storage.dart';
import '../storage/local_namespace_resolver.dart';
import '../time/clock.dart';
import 'recovery_snapshot.dart';
import 'sync_metadata_storage.dart';

/// Local-only "last known good" backup of a UID's raw user-owned data,
/// captured immediately before a destructive or conflict-prone replacement
/// (e.g. tombstone delete). Only the single latest snapshot is kept — a
/// new [create] call replaces whatever was there before.
///
/// No restore UI and no automatic restore exist yet (Phase 1C only builds
/// the create/read/clear primitives); a future sync engine is expected to
/// call [create] before its own conflict-resolution replacements too.
class RecoverySnapshotStorage {
  static const _baseKey = 'recovery_snapshot';

  final LocalNamespaceResolver _namespaceResolver;
  final Clock _clock;
  final HabitStorage _habitStorage;
  final AdaptiveSuggestionStorage _suggestionStorage;
  final SettingsStorage _settingsStorage;
  final SyncMetadataStorage _syncMetadataStorage;

  Future<void> _writeQueue = Future.value();

  RecoverySnapshotStorage({
    LocalNamespaceResolver? namespaceResolver,
    Clock? clock,
    HabitStorage? habitStorage,
    AdaptiveSuggestionStorage? suggestionStorage,
    SettingsStorage? settingsStorage,
    SyncMetadataStorage? syncMetadataStorage,
  }) : _namespaceResolver = namespaceResolver ?? const LocalNamespaceResolver(),
       _clock = clock ?? const SystemClock(),
       _habitStorage = habitStorage ?? HabitStorage(),
       _suggestionStorage = suggestionStorage ?? AdaptiveSuggestionStorage(),
       _settingsStorage = settingsStorage ?? SettingsStorage(),
       _syncMetadataStorage = syncMetadataStorage ?? SyncMetadataStorage();

  Future<T> _enqueueWrite<T>(Future<T> Function() action) {
    final result = _writeQueue.then((_) => action());
    _writeQueue = result.then((_) {}, onError: (_) {});
    return result;
  }

  /// Captures the full current raw dataset (habits and suggestions
  /// including tombstones, settings, sync metadata) for the active
  /// namespace and persists it as the single latest snapshot, tagged with
  /// [reason]. Throws a [StateError] if no namespace is available.
  Future<RecoverySnapshot> create({required String reason}) {
    return _enqueueWrite(() async {
      final result = _namespaceResolver.resolveKey(_baseKey);
      if (!result.isAvailable) {
        throw StateError(
          'RecoverySnapshotStorage.create: no local namespace available',
        );
      }

      final habits = await _habitStorage.loadHabitsRaw() ?? [];
      final suggestions = await _suggestionStorage.loadSuggestionsRaw();
      final settings = await _settingsStorage.loadSettings();
      final syncMetadata = await _syncMetadataStorage.load();

      final snapshot = RecoverySnapshot(
        createdAt: _clock.now(),
        reason: reason,
        habits: habits.map((h) => h.toJson()).toList(),
        suggestions: suggestions.map((s) => s.toJson()).toList(),
        settings: settings.toJson(),
        syncMetadata: syncMetadata.toJson(),
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(result.key!, jsonEncode(snapshot.toJson()));
      return snapshot;
    });
  }

  /// Reads the current snapshot, or `null` if none exists, it is
  /// malformed, or no namespace is available.
  Future<RecoverySnapshot?> read() async {
    final result = _namespaceResolver.resolveKey(_baseKey);
    if (!result.isAvailable) return null;

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(result.key!);
    if (raw == null) return null;

    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return RecoverySnapshot.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  /// Removes the current snapshot, if any.
  Future<void> clear() {
    return _enqueueWrite(() async {
      final result = _namespaceResolver.resolveKey(_baseKey);
      if (!result.isAvailable) return;
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(result.key!);
    });
  }
}
