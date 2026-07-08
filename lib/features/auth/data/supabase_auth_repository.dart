import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/auth_error.dart';
import '../domain/auth_identity.dart';
import '../domain/auth_result.dart';
import 'auth_repository.dart';

/// Concrete [AuthRepository] backed by `supabase_flutter`'s
/// `GoTrueClient` (installed `supabase_flutter: ^2.15.0`,
/// `gotrue: 2.22.0`, confirmed via the resolved `pubspec.lock`).
///
/// **Anonymous-to-email linking**: `GoTrueClient.updateUser(UserAttributes
/// (email: ..., password: ...))` is the confirmed mechanism. Inspecting
/// the installed SDK source (`gotrue_client.dart`): `updateUser` sends a
/// `PUT /user` using the *current* session's access token and then does
/// `_currentSession = currentSession?.copyWith(user: userResponse.user)`
/// — it only ever replaces the `user` field of the existing session
/// object; nothing in this path constructs a new session or a new user
/// id. The uid is therefore preserved by construction, not by
/// coincidence. This repository still re-reads and compares the uid
/// after the call (see [linkEmailPassword]) as a defensive check, per the
/// approved plan's "verify, don't just assume" requirement — but no
/// workaround was needed; the SDK already supports the invariant.
///
/// **Anonymous flag**: `User.isAnonymous` (a plain `bool` field) is read
/// directly off the SDK's `User` object — confirmed present in
/// `gotrue`'s `types/user.dart`.
///
/// **Auth state changes**: `GoTrueClient.onAuthStateChange` is a
/// `Stream<AuthState>` (`SIGNED_IN`, `SIGNED_OUT`, `USER_UPDATED`, etc. —
/// `AuthChangeEvent` enum in `gotrue`'s `constants.dart`). Not consumed by
/// this Phase 2A spike (no UI to react yet), but the SDK's support is
/// confirmed for Phase 2B.
class SupabaseAuthRepository implements AuthRepository {
  final GoTrueClient _auth;

  SupabaseAuthRepository({GoTrueClient? auth})
    : _auth = auth ?? Supabase.instance.client.auth;

  @override
  AuthIdentity currentIdentity() {
    final user = _auth.currentSession?.user;
    if (user == null) return AuthIdentity.unauthenticated;
    return _identityFromUser(user, _kindForUser(user));
  }

  @override
  Future<AuthResult<AuthIdentity>> ensureAnonymousSession() async {
    final existing = _auth.currentSession?.user;
    if (existing != null) {
      return AuthResult.success(
        _identityFromUser(existing, _kindForUser(existing)),
      );
    }
    try {
      final response = await _auth.signInAnonymously();
      final user = response.user;
      if (user == null) {
        return AuthResult.failure(
          const AuthFailure(
            AuthErrorCode.unknown,
            'Could not establish a session.',
          ),
        );
      }
      return AuthResult.success(
        _identityFromUser(user, AuthIdentityKind.anonymous),
      );
    } catch (error) {
      return AuthResult.failure(mapAuthException(error));
    }
  }

  @override
  Future<AuthResult<AuthIdentity>> linkEmailPassword({
    required String email,
    required String password,
  }) async {
    final localFormatError = _validateEmailFormat(email);
    if (localFormatError != null) {
      return AuthResult.failure(localFormatError);
    }

    final before = _auth.currentSession?.user;
    if (before == null || !before.isAnonymous) {
      return AuthResult.failure(
        const AuthFailure(
          AuthErrorCode.sessionMissing,
          'No anonymous session to link.',
        ),
      );
    }
    final beforeUid = before.id;

    try {
      final response = await _auth.updateUser(
        UserAttributes(email: email, password: password),
      );
      final after = response.user ?? _auth.currentSession?.user;
      if (after == null) {
        return AuthResult.failure(
          const AuthFailure(
            AuthErrorCode.unknown,
            'Linking did not return a user.',
          ),
        );
      }
      if (after.id != beforeUid) {
        // Never expected given the SDK's updateUser implementation (see
        // class doc), but checked explicitly rather than assumed.
        return AuthResult.failure(
          const AuthFailure(
            AuthErrorCode.identityChangedUnexpectedly,
            'The account identity changed unexpectedly during linking.',
          ),
        );
      }
      return AuthResult.success(
        _identityFromUser(after, AuthIdentityKind.linkedEmail),
      );
    } catch (error) {
      return AuthResult.failure(mapAuthException(error));
    }
  }

