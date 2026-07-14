import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_habit_coach/core/storage/local_namespace_cleanup_service.dart';
import 'package:smart_habit_coach/core/storage/local_namespace_resolver.dart';
import 'package:smart_habit_coach/features/auth/data/account_deletion_repository.dart';
import 'package:smart_habit_coach/features/auth/data/account_deletion_service.dart';
import 'package:smart_habit_coach/features/auth/domain/account_deletion_result.dart';
import 'package:smart_habit_coach/features/auth/domain/auth_identity.dart';
import 'package:smart_habit_coach/features/home/data/habit_storage.dart';
import 'package:smart_habit_coach/features/home/data/notification_service.dart';
import 'package:smart_habit_coach/features/home/domain/habit.dart';

import '../../../support/fake_auth_repository.dart';
import '../../../support/test_namespace.dart';

const _deletedUid = testNamespaceUid;

class _FakeDeletionRepository implements AccountDeletionRepository {
  AccountDeletionCloudResult result = AccountDeletionCloudResult.success();
  int calls = 0;

  @override
  Future<AccountDeletionCloudResult> deleteAccount() async {
    calls++;
    return result;
  }
}

class _FailingCleanupService implements LocalNamespaceCleanupService {
  @override
  Future<void> wipeNamespace(String uid) async {
    throw StateError('disk error');
  }
}

class _RecordingCleanupService implements LocalNamespaceCleanupService {
  final List<String> wipedUids = [];

  @override
  Future<void> wipeNamespace(String uid) async {
    wipedUids.add(uid);
  }
}

class _FakeNotifications extends NotificationService {
  final List<String> cancelled = [];
  bool cancelAllCalled = false;

  @override
  Future<void> cancelHabitReminder(String habitId) async {
    cancelled.add(habitId);
  }

  @override
  Future<void> cancelAll() async {
    cancelAllCalled = true;
  }
}

