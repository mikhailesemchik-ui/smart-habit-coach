import '../../../core/sync/recovery_snapshot_storage.dart';
import '../../../core/sync/sync_metadata_storage.dart';
import '../../coach/data/adaptive_suggestion_storage.dart';
import '../../home/data/habit_storage.dart';
import '../../profile/data/settings_storage.dart';
import '../domain/auth_error.dart';
import '../domain/auth_identity.dart';
import '../domain/meaningful_local_data.dart';
import 'auth_repository.dart';

enum ReturningSignInOutcome {
  /// S1: the anonymous namespace was empty/negligible, so sign-in
  /// proceeded immediately and succeeded.
  signedIn,

  /// S2: the anonymous namespace has meaningful data and the caller has
  /// not yet confirmed how to proceed. No Supabase call has been made.
  /// Call [ReturningUserSignInService.attemptSignIn] again with
  /// `preserveConfirmed: true` to proceed (creating a snapshot first), or
  /// simply do nothing to cancel — nothing has changed yet either way.
  confirmationRequired,

  /// [AuthRepository.signInWithEmailPassword] itself failed. The
  /// anonymous session/namespace is untouched.
  failed,
}

class ReturningUserSignInResult {
  final ReturningSignInOutcome outcome;
  final AuthIdentity? identity;
  final AuthFailure? failure;

  const ReturningUserSignInResult({
    required this.outcome,
    this.identity,
    this.failure,
  });
}

/// Orchestrates the Phase 2B S1/S2 returning-user sign-in decision (logic
/// only — no dialogs/screens here). See the approved plan's "returning
/// user sign-in" section for the full S1/S2 rationale.
class ReturningUserSignInService {
  final AuthRepository _authRepository;
  final HabitStorage _habitStorage;
  final AdaptiveSuggestionStorage _suggestionStorage;
  final SettingsStorage _settingsStorage;
  final SyncMetadataStorage _syncMetadataStorage;
  final RecoverySnapshotStorage _recoverySnapshotStorage;

  ReturningUserSignInService({
    required AuthRepository authRepository,
    HabitStorage? habitStorage,
    AdaptiveSuggestionStorage? suggestionStorage,
    SettingsStorage? settingsStorage,
    SyncMetadataStorage? syncMetadataStorage,
    RecoverySnapshotStorage? recoverySnapshotStorage,
  }) : _authRepository = authRepository,
       _habitStorage = habitStorage ?? HabitStorage(),
       _suggestionStorage = suggestionStorage ?? AdaptiveSuggestionStorage(),
       _settingsStorage = settingsStorage ?? SettingsStorage(),
       _syncMetadataStorage = syncMetadataStorage ?? SyncMetadataStorage(),
       _recoverySnapshotStorage =
           recoverySnapshotStorage ?? RecoverySnapshotStorage();

  /// Attempts a returning-user sign-in.
  ///
  /// - S1 (anonymous namespace empty/negligible): signs in immediately,
  ///   no confirmation needed, no data is copied — the newly-active
  ///   namespace is simply whatever the returning account's own uid
  ///   already has locally (possibly nothing, on a new device).
  /// - S2 (anonymous namespace has meaningful data) and
  ///   [preserveConfirmed] is `false`: returns
  ///   [ReturningSignInOutcome.confirmationRequired] and calls
  ///   `signInWithEmailPassword` **not at all** — nothing changes.
  /// - S2 with [preserveConfirmed] `true`: creates a `RecoverySnapshot` of
  ///   the anonymous namespace first (the anonymous data itself is never
  ///   deleted or moved — the snapshot is an extra safety net, not the
  ///   preservation mechanism itself), then signs in.
  ///
  /// In every path, the anonymous namespace's data is never copied,
  /// merged, or uploaded under the returning account's uid — signing in
  /// simply changes which namespace is active going forward.
  Future<ReturningUserSignInResult> attemptSignIn({
    required String email,
    required String password,
    bool preserveConfirmed = false,
  }) async {
    final anonymousIdentity = _authRepository.currentIdentity();
    if (anonymousIdentity.kind != AuthIdentityKind.anonymous ||
        anonymousIdentity.uid.trim().isEmpty) {
      return const ReturningUserSignInResult(
        outcome: ReturningSignInOutcome.failed,
        failure: AuthFailure(
          AuthErrorCode.sessionMissing,
          'No anonymous session to replace.',
        ),
      );
    }
    final anonymousUid = anonymousIdentity.uid;

    final meaningful = await hasMeaningfulLocalData(
      habitStorage: _habitStorage,
      suggestionStorage: _suggestionStorage,
      settingsStorage: _settingsStorage,
      syncMetadataStorage: _syncMetadataStorage,
      recoverySnapshotStorage: _recoverySnapshotStorage,
    );

    if (meaningful && !preserveConfirmed) {
      return const ReturningUserSignInResult(
        outcome: ReturningSignInOutcome.confirmationRequired,
      );
    }

    if (meaningful) {
      await _recoverySnapshotStorage.create(reason: 'beforeAccountSwitch');
    }

    final result = await _authRepository.signInWithEmailPassword(
      email: email,
      password: password,
    );

    if (!result.isSuccess) {
      return ReturningUserSignInResult(
        outcome: ReturningSignInOutcome.failed,
        failure: result.failure,
      );
    }

    final returningIdentity = result.value;
    if (returningIdentity.uid.trim().isEmpty || returningIdentity.isAnonymous) {
      return const ReturningUserSignInResult(
        outcome: ReturningSignInOutcome.failed,
        failure: AuthFailure(
          AuthErrorCode.unknown,
          'Sign-in did not return an authenticated user.',
        ),
      );
    }

    if (returningIdentity.uid == anonymousUid) {
      return const ReturningUserSignInResult(
        outcome: ReturningSignInOutcome.failed,
        failure: AuthFailure(
          AuthErrorCode.identityChangedUnexpectedly,
          'The returning account reused the anonymous identity unexpectedly.',
        ),
      );
    }

    return ReturningUserSignInResult(
      outcome: ReturningSignInOutcome.signedIn,
      identity: returningIdentity,
    );
  }
}
