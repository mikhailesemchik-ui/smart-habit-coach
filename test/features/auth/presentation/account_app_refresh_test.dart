import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_habit_coach/app.dart';
import 'package:smart_habit_coach/core/storage/local_namespace_resolver.dart';
import 'package:smart_habit_coach/core/storage/user_data_schema_migrator.dart';
import 'package:smart_habit_coach/features/auth/domain/auth_identity.dart';
import 'package:smart_habit_coach/features/auth/presentation/account_keys.dart';
import 'package:smart_habit_coach/features/home/data/notification_reconciliation_service.dart';
import 'package:smart_habit_coach/features/navigation/presentation/navigation_keys.dart';
import 'package:smart_habit_coach/features/profile/presentation/profile_keys.dart';
import 'package:smart_habit_coach/features/profile/presentation/profile_screen.dart';
import 'package:smart_habit_coach/features/startup/data/auth_session_gateway.dart';

import '../../../support/fake_auth_repository.dart';
import '../../../support/test_namespace.dart';

class _RecordingReconciliationService
    implements NotificationReconciliationService {
  int calls = 0;

  @override
  Future<void> reconcile() async {
    calls++;
  }
}

class _ReadyAuthGateway implements AuthSessionGateway {
  @override
  Future<bool> ensureSession() async => true;
}

class _ReadySchemaMigrator implements LocalUserDataSchemaMigrator {
  int callCount = 0;

  @override
  Future<bool> run() async {
    callCount++;
    return true;
  }
}

void main() {
  setUp(() {
    LocalNamespaceResolver.debugUidOverride = testNamespaceUid;
    SharedPreferences.setMockInitialValues({
      'onboarding_completed': true,
      'app_settings:$testNamespaceUid':
          '{"displayName":"Anonymous","themeMode":"system","startOfWeek":"monday"}',
      'app_settings:returning-uid':
          '{"displayName":"Returning","themeMode":"system","startOfWeek":"monday"}',
    });
  });

  tearDown(() {
    LocalNamespaceResolver.debugUidOverride = testNamespaceUid;
  });

  testWidgets('successful sign-in reloads app state for the returning uid', (
    tester,
  ) async {
    final schemaMigrator = _ReadySchemaMigrator();
    final repository = FakeAuthRepository(
      initialIdentity: const AuthIdentity(
        uid: testNamespaceUid,
        kind: AuthIdentityKind.anonymous,
      ),
      onIdentityChanged: (identity) {
        if (identity.uid.trim().isNotEmpty) {
          LocalNamespaceResolver.debugUidOverride = identity.uid;
        }
      },
    );

    await tester.pumpWidget(
      SmartHabitCoachApp(
        authGateway: _ReadyAuthGateway(),
        schemaMigrator: schemaMigrator,
        accountAuthRepository: repository,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(profileNavigationDestinationKey));
    await tester.pumpAndSettle();
    expect(find.text('Anonymous'), findsWidgets);

    final accountTile = find.byKey(profileAccountTileKey);
    await tester.scrollUntilVisible(
      accountTile,
      200,
      scrollable: find
          .descendant(
            of: find.byType(ProfileScreen),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();

    await tester.tap(accountTile);
    await tester.pumpAndSettle();
    expect(find.byKey(accountSignInActionKey), findsOneWidget);
    await tester.tap(find.byKey(accountSignInActionKey));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(signInEmailFieldKey),
      'jamie@example.com',
    );
    await tester.enterText(find.byKey(signInPasswordFieldKey), 'password123');
    await tester.tap(find.byKey(signInSubmitButtonKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(preserveAndSignInButtonKey));
    await tester.pumpAndSettle();

    expect(find.text('Get Started'), findsNothing);
    expect(find.text('Anonymous', skipOffstage: false), findsNothing);
    expect(find.text('Returning', skipOffstage: false), findsWidgets);
    expect(schemaMigrator.callCount, greaterThanOrEqualTo(2));

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString('app_settings:$testNamespaceUid'),
      contains('Anonymous'),
    );
    expect(
      prefs.getString('app_settings:returning-uid'),
      contains('Returning'),
    );
  });

  testWidgets('successful sign-in reconciles notification scheduling', (
    tester,
  ) async {
    final schemaMigrator = _ReadySchemaMigrator();
    final reconciliation = _RecordingReconciliationService();
    final repository = FakeAuthRepository(
      initialIdentity: const AuthIdentity(
        uid: testNamespaceUid,
        kind: AuthIdentityKind.anonymous,
      ),
      onIdentityChanged: (identity) {
        if (identity.uid.trim().isNotEmpty) {
          LocalNamespaceResolver.debugUidOverride = identity.uid;
        }
      },
    );

    await tester.pumpWidget(
      SmartHabitCoachApp(
        authGateway: _ReadyAuthGateway(),
        schemaMigrator: schemaMigrator,
        accountAuthRepository: repository,
        notificationReconciliationService: reconciliation,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(profileNavigationDestinationKey));
    await tester.pumpAndSettle();

    final accountTile = find.byKey(profileAccountTileKey);
    await tester.scrollUntilVisible(
      accountTile,
      200,
      scrollable: find
          .descendant(
            of: find.byType(ProfileScreen),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(accountTile);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(accountSignInActionKey));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(signInEmailFieldKey),
      'jamie@example.com',
    );
    await tester.enterText(find.byKey(signInPasswordFieldKey), 'password123');
    await tester.tap(find.byKey(signInSubmitButtonKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(preserveAndSignInButtonKey));
    await tester.pumpAndSettle();

    expect(reconciliation.calls, greaterThanOrEqualTo(1));
  });
}
