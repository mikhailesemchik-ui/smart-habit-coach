import 'package:supabase_flutter/supabase_flutter.dart';

enum AccountDeletionCloudErrorCode {
  networkUnavailable,
  permissionDenied,
  functionUnavailable,
  remoteDeletionFailed,
  unknown,
}

class AccountDeletionCloudFailure {
  final AccountDeletionCloudErrorCode code;
  final String message;

  const AccountDeletionCloudFailure(this.code, this.message);
}

class AccountDeletionCloudResult {
  final bool isSuccess;
  final AccountDeletionCloudFailure? failure;

  const AccountDeletionCloudResult._({required this.isSuccess, this.failure});

  factory AccountDeletionCloudResult.success() =>
      const AccountDeletionCloudResult._(isSuccess: true);

  factory AccountDeletionCloudResult.failure(
    AccountDeletionCloudFailure failure,
  ) => AccountDeletionCloudResult._(isSuccess: false, failure: failure);
}

/// Injectable boundary around the `delete-account` Supabase Edge Function.
/// Never accepts a user id parameter — the backend derives the account to
/// delete solely from the caller's own JWT, so this repository has no way
/// to request deletion of any account other than the currently
/// authenticated one.
abstract interface class AccountDeletionRepository {
  Future<AccountDeletionCloudResult> deleteAccount();
}

/// Calls the `delete-account` Edge Function. Contains no service-role
/// credentials — those exist only inside the Edge Function's own server
/// environment (see `supabase/functions/delete-account/index.ts`).
class SupabaseAccountDeletionRepository implements AccountDeletionRepository {
  final SupabaseClient _client;

  SupabaseAccountDeletionRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  @override
  Future<AccountDeletionCloudResult> deleteAccount() async {
    final FunctionResponse response;
    try {
      response = await _client.functions
          .invoke('delete-account')
          .timeout(const Duration(seconds: 20));
    } on FunctionException catch (e) {
      return AccountDeletionCloudResult.failure(_mapStatus(e.status));
    } catch (_) {
      return AccountDeletionCloudResult.failure(
        const AccountDeletionCloudFailure(
          AccountDeletionCloudErrorCode.unknown,
          'Something went wrong. Please try again.',
        ),
      );
    }

    final data = response.data;
    if (data is Map && data['success'] == true) {
      return AccountDeletionCloudResult.success();
    }

    return AccountDeletionCloudResult.failure(
      const AccountDeletionCloudFailure(
        AccountDeletionCloudErrorCode.remoteDeletionFailed,
        'Could not delete the account right now. Please try again.',
      ),
    );
  }

  AccountDeletionCloudFailure _mapStatus(int status) {
    switch (status) {
      case 401:
        return const AccountDeletionCloudFailure(
          AccountDeletionCloudErrorCode.permissionDenied,
          'Your session is not ready. Please retry from startup.',
        );
      case 404:
        return const AccountDeletionCloudFailure(
          AccountDeletionCloudErrorCode.functionUnavailable,
          'Account deletion is not available right now.',
        );
      case 0:
        return const AccountDeletionCloudFailure(
          AccountDeletionCloudErrorCode.networkUnavailable,
          'Could not connect. Check your connection and try again.',
        );
      default:
        return const AccountDeletionCloudFailure(
          AccountDeletionCloudErrorCode.remoteDeletionFailed,
          'Could not delete the account right now. Please try again.',
        );
    }
  }
}
