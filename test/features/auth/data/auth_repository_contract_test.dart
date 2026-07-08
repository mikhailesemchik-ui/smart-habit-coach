import 'package:flutter_test/flutter_test.dart';
import 'package:smart_habit_coach/features/auth/domain/auth_error.dart';
import 'package:smart_habit_coach/features/auth/domain/auth_identity.dart';

import '../../../support/fake_auth_repository.dart';

/// Exercises the [AuthRepository] contract itself (via the fake) - every
/// consumer (ReturningUserSignInService, a future Phase 2B UI) depends
/// only on this contract, so proving it holds here is what makes the
/// concrete `SupabaseAuthRepository`'s wiring safe to trust without a
/// live Supabase project in this test environment.
void main() {
  group('AuthRepository contract', () {
    test('currentIdentity is unauthenticated with no session', () {
      final repo = FakeAuthRepository();
      expect(repo.currentIdentity().kind, AuthIdentityKind.unauthenticated);
    });

    test('ensureAnonymousSession establishes an anonymous identity', () async {
      final repo = FakeAuthRepository();

      final result = await repo.ensureAnonymousSession();

      expect(result.isSuccess, isTrue);
      expect(result.value.kind, AuthIdentityKind.anonymous);
      expect(result.value.uid, isNotEmpty);
    });

    test(
      'ensureAnonymousSession is a no-op if a session already exists',
      () async {
        final repo = FakeAuthRepository();
        final first = await repo.ensureAnonymousSession();

        final second = await repo.ensureAnonymousSession();

        expect(second.value.uid, first.value.uid);
      },
    );

    test(
      'a network failure establishing the anonymous session is reported',
      () async {
        final repo = FakeAuthRepository(anonymousSessionSucceeds: false);

        final result = await repo.ensureAnonymousSession();

        expect(result.isSuccess, isFalse);
        expect(result.failure!.code, AuthErrorCode.networkUnavailable);
      },
    );

    test('successful link preserves the uid and reports linkedEmail', () async {
      final repo = FakeAuthRepository();
      final anon = await repo.ensureAnonymousSession();

      final result = await repo.linkEmailPassword(
        email: 'jamie@example.com',
        password: 'password123',
      );

      expect(result.isSuccess, isTrue);
      expect(result.value.uid, anon.value.uid);
      expect(result.value.kind, AuthIdentityKind.linkedEmail);
      expect(result.value.email, 'jamie@example.com');
    });

    test('link can report email confirmation pending', () async {
      final repo = FakeAuthRepository(linkedEmailConfirmed: false);
      await repo.ensureAnonymousSession();

      final result = await repo.linkEmailPassword(
        email: 'jamie@example.com',
        password: 'password123',
      );

      expect(result.isSuccess, isTrue);
      expect(result.value.kind, AuthIdentityKind.linkedEmail);
      expect(result.value.emailConfirmed, isFalse);
    });

    test(
      'linking without an anonymous session returns sessionMissing',
      () async {
        final repo = FakeAuthRepository();

        final result = await repo.linkEmailPassword(
          email: 'jamie@example.com',
          password: 'password123',
        );

        expect(result.isSuccess, isFalse);
        expect(result.failure!.code, AuthErrorCode.sessionMissing);
      },
    );

    test(
      'linking from a non-anonymous session returns sessionMissing',
      () async {
        final repo = FakeAuthRepository(
          initialIdentity: const AuthIdentity(
            uid: 'linked-uid',
            kind: AuthIdentityKind.linkedEmail,
            email: 'jamie@example.com',
          ),
        );

        final result = await repo.linkEmailPassword(
          email: 'other@example.com',
          password: 'password123',
        );

        expect(result.isSuccess, isFalse);
        expect(result.failure!.code, AuthErrorCode.sessionMissing);
      },
    );

    test('a link failure leaves the anonymous session usable', () async {
      final repo = FakeAuthRepository(
        linkFailure: const AuthFailure(
          AuthErrorCode.emailAlreadyInUse,
          'That email is already registered.',
        ),
      );
      final anon = await repo.ensureAnonymousSession();

      final result = await repo.linkEmailPassword(
        email: 'jamie@example.com',
        password: 'password123',
      );

      expect(result.isSuccess, isFalse);
      expect(result.failure!.code, AuthErrorCode.emailAlreadyInUse);
      // The session is untouched - still the same anonymous identity.
      expect(repo.currentIdentity().kind, AuthIdentityKind.anonymous);
      expect(repo.currentIdentity().uid, anon.value.uid);
    });

    test(
      'an unexpected uid change during linking is detected and reported',
      () async {
        final repo = FakeAuthRepository(
          linkResultUidOverride: 'a-completely-different-uid',
        );
        await repo.ensureAnonymousSession();

        final result = await repo.linkEmailPassword(
          email: 'jamie@example.com',
          password: 'password123',
        );

        expect(result.isSuccess, isFalse);
        expect(result.failure!.code, AuthErrorCode.identityChangedUnexpectedly);
      },
    );

    test(
      'signInWithEmailPassword success reports authenticatedReturningUser',
      () async {
        final repo = FakeAuthRepository();

        final result = await repo.signInWithEmailPassword(
          email: 'jamie@example.com',
          password: 'password123',
        );

        expect(result.isSuccess, isTrue);
        expect(result.value.kind, AuthIdentityKind.authenticatedReturningUser);
      },
    );

    test('invalid credentials are reported without throwing', () async {
      final repo = FakeAuthRepository(
        signInFailure: const AuthFailure(
          AuthErrorCode.invalidCredentials,
          'Incorrect email or password.',
        ),
      );

      final result = await repo.signInWithEmailPassword(
        email: 'jamie@example.com',
        password: 'wrong',
      );

      expect(result.isSuccess, isFalse);
      expect(result.failure!.code, AuthErrorCode.invalidCredentials);
    });

    test('signOut clears the identity back to unauthenticated', () async {
      final repo = FakeAuthRepository();
      await repo.ensureAnonymousSession();

      final result = await repo.signOut();

      expect(result.isSuccess, isTrue);
      expect(repo.currentIdentity().kind, AuthIdentityKind.unauthenticated);
      expect(repo.signOutCallCount, 1);
    });
  });
}
