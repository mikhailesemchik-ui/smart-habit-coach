import 'cloud_result.dart';

class CloudBackendException implements Exception {
  final CloudErrorCode code;

  const CloudBackendException(this.code);
}

abstract interface class CloudAuthSessionProvider {
  String? currentUid();
}

abstract interface class CloudBackend {
  Future<List<Map<String, dynamic>>> fetchRows({
    required String table,
    required String userId,
  });

  Future<List<Map<String, dynamic>>> fetchRowsUpdatedSince({
    required String table,
    required String userId,
    required DateTime updatedSince,
  });

  Future<void> upsertRows({
    required String table,
    required List<Map<String, dynamic>> rows,
    required String onConflict,
  });

  Future<void> hardDeleteRow({
    required String table,
    required String userId,
    required String id,
  });
}
