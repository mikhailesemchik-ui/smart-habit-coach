import '../domain/auth_identity.dart';
import '../domain/auth_result.dart';

/// Injectable boundary around Supabase auth. Presentation and
/// orchestration code depend only on this interface (and
/// [AuthIdentity]/[AuthResult]), never on `supabase_flutter`/`gotrue`
/// types directly, so both can be tested with a fake and swapped without
/// touching call sites.
abstract interface class AuthRepository {
  /// Reads the current identity without making a network call.
  /// [AuthIdentityKind.unauthenticated] if there is no session.
  AuthIdentity currentIdentity();

  /// Establishes an anonymous session if none exists yet; returns the
  /// existing identity unchanged if one already does. This is the
  /// first-launch mechanism — see `AuthSessionGateway` (Phase 1A), which
  /// this repository is intended to eventually back.
  Future<AuthResult<AuthIdentity>> ensureAnonymousSession();

  /// Upgrades the *current* anonymous session in place by attaching an
  /// email/password credential — the uid must not change. Returns
  /// [AuthErrorCode.sessionMissing] if there is no anonymous session to
  /// link, and [AuthErrorCode.identityChangedUnexpectedly] if the uid
  /// changed after the operation (a defensive check; not expected to ever
  /// trigger given the SDK's documented `updateUser` behavior, but the
  /// invariant is never assumed silently).
  Future<AuthResult<AuthIdentity>> linkEmailPassword({
    required String email,
    required String password,
  });

  /// Signs in as a returning, previously-registered email user. This is a
  /// *different* identity than whatever anonymous uid was active before
  /// the call — callers must decide what to do with the outgoing
  /// anonymous namespace (see `ReturningUserSignInService`) before
  /// calling this.
  Future<AuthResult<AuthIdentity>> signInWithEmailPassword({
    required String email,
    required String password,
  });

  /// Signs out the current session. Does not touch any local namespaced
  /// data. Establishing a new anonymous identity afterward is a separate,
  /// explicit step (the existing first-launch mechanism), never automatic
  /// here.
  Future<AuthResult<void>> signOut();
}
