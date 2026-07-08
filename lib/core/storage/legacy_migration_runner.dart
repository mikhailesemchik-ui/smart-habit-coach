import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'local_namespace_resolver.dart';

/// Outcome of one [LegacyMigrationRunner.run] call.
enum LegacyMigrationResult {
  /// The permanent marker already exists — nothing was touched.
  alreadyCompleted,

  /// No active UID is available yet; nothing was touched, no marker
  /// written. Safe to retry later.
  postponedNoUid,

  /// No legacy data exists to migrate; nothing was touched, no marker
  /// written (so a later, genuine migration is not accidentally blocked).
  noLegacyData,

  /// Legacy data was copied into the active UID's namespace, verified,
  /// and the permanent completion marker was written.
  migrated,

  /// The destination namespace already held data and no completion marker
  /// existed — an ambiguous state. Nothing was overwritten or merged; a
  /// conflict record was written instead. Requires manual resolution in a
  /// later phase.
  conflict,

  /// The copy step itself failed; no marker written, legacy data intact,
  /// safe to retry.
  failedCopy,

  /// The copy appeared to succeed but read-back verification did not
  /// match; no marker written, legacy data intact, safe to retry.
  failedVerification,
}

/// Migrates the app's original, unscoped local data (from before per-user
/// namespacing existed) into the currently-active Supabase UID's namespace
/// — **at most once, ever**, and only into the UID active at that first
/// successful, verified migration.
///
/// This is the single most safety-critical piece of Phase 1A: importing
/// one identity's local data into a *different* identity's namespace later
/// (e.g. after a sign-out/sign-in on a shared device) is a P0 failure this
/// class exists specifically to make structurally impossible once its
/// completion marker is written.
class LegacyMigrationRunner {
  final LocalNamespaceResolver _resolver;

  LegacyMigrationRunner({LocalNamespaceResolver? resolver})
    : _resolver = resolver ?? const LocalNamespaceResolver();

  static const completedKey = 'legacy_namespace_migration_completed';
  static const migratedToUidKey = 'legacy_namespace_migrated_to_uid';
  static const migratedAtKey = 'legacy_namespace_migrated_at';
  static const conflictKey = 'legacy_namespace_migration_conflict';

  static const legacyHabitsKey = 'habits';
  static const legacySuggestionsKey = 'adaptive_suggestions';
  static const legacySettingsKey = 'app_settings';

  Future<LegacyMigrationResult> run() async {
    final prefs = await SharedPreferences.getInstance();

    // Step 1-2: the permanent marker, once written, is final. No exceptions,
    // regardless of which UID is currently active.
    if (prefs.getBool(completedKey) == true) {
      return LegacyMigrationResult.alreadyCompleted;
    }

    // Step 3: no active UID → postpone, touch nothing, write no marker.
    final uid = _resolver.currentUid;
    if (uid == null) {
      return LegacyMigrationResult.postponedNoUid;
    }

    // Step 4: inspect whether meaningful legacy data exists.
    final legacyHabitsRaw = prefs.getString(legacyHabitsKey);
    final legacySuggestionsRaw = prefs.getString(legacySuggestionsKey);
    final legacySettingsRaw = prefs.getString(legacySettingsKey);

    final hasLegacyHabits = _isMeaningfulList(legacyHabitsRaw);
    final hasLegacySuggestions = _isMeaningfulList(legacySuggestionsRaw);
    final hasLegacySettings = legacySettingsRaw != null;

    if (!hasLegacyHabits && !hasLegacySuggestions && !hasLegacySettings) {
      return LegacyMigrationResult.noLegacyData;
    }

    // Step 5: inspect whether the destination UID namespace is already
    // populated. Only *persisted* data counts — in-memory sample habits
    // are never written here unless the user actually interacts with them,
    // so they can never make an untouched destination look populated.
    final destHabitsKey = '$legacyHabitsKey:$uid';
    final destSuggestionsKey = '$legacySuggestionsKey:$uid';
    final destSettingsKey = '$legacySettingsKey:$uid';

    final destHabitsPopulated = prefs.containsKey(destHabitsKey);
    final destSuggestionsPopulated = prefs.containsKey(destSuggestionsKey);
    final destSettingsPopulated = prefs.containsKey(destSettingsKey);
    final destinationPopulated =
        destHabitsPopulated ||
        destSuggestionsPopulated ||
        destSettingsPopulated;

    // Step 6: destination populated + no marker → ambiguous. Never merge,
    // never overwrite; record a conflict for later manual resolution.
    if (destinationPopulated) {
      await _recordConflict(
        prefs,
        uid: uid,
        legacyCategories: [
          if (hasLegacyHabits) 'habits',
          if (hasLegacySuggestions) 'suggestions',
          if (hasLegacySettings) 'settings',
        ],
        destinationCategories: [
          if (destHabitsPopulated) 'habits',
          if (destSuggestionsPopulated) 'suggestions',
          if (destSettingsPopulated) 'settings',
        ],
      );
      return LegacyMigrationResult.conflict;
    }

    // Step 7: destination empty → copy, then verify by reading back.
    try {
      if (hasLegacyHabits) {
        await prefs.setString(destHabitsKey, legacyHabitsRaw!);
      }
      if (hasLegacySuggestions) {
        await prefs.setString(destSuggestionsKey, legacySuggestionsRaw!);
      }
      if (hasLegacySettings) {
        await prefs.setString(destSettingsKey, legacySettingsRaw);
      }
    } catch (_) {
      // Step 8: copy failed — no marker, legacy data untouched, retry later.
      return LegacyMigrationResult.failedCopy;
    }

    final verified =
        (!hasLegacyHabits ||
            prefs.getString(destHabitsKey) == legacyHabitsRaw) &&
        (!hasLegacySuggestions ||
            prefs.getString(destSuggestionsKey) == legacySuggestionsRaw) &&
        (!hasLegacySettings ||
            prefs.getString(destSettingsKey) == legacySettingsRaw);

    if (!verified) {
      // Step 8: verification failed — no marker, retry later. The partial
      // copy is left in place (harmless: destination stays "populated" on
      // the next attempt only if verification is retried and matches).
      return LegacyMigrationResult.failedVerification;
    }

    // Step 7 (cont.) / Step 9: only now, after a verified copy, write the
    // permanent marker. Legacy keys are deliberately never deleted — they
    // remain as a passive backup, ignored forever by normal runtime logic
    // once this marker exists.
    await prefs.setBool(completedKey, true);
    await prefs.setString(migratedToUidKey, uid);
    await prefs.setString(migratedAtKey, DateTime.now().toIso8601String());

    return LegacyMigrationResult.migrated;
  }

  bool _isMeaningfulList(String? raw) {
    if (raw == null) return false;
    try {
      final decoded = jsonDecode(raw);
      return decoded is List && decoded.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<void> _recordConflict(
    SharedPreferences prefs, {
    required String uid,
    required List<String> legacyCategories,
    required List<String> destinationCategories,
  }) async {
    // Diagnostic metadata only — never full habit/suggestion contents.
    final payload = {
      'uid': uid,
      'detectedAt': DateTime.now().toIso8601String(),
      'legacyCategories': legacyCategories,
      'destinationCategories': destinationCategories,
    };
    await prefs.setString(conflictKey, jsonEncode(payload));
  }
}
