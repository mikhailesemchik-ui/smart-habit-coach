/// Stable, UI-safe error categories for auth operations. Never surfaces raw
/// SDK exception messages/stack traces — [AuthRepository] implementations
/// map every underlying SDK exception into one of these before returning.
enum AuthErrorCode {
  invalidEmail,
  weakPassword,
  invalidCredentials,
  emailAlreadyInUse,
  emailNotConfirmed,
  networkUnavailable,
  rateLimited,
  sessionMissing,

  /// The single most safety-critical mapped error: an operation that is
  /// supposed to preserve the active uid (anonymous-to-email linking)
  /// observed a *different* uid afterward. Callers must treat local data
  /// as still belonging to the pre-operation uid and must never write it
  /// under the new one.
  identityChangedUnexpectedly,

  unknown,
}

class AuthFailure {
  final AuthErrorCode code;

  /// Short, human-readable, non-technical message — safe to show in a
  /// future UI. Never a raw exception message or stack trace.
  final String message;

  const AuthFailure(this.code, this.message);

  @override
  String toString() => 'AuthFailure($code, $message)';
}
