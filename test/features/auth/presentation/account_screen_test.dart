import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_habit_coach/core/storage/local_namespace_resolver.dart';
import 'package:smart_habit_coach/features/auth/domain/auth_error.dart';
import 'package:smart_habit_coach/features/auth/domain/auth_identity.dart';
import 'package:smart_habit_coach/features/auth/presentation/account_keys.dart';
import 'package:smart_habit_coach/features/auth/presentation/account_screen.dart';
import 'package:smart_habit_coach/features/home/data/habit_storage.dart';
import 'package:smart_habit_coach/features/home/domain/habit.dart';

import '../../../support/fake_auth_repository.dart';
import '../../../support/test_namespace.dart';

const _anonymousIdentity = AuthIdentity(
  uid: testNamespaceUid,
  kind: AuthIdentityKind.anonymous,
);

Future<void> _pumpAccount(
  WidgetTester tester,
  FakeAuthRepository repository,
) async {
  await tester.pumpWidget(
    MaterialApp(home: AccountScreen(authRepository: repository)),
  );
  await tester.pumpAndSettle();
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

  testWidgets('Account screen shows anonymous state', (tester) async {
    await _pumpAccount(
      tester,
      FakeAuthRepository(initialIdentity: _anonymousIdentity),
    );

    expect(find.text('Anonymous account'), findsOneWidget);
    expect(find.text('Link account'), findsOneWidget);
    expect(find.text('Sign in to existing account'), findsOneWidget);
    expect(find.textContaining(testNamespaceUid), findsNothing);
  });

  testWidgets('Account screen shows linked email state', (tester) async {
    await _pumpAccount(
      tester,
      FakeAuthRepository(
        initialIdentity: const AuthIdentity(
          uid: 'linked-uid',
          kind: AuthIdentityKind.linkedEmail,
          email: 'jamie@example.com',
          emailConfirmed: true,
        ),
      ),
    );

    expect(find.text('jamie@example.com'), findsOneWidget);
    expect(find.text('Email confirmed.'), findsOneWidget);
    expect(find.text('Sign out'), findsOneWidget);
  });

  testWidgets('Account screen shows confirmation pending state', (
    tester,
  ) async {
    await _pumpAccount(
      tester,
      FakeAuthRepository(
        initialIdentity: const AuthIdentity(
          uid: 'linked-uid',
          kind: AuthIdentityKind.linkedEmail,
          email: 'jamie@example.com',
          emailConfirmed: false,
        ),
      ),
    );

    expect(
      find.text('Check your email to confirm the address.'),
      findsOneWidget,
    );
  });

  testWidgets('Account screen shows unauthenticated retry state', (
    tester,
  ) async {
    await _pumpAccount(tester, FakeAuthRepository());

    expect(find.text('Session not ready'), findsOneWidget);
    expect(find.byKey(accountRetryButtonKey), findsOneWidget);
  });

  testWidgets('Link form validates email and password mismatch', (
    tester,
  ) async {
    await _pumpAccount(
      tester,
      FakeAuthRepository(initialIdentity: _anonymousIdentity),
    );

    await tester.tap(find.byKey(accountLinkActionKey));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(linkEmailFieldKey), 'bad');
    await tester.enterText(find.byKey(linkPasswordFieldKey), '123456');
    await tester.enterText(find.byKey(linkConfirmPasswordFieldKey), '654321');
    await tester.tap(find.byKey(linkSubmitButtonKey));
    await tester.pumpAndSettle();

    expect(find.text('Enter a valid email address.'), findsOneWidget);
    expect(find.text('Passwords must match.'), findsOneWidget);
  });

  testWidgets('Link flow shows typed error safely', (tester) async {
    await _pumpAccount(
      tester,
      FakeAuthRepository(
        initialIdentity: _anonymousIdentity,
        linkFailure: const AuthFailure(
          AuthErrorCode.emailAlreadyInUse,
          'raw backend detail',
        ),
      ),
    );

    await tester.tap(find.byKey(accountLinkActionKey));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(linkEmailFieldKey), 'jamie@example.com');
    await tester.enterText(find.byKey(linkPasswordFieldKey), 'password123');
    await tester.enterText(
      find.byKey(linkConfirmPasswordFieldKey),
      'password123',
    );
    await tester.tap(find.byKey(linkSubmitButtonKey));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('That email is already registered'),
      findsOneWidget,
    );
    expect(find.textContaining('raw backend detail'), findsNothing);
  });

  testWidgets('S2 sign-in shows confirmation before signing in', (
    tester,
  ) async {
    await _addHabit('anon-habit');
    final repository = FakeAuthRepository(initialIdentity: _anonymousIdentity);
    await _pumpAccount(tester, repository);

    await tester.tap(find.byKey(accountSignInActionKey));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(signInEmailFieldKey),
      'jamie@example.com',
    );
    await tester.enterText(find.byKey(signInPasswordFieldKey), 'password123');
    await tester.tap(find.byKey(signInSubmitButtonKey));
    await tester.pumpAndSettle();

    expect(find.text('Preserve local data?'), findsOneWidget);
    expect(repository.signInWithEmailPasswordCallCount, 0);
  });

  testWidgets('S2 cancel leaves anonymous account visible', (tester) async {
    await _addHabit('anon-habit');
    final repository = FakeAuthRepository(initialIdentity: _anonymousIdentity);
    await _pumpAccount(tester, repository);

    await tester.tap(find.byKey(accountSignInActionKey));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(signInEmailFieldKey),
      'jamie@example.com',
    );
    await tester.enterText(find.byKey(signInPasswordFieldKey), 'password123');
    await tester.tap(find.byKey(signInSubmitButtonKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(cancelAccountSwitchButtonKey));
    await tester.pumpAndSettle();

    expect(find.text('Anonymous account'), findsOneWidget);
    expect(repository.signInWithEmailPasswordCallCount, 0);
  });

  testWidgets('Sign out requires confirmation', (tester) async {
    final repository = FakeAuthRepository(
      initialIdentity: const AuthIdentity(
        uid: 'linked-uid',
        kind: AuthIdentityKind.linkedEmail,
        email: 'jamie@example.com',
        emailConfirmed: true,
      ),
      anonymousUid: 'fresh-anon-uid',
    );
    await _pumpAccount(tester, repository);

    await tester.tap(find.byKey(signOutActionKey));
    await tester.pumpAndSettle();

    expect(find.text('Sign out?'), findsOneWidget);
    expect(repository.signOutCallCount, 0);

    await tester.tap(find.widgetWithText(FilledButton, 'Sign out'));
    await tester.pumpAndSettle();

    expect(repository.signOutCallCount, 1);
    expect(find.text('Anonymous account'), findsOneWidget);
  });
}
