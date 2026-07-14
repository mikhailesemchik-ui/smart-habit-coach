import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_habit_coach/core/storage/local_namespace_cleanup_service.dart';
import 'package:smart_habit_coach/core/storage/local_namespace_resolver.dart';
import 'package:smart_habit_coach/features/auth/data/account_deletion_repository.dart';
import 'package:smart_habit_coach/features/auth/data/account_deletion_service.dart';
import 'package:smart_habit_coach/features/auth/domain/account_deletion_result.dart';
import 'package:smart_habit_coach/features/auth/domain/auth_error.dart';
import 'package:smart_habit_coach/features/auth/domain/auth_identity.dart';
import 'package:smart_habit_coach/features/auth/presentation/account_controller.dart';
import 'package:smart_habit_coach/features/home/data/habit_storage.dart';
import 'package:smart_habit_coach/features/home/data/notification_service.dart';
import 'package:smart_habit_coach/features/home/domain/habit.dart';

import '../../../support/fake_auth_repository.dart';
import '../../../support/test_namespace.dart';

const _anonymousIdentity = AuthIdentity(
  uid: testNamespaceUid,
  kind: AuthIdentityKind.anonymous,
);

const _linkedIdentity = AuthIdentity(
  uid: testNamespaceUid,
  kind: AuthIdentityKind.linkedEmail,
  email: 'jamie@example.com',
  emailConfirmed: true,
);

class _FakeDeletionRepository implements AccountDeletionRepository {
  AccountDeletionCloudResult result = AccountDeletionCloudResult.success();

  @override
  Future<AccountDeletionCloudResult> deleteAccount() async => result;
}

class _RecordingCleanupService implements LocalNamespaceCleanupService {
  final wipedUids = <String>[];

  @override
  Future<void> wipeNamespace(String uid) async => wipedUids.add(uid);
}

class _FakeNotificationService extends NotificationService {
  final cancelledHabitIds = <String>[];

  @override
  Future<void> initialize() async {}

  @override
  Future<void> scheduleHabitReminder(Habit habit) async {}

  @override
  Future<void> cancelHabitReminder(String habitId) async {
    cancelledHabitIds.add(habitId);
  }
}

