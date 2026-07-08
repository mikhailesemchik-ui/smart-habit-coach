import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_habit_coach/core/storage/local_namespace_resolver.dart';
import 'package:smart_habit_coach/core/sync/recovery_snapshot_storage.dart';
import 'package:smart_habit_coach/features/auth/data/returning_user_sign_in_service.dart';
import 'package:smart_habit_coach/features/auth/domain/auth_error.dart';
import 'package:smart_habit_coach/features/auth/domain/auth_identity.dart';
import 'package:smart_habit_coach/features/home/data/habit_storage.dart';
import 'package:smart_habit_coach/features/home/domain/habit.dart';

import '../../../support/fake_auth_repository.dart';
import '../../../support/test_namespace.dart';

const _anonymousIdentity = AuthIdentity(
  uid: testNamespaceUid,
  kind: AuthIdentityKind.anonymous,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() {
    LocalNamespaceResolver.debugUidOverride = testNamespaceUid;
  });

  group('ReturningUserSignInService', () {
    test(
      'S1: an empty anonymous namespace signs in immediately (no confirmation)',
      () async {
        final authRepository = FakeAuthRepository(
          initialIdentity: _anonymousIdentity,
        );
        final service = ReturningUserSignInService(
          authRepository: authRepository,
        );

        final result = await service.attemptSignIn(
          email: 'jamie@example.com',
          password: 'password123',
        );

        expect(result.outcome, ReturningSignInOutcome.signedIn);
        expect(result.identity!.uid, 'returning-uid');
        expect(authRepository.signInWithEmailPasswordCallCount, 1);
      },
    );

    test(
      'S2: a meaningful anonymous namespace requires confirmation first',
      () async {
        final habitStorage = HabitStorage();
        await habitStorage.upsertHabit(
          Habit(
            id: '1',
            title: 'Drink water',
            scheduledTime: '08:00 AM',
            icon: Icons.local_drink_outlined,
          ),
        );
        final authRepository = FakeAuthRepository(
          initialIdentity: _anonymousIdentity,
        );
        final service = ReturningUserSignInService(
          authRepository: authRepository,
          habitStorage: habitStorage,
        );

        final result = await service.attemptSignIn(
          email: 'jamie@example.com',
          password: 'password123',
        );

        expect(result.outcome, ReturningSignInOutcome.confirmationRequired);
        // Cancel is implicit: nothing was called and nothing changed.
        expect(authRepository.signInWithEmailPasswordCallCount, 0);
        expect(
          authRepository.currentIdentity().kind,
          AuthIdentityKind.anonymous,
        );
      },
    );

    test(
      'confirming preservation creates a recovery snapshot before signing in',
      () async {
        final habitStorage = HabitStorage();
        await habitStorage.upsertHabit(
          Habit(
            id: '1',
            title: 'Drink water',
            scheduledTime: '08:00 AM',
            icon: Icons.local_drink_outlined,
          ),
        );
        final authRepository = FakeAuthRepository(
          initialIdentity: _anonymousIdentity,
        );
        final recoverySnapshotStorage = RecoverySnapshotStorage(
          habitStorage: habitStorage,
        );
        final service = ReturningUserSignInService(
          authRepository: authRepository,
          habitStorage: habitStorage,
          recoverySnapshotStorage: recoverySnapshotStorage,
        );

        final result = await service.attemptSignIn(
          email: 'jamie@example.com',
          password: 'password123',
          preserveConfirmed: true,
        );

        expect(result.outcome, ReturningSignInOutcome.signedIn);
        final snapshot = await recoverySnapshotStorage.read();
        expect(snapshot, isNotNull);
        expect(snapshot!.reason, 'beforeAccountSwitch');
        expect(snapshot.habits.single['id'], '1');
      },
    );

    test(
      'the anonymous namespace is never copied/merged into the returning uid',
      () async {
        final habitStorage = HabitStorage();
        await habitStorage.upsertHabit(
          Habit(
            id: 'anon-habit',
            title: 'Drink water',
            scheduledTime: '08:00 AM',
            icon: Icons.local_drink_outlined,
          ),
        );
        final authRepository = FakeAuthRepository(
          initialIdentity: _anonymousIdentity,
        );
        final service = ReturningUserSignInService(
          authRepository: authRepository,
          habitStorage: habitStorage,
        );

        await service.attemptSignIn(
          email: 'jamie@example.com',
          password: 'password123',
          preserveConfirmed: true,
        );

        // Switch the active namespace to the returning account's uid and
        // confirm its habit collection does not contain the anonymous one.
        LocalNamespaceResolver.debugUidOverride = 'returning-uid';
        final returningHabits = await habitStorage.loadHabitsRaw();
        expect(returningHabits, isNull);

        LocalNamespaceResolver.debugUidOverride = testNamespaceUid;
        final anonymousHabits = await habitStorage.loadHabitsRaw();
        expect(anonymousHabits!.single.id, 'anon-habit');
      },
    );

    test(
      'cancelling leaves the anonymous session and data unchanged',
      () async {
        final habitStorage = HabitStorage();
        final habit = await habitStorage.upsertHabit(
          Habit(
            id: '1',
            title: 'Drink water',
            scheduledTime: '08:00 AM',
            icon: Icons.local_drink_outlined,
          ),
        );
        final authRepository = FakeAuthRepository(
          initialIdentity: _anonymousIdentity,
        );
        final service = ReturningUserSignInService(
          authRepository: authRepository,
          habitStorage: habitStorage,
        );

        final result = await service.attemptSignIn(
          email: 'jamie@example.com',
          password: 'password123',
        );

        expect(result.outcome, ReturningSignInOutcome.confirmationRequired);
        expect(
          authRepository.currentIdentity().kind,
          AuthIdentityKind.anonymous,
        );
        final stillThere = await habitStorage.loadHabits();
        expect(stillThere!.single.id, habit.id);
      },
    );

    test(
      'sign-in failure leaves the existing anonymous local data intact',
      () async {
        final habitStorage = HabitStorage();
        await habitStorage.upsertHabit(
          Habit(
            id: '1',
            title: 'Drink water',
            scheduledTime: '08:00 AM',
            icon: Icons.local_drink_outlined,
          ),
        );
        final authRepository = FakeAuthRepository(
          initialIdentity: _anonymousIdentity,
          signInFailure: const AuthFailure(
            AuthErrorCode.invalidCredentials,
            'Incorrect email or password.',
          ),
        );
        final service = ReturningUserSignInService(
          authRepository: authRepository,
          habitStorage: habitStorage,
        );

        final result = await service.attemptSignIn(
          email: 'jamie@example.com',
          password: 'wrong-password',
          preserveConfirmed: true,
        );

        expect(result.outcome, ReturningSignInOutcome.failed);
        expect(result.failure!.code, AuthErrorCode.invalidCredentials);
        final stillThere = await habitStorage.loadHabits();
        expect(stillThere, isNotNull);
        expect(stillThere!.single.id, '1');
      },
    );

    test('sign-in requires an active anonymous identity first', () async {
      final authRepository = FakeAuthRepository();
      final service = ReturningUserSignInService(
        authRepository: authRepository,
      );

      final result = await service.attemptSignIn(
        email: 'jamie@example.com',
        password: 'password123',
      );

      expect(result.outcome, ReturningSignInOutcome.failed);
      expect(result.failure!.code, AuthErrorCode.sessionMissing);
      expect(authRepository.signInWithEmailPasswordCallCount, 0);
    });

    test('blank signed-in uid is rejected', () async {
      final authRepository = FakeAuthRepository(
        initialIdentity: _anonymousIdentity,
        signInIdentity: const AuthIdentity(
          uid: '',
          kind: AuthIdentityKind.authenticatedReturningUser,
          email: 'jamie@example.com',
        ),
      );
      final service = ReturningUserSignInService(
        authRepository: authRepository,
      );

      final result = await service.attemptSignIn(
        email: 'jamie@example.com',
        password: 'password123',
      );

      expect(result.outcome, ReturningSignInOutcome.failed);
      expect(result.failure!.code, AuthErrorCode.unknown);
    });

    test('a sign-in result that remains anonymous is rejected', () async {
      final authRepository = FakeAuthRepository(
        initialIdentity: _anonymousIdentity,
        signInIdentity: const AuthIdentity(
          uid: 'returning-uid',
          kind: AuthIdentityKind.anonymous,
        ),
      );
      final service = ReturningUserSignInService(
        authRepository: authRepository,
      );

      final result = await service.attemptSignIn(
        email: 'jamie@example.com',
        password: 'password123',
      );

      expect(result.outcome, ReturningSignInOutcome.failed);
      expect(result.failure!.code, AuthErrorCode.unknown);
    });

    test('returning uid matching the anonymous uid is rejected', () async {
      final authRepository = FakeAuthRepository(
        initialIdentity: _anonymousIdentity,
        signInIdentity: const AuthIdentity(
          uid: testNamespaceUid,
          kind: AuthIdentityKind.authenticatedReturningUser,
          email: 'jamie@example.com',
        ),
      );
      final service = ReturningUserSignInService(
        authRepository: authRepository,
      );

      final result = await service.attemptSignIn(
        email: 'jamie@example.com',
        password: 'password123',
      );

      expect(result.outcome, ReturningSignInOutcome.failed);
      expect(result.failure!.code, AuthErrorCode.identityChangedUnexpectedly);
    });
  });
}
