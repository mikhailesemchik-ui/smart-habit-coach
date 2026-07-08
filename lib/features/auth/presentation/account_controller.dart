import 'package:flutter/foundation.dart';

import '../../home/data/habit_storage.dart';
import '../../home/data/notification_service.dart';
import '../data/auth_repository.dart';
import '../data/returning_user_sign_in_service.dart';
import '../data/sign_out_service.dart';
import '../data/supabase_auth_repository.dart';
import '../domain/auth_error.dart';
import '../domain/auth_identity.dart';

const accountPasswordMinLength = 6;

enum AccountOperation { none, loading, linking, signingIn, signingOut }

class PendingReturningSignIn {
  final String email;
  final String password;

  const PendingReturningSignIn({required this.email, required this.password});
}

class AccountState {
  final AuthIdentity identity;
  final AccountOperation operation;
  final AuthFailure? failure;
  final String? successMessage;
  final PendingReturningSignIn? pendingSignIn;

  const AccountState({
    required this.identity,
    this.operation = AccountOperation.none,
    this.failure,
    this.successMessage,
    this.pendingSignIn,
  });

  bool get isBusy => operation != AccountOperation.none;
  bool get confirmationRequired => pendingSignIn != null;

  AccountState copyWith({
    AuthIdentity? identity,
    AccountOperation? operation,
    AuthFailure? failure,
    String? successMessage,
    PendingReturningSignIn? pendingSignIn,
    bool clearFailure = false,
    bool clearSuccess = false,
    bool clearPendingSignIn = false,
  }) {
    return AccountState(
      identity: identity ?? this.identity,
      operation: operation ?? this.operation,
      failure: clearFailure ? null : failure ?? this.failure,
      successMessage: clearSuccess
          ? null
          : successMessage ?? this.successMessage,
      pendingSignIn: clearPendingSignIn
          ? null
          : pendingSignIn ?? this.pendingSignIn,
    );
  }
}

class AccountController extends ChangeNotifier {
  final AuthRepository _authRepository;
  final ReturningUserSignInService _returningUserSignInService;
  final SignOutService _signOutService;
  final HabitStorage _habitStorage;
  final NotificationService _notificationService;
  final Future<void> Function()? _onIdentityChanged;

  AccountState _state = const AccountState(
    identity: AuthIdentity.unauthenticated,
    operation: AccountOperation.loading,
  );

  AccountController({
    AuthRepository? authRepository,
    ReturningUserSignInService? returningUserSignInService,
    SignOutService? signOutService,
    HabitStorage? habitStorage,
    NotificationService? notificationService,
    Future<void> Function()? onIdentityChanged,
  }) : _authRepository = authRepository ?? SupabaseAuthRepository(),
       _habitStorage = habitStorage ?? HabitStorage(),
       _notificationService = notificationService ?? NotificationService(),
       _onIdentityChanged = onIdentityChanged,
       _returningUserSignInService =
           returningUserSignInService ??
           ReturningUserSignInService(
             authRepository: authRepository ?? SupabaseAuthRepository(),
             habitStorage: habitStorage,
           ),
       _signOutService =
           signOutService ??
           SignOutService(
             authRepository: authRepository ?? SupabaseAuthRepository(),
           );

  AccountState get state => _state;

  void _emit(AccountState state) {
    _state = state;
    notifyListeners();
  }

  Future<void> load() async {
    _emit(
      _state.copyWith(
        operation: AccountOperation.loading,
        clearFailure: true,
        clearSuccess: true,
        clearPendingSignIn: true,
      ),
    );
    _emit(
      _state.copyWith(
        identity: _authRepository.currentIdentity(),
        operation: AccountOperation.none,
      ),
    );
  }

  Future<void> linkAccount({
    required String email,
    required String password,
  }) async {
    if (_state.isBusy) return;
    _emit(
      _state.copyWith(
        operation: AccountOperation.linking,
        clearFailure: true,
        clearSuccess: true,
        clearPendingSignIn: true,
      ),
    );

    final result = await _authRepository.linkEmailPassword(
      email: email.trim(),
      password: password,
    );
    if (!result.isSuccess) {
      _emit(
        _state.copyWith(
          operation: AccountOperation.none,
          failure: result.failure,
        ),
      );
      return;
    }

    final identity = result.value;
    _emit(
      _state.copyWith(
        identity: identity,
        operation: AccountOperation.none,
        clearFailure: true,
        successMessage: identity.emailConfirmed == false
            ? 'Check your email to confirm the address. Your current local data remains safe while confirmation is pending.'
            : 'Account linked.',
      ),
    );
  }

