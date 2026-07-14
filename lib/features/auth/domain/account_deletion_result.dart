import 'auth_identity.dart';

/// Typed failure categories for the full account-deletion flow — never a
/// raw exception message or stack trace reaches the UI.
enum AccountDeletionFailureCode {
  /// Deletion was requested for an anonymous identity. Anonymous accounts
  /// never expose this destructive flow — this code only exists as a
  /// defensive guard inside [AccountDeletionService] itself.
  anonymousNotAllowed,

  /// No authenticated session exists at all.
  unauthenticated,

  networkUnavailable,
  permissionDenied,

  /// The delete-account backend function could not be reached/invoked at
  /// all (as distinct from the function running and reporting failure).
  functionUnavailable,

  /// The backend function ran but reported that account deletion failed.
  remoteDeletionFailed,

  /// Remote deletion succeeded, but wiping the local namespace afterward
  /// failed.
  localCleanupFailed,

  /// Remote (and local) deletion succeeded, but establishing a fresh
  /// anonymous identity afterward failed.
  anonymousReauthFailed,

  /// The active identity changed mid-flow (e.g. a race with another
  /// sign-in). Local cleanup is deliberately skipped in this case — see
  /// [AccountDeletionService] for the full rationale.
  identityChanged,

  unknown,
}

class AccountDeletionFailure {
  final AccountDeletionFailureCode code;

  /// Short, human-readable, non-technical message — never a raw SDK/HTTP
  /// exception message.
  final String message;

  const AccountDeletionFailure(this.code, this.message);
}

/// Typed result of [AccountDeletionService.deleteAccount].
///
/// [isSuccess] is true only when the account was deleted remotely, the
/// local namespace was wiped, and a fresh anonymous identity was
/// established — the complete, clean end state. [partialFailure] is true
/// whenever remote account deletion itself succeeded but a later step
/// (local cleanup or establishing a new anonymous identity) did not; in
/// that case the account is genuinely gone from the backend and must never
/// be reported as fully intact, even though the local app state may be
/// incomplete. [newIdentity] carries whatever fresh identity was
/// established, if any — set even on a partial failure so the caller can
/// still move the UI forward when possible.
class AccountDeletionResult {
  final bool isSuccess;
  final bool partialFailure;
  final AuthIdentity? newIdentity;
  final AccountDeletionFailure? failure;

  const AccountDeletionResult._({
    required this.isSuccess,
    required this.partialFailure,
    this.newIdentity,
    this.failure,
  });

  factory AccountDeletionResult.success(AuthIdentity newIdentity) =>
      AccountDeletionResult._(
        isSuccess: true,
        partialFailure: false,
        newIdentity: newIdentity,
      );

  factory AccountDeletionResult.failure(
    AccountDeletionFailure failure, {
    bool partialFailure = false,
    AuthIdentity? newIdentity,
  }) => AccountDeletionResult._(
    isSuccess: false,
    partialFailure: partialFailure,
    newIdentity: newIdentity,
    failure: failure,
  );
}
