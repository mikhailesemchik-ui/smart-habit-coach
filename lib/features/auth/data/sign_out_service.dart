import '../domain/auth_error.dart';
import '../domain/auth_identity.dart';
import '../domain/auth_result.dart';
import 'auth_repository.dart';

/// Application-level sign-out flow for Phase 2A.
///
/// The repository signs out only. This service handles the app invariant
/// that local-first storage should resume under a fresh anonymous UID after
/// a linked/returning user signs out, without deleting or moving any data.
class SignOutService {
  final AuthRepository _authRepository;

  SignOutService({required AuthRepository authRepository})
    : _authRepository = authRepository;

  Future<AuthResult<AuthIdentity>> signOutToFreshAnonymous() async {
    final previousIdentity = _authRepository.currentIdentity();

    final signOutResult = await _authRepository.signOut();
    if (!signOutResult.isSuccess) {
      return AuthResult.failure(signOutResult.failure!);
    }

    final anonymousResult = await _authRepository.ensureAnonymousSession();
    if (!anonymousResult.isSuccess) {
      return AuthResult.failure(anonymousResult.failure!);
    }

    final anonymousIdentity = anonymousResult.value;
    if (anonymousIdentity.kind != AuthIdentityKind.anonymous ||
        anonymousIdentity.uid.trim().isEmpty) {
      return AuthResult.failure(
        const AuthFailure(
          AuthErrorCode.sessionMissing,
          'Could not establish an anonymous session.',
        ),
      );
    }

    if (previousIdentity.uid.trim().isNotEmpty &&
        previousIdentity.uid == anonymousIdentity.uid) {
      return AuthResult.failure(
        const AuthFailure(
          AuthErrorCode.identityChangedUnexpectedly,
          'A fresh anonymous identity was not created.',
        ),
      );
    }

    return AuthResult.success(anonymousIdentity);
  }
}
