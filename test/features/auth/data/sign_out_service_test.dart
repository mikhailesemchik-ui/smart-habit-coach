import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_habit_coach/core/storage/local_namespace_resolver.dart';
import 'package:smart_habit_coach/features/auth/data/sign_out_service.dart';
import 'package:smart_habit_coach/features/auth/domain/auth_error.dart';
import 'package:smart_habit_coach/features/auth/domain/auth_identity.dart';
import 'package:smart_habit_coach/features/home/data/habit_storage.dart';
import 'package:smart_habit_coach/features/home/domain/habit.dart';

import '../../../support/fake_auth_repository.dart';
import '../../../support/test_namespace.dart';

const _linkedIdentity = AuthIdentity(
  uid: 'linked-uid',
  kind: AuthIdentityKind.linkedEmail,
  email: 'jamie@example.com',
  emailConfirmed: true,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() {
    LocalNamespaceResolver.debugUidOverride = testNamespaceUid;
  });

  group('SignOutService', () {
    test('sign-out succeeds and creates a fresh anonymous identity', () async {
      final authRepository = FakeAuthRepository(
        initialIdentity: _linkedIdentity,
        anonymousUid: 'fresh-anon-uid',
      );
      final service = SignOutService(authRepository: authRepository);

      final result = await service.signOutToFreshAnonymous();

      expect(result.isSuccess, isTrue);
      expect(result.value.kind, AuthIdentityKind.anonymous);
      expect(result.value.uid, 'fresh-anon-uid');
      expect(authRepository.signOutCallCount, 1);
      expect(authRepository.ensureAnonymousSessionCallCount, 1);
    });

    test(
      'signed-in namespace remains intact and new anonymous namespace is isolated',
      () async {
        final habitStorage = HabitStorage();
        LocalNamespaceResolver.debugUidOverride = _linkedIdentity.uid;
        await habitStorage.upsertHabit(
          Habit(
            id: 'linked-habit',
            title: 'Read',
            scheduledTime: '08:00 PM',
            icon: Icons.menu_book_outlined,
          ),
        );

        final authRepository = FakeAuthRepository(
          initialIdentity: _linkedIdentity,
          anonymousUid: 'fresh-anon-uid',
        );
        final service = SignOutService(authRepository: authRepository);

        final result = await service.signOutToFreshAnonymous();

        expect(result.isSuccess, isTrue);

        LocalNamespaceResolver.debugUidOverride = _linkedIdentity.uid;
        final linkedHabits = await habitStorage.loadHabitsRaw();
        expect(linkedHabits!.single.id, 'linked-habit');

        LocalNamespaceResolver.debugUidOverride = 'fresh-anon-uid';
        final anonymousHabits = await habitStorage.loadHabitsRaw();
        expect(anonymousHabits, isNull);
      },
    );

    test(
      'sign-out failure is controlled and does not create anonymous identity',
      () async {
        final authRepository = FakeAuthRepository(
          initialIdentity: _linkedIdentity,
          signOutFailure: const AuthFailure(
            AuthErrorCode.networkUnavailable,
            'Could not reach the server.',
          ),
        );
        final service = SignOutService(authRepository: authRepository);

        final result = await service.signOutToFreshAnonymous();

        expect(result.isSuccess, isFalse);
        expect(result.failure!.code, AuthErrorCode.networkUnavailable);
        expect(authRepository.signOutCallCount, 1);
        expect(authRepository.ensureAnonymousSessionCallCount, 0);
        expect(authRepository.currentIdentity(), _linkedIdentity);
      },
    );

    test('anonymous recreation failure is controlled after sign-out', () async {
      final authRepository = FakeAuthRepository(
        initialIdentity: _linkedIdentity,
        anonymousSessionSucceeds: false,
      );
      final service = SignOutService(authRepository: authRepository);

      final result = await service.signOutToFreshAnonymous();

      expect(result.isSuccess, isFalse);
      expect(result.failure!.code, AuthErrorCode.networkUnavailable);
      expect(authRepository.signOutCallCount, 1);
      expect(authRepository.ensureAnonymousSessionCallCount, 1);
      expect(
        authRepository.currentIdentity().kind,
        AuthIdentityKind.unauthenticated,
      );
    });

    test('reusing the previous signed-in uid is rejected', () async {
      final authRepository = FakeAuthRepository(
        initialIdentity: _linkedIdentity,
        anonymousUid: _linkedIdentity.uid,
      );
      final service = SignOutService(authRepository: authRepository);

      final result = await service.signOutToFreshAnonymous();

      expect(result.isSuccess, isFalse);
      expect(result.failure!.code, AuthErrorCode.identityChangedUnexpectedly);
    });

    test('blank anonymous uid is rejected', () async {
      final authRepository = FakeAuthRepository(
        initialIdentity: _linkedIdentity,
        anonymousUid: ' ',
      );
      final service = SignOutService(authRepository: authRepository);

      final result = await service.signOutToFreshAnonymous();

      expect(result.isSuccess, isFalse);
      expect(result.failure!.code, AuthErrorCode.sessionMissing);
    });
  });
}