  @override
  Future<AuthResult<AuthIdentity>> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {
    final localFormatError = _validateEmailFormat(email);
    if (localFormatError != null) {
      return AuthResult.failure(localFormatError);
    }

    try {
      final response = await _auth.signInWithPassword(
        email: email,
        password: password,
      );
      final user = response.user;
      if (user == null) {
        return AuthResult.failure(
          const AuthFailure(
            AuthErrorCode.unknown,
            'Sign-in did not return a user.',
          ),
        );
      }
      return AuthResult.success(
        _identityFromUser(user, AuthIdentityKind.authenticatedReturningUser),
      );
    } catch (error) {
      return AuthResult.failure(mapAuthException(error));
    }
  }

  @override
  Future<AuthResult<void>> signOut() async {
    try {
      await _auth.signOut();
      return AuthResult.success(null);
    } catch (error) {
      return AuthResult.failure(mapAuthException(error));
    }
  }

  AuthIdentityKind _kindForUser(User user) => user.isAnonymous
      ? AuthIdentityKind.anonymous
      : AuthIdentityKind.linkedEmail;

  AuthIdentity _identityFromUser(User user, AuthIdentityKind kind) {
    return AuthIdentity(
      uid: user.id,
      kind: kind,
      email: user.email,
      emailConfirmed: user.email == null ? null : user.emailConfirmedAt != null,
    );
  }

  AuthFailure? _validateEmailFormat(String email) {
    final valid = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);
    if (valid) return null;
    return const AuthFailure(
      AuthErrorCode.invalidEmail,
      'Enter a valid email address.',
    );
  }
}

/// Maps any exception thrown by the installed `gotrue`/`supabase_flutter`
/// SDK into a stable [AuthFailure]. Pure and side-effect free, so it can
/// be unit-tested directly with hand-constructed exception instances —
/// no live Supabase project required.
AuthFailure mapAuthException(Object error) {
  if (error is AuthSessionMissingException) {
    return const AuthFailure(
      AuthErrorCode.sessionMissing,
      'No session available.',
    );
  }
  if (error is AuthRetryableFetchException) {
    return const AuthFailure(
      AuthErrorCode.networkUnavailable,
      'Could not reach the server. Check your connection.',
    );
  }
  if (error is AuthWeakPasswordException) {
    return const AuthFailure(
      AuthErrorCode.weakPassword,
      'Choose a stronger password.',
    );
  }
  if (error is AuthApiException) {
    switch (error.code) {
      case 'email_exists':
      case 'user_already_exists':
        return const AuthFailure(
          AuthErrorCode.emailAlreadyInUse,
          'That email is already registered.',
        );
      case 'weak_password':
        return const AuthFailure(
          AuthErrorCode.weakPassword,
          'Choose a stronger password.',
        );
      case 'invalid_email':
      case 'validation_failed':
        return const AuthFailure(
          AuthErrorCode.invalidEmail,
          'Enter a valid email address.',
        );
      case 'email_not_confirmed':
        return const AuthFailure(
          AuthErrorCode.emailNotConfirmed,
          'Confirm your email before signing in.',
        );
      case 'over_request_rate_limit':
      case 'over_email_send_rate_limit':
      case 'over_sms_send_rate_limit':
        return const AuthFailure(
          AuthErrorCode.rateLimited,
          'Too many attempts. Try again shortly.',
        );
      case 'session_not_found':
      case 'user_not_found':
        return const AuthFailure(
          AuthErrorCode.sessionMissing,
          'No session available.',
        );
    }
    // The GoTrue server uses `invalid_credentials` for a wrong
    // email/password combination; older/edge responses may omit `code`
    // entirely and rely on the message instead, so both are checked.
    final message = error.message.toLowerCase();
    if (error.code == 'invalid_credentials' ||
        message.contains('invalid login credentials') ||
        message.contains('invalid credentials')) {
      return const AuthFailure(
        AuthErrorCode.invalidCredentials,
        'Incorrect email or password.',
      );
    }
    return const AuthFailure(
      AuthErrorCode.unknown,
      'Something went wrong. Please try again.',
    );
  }
  return const AuthFailure(
    AuthErrorCode.unknown,
    'Something went wrong. Please try again.',
  );
}
