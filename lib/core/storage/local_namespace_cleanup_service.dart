import 'package:shared_preferences/shared_preferences.dart';

/// Every namespaced local storage base key that belongs to a single UID's
/// data. Kept as one explicit list so this is the single place that has to
/// stay in sync when a new namespaced storage class is added — the same
/// discipline `LocalNamespaceResolver` already applies to key
/// construction.
const _namespacedBaseKeys = [
  'habits',
  'adaptive_suggestions',
  'app_settings',
  'sync_metadata',
  'recovery_snapshot',
  'local_schema_version',
];

/// Permanently removes one specific UID's entire local namespace.
///
/// This is the **only** approved place in the app that performs a bulk,
/// physical removal of namespaced local data — every other storage class
/// only ever tombstones or namespace-scopes its reads/writes. It exists
/// for account deletion (Phase 7): once an account is confirmed deleted
/// server-side, there is no reason to keep its local data around, and no
/// future recovery path that would ever need it.
///
/// Takes an explicit [uid] rather than reading the *current* active
/// namespace, so a caller can never accidentally wipe whichever identity
/// happens to be active at call time — it always wipes exactly the UID it
/// was told to, nothing else.
class LocalNamespaceCleanupService {
  const LocalNamespaceCleanupService();

  /// Removes every namespaced key for [uid]. Never touches any other UID's
  /// keys. Safe to call even if some or all keys are already absent.
  Future<void> wipeNamespace(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    for (final baseKey in _namespacedBaseKeys) {
      await prefs.remove('$baseKey:$uid');
    }
  }
}
