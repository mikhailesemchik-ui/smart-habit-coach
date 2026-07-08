import 'dart:async';

import 'package:smart_habit_coach/core/storage/local_namespace_resolver.dart';

import 'support/test_namespace.dart';

/// Runs before every test file's `main()`. Injects a stable fake UID so the
/// whole suite exercises namespaced storage without any test needing to
/// initialize a real Supabase client. Individual tests that need to
/// exercise a different UID, multiple UIDs, or the "no UID available"
/// state override `LocalNamespaceResolver.debugUidOverride` themselves and
/// should restore it (typically back to [testNamespaceUid]) in `tearDown`.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  LocalNamespaceResolver.debugUidOverride = testNamespaceUid;
  await testMain();
}
