import 'package:flutter_test/flutter_test.dart';
import 'package:smart_habit_coach/core/storage/local_namespace_resolver.dart';

import '../../support/test_namespace.dart';

void main() {
  tearDown(() {
    LocalNamespaceResolver.debugUidOverride = testNamespaceUid;
  });

  group('LocalNamespaceResolver', () {
    test('resolveKey is unavailable when no UID override is set (Supabase '
        'uninitialized, no session) — never a plain-key fallback', () {
      LocalNamespaceResolver.debugUidOverride = null;
      const resolver = LocalNamespaceResolver();

      final result = resolver.resolveKey('habits');

      expect(result.isAvailable, isFalse);
      expect(result.key, isNull);
    });

    test(
      'currentUid is null when no override and Supabase is uninitialized',
      () {
        LocalNamespaceResolver.debugUidOverride = null;
        const resolver = LocalNamespaceResolver();

        expect(resolver.currentUid, isNull);
      },
    );

    test('same debugUidOverride produces the same key every time', () {
      LocalNamespaceResolver.debugUidOverride = 'uid-a';
      const resolver = LocalNamespaceResolver();

      final first = resolver.resolveKey('habits');
      final second = resolver.resolveKey('habits');

      expect(first.key, second.key);
      expect(first.key, 'habits:uid-a');
    });

    test(
      'different debugUidOverride values produce different, isolated keys',
      () {
        const resolver = LocalNamespaceResolver();

        LocalNamespaceResolver.debugUidOverride = 'uid-a';
        final a = resolver.resolveKey('habits');

        LocalNamespaceResolver.debugUidOverride = 'uid-b';
        final b = resolver.resolveKey('habits');

        expect(a.key, isNot(equals(b.key)));
      },
    );

    test(
      'blank debugUidOverride is treated as unavailable, not a valid UID',
      () {
        LocalNamespaceResolver.debugUidOverride = '   ';
        const resolver = LocalNamespaceResolver();

        final result = resolver.resolveKey('habits');

        expect(result.isAvailable, isFalse);
        expect(result.key, isNull);
      },
    );

    test('currentUid reflects a set debugUidOverride', () {
      LocalNamespaceResolver.debugUidOverride = 'uid-a';
      const resolver = LocalNamespaceResolver();

      expect(resolver.currentUid, 'uid-a');
    });

    test('key coverage: habits, adaptive_suggestions, app_settings, and a '
        'schema-version key are all distinct and stable for the same UID', () {
      LocalNamespaceResolver.debugUidOverride = 'uid-a';
      const resolver = LocalNamespaceResolver();

      final habits = resolver.resolveKey('habits').key;
      final suggestions = resolver.resolveKey('adaptive_suggestions').key;
      final settings = resolver.resolveKey('app_settings').key;
      final schemaVersion = resolver.resolveKey('local_schema_version').key;

      final keys = {habits, suggestions, settings, schemaVersion};
      expect(
        keys.length,
        4,
        reason: 'every base key must map to a distinct namespaced key',
      );
      expect(habits, 'habits:uid-a');
      expect(suggestions, 'adaptive_suggestions:uid-a');
      expect(settings, 'app_settings:uid-a');
      expect(schemaVersion, 'local_schema_version:uid-a');
    });
  });
}
