import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'local_namespace_resolver.dart';

/// Returns the single timestamp used for every record backfilled during
/// one migration run. Injectable so tests can assert every migrated
/// record receives exactly the same value, and so migration never calls
/// `DateTime.now()` once per record.
typedef MigrationClock = DateTime Function();

DateTime _systemClock() => DateTime.now().toUtc();

/// Migrates the per-UID local user-data schema (namespaced `habits` and
/// `adaptive_suggestions`) in place, tracking one schema version per UID
/// at `local_schema_version:<uid>`.
///
/// Schema versions:
/// - **0** (implicit — no version has ever been recorded): the
///   pre-Phase-1A shape. Records may be entirely missing `createdAt` /
///   `updatedAt`; `deletedAt` never existed.
/// - **1** (`targetVersion`): every stored habit/suggestion record has
///   `createdAt` and `updatedAt` populated — backfilled with one
///   deterministic migration timestamp for every record touched in a
///   single run, never `DateTime.now()` per record. `deletedAt` is left
///   absent/null unless a record already had it; this migration never
///   introduces a tombstone.
///
/// The version is written only after every category's backfill succeeds;
/// a failure (e.g. corrupt low-level write) leaves the version untouched
/// so the next run retries from scratch. Malformed individual records
/// (non-`Map` list entries) and unparseable/non-list top-level data are
/// preserved byte-for-byte rather than destructively rewritten — the
/// existing per-record-tolerant storage readers already handle that shape
/// at load time. Unknown JSON fields on valid records survive because
/// this migration edits the raw decoded JSON map directly rather than
/// round-tripping through the strongly-typed `Habit`/
/// `AdaptiveHabitSuggestion` models.
///
/// The model-level `DateTime.utc(2000, 1, 1)` fallback in
/// `Habit.fromJson` / `AdaptiveHabitSuggestion.fromJson` remains as
/// defensive parsing for any record this migration hasn't reached (or a
/// malformed timestamp value) — it does not replace this persisted,
/// one-time migration.
class LocalUserDataSchemaMigrator {
  static const targetVersion = 1;
  static const _habitsBaseKey = 'habits';
  static const _suggestionsBaseKey = 'adaptive_suggestions';
  static const _versionBaseKey = 'local_schema_version';

  final LocalNamespaceResolver _namespaceResolver;
  final MigrationClock _clock;

  LocalUserDataSchemaMigrator({
    LocalNamespaceResolver? namespaceResolver,
    MigrationClock clock = _systemClock,
  }) : _namespaceResolver = namespaceResolver ?? const LocalNamespaceResolver(),
       _clock = clock;

  /// Runs the migration for the currently active UID's namespace.
  ///
  /// Returns `false` without writing anything if no real, non-blank UID is
  /// currently available — callers must not invoke this before a UID
  /// exists. Returns `true` once the active namespace is confirmed at
  /// [targetVersion] (whether this call just migrated it, it was already
  /// there, or there is simply nothing stored yet to migrate).
  Future<bool> run() async {
    final uid = _namespaceResolver.currentUid;
    if (uid == null) return false;

    final prefs = await SharedPreferences.getInstance();
    final versionKey = '$_versionBaseKey:$uid';
    final version = prefs.getInt(versionKey) ?? 0;
    if (version >= targetVersion) return true;

    final timestamp = _clock().toIso8601String();

    try {
      await _backfillTimestamps(prefs, '$_habitsBaseKey:$uid', timestamp);
      await _backfillTimestamps(prefs, '$_suggestionsBaseKey:$uid', timestamp);
    } catch (_) {
      // Do not advance the version on failure; safe to retry on next run.
      return false;
    }

    await prefs.setInt(versionKey, targetVersion);
    return true;
  }

  Future<void> _backfillTimestamps(
    SharedPreferences prefs,
    String key,
    String timestamp,
  ) async {
    final raw = prefs.getString(key);
    if (raw == null) return; // Nothing stored under this key yet.

    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      // Unparseable data is left untouched, not destructively rewritten —
      // the storage readers already tolerate this shape at load time.
      return;
    }
    if (decoded is! List) return;

    final migrated = decoded.map((item) {
      if (item is! Map) return item; // Preserve malformed entries verbatim.
      final map = Map<String, dynamic>.from(item);
      map.putIfAbsent('createdAt', () => timestamp);
      map.putIfAbsent('updatedAt', () => timestamp);
      return map;
    }).toList();

    await prefs.setString(key, jsonEncode(migrated));
  }
}
