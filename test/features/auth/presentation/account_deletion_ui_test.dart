import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_habit_coach/core/storage/local_namespace_cleanup_service.dart';
import 'package:smart_habit_coach/core/storage/local_namespace_resolver.dart';
import 'package:smart_habit_coach/features/auth/data/account_deletion_repository.dart';
import 'package:smart_habit_coach/features/auth/data/account_deletion_service.dart';
import 'package:smart_habit_coach/features/auth/domain/auth_identity.dart';
import 'package:smart_habit_coach/features/auth/presentation/account_controller.dart';
import 'package:smart_habit_coach/features/auth/presentation/account_keys.dart';
import 'package:smart_habit_coach/features/auth/presentation/account_screen.dart';
import 'package:smart_habit_coach/features/home/data/notification_service.dart';

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
  int calls = 0;

  @override
  Future<AccountDeletionCloudResult> deleteAccount() async {
    calls++;
    return result;
  }
}

class _NoopCleanupService implements LocalNamespaceCleanupService {
  @override
  Future<void> wipeNamespace(String uid) async {}
}

class _NoopNotifications extends NotificationService {
  @override
  Future<void> cancelHabitReminder(String habitId) async {}

  @override
  Future<void> cancelAll() async {}
}

Future<void> _pumpAccount(
  WidgetTester tester,
  FakeAuthRepository repository, {
  AccountController? controller,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: AccountScreen(authRepository: repository, controller: controller),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    LocalNamespaceResolver.debugUidOverride = testNamespaceUid;
  });
  tearDown(() {
    LocalNamespaceResolver.debugUidOverride = testNamespaceUid;
  });

  testWidgets('Delete account is hidden for anonymous users', (tester) async {
    await _pumpAccount(
      tester,
      FakeAuthRepository(initialIdentity: _anonymousIdentity),
    );

    expect(find.byKey(deleteAccountActionKey), findsNothing);
  });

  testWidgets('Delete account is visible for email-backed users', (
    tester,
  ) async {
    await _pumpAccount(
      tester,
      FakeAuthRepository(initialIdentity: _linkedIdentity),
    );

    expect(find.byKey(deleteAccountActionKey), findsOneWidget);
  });

  testWidgets('confirmation dialog requires the acknowledgement checkbox', (
    tester,
  ) async {
    await _pumpAccount(
      tester,
      FakeAuthRepository(initialIdentity: _linkedIdentity),
    );

    await tester.tap(find.byKey(deleteAccountActionKey));
    await tester.pumpAndSettle();

    expect(find.text('Delete account?'), findsOneWidget);
    final confirmButton = tester.widget<FilledButton>(
      find.byKey(deleteAccountConfirmButtonKey),
    );
    expect(confirmButton.onPressed, isNull);

    await tester.tap(find.byKey(deleteAccountConfirmCheckboxKey));
    await tester.pumpAndSettle();

    final enabledButton = tester.widget<FilledButton>(
      find.byKey(deleteAccountConfirmButtonKey),
    );
    expect(enabledButton.onPressed, isNotNull);
  });

  testWidgets('cancel leaves the account untouched', (tester) async {
    final repository = FakeAuthRepository(initialIdentity: _linkedIdentity);
    await _pumpAccount(tester, repository);

    await tester.tap(find.byKey(deleteAccountActionKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(deleteAccountCancelButtonKey));
    await tester.pumpAndSettle();

    expect(find.text('jamie@example.com'), findsOneWidget);
  });

  testWidgets('success returns to a fresh anonymous account', (tester) async {
    final authRepository = FakeAuthRepository(
      initialIdentity: _linkedIdentity,
      anonymousUid: 'fresh-anon-uid',
    );
    final controller = AccountController(
      authRepository: authRepository,
      deletionService: AccountDeletionService(
        authRepository: authRepository,
        deletionRepository: _FakeDeletionRepository(),
        cleanupService: _NoopCleanupService(),
        notificationService: _NoopNotifications(),
      ),
    );
    await _pumpAccount(tester, authRepository, controller: controller);

    await tester.tap(find.byKey(deleteAccountActionKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(deleteAccountConfirmCheckboxKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(deleteAccountConfirmButtonKey));
    await tester.pumpAndSettle();

    expect(find.text('Anonymous account'), findsOneWidget);
    expect(find.text('jamie@example.com'), findsNothing);
    expect(find.byKey(deleteAccountActionKey), findsNothing);
  });

  testWidgets('remote failure shows a friendly error, never a raw exception', (
    tester,
  ) async {
    final authRepository = FakeAuthRepository(initialIdentity: _linkedIdentity);
    final controller = AccountController(
      authRepository: authRepository,
      deletionService: AccountDeletionService(
        authRepository: authRepository,
        deletionRepository: _FakeDeletionRepository()
          ..result = AccountDeletionCloudResult.failure(
            const AccountDeletionCloudFailure(
              AccountDeletionCloudErrorCode.remoteDeletionFailed,
              'raw backend detail',
            ),
          ),
        cleanupService: _NoopCleanupService(),
        notificationService: _NoopNotifications(),
      ),
    );
    await _pumpAccount(tester, authRepository, controller: controller);

    await tester.tap(find.byKey(deleteAccountActionKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(deleteAccountConfirmCheckboxKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(deleteAccountConfirmButtonKey));
    await tester.pumpAndSettle();

    expect(find.text('jamie@example.com'), findsOneWidget);
    expect(find.textContaining('raw backend detail'), findsNothing);
    expect(find.byKey(deleteAccountActionKey), findsOneWidget);
  });

  testWidgets('partial failure is shown without claiming full success', (
    tester,
  ) async {
    final authRepository = FakeAuthRepository(
      initialIdentity: _linkedIdentity,
      anonymousSessionSucceeds: false,
    );
    final controller = AccountController(
      authRepository: authRepository,
      deletionService: AccountDeletionService(
        authRepository: authRepository,
        deletionRepository: _FakeDeletionRepository(),
        cleanupService: _NoopCleanupService(),
        notificationService: _NoopNotifications(),
      ),
    );
    await _pumpAccount(tester, authRepository, controller: controller);

    await tester.tap(find.byKey(deleteAccountActionKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(deleteAccountConfirmCheckboxKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(deleteAccountConfirmButtonKey));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('a fresh identity could not be set up'),
      findsOneWidget,
    );
    expect(find.textContaining('Exception'), findsNothing);
    expect(find.textContaining('StateError'), findsNothing);
  });

  testWidgets('duplicate confirm taps do not call deletion twice', (
    tester,
  ) async {
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
        cleanupService: _NoopCleanupService(),
        notificationService: _NoopNotifications(),
      ),
    );
    await _pumpAccount(tester, authRepository, controller: controller);

    await tester.tap(find.byKey(deleteAccountActionKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(deleteAccountConfirmCheckboxKey));
    await tester.pumpAndSettle();

    final first = controller.deleteAccount();
    final second = controller.deleteAccount();
    await Future.wait([first, second]);

    expect(deletionRepository.calls, 1);
  });
}
