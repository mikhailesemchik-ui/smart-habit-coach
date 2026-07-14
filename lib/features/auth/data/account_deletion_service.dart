import '../../../core/storage/local_namespace_cleanup_service.dart';
import '../../home/data/habit_storage.dart';
import '../../home/data/notification_service.dart';
import '../domain/account_deletion_result.dart';
import '../domain/auth_identity.dart';
import 'account_deletion_repository.dart';
import 'auth_repository.dart';
import 'supabase_auth_repository.dart';

/// Orchestrates the full account-deletion flow: remote/auth deletion,
/// local namespace cleanup, notification cancellation, and re-establishing
/// a fresh anonymous identity.
///
/// **RecoverySnapshot policy**: this flow deliberately does *not* create or
/// preserve a `RecoverySnapshot` for the deleted UID. `RecoverySnapshot` is
/// an internal safety net for destructive operations that stay *within*
/// the same namespace (e.g. Phase 4 sync replacement) — it is useless once
/// that namespace itself is about to be permanently wiped, and creating
/// one immediately before deleting it would be pointless. The user-facing
/// backup mechanism for account deletion is the Phase 6 data export,
/// which the confirmation UI directs the user to use beforehand. The
/// existing recovery snapshot for the deleted UID (if any) is wiped along
/// with the rest of its namespace, per [LocalNamespaceCleanupService].
///
/// **Ordering**: remote deletion is requested first; local data is only
/// ever touched after the backend confirms the account is gone. If the
/// active identity changes between the remote call and local cleanup (a
/// race with another sign-in), local cleanup is skipped entirely rather
/// than guessing which namespace to wipe — see [deleteAccount].
class AccountDeletionService {
  final AuthRepository _authRepository;
  final AccountDeletionRepository _deletionRepository;
  final HabitStorage _habitStorage;
  final NotificationService _notificationService;
  final LocalNamespaceCleanupService _cleanupService;

  AccountDeletionService({
    AuthRepository? authRepository,
    AccountDeletionRepository? deletionRepository,
    HabitStorage? habitStorage,
    NotificationService? notificationService,
    LocalNamespaceCleanupService? cleanupService,
  }) : _authRepository = authRepository ?? SupabaseAuthRepository(),
       _deletionRepository =
           deletionRepository ?? SupabaseAccountDeletionRepository(),
       _habitStorage = habitStorage ?? HabitStorage(),
       _notificationService = notificationService ?? NotificationService(),
       _cleanupService = cleanupService ?? const LocalNamespaceCleanupService();

  Future<AccountDeletionResult> deleteAccount() async {
    final identity = _authRepository.currentIdentity();
    if (identity.kind == AuthIdentityKind.unauthenticated) {
      return AccountDeletionResult.failure(
        const AccountDeletionFailure(
          AccountDeletionFailureCode.unauthenticated,
          'Your session is not ready. Please retry from startup.',
        ),
      );
    }
    if (identity.isAnonymous) {
      return AccountDeletionResult.failure(
        const AccountDeletionFailure(
          AccountDeletionFailureCode.anonymousNotAllowed,
          'Anonymous accounts cannot be deleted this way.',
        ),
      );
    }

    final uidBeingDeleted = identity.uid;

    final cloudResult = await _deletionRepository.deleteAccount();
    if (!cloudResult.isSuccess) {
      // Remote deletion failed — local data and the current session are
      // left completely untouched, so the user can simply retry.
      return AccountDeletionResult.failure(
        _mapCloudFailure(cloudResult.failure!),
      );
    }

    // The account is now gone server-side. Guard against a mid-flight
    // identity change before touching anything local — if the active
    // session no longer matches the account we just deleted, we cannot
    // safely determine what to wipe, so local cleanup is skipped entirely
    // rather than risking another identity's data.
    if (_authRepository.currentIdentity().uid != uidBeingDeleted) {
      return AccountDeletionResult.failure(
        const AccountDeletionFailure(
          AccountDeletionFailureCode.identityChanged,
          'The account was deleted, but the active session changed '
          'unexpectedly. Please restart the app.',
        ),
        partialFailure: true,
      );
    }

    // Capture reminder ids while the deleted UID's namespace is still the
    // active one (HabitStorage always reads the *current* namespace).
    final habitIds =
        (await _habitStorage.loadHabitsRaw())?.map((h) => h.id).toList() ??
        const <String>[];

    var localWipeSucceeded = true;
    try {
      await _cleanupService.wipeNamespace(uidBeingDeleted);
    } catch (_) {
      localWipeSucceeded = false;
    }

    for (final id in habitIds) {
      await _notificationService.cancelHabitReminder(id);
    }
    await _notificationService.cancelAll();

    await _authRepository.signOut();
    final anonResult = await _authRepository.ensureAnonymousSession();
    final newIdentity = anonResult.isSuccess ? anonResult.value : null;
    final reauthSucceeded =
        newIdentity != null &&
        newIdentity.kind == AuthIdentityKind.anonymous &&
        newIdentity.uid.trim().isNotEmpty &&
        newIdentity.uid != uidBeingDeleted;

    if (!reauthSucceeded) {
      return AccountDeletionResult.failure(
        const AccountDeletionFailure(
          AccountDeletionFailureCode.anonymousReauthFailed,
          'The account was deleted, but a fresh identity could not be '
          'set up. Please retry from startup.',
        ),
        partialFailure: true,
        newIdentity: newIdentity,
      );
    }

    if (!localWipeSucceeded) {
      return AccountDeletionResult.failure(
        const AccountDeletionFailure(
          AccountDeletionFailureCode.localCleanupFailed,
          'The account was deleted, but some local data could not be '
          'cleared from this device.',
        ),
        partialFailure: true,
        newIdentity: newIdentity,
      );
    }

    return AccountDeletionResult.success(newIdentity);
  }

  // Never forwards `cloud.message` — only the stable error *code* crosses
  // this boundary, mirroring `SyncCoordinator._cloudFailure`. Every
  // display string is a fixed, safe message chosen here or in
  // `accountDeletionFailureMessage`, never whatever text a backend/SDK
  // exception happened to carry.
  AccountDeletionFailure _mapCloudFailure(AccountDeletionCloudFailure cloud) {
    return switch (cloud.code) {
      AccountDeletionCloudErrorCode.networkUnavailable =>
        const AccountDeletionFailure(
          AccountDeletionFailureCode.networkUnavailable,
          'Could not connect. Check your connection and try again.',
        ),
      AccountDeletionCloudErrorCode.permissionDenied =>
        const AccountDeletionFailure(
          AccountDeletionFailureCode.permissionDenied,
          'Your session is not ready. Please retry from startup.',
        ),
      AccountDeletionCloudErrorCode.functionUnavailable =>
        const AccountDeletionFailure(
          AccountDeletionFailureCode.functionUnavailable,
          'Account deletion is not available right now.',
        ),
      AccountDeletionCloudErrorCode.remoteDeletionFailed =>
        const AccountDeletionFailure(
          AccountDeletionFailureCode.remoteDeletionFailed,
          'Could not delete the account right now. Please try again.',
        ),
      AccountDeletionCloudErrorCode.unknown => const AccountDeletionFailure(
        AccountDeletionFailureCode.unknown,
        'Something went wrong. Please try again.',
      ),
    };
  }
}
