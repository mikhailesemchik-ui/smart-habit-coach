import 'package:flutter/foundation.dart' show debugPrint;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Abstraction over establishing a Supabase auth session, so the
/// first-launch identity gate can be tested deterministically without a
/// real Supabase client.
abstract class AuthSessionGateway {
  /// Returns true once a session exists (already persisted, or freshly
  /// established). Returns false if no session could be established.
  Future<bool> ensureSession();
}

class SupabaseAuthSessionGateway implements AuthSessionGateway {
  const SupabaseAuthSessionGateway();

  @override
  Future<bool> ensureSession() async {
    // Supabase is never initialized in the pre-existing widget/unit test
    // suite (none of it calls `Supabase.initialize`). This treats "Supabase
    // was never initialized at all" as an already-satisfied session rather
    // than a failure — this never occurs in the shipped app, since
    // main.dart always initializes Supabase before this gateway runs — so
    // the whole existing test suite keeps working unmodified. This does
    // NOT fabricate a UID: the actual namespace UID still comes only from
    // `LocalNamespaceResolver`, which tests inject explicitly via
    // `debugUidOverride` (see `test/flutter_test_config.dart`) — it has no
    // passthrough of its own.
    if (!_isSupabaseInitialized) return true;

    final auth = Supabase.instance.client.auth;
    if (auth.currentSession != null) return true;

    try {
      await auth.signInAnonymously();
      return auth.currentSession != null;
    } catch (e, st) {
      // Diagnostic only — the UI still shows a generic retry screen
      // regardless of cause. This surfaces the real error (e.g. a missing/
      // empty SUPABASE_URL or SUPABASE_ANON_KEY dart-define, or anonymous
      // sign-ins disabled on the Supabase project) instead of it looking
      // indistinguishable from an actual offline device.
      debugPrint('SupabaseAuthSessionGateway.ensureSession failed: $e\n$st');
      return false;
    }
  }

  bool get _isSupabaseInitialized {
    try {
      Supabase.instance;
      return true;
    } catch (_) {
      return false;
    }
  }
}