  Future<void> signIn({required String email, required String password}) async {
    await _attemptReturningSignIn(
      email: email.trim(),
      password: password,
      preserveConfirmed: false,
    );
  }

  Future<void> confirmPreserveAndSignIn() async {
    final pending = _state.pendingSignIn;
    if (pending == null || _state.isBusy) return;
    await _attemptReturningSignIn(
      email: pending.email,
      password: pending.password,
      preserveConfirmed: true,
    );
  }

  void cancelPendingSignIn() {
    if (_state.isBusy) return;
    _emit(_state.copyWith(clearPendingSignIn: true, clearFailure: true));
  }

  Future<void> signOut() async {
    if (_state.isBusy) return;
    final previousHabitIds = await _currentHabitIds();
    _emit(
      _state.copyWith(
        operation: AccountOperation.signingOut,
        clearFailure: true,
        clearSuccess: true,
      ),
    );

    final result = await _signOutService.signOutToFreshAnonymous();
    if (!result.isSuccess) {
      _emit(
        _state.copyWith(
          operation: AccountOperation.none,
          failure: result.failure,
        ),
      );
      return;
    }

    await _cancelReminders(previousHabitIds);
    await _onIdentityChanged?.call();
    _emit(
      _state.copyWith(
        identity: result.value,
        operation: AccountOperation.none,
        clearFailure: true,
        successMessage: 'Signed out. A fresh anonymous identity is active.',
      ),
    );
  }

  Future<void> _attemptReturningSignIn({
    required String email,
    required String password,
    required bool preserveConfirmed,
  }) async {
    if (_state.isBusy) return;
    final previousHabitIds = await _currentHabitIds();
    _emit(
      _state.copyWith(
        operation: AccountOperation.signingIn,
        clearFailure: true,
        clearSuccess: true,
      ),
    );

    final result = await _returningUserSignInService.attemptSignIn(
      email: email,
      password: password,
      preserveConfirmed: preserveConfirmed,
    );

    switch (result.outcome) {
      case ReturningSignInOutcome.confirmationRequired:
        _emit(
          _state.copyWith(
            operation: AccountOperation.none,
            pendingSignIn: PendingReturningSignIn(
              email: email,
              password: password,
            ),
          ),
        );
      case ReturningSignInOutcome.failed:
        _emit(
          _state.copyWith(
            operation: AccountOperation.none,
            failure: result.failure,
            clearPendingSignIn: preserveConfirmed,
          ),
        );
      case ReturningSignInOutcome.signedIn:
        await _cancelReminders(previousHabitIds);
        await _onIdentityChanged?.call();
        _emit(
          _state.copyWith(
            identity: result.identity ?? _authRepository.currentIdentity(),
            operation: AccountOperation.none,
            clearFailure: true,
            successMessage: 'Signed in.',
            clearPendingSignIn: true,
          ),
        );
    }
  }

  Future<List<String>> _currentHabitIds() async {
    final habits = await _habitStorage.loadHabitsRaw();
    return habits?.map((h) => h.id).toList() ?? const <String>[];
  }

  Future<void> _cancelReminders(List<String> habitIds) async {
    for (final id in habitIds) {
      await _notificationService.cancelHabitReminder(id);
    }
  }
}

String authFailureMessage(AuthFailure failure) {
  return switch (failure.code) {
    AuthErrorCode.invalidEmail => 'Enter a valid email address.',
    AuthErrorCode.weakPassword => 'Use a stronger password.',
    AuthErrorCode.invalidCredentials => 'Incorrect email or password.',
    AuthErrorCode.emailAlreadyInUse =>
      'That email is already registered. Try signing in instead.',
    AuthErrorCode.emailNotConfirmed => 'Confirm your email before signing in.',
    AuthErrorCode.networkUnavailable =>
      'Could not connect. Check your connection and try again.',
    AuthErrorCode.rateLimited => 'Too many attempts. Try again shortly.',
    AuthErrorCode.sessionMissing =>
      'Your session is not ready. Please retry from startup.',
    AuthErrorCode.identityChangedUnexpectedly =>
      'For safety, the account change was stopped because the identity changed unexpectedly.',
    AuthErrorCode.unknown => 'Something went wrong. Please try again.',
  };
}

String? validateAccountEmail(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return 'Enter your email.';
  final valid = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(trimmed);
  return valid ? null : 'Enter a valid email address.';
}

String? validateAccountPassword(String value, {bool requireMinimum = true}) {
  if (value.isEmpty) return 'Enter your password.';
  if (requireMinimum && value.length < accountPasswordMinLength) {
    return 'Use at least $accountPasswordMinLength characters.';
  }
  return null;
}
