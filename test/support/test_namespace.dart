/// Stable fake UID injected into [LocalNamespaceResolver.debugUidOverride]
/// for the whole test suite (see `test/flutter_test_config.dart`), so tests
/// never need a real Supabase client to exercise namespaced storage.
const testNamespaceUid = 'test-user-id';
