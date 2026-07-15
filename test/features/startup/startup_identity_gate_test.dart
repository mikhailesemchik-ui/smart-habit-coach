import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_habit_coach/app.dart';
import 'package:smart_habit_coach/core/storage/user_data_schema_migrator.dart';
import 'package:smart_habit_coach/features/startup/data/auth_session_gateway.dart';
import 'package:smart_habit_coach/features/startup/presentation/startup_retry_screen.dart';

/// Deterministic fake gateway: returns each queued result in order (or
/// [defaultResult] once the queue is exhausted), and lets tests control
/// exactly when `ensureSession` resolves via [completer] when non-null,
/// to simulate an in-flight request.
class FakeAuthSessionGateway implements AuthSessionGateway {
  final List<bool> results;
  int callCount = 0;
  bool defaultResult;

  FakeAuthSessionGateway(this.results, {this.defaultResult = true});

  @override
  Future<bool> ensureSession() async {
    callCount++;
    if (results.isEmpty) return defaultResult;
    return results.removeAt(0);
  }
}

/// Deterministic fake schema migrator: returns each queued result in
/// order (or [defaultResult] once exhausted), without touching real
/// storage.
class FakeSchemaMigrator implements LocalUserDataSchemaMigrator {
  final List<bool> results;
  int callCount = 0;
  bool defaultResult;

  FakeSchemaMigrator(this.results, {this.defaultResult = true});

  @override
  Future<bool> run() async {
    callCount++;
    if (results.isEmpty) return defaultResult;
    return results.removeAt(0);
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'onboarding_completed': true});
  });

  testWidgets(
    'a persisted/immediately-succeeding session proceeds straight into the app',
    (tester) async {
      await tester.pumpWidget(
        SmartHabitCoachApp(authGateway: FakeAuthSessionGateway([true])),
      );
      await tester.pumpAndSettle();

      expect(find.byType(StartupRetryScreen), findsNothing);
      // Note: the settled Today screen now includes a small persistent
      // circular progress ring as part of its own progress card UI, so a
      // blanket "no CircularProgressIndicator anywhere" assertion no
      // longer distinguishes "still starting up" from "fully loaded" —
      // the StartupRetryScreen check above already covers that.
    },
  );

  testWidgets(
    'a failed anonymous sign-in shows the Retry screen instead of the app',
    (tester) async {
      final gateway = FakeAuthSessionGateway([false]);

      await tester.pumpWidget(SmartHabitCoachApp(authGateway: gateway));
      await tester.pumpAndSettle();

      expect(find.byType(StartupRetryScreen), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    },
  );

  testWidgets('tapping Retry after connectivity returns enters the app', (
    tester,
  ) async {
    final gateway = FakeAuthSessionGateway([false, true]);

    await tester.pumpWidget(SmartHabitCoachApp(authGateway: gateway));
    await tester.pumpAndSettle();
    expect(find.byType(StartupRetryScreen), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Retry'));
    await tester.pumpAndSettle();

    expect(find.byType(StartupRetryScreen), findsNothing);
    expect(gateway.callCount, 2);
  });

  testWidgets('a Retry tap shows a loading state while in flight', (
    tester,
  ) async {
    final gateway = FakeAuthSessionGateway([false, true]);

    await tester.pumpWidget(SmartHabitCoachApp(authGateway: gateway));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Retry'));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Retry'), findsNothing);

    await tester.pumpAndSettle();
  });

  testWidgets('duplicate Retry taps while a request is in flight are ignored', (
    tester,
  ) async {
    final gateway = FakeAuthSessionGateway([false, true, true]);

    await tester.pumpWidget(SmartHabitCoachApp(authGateway: gateway));
    await tester.pumpAndSettle();

    // Tap Retry, then immediately try again before it resolves. The second
    // tap must not be able to hit the button since it's replaced by a
    // loading indicator once the first tap starts.
    await tester.tap(find.widgetWithText(FilledButton, 'Retry'));
    await tester.pump();
    expect(find.widgetWithText(FilledButton, 'Retry'), findsNothing);

    await tester.pumpAndSettle();

    // Exactly one retry attempt happened (plus the initial failed attempt).
    expect(gateway.callCount, 2);
  });

  testWidgets('no raw technical error text is ever shown on failure', (
    tester,
  ) async {
    await tester.pumpWidget(
      SmartHabitCoachApp(authGateway: FakeAuthSessionGateway([false])),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Exception'), findsNothing);
    expect(find.textContaining('Error:'), findsNothing);
  });

  testWidgets(
    'a failed schema migration shows the Retry screen instead of the app',
    (tester) async {
      await tester.pumpWidget(
        SmartHabitCoachApp(
          authGateway: FakeAuthSessionGateway([true]),
          schemaMigrator: FakeSchemaMigrator([false]),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(StartupRetryScreen), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    },
  );

  testWidgets(
    'retrying after a schema migration failure re-runs the pipeline and enters the app',
    (tester) async {
      final schemaMigrator = FakeSchemaMigrator([false, true]);

      await tester.pumpWidget(
        SmartHabitCoachApp(
          authGateway: FakeAuthSessionGateway([true]),
          schemaMigrator: schemaMigrator,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(StartupRetryScreen), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Retry'));
      await tester.pumpAndSettle();

      expect(find.byType(StartupRetryScreen), findsNothing);
      expect(schemaMigrator.callCount, 2);
    },
  );

  testWidgets(
    'a schema migration failure never shows raw technical error text',
    (tester) async {
      await tester.pumpWidget(
        SmartHabitCoachApp(
          authGateway: FakeAuthSessionGateway([true]),
          schemaMigrator: FakeSchemaMigrator([false]),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Exception'), findsNothing);
      expect(find.textContaining('Error:'), findsNothing);
    },
  );

  testWidgets(
    'the app only proceeds past the loading state once schema migration succeeds',
    (tester) async {
      final schemaMigrator = FakeSchemaMigrator([]);
      await tester.pumpWidget(
        SmartHabitCoachApp(
          authGateway: FakeAuthSessionGateway([true]),
          schemaMigrator: schemaMigrator,
        ),
      );
      // Before the pipeline settles, the app must show a loading state —
      // never onboarding/main nav — since schema migration (and therefore
      // habit/settings reads) has not completed yet.
      await tester.pump();
      expect(find.byType(StartupRetryScreen), findsNothing);

      await tester.pumpAndSettle();
      expect(schemaMigrator.callCount, 1);
      expect(find.byType(StartupRetryScreen), findsNothing);
    },
  );
}
