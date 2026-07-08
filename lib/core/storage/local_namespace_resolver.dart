import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Result of resolving a namespaced local storage key.
class NamespaceKeyResult {
  final String? key;
  final bool isAvailable;

  const NamespaceKeyResult._(this.key, this.isAvailable);

  factory NamespaceKeyResult.available(String key) =>
      NamespaceKeyResult._(key, true);

  factory NamespaceKeyResult.unavailable() =>
      const NamespaceKeyResult._(null, false);
}

/// Resolves the Supabase auth UID that scopes all local, user-owned
/// storage, and builds the namespaced keys storage classes read/write.
///
/// Production code must never guess or fabricate a UID, and must never
/// fall back to an unscoped key for any reason — not a missing session,
/// not a blank UID, and not an uninitialized Supabase client. [currentUid]
/// and [resolveKey] both return an explicit "unavailable" state in every
/// one of those cases; there is no passthrough. The only code path
/// permitted to read or write the old unscoped keys is
/// `LegacyMigrationRunner`, which uses its own hardcoded legacy key
/// constants, never this resolver.
class LocalNamespaceResolver {
  const LocalNamespaceResolver();

  /// Test-only override for the active UID. Must only ever be set from
  /// test code (see `@visibleForTesting`) — production never touches
  /// this. Tests inject a stable fake UID (e.g. `'test-user-id'`) here
  /// instead of initializing a real Supabase client.
  @visibleForTesting
  static String? debugUidOverride;

  /// The active, real Supabase auth UID, or null when it is unavailable
  /// for any reason: no session, a blank UID, or Supabase never having
  /// been initialized. Never guessed, generated, or shared.
  String? get currentUid {
    final override = debugUidOverride;
    if (override != null && override.trim().isNotEmpty) return override;
    if (!_isSupabaseInitialized) return null;
    final uid = Supabase.instance.client.auth.currentSession?.user.id;
    if (uid == null || uid.trim().isEmpty) return null;
    return uid;
  }

  bool get _isSupabaseInitialized {
    try {
      Supabase.instance;
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Resolves the namespaced key for [baseKey] (e.g. `habits`).
  ///
  /// Returns `<baseKey>:<uid>` only when [currentUid] is a real, non-blank
  /// UID. Returns [NamespaceKeyResult.unavailable] in every other case —
  /// there is no unscoped fallback, regardless of why a UID is missing.
  NamespaceKeyResult resolveKey(String baseKey) {
    final uid = currentUid;
    if (uid == null) return NamespaceKeyResult.unavailable();
    return NamespaceKeyResult.available('$baseKey:$uid');
  }
}
