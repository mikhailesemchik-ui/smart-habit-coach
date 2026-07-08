import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// A single, ordered local schema migration step.
///
/// [targetVersion] is the version reached once this step succeeds.
/// [migrate] receives the currently-decoded JSON value stored at a
/// namespaced key (or `null` if nothing is stored yet) and returns the
/// migrated value to persist. Steps must be pure and side-effect free
/// beyond their return value — the runner handles reading/writing.
class LocalSchemaMigrationStep {
  final int targetVersion;
  final Object? Function(Object? current) migrate;

  const LocalSchemaMigrationStep({
    required this.targetVersion,
    required this.migrate,
  });
}

/// Runs a linear list of [LocalSchemaMigrationStep]s against one namespaced
/// storage key, tracking the applied version at a separate namespaced
/// version key.
///
/// Requirements this satisfies:
/// - migrations run in order, never skipping or reordering;
/// - re-running is idempotent (a step already applied — i.e. the stored
///   version already meets or exceeds its target — is skipped);
/// - a failed step does not advance the stored version, so it is retried
///   safely on the next run;
/// - no blanket reset: only the specific migration's transform touches the
///   stored value, and only after every earlier step has already
///   succeeded.
class LocalSchemaMigrationRunner {
  final String dataKey;
  final String versionKey;
  final List<LocalSchemaMigrationStep> steps;

  const LocalSchemaMigrationRunner({
    required this.dataKey,
    required this.versionKey,
    required this.steps,
  });

  /// Applies every step whose [LocalSchemaMigrationStep.targetVersion] is
  /// greater than the currently-recorded version, in order. Returns the
  /// final version reached (may be unchanged if nothing needed to run, or
  /// stop early if a step throws — the exception propagates so callers can
  /// decide how to handle a failed migration; nothing is marked complete
  /// for a step that did not finish).
  Future<int> run() async {
    final prefs = await SharedPreferences.getInstance();
    var version = prefs.getInt(versionKey) ?? 0;

    for (final step in steps) {
      if (step.targetVersion <= version) continue;

      final raw = prefs.getString(dataKey);
      Object? current;
      if (raw != null) {
        try {
          current = jsonDecode(raw);
        } catch (_) {
          current = null;
        }
      }

      final migrated = step.migrate(current);
      await prefs.setString(dataKey, jsonEncode(migrated));
      version = step.targetVersion;
      await prefs.setInt(versionKey, version);
    }

    return version;
  }
}
