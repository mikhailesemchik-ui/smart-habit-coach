import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Static checks over the `delete-account` Edge Function source, since this
/// repo has no Deno test runner wired up. These assert structural safety
/// properties from the source text itself — they do not execute the
/// function.
void main() {
  late String source;
  late String config;

  setUpAll(() {
    source = File(
      'supabase/functions/delete-account/index.ts',
    ).readAsStringSync();
    config = File('supabase/config.toml').readAsStringSync();
  });

  test('the delete-account function exists', () {
    expect(
      File('supabase/functions/delete-account/index.ts').existsSync(),
      isTrue,
    );
  });

  test('JWT verification is required in config.toml', () {
    final functionBlock = config.split('[functions.delete-account]').last;
    expect(functionBlock, contains('verify_jwt = true'));
  });

  test('the function derives the user id from the JWT, not the body', () {
    expect(source, contains('parseUserIdFromJwt'));
    // The only body-reading call in this function is `req.json()`, which
    // is absent entirely — the function must never read a user id out of
    // an arbitrary request body.
    expect(source, isNot(contains('req.json()')));
    expect(source, isNot(contains('body.user_id')));
    expect(source, isNot(contains('body.userId')));
  });

  test('the function reads the service-role key only from an env var', () {
    expect(source, contains('Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")'));
    // No literal key material of any kind is embedded in source.
    expect(source, isNot(contains('eyJhbGciOi')));
  });

  test('the function never logs the raw error object', () {
    // console.error calls in this file must not interpolate the raw
    // `error` value itself (which could carry provider-specific detail);
    // only status codes / fixed strings are logged.
    expect(source, isNot(contains('console.error(error)')));
  });

  test('the function returns a stable, typed JSON error shape', () {
    expect(source, contains('errorResponse'));
    expect(source, contains('success: false'));
  });

  test('no service-role secret exists anywhere in the Flutter client', () {
    final libDir = Directory('lib');
    for (final entity in libDir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final content = entity.readAsStringSync();
      expect(
        content.contains('SUPABASE_SERVICE_ROLE'),
        isFalse,
        reason: '${entity.path} must never reference a service-role key',
      );
      expect(
        content.toLowerCase().contains('service_role'),
        isFalse,
        reason: '${entity.path} must never reference a service-role key',
      );
    }
  });
}
