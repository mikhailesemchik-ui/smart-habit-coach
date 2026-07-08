import 'package:smart_habit_coach/features/auth/data/auth_repository.dart';
import 'package:smart_habit_coach/features/auth/domain/auth_error.dart';
import 'package:smart_habit_coach/features/auth/domain/auth_identity.dart';
import 'package:smart_habit_coach/features/auth/domain/auth_result.dart';

/// Deterministic fake for [AuthRepository]: no real Supabase client, no
/// network. Behavior is configured per test via constructor fields.
class FakeAuthRepository implements AuthRepository {
  AuthIdentity _identity;
  final bool anonymousSessionSucceeds;
  final AuthFailure? linkFailure;
  final AuthFailure? signInFailure;
  final AuthFailure? signOutFailure;
  final String anonymousUid;

  /// If non-null, the uid reported after a successful link call. This lets
  /// tests simulate the defensive identity-changed invariant.
  final String? linkResultUidOverride;

  final bool linkedEmailConfirmed;
  final AuthIdentity? signInIdentity;

  int ensureAnonymousSessionCallCount = 0;
  int signInWithEmailPasswordCallCount = 0;
  int linkEmailPasswordCallCount = 0;
  int signOutCallCount = 0;

  FakeAuthRepository({
    AuthIdentity? initialIdentity,
    this.anonymousSessionSucceeds = true,
    this.linkFailure,
    this.signInFailure,
    this.signOutFailure,
    this.anonymousUid = 'anon-uid',
    this.linkResultUidOverride,
    this.linkedEmailConfirmed = true,
    this.signInIdentity,
  }) : _identity = initialIdentity ?? AuthIdentity.unauthenticated;

  @override
  AuthIdentity currentIdentity() => _identity;

  @override
  Future<AuthResult<AuthIdentity>> ensureAnonymousSession() async {
    ensureAnonymousSessionCallCount++;
    if (_identity.kind != AuthIdentityKind.unauthenticated) {
      return AuthResult.success(_identity);
    }
    if (!anonymousSessionSucceeds) {
      return AuthResult.failure(
        const AuthFailure(
          AuthErrorCode.networkUnavailable,
          'Could not reach the server.',
        ),
      );
    }
    _identity = AuthIdentity(
      uid: anonymousUid,
      kind: AuthIdentityKind.anonymous,
    );
    return AuthResult.success(_identity);
  }

  @override
  Future<AuthResult<AuthIdentity>> linkEmailPassword({
    required String email,
    required String password,
  }) async {
    linkEmailPasswordCallCount++;
    if (_identity.kind != AuthIdentityKind.anonymous) {
      return AuthResult.failure(
        const AuthFailure(
          AuthErrorCode.sessionMissing,
          'No anonymous session to link.',
        ),
      );
    }
    if (linkFailure != null) {
      return AuthResult.failure(linkFailure!);
    }
    final resultUid = linkResultUidOverride ?? _identity.uid;
    if (resultUid != _identity.uid) {
      return AuthResult.failure(
        const AuthFailure(
          AuthErrorCode.identityChangedUnexpectedly,
          'The account identity changed unexpectedly during linking.',
        ),
      );
    }
    _identity = AuthIdentity(
      uid: resultUid,
      kind: AuthIdentityKind.linkedEmail,
      email: email,
      emailConfirmed: linkedEmailConfirmed,
    );
    return AuthResult.success(_identity);
  }

  @override
  Future<AuthResult<AuthIdentity>> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {
    signInWithEmailPasswordCallCount++;
    if (signInFailure != null) {
      return AuthResult.failure(signInFailure!);
    }
    _identity =
        signInIdentity ??
        AuthIdentity(
          uid: 'returning-uid',
          kind: AuthIdentityKind.authenticatedReturningUser,
          email: email,
          emailConfirmed: true,
        );
    return AuthResult.success(_identity);
  }

  @override
  Future<AuthResult<void>> signOut() async {
    signOutCallCount++;
    if (signOutFailure != null) {
      return AuthResult.failure(signOutFailure!);
    }
    _identity = AuthIdentity.unauthenticated;
    return AuthResult.success(null);
  }
}