Future<void> _addHabit(String id) async {
  await HabitStorage().upsertHabit(
    Habit(
      id: id,
      title: id,
      scheduledTime: '08:00 AM',
      icon: Icons.check_circle_outline,
    ),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    LocalNamespaceResolver.debugUidOverride = testNamespaceUid;
  });

  tearDown(() {
    LocalNamespaceResolver.debugUidOverride = testNamespaceUid;
  });

  group('AccountController', () {
    test('loads anonymous identity', () async {
      final controller = AccountController(
        authRepository: FakeAuthRepository(initialIdentity: _anonymousIdentity),
      );

      await controller.load();

      expect(controller.state.identity.kind, AuthIdentityKind.anonymous);
      expect(controller.state.operation, AccountOperation.none);
    });

    test('link success keeps same uid and reports confirmed email', () async {
      final controller = AccountController(
        authRepository: FakeAuthRepository(initialIdentity: _anonymousIdentity),
      );
      await controller.load();

      await controller.linkAccount(
        email: ' jamie@example.com ',
        password: 'password123',
      );

      expect(controller.state.identity.uid, testNamespaceUid);
      expect(controller.state.identity.kind, AuthIdentityKind.linkedEmail);
      expect(controller.state.identity.email, 'jamie@example.com');
      expect(controller.state.successMessage, 'Account linked.');
    });

    test('link confirmation pending shows verification copy', () async {
      final controller = AccountController(
        authRepository: FakeAuthRepository(
          initialIdentity: _anonymousIdentity,
          linkedEmailConfirmed: false,
        ),
      );
      await controller.load();

      await controller.linkAccount(
        email: 'jamie@example.com',
        password: 'password123',
      );

      expect(controller.state.identity.emailConfirmed, isFalse);
      expect(controller.state.successMessage, contains('Check your email'));
    });

    test('typed link failure is stored without raw exception text', () async {
      final controller = AccountController(
        authRepository: FakeAuthRepository(
          initialIdentity: _anonymousIdentity,
          linkFailure: const AuthFailure(
            AuthErrorCode.identityChangedUnexpectedly,
            'raw sdk detail',
          ),
        ),
      );
      await controller.load();

      await controller.linkAccount(
        email: 'jamie@example.com',
        password: 'password123',
      );

      expect(
        controller.state.failure!.code,
        AuthErrorCode.identityChangedUnexpectedly,
      );
      expect(
        authFailureMessage(controller.state.failure!),
        isNot(contains('raw sdk detail')),
      );
    });

    test(
      'S1 sign-in switches identity and cancels previous reminders',
      () async {
        final notifications = _FakeNotificationService();
        final controller = AccountController(
          authRepository: FakeAuthRepository(
            initialIdentity: _anonymousIdentity,
          ),
          notificationService: notifications,
        );
        await controller.load();

        await controller.signIn(
          email: 'jamie@example.com',
          password: 'password123',
        );

        expect(controller.state.identity.uid, 'returning-uid');
        expect(notifications.cancelledHabitIds, isEmpty);
      },
    );

    test(
      'S2 requires confirmation before sign-in when data is meaningful',
      () async {
        await _addHabit('anon-habit');
        final repo = FakeAuthRepository(initialIdentity: _anonymousIdentity);
        final controller = AccountController(authRepository: repo);
        await controller.load();

        await controller.signIn(
          email: 'jamie@example.com',
          password: 'password123',
        );

        expect(controller.state.confirmationRequired, isTrue);
        expect(repo.signInWithEmailPasswordCallCount, 0);
        expect(controller.state.identity.kind, AuthIdentityKind.anonymous);
      },
    );

    test(
      'S2 preserve creates snapshot then signs in without copying data',
      () async {
        await _addHabit('anon-habit');
        final repo = FakeAuthRepository(initialIdentity: _anonymousIdentity);
        final notifications = _FakeNotificationService();
        final controller = AccountController(
          authRepository: repo,
          notificationService: notifications,
        );
        await controller.load();
        await controller.signIn(
          email: 'jamie@example.com',
          password: 'password123',
        );

        await controller.confirmPreserveAndSignIn();

        expect(controller.state.identity.uid, 'returning-uid');
        expect(notifications.cancelledHabitIds, contains('anon-habit'));
        LocalNamespaceResolver.debugUidOverride = 'returning-uid';
        expect(await HabitStorage().loadHabitsRaw(), isNull);
        LocalNamespaceResolver.debugUidOverride = testNamespaceUid;
        expect((await HabitStorage().loadHabitsRaw())!.single.id, 'anon-habit');
      },
    );

    test('S2 cancel leaves anonymous state unchanged', () async {
      await _addHabit('anon-habit');
      final repo = FakeAuthRepository(initialIdentity: _anonymousIdentity);
      final notifications = _FakeNotificationService();
      final controller = AccountController(
        authRepository: repo,
        notificationService: notifications,
      );
      await controller.load();
      await controller.signIn(
        email: 'jamie@example.com',
        password: 'password123',
      );

      controller.cancelPendingSignIn();

      expect(controller.state.confirmationRequired, isFalse);
      expect(controller.state.identity.kind, AuthIdentityKind.anonymous);
      expect(repo.signInWithEmailPasswordCallCount, 0);
    });

    test('returning sign-in failures show typed errors', () async {
      final controller = AccountController(
        authRepository: FakeAuthRepository(
          initialIdentity: _anonymousIdentity,
          signInFailure: const AuthFailure(
            AuthErrorCode.invalidCredentials,
            'Incorrect email or password.',
          ),
        ),
      );
      await controller.load();

      await controller.signIn(email: 'jamie@example.com', password: 'wrong');

      expect(controller.state.failure!.code, AuthErrorCode.invalidCredentials);
    });

    test('blank returning uid is rejected', () async {
      final controller = AccountController(
        authRepository: FakeAuthRepository(
          initialIdentity: _anonymousIdentity,
          signInIdentity: const AuthIdentity(
            uid: '',
            kind: AuthIdentityKind.authenticatedReturningUser,
            email: 'jamie@example.com',
          ),
        ),
      );
      await controller.load();

      await controller.signIn(
        email: 'jamie@example.com',
        password: 'password123',
      );

      expect(controller.state.failure!.code, AuthErrorCode.unknown);
    });

    test('anonymous returning identity is rejected', () async {
      final controller = AccountController(
        authRepository: FakeAuthRepository(
          initialIdentity: _anonymousIdentity,
          signInIdentity: const AuthIdentity(
            uid: 'returning-uid',
            kind: AuthIdentityKind.anonymous,
          ),
        ),
      );
      await controller.load();

      await controller.signIn(
        email: 'jamie@example.com',
        password: 'password123',
      );

      expect(controller.state.failure!.code, AuthErrorCode.unknown);
    });

    test('same uid returning identity is rejected', () async {
      final controller = AccountController(
        authRepository: FakeAuthRepository(
          initialIdentity: _anonymousIdentity,
          signInIdentity: const AuthIdentity(
            uid: testNamespaceUid,
            kind: AuthIdentityKind.authenticatedReturningUser,
            email: 'jamie@example.com',
          ),
        ),
      );
      await controller.load();

      await controller.signIn(
        email: 'jamie@example.com',
        password: 'password123',
      );

      expect(
        controller.state.failure!.code,
        AuthErrorCode.identityChangedUnexpectedly,
      );
    });

    test(
      'sign out creates fresh anonymous identity and keeps old namespace',
      () async {
        LocalNamespaceResolver.debugUidOverride = 'linked-uid';
        await _addHabit('linked-habit');
        final notifications = _FakeNotificationService();
        final repo = FakeAuthRepository(
          initialIdentity: const AuthIdentity(
            uid: 'linked-uid',
            kind: AuthIdentityKind.linkedEmail,
            email: 'jamie@example.com',
            emailConfirmed: true,
          ),
          anonymousUid: 'fresh-anon-uid',
        );
        final controller = AccountController(
          authRepository: repo,
          notificationService: notifications,
        );
        await controller.load();

        await controller.signOut();

        expect(controller.state.identity.uid, 'fresh-anon-uid');
        expect(notifications.cancelledHabitIds, contains('linked-habit'));
        LocalNamespaceResolver.debugUidOverride = 'linked-uid';
        expect(
          (await HabitStorage().loadHabitsRaw())!.single.id,
          'linked-habit',
        );
      },
    );

    test('sign out same uid reuse is rejected safely', () async {
      final controller = AccountController(
        authRepository: FakeAuthRepository(
          initialIdentity: const AuthIdentity(
            uid: 'linked-uid',
            kind: AuthIdentityKind.linkedEmail,
          ),
          anonymousUid: 'linked-uid',
        ),
      );
      await controller.load();

      await controller.signOut();

      expect(
        controller.state.failure!.code,
        AuthErrorCode.identityChangedUnexpectedly,
      );
    });

    test('anonymous recreation failure is shown safely', () async {
      final controller = AccountController(
        authRepository: FakeAuthRepository(
          initialIdentity: const AuthIdentity(
            uid: 'linked-uid',
            kind: AuthIdentityKind.linkedEmail,
          ),
          anonymousSessionSucceeds: false,
        ),
      );
      await controller.load();

      await controller.signOut();

      expect(controller.state.failure!.code, AuthErrorCode.networkUnavailable);
    });
  });

  group('AccountController.deleteAccount', () {
    test('success returns to a fresh anonymous identity', () async {
      final authRepository = FakeAuthRepository(
        initialIdentity: _linkedIdentity,
        anonymousUid: 'fresh-anon-uid',
      );
      final cleanup = _RecordingCleanupService();
      var identityChangedCalls = 0;
      final controller = AccountController(
        authRepository: authRepository,
        deletionService: AccountDeletionService(
          authRepository: authRepository,
          deletionRepository: _FakeDeletionRepository(),
          cleanupService: cleanup,
          notificationService: _FakeNotificationService(),
        ),
        onIdentityChanged: () async {
          identityChangedCalls++;
        },
      );
      await controller.load();

      await controller.deleteAccount();

      expect(controller.state.identity.uid, 'fresh-anon-uid');
      expect(controller.state.identity.kind, AuthIdentityKind.anonymous);
      expect(controller.state.deletionFailure, isNull);
      expect(controller.state.successMessage, isNotNull);
      expect(identityChangedCalls, 1);
      expect(cleanup.wipedUids, [testNamespaceUid]);
    });

    test(
      'remote failure shows a friendly error and keeps the account',
      () async {
        final authRepository = FakeAuthRepository(
          initialIdentity: _linkedIdentity,
        );
        final controller = AccountController(
          authRepository: authRepository,
          deletionService: AccountDeletionService(
            authRepository: authRepository,
            deletionRepository: _FakeDeletionRepository()
              ..result = AccountDeletionCloudResult.failure(
                const AccountDeletionCloudFailure(
                  AccountDeletionCloudErrorCode.networkUnavailable,
                  'raw',
                ),
              ),
            cleanupService: _RecordingCleanupService(),
            notificationService: _FakeNotificationService(),
          ),
        );
        await controller.load();

        await controller.deleteAccount();

        expect(controller.state.identity.uid, testNamespaceUid);
        expect(controller.state.identity.kind, AuthIdentityKind.linkedEmail);
        expect(
          controller.state.deletionFailure!.code,
          AccountDeletionFailureCode.networkUnavailable,
        );
        expect(controller.state.deletionPartialFailure, isFalse);
        expect(
          accountDeletionFailureMessage(controller.state.deletionFailure!),
          isNot(contains('raw')),
        );
      },
    );

    test(
      'partial failure is shown safely without raw exception text',
      () async {
        final authRepository = FakeAuthRepository(
          initialIdentity: _linkedIdentity,
          anonymousSessionSucceeds: false,
        );
        final controller = AccountController(
          authRepository: authRepository,
          deletionService: AccountDeletionService(
            authRepository: authRepository,
            deletionRepository: _FakeDeletionRepository(),
            cleanupService: _RecordingCleanupService(),
            notificationService: _FakeNotificationService(),
          ),
        );
        await controller.load();

        await controller.deleteAccount();

        expect(controller.state.deletionPartialFailure, isTrue);
        expect(
          controller.state.deletionFailure!.code,
          AccountDeletionFailureCode.anonymousReauthFailed,
        );
        final message = accountDeletionFailureMessage(
          controller.state.deletionFailure!,
        );
        expect(message, isNot(contains('Exception')));
        expect(message, isNot(contains('StackTrace')));
      },
    );

    test('duplicate calls while deleting are ignored', () async {
      final authRepository = FakeAuthRepository(
        initialIdentity: _linkedIdentity,
        anonymousUid: 'fresh-anon-uid',
      );
      final deletionRepository = _FakeDeletionRepository();
      final controller = AccountController(
        authRepository: authRepository,
        deletionService: AccountDeletionService(
          authRepository: authRepository,
          deletionRepository: deletionRepository,
          cleanupService: _RecordingCleanupService(),
          notificationService: _FakeNotificationService(),
        ),
      );
      await controller.load();

      final first = controller.deleteAccount();
      final second = controller.deleteAccount();
      await Future.wait([first, second]);

      expect(controller.state.identity.uid, 'fresh-anon-uid');
    });
  });

  group('validation and error copy', () {
    test('validates email and password fields', () {
      expect(validateAccountEmail(''), 'Enter your email.');
      expect(validateAccountEmail('bad'), 'Enter a valid email address.');
      expect(validateAccountEmail('a@example.com'), isNull);
      expect(validateAccountPassword(''), 'Enter your password.');
      expect(validateAccountPassword('123'), 'Use at least 6 characters.');
      expect(validateAccountPassword('123456'), isNull);
    });

    test('maps typed failures to friendly messages', () {
      expect(
        authFailureMessage(
          const AuthFailure(AuthErrorCode.emailNotConfirmed, 'raw'),
        ),
        'Confirm your email before signing in.',
      );
      expect(
        authFailureMessage(
          const AuthFailure(AuthErrorCode.identityChangedUnexpectedly, 'raw'),
        ),
        isNot(contains('raw')),
      );
    });
  });
}
