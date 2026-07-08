import 'package:flutter_test/flutter_test.dart';
import 'package:smart_habit_coach/features/auth/data/supabase_auth_repository.dart';
import 'package:smart_habit_coach/features/auth/domain/auth_error.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('mapAuthException', () {
    test('AuthSessionMissingException maps to sessionMissing', () {
      final failure = mapAuthException(AuthSessionMissingException());
      expect(failure.code, AuthErrorCode.sessionMissing);
    });

    test('AuthRetryableFetchException maps to networkUnavailable', () {
      final failure = mapAuthException(AuthRetryableFetchException());
      expect(failure.code, AuthErrorCode.networkUnavailable);
    });

    test('AuthWeakPasswordException maps to weakPassword', () {
      final failure = mapAuthException(
        AuthWeakPasswordException(
          message: 'weak',
          statusCode: '422',
          reasons: const ['length'],
        ),
      );
      expect(failure.code, AuthErrorCode.weakPassword);
    });

    test('AuthApiException with email_exists maps to emailAlreadyInUse', () {
      final failure = mapAuthException(
        AuthApiException('exists', code: 'email_exists'),
      );
      expect(failure.code, AuthErrorCode.emailAlreadyInUse);
    });

    test('AuthApiException with weak_password code maps to weakPassword', () {
      final failure = mapAuthException(
        AuthApiException('weak', code: 'weak_password'),
      );
      expect(failure.code, AuthErrorCode.weakPassword);
    });

    test('AuthApiException with invalid_email maps to invalidEmail', () {
      final failure = mapAuthException(
        AuthApiException('bad email', code: 'invalid_email'),
      );
      expect(failure.code, AuthErrorCode.invalidEmail);
    });

    test('AuthApiException with validation_failed maps to invalidEmail', () {
      final failure = mapAuthException(
        AuthApiException('validation failed', code: 'validation_failed'),
      );
      expect(failure.code, AuthErrorCode.invalidEmail);
    });

    test(
      'AuthApiException with email_not_confirmed maps to emailNotConfirmed',
      () {
        final failure = mapAuthException(
          AuthApiException('not confirmed', code: 'email_not_confirmed'),
        );
        expect(failure.code, AuthErrorCode.emailNotConfirmed);
      },
    );

    test(
      'AuthApiException with over_request_rate_limit maps to rateLimited',
      () {
        final failure = mapAuthException(
          AuthApiException('slow down', code: 'over_request_rate_limit'),
        );
        expect(failure.code, AuthErrorCode.rateLimited);
      },
    );

    test(
      'AuthApiException with invalid_credentials code maps to invalidCredentials',
      () {
        final failure = mapAuthException(
          AuthApiException('bad creds', code: 'invalid_credentials'),
        );
        expect(failure.code, AuthErrorCode.invalidCredentials);
      },
    );

    test('AuthApiException with no code but an "Invalid login credentials" '
        'message still maps to invalidCredentials', () {
      final failure = mapAuthException(
        AuthApiException('Invalid login credentials', statusCode: '400'),
      );
      expect(failure.code, AuthErrorCode.invalidCredentials);
    });

    test('an unrecognized AuthApiException code maps to unknown safely', () {
      final failure = mapAuthException(
        AuthApiException('database exploded', code: 'some_unmapped_code'),
      );
      expect(failure.code, AuthErrorCode.unknown);
      expect(failure.message, isNot(contains('database exploded')));
    });

    test('a non-auth exception maps to unknown', () {
      final failure = mapAuthException(StateError('boom'));
      expect(failure.code, AuthErrorCode.unknown);
    });

    test(
      'mapped failures never carry the raw exception message for unknown-safe codes',
      () {
        final failure = mapAuthException(AuthSessionMissingException());
        expect(failure.message, isNot(contains('AuthSessionMissingException')));
      },
    );
  });
}
