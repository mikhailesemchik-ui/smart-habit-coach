import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_habit_coach/features/home/data/notification_service.dart';
import 'package:smart_habit_coach/features/profile/domain/app_settings.dart';
import 'package:smart_habit_coach/features/profile/presentation/profile_keys.dart';
import 'package:smart_habit_coach/features/profile/presentation/profile_screen.dart';

class _FakeNotifications extends NotificationService {
  NotificationPermissionStatus status;
  int requestCalls = 0;
  Completer<void>? requestGate;

  _FakeNotifications(this.status);

  @override
  Future<NotificationPermissionStatus> permissionStatus() async => status;

  @override
  Future<bool> requestPermission() async {
    requestCalls++;
    final gate = requestGate;
    if (gate != null) await gate.future;
    status = NotificationPermissionStatus.granted;
    return true;
  }
}

Future<void> _pump(
  WidgetTester tester,
  NotificationService notifications,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: ProfileScreen(
        settings: AppSettings.defaults,
        onSettingsChanged: (_) {},
        notificationService: notifications,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> useTallViewport(WidgetTester tester) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
  }

  testWidgets('shows granted status with no recovery action', (tester) async {
    await _pump(
      tester,
      _FakeNotifications(NotificationPermissionStatus.granted),
    );

    expect(find.byKey(notificationPermissionStatusKey), findsOneWidget);
    expect(find.text('Reminders are enabled'), findsOneWidget);
    expect(find.byKey(notificationPermissionRequestButtonKey), findsNothing);
  });

  testWidgets('shows denied status with user-friendly recovery copy', (
    tester,
  ) async {
    await _pump(
      tester,
      _FakeNotifications(NotificationPermissionStatus.denied),
    );

    expect(find.text('Reminders are turned off'), findsOneWidget);
    expect(find.textContaining('may not appear'), findsOneWidget);
    expect(find.byKey(notificationPermissionRequestButtonKey), findsOneWidget);
  });

  testWidgets('shows unknown status without raw plugin error text', (
    tester,
  ) async {
    await _pump(
      tester,
      _FakeNotifications(NotificationPermissionStatus.unknown),
    );

    expect(find.text('Reminder status unavailable'), findsOneWidget);
    expect(find.textContaining('MissingPluginException'), findsNothing);
    expect(find.textContaining('PlatformException'), findsNothing);
  });

  testWidgets(
    'tapping Enable reminders requests permission once and updates status',
    (tester) async {
      await useTallViewport(tester);
      final fake = _FakeNotifications(NotificationPermissionStatus.denied);
      await _pump(tester, fake);

      final button = find.byKey(notificationPermissionRequestButtonKey);
      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(fake.requestCalls, 1);
      expect(find.text('Reminders are enabled'), findsOneWidget);
      expect(find.byKey(notificationPermissionRequestButtonKey), findsNothing);
    },
  );

  testWidgets('duplicate taps while requesting do not call twice', (
    tester,
  ) async {
    await useTallViewport(tester);
    final fake = _FakeNotifications(NotificationPermissionStatus.denied)
      ..requestGate = Completer<void>();
    await _pump(tester, fake);

    final button = find.byKey(notificationPermissionRequestButtonKey);
    await tester.tap(button);
    await tester.tap(button);
    fake.requestGate!.complete();
    await tester.pumpAndSettle();

    expect(fake.requestCalls, 1);
  });
}