AuthIdentity _linkedIdentity({String uid = _deletedUid}) => AuthIdentity(
  uid: uid,
  kind: AuthIdentityKind.linkedEmail,
  email: 'jamie@example.com',
  emailConfirmed: true,
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    LocalNamespaceResolver.debugUidOverride = _deletedUid;
  });
  tearDown(() {
    LocalNamespaceResolver.debugUidOverride = testNamespaceUid;
  });

  test('anonymous identity is rejected', () async {
    final authRepository = FakeAuthRepository(
      initialIdentity: const AuthIdentity(
        uid: 'anon-1',
        kind: AuthIdentityKind.anonymous,
      ),
    );
    final deletionRepository = _FakeDeletionRepository();
    final service = AccountDeletionService(
      authRepository: authRepository,
      deletionRepository: deletionRepository,
      cleanupService: _RecordingCleanupService(),
      notificationService: _FakeNotifications(),
    );

    final result = await service.deleteAccount();

    expect(result.isSuccess, isFalse);
    expect(
      result.failure!.code,
      AccountDeletionFailureCode.anonymousNotAllowed,
    );
    expect(deletionRepository.calls, 0);
  });

  test('unauthenticated identity is rejected', () async {
    final authRepository = FakeAuthRepository(
      initialIdentity: AuthIdentity.unauthenticated,
    );
    final deletionRepository = _FakeDeletionRepository();
    final service = AccountDeletionService(
      authRepository: authRepository,
      deletionRepository: deletionRepository,
      cleanupService: _RecordingCleanupService(),
      notificationService: _FakeNotifications(),
    );

    final result = await service.deleteAccount();

    expect(result.isSuccess, isFalse);
    expect(result.failure!.code, AccountDeletionFailureCode.unauthenticated);
    expect(deletionRepository.calls, 0);
  });

  test('remote deletion failure keeps local data and session intact', () async {
    final authRepository = FakeAuthRepository(
      initialIdentity: _linkedIdentity(),
    );
    final deletionRepository = _FakeDeletionRepository()
      ..result = AccountDeletionCloudResult.failure(
        const AccountDeletionCloudFailure(
          AccountDeletionCloudErrorCode.networkUnavailable,
          'raw network detail',
        ),
      );
    final cleanup = _RecordingCleanupService();
    final service = AccountDeletionService(
      authRepository: authRepository,
      deletionRepository: deletionRepository,
      cleanupService: cleanup,
      notificationService: _FakeNotifications(),
    );

    final result = await service.deleteAccount();

    expect(result.isSuccess, isFalse);
    expect(result.partialFailure, isFalse);
    expect(result.failure!.code, AccountDeletionFailureCode.networkUnavailable);
    expect(cleanup.wipedUids, isEmpty);
    expect(authRepository.signOutCallCount, 0);
    expect(authRepository.currentIdentity().uid, _deletedUid);
  });

  test('remote failure never surfaces the raw backend message', () async {
    final authRepository = FakeAuthRepository(
      initialIdentity: _linkedIdentity(),
    );
    final deletionRepository = _FakeDeletionRepository()
      ..result = AccountDeletionCloudResult.failure(
        const AccountDeletionCloudFailure(
          AccountDeletionCloudErrorCode.unknown,
          'raw backend exception detail',
        ),
      );
    final service = AccountDeletionService(
      authRepository: authRepository,
      deletionRepository: deletionRepository,
      cleanupService: _RecordingCleanupService(),
      notificationService: _FakeNotifications(),
    );

    final result = await service.deleteAccount();

    expect(result.failure!.message, isNot(contains('raw backend')));
  });

  test(
    'remote deletion success cleans up local data and returns fresh anon',
    () async {
      final habitStorage = HabitStorage();
      await habitStorage.saveHabits([
        Habit(
          id: 'h1',
          title: 'Walk',
          scheduledTime: '08:00 AM',
          icon: Icons.directions_walk_outlined,
        ),
      ]);
      final authRepository = FakeAuthRepository(
        initialIdentity: _linkedIdentity(),
        anonymousUid: 'fresh-anon-uid',
      );
      final deletionRepository = _FakeDeletionRepository();
      final cleanup = _RecordingCleanupService();
      final notifications = _FakeNotifications();
      final service = AccountDeletionService(
        authRepository: authRepository,
        deletionRepository: deletionRepository,
        habitStorage: habitStorage,
        cleanupService: cleanup,
        notificationService: notifications,
      );

      final result = await service.deleteAccount();

      expect(result.isSuccess, isTrue);
      expect(result.partialFailure, isFalse);
      expect(result.newIdentity!.uid, 'fresh-anon-uid');
      expect(result.newIdentity!.kind, AuthIdentityKind.anonymous);
      expect(cleanup.wipedUids, [_deletedUid]);
      expect(notifications.cancelled, contains('h1'));
      expect(notifications.cancelAllCalled, isTrue);
      expect(authRepository.signOutCallCount, 1);
      expect(authRepository.ensureAnonymousSessionCallCount, 1);
    },
  );

  test(
    'backend success then local cleanup failure reports partial failure',
    () async {
      final authRepository = FakeAuthRepository(
        initialIdentity: _linkedIdentity(),
        anonymousUid: 'fresh-anon-uid',
      );
      final deletionRepository = _FakeDeletionRepository();
      final service = AccountDeletionService(
        authRepository: authRepository,
        deletionRepository: deletionRepository,
        cleanupService: _FailingCleanupService(),
        notificationService: _FakeNotifications(),
      );

      final result = await service.deleteAccount();

      expect(result.isSuccess, isFalse);
      expect(result.partialFailure, isTrue);
      expect(
        result.failure!.code,
        AccountDeletionFailureCode.localCleanupFailed,
      );
      // The app still moves forward to the fresh anonymous identity even
      // though local cleanup of the deleted namespace failed.
      expect(result.newIdentity!.uid, 'fresh-anon-uid');
    },
  );

  test(
    'anonymous reauth failure after deletion is reported as partial',
    () async {
      final authRepository = FakeAuthRepository(
        initialIdentity: _linkedIdentity(),
        anonymousSessionSucceeds: false,
      );
      final deletionRepository = _FakeDeletionRepository();
      final cleanup = _RecordingCleanupService();
      final service = AccountDeletionService(
        authRepository: authRepository,
        deletionRepository: deletionRepository,
        cleanupService: cleanup,
        notificationService: _FakeNotifications(),
      );

      final result = await service.deleteAccount();

      expect(result.isSuccess, isFalse);
      expect(result.partialFailure, isTrue);
      expect(
        result.failure!.code,
        AccountDeletionFailureCode.anonymousReauthFailed,
      );
      // Local cleanup still happened — only re-establishing anonymity failed.
      expect(cleanup.wipedUids, [_deletedUid]);
    },
  );

  test(
    'identity changed mid-flow after remote success skips local cleanup',
    () async {
      final authRepository = _IdentityChangingAuthRepository(
        initial: _linkedIdentity(),
        changedTo: _linkedIdentity(uid: 'a-different-uid'),
      );
      final deletionRepository = _FakeDeletionRepository();
      final cleanup = _RecordingCleanupService();
      final service = AccountDeletionService(
        authRepository: authRepository,
        deletionRepository: deletionRepository,
        cleanupService: cleanup,
        notificationService: _FakeNotifications(),
      );

      final result = await service.deleteAccount();

      expect(result.isSuccess, isFalse);
      expect(result.partialFailure, isTrue);
      expect(result.failure!.code, AccountDeletionFailureCode.identityChanged);
      expect(cleanup.wipedUids, isEmpty);
    },
  );

  test('does not wipe another UID\'s local data', () async {
    LocalNamespaceResolver.debugUidOverride = _deletedUid;
    final habitStorage = HabitStorage();
    await habitStorage.saveHabits([
      Habit(
        id: 'deleted-uid-habit',
        title: 'Walk',
        scheduledTime: '08:00 AM',
        icon: Icons.directions_walk_outlined,
      ),
    ]);

    LocalNamespaceResolver.debugUidOverride = 'other-uid';
    final otherHabitStorage = HabitStorage();
    await otherHabitStorage.saveHabits([
      Habit(
        id: 'other-uid-habit',
        title: 'Read',
        scheduledTime: '09:00 AM',
        icon: Icons.book_outlined,
      ),
    ]);

    LocalNamespaceResolver.debugUidOverride = _deletedUid;
    final authRepository = FakeAuthRepository(
      initialIdentity: _linkedIdentity(),
      anonymousUid: 'fresh-anon-uid',
    );
    final service = AccountDeletionService(
      authRepository: authRepository,
      deletionRepository: _FakeDeletionRepository(),
      habitStorage: habitStorage,
      cleanupService: const LocalNamespaceCleanupService(),
      notificationService: _FakeNotifications(),
    );

    await service.deleteAccount();

    LocalNamespaceResolver.debugUidOverride = 'other-uid';
    final remaining = await otherHabitStorage.loadHabitsRaw();
    expect(remaining!.map((h) => h.id), contains('other-uid-habit'));
  });
}

/// Reports [initial] on the first `currentIdentity()` read (used by the
/// pre-flight check and the uid-captured-before-the-call), then switches to
/// [changedTo] for every subsequent read — simulating a genuine race where
/// another sign-in completes while the delete-account network call is in
/// flight.
class _IdentityChangingAuthRepository extends FakeAuthRepository {
  final AuthIdentity changedTo;
  int _reads = 0;

  _IdentityChangingAuthRepository({
    required AuthIdentity initial,
    required this.changedTo,
  }) : super(initialIdentity: initial);

  @override
  AuthIdentity currentIdentity() {
    _reads++;
    return _reads == 1 ? super.currentIdentity() : changedTo;
  }
}
