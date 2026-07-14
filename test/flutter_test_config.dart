import 'dart:async';

import 'package:smart_habit_coach/core/storage/local_namespace_resolver.dart';
import 'package:smart_habit_coach/features/home/data/notification_service.dart';

import 'support/test_namespace.dart';

/// Runs before every test file's `main()`. Injects a stable fake UID so the
/// whole suite exercises namespaced storage without any test needing to
/// initialize a real Supabase client. Individual tests that need to
/// exercise a different UID, multiple UIDs, or the "no UID available"
/// state override `LocalNamespaceResolver.debugUidOverride` themselves and
/// should restore it (typically back to [testNamespaceUid]) in `tearDown`.
///
/// Also suppresses `NotificationService`'s debug logging suite-wide: many
/// widget tests construct a real (unfaked) `NotificationService()`, whose
/// plugin calls always fail with no platform channel registered — expected,
/// already-handled noise, not a real error.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  LocalNamespaceResolver.debugUidOverride = testNamespaceUid;
  NotificationService.debugSuppressLogging = true;
  await testMain();
}
