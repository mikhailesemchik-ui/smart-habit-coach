import 'package:supabase_flutter/supabase_flutter.dart';

import 'cloud_backend.dart';
import 'cloud_records.dart';
import 'cloud_result.dart';

abstract interface class HabitCloudRepository {
  Future<CloudResult<List<CloudHabitRecord>>> fetchAll();
  Future<CloudResult<List<CloudHabitRecord>>> fetchUpdatedSince(
    DateTime updatedSince,
  );
  Future<CloudResult<void>> upsert(CloudHabitRecord record);
  Future<CloudResult<void>> upsertMany(List<CloudHabitRecord> records);
  Future<CloudResult<void>> hardDelete(String id);
}

abstract interface class AdaptiveSuggestionCloudRepository {
  Future<CloudResult<List<CloudAdaptiveSuggestionRecord>>> fetchAll();
  Future<CloudResult<List<CloudAdaptiveSuggestionRecord>>> fetchUpdatedSince(
    DateTime updatedSince,
  );
  Future<CloudResult<void>> upsert(CloudAdaptiveSuggestionRecord record);
  Future<CloudResult<void>> upsertMany(
    List<CloudAdaptiveSuggestionRecord> records,
  );
  Future<CloudResult<void>> hardDelete(String id);
}

abstract interface class SettingsCloudRepository {
  Future<CloudResult<CloudSettingsRecord?>> fetch();
  Future<CloudResult<void>> upsert(CloudSettingsRecord record);
}

class SupabaseCloudAuthSessionProvider implements CloudAuthSessionProvider {
  final SupabaseClient _client;

  SupabaseCloudAuthSessionProvider({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  @override
  String? currentUid() => _client.auth.currentSession?.user.id;
}

class SupabaseCloudBackend implements CloudBackend {
  final SupabaseClient _client;

  SupabaseCloudBackend({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  @override
  Future<List<Map<String, dynamic>>> fetchRows({
    required String table,
    required String userId,
  }) async {
    final response = await _client.from(table).select().eq('user_id', userId);
    return _rowsFromResponse(response);
  }

  @override
  Future<List<Map<String, dynamic>>> fetchRowsUpdatedSince({
    required String table,
    required String userId,
    required DateTime updatedSince,
  }) async {
    final response = await _client
        .from(table)
        .select()
        .eq('user_id', userId)
        .gte('updated_at', updatedSince.toIso8601String());
    return _rowsFromResponse(response);
  }

  @override
  Future<void> upsertRows({
    required String table,
    required List<Map<String, dynamic>> rows,
    required String onConflict,
  }) async {
    if (rows.isEmpty) return;
    await _client.from(table).upsert(rows, onConflict: onConflict);
  }

  @override
  Future<void> hardDeleteRow({
    required String table,
    required String userId,
    required String id,
  }) async {
    await _client.from(table).delete().eq('user_id', userId).eq('id', id);
  }

  List<Map<String, dynamic>> _rowsFromResponse(Object? response) {
    if (response is! List) {
      throw const CloudMappingException('response was not a list');
    }
    return response.map((item) {
      if (item is! Map) {
        throw const CloudMappingException('response row was not an object');
      }
      return Map<String, dynamic>.from(item);
    }).toList();
  }
}

abstract class _CloudRepositoryBase {
  final CloudAuthSessionProvider sessionProvider;
  final CloudBackend backend;

  const _CloudRepositoryBase({
    required this.sessionProvider,
    required this.backend,
  });

  CloudResult<String> activeUid() {
    final uid = sessionProvider.currentUid();
    if (uid == null) {
      return CloudResult.failure(
        const CloudFailure(
          CloudErrorCode.unauthenticated,
          'A signed-in user is required.',
        ),
      );
    }
    if (uid.trim().isEmpty) {
      return CloudResult.failure(
        const CloudFailure(CloudErrorCode.unauthenticated, 'User id missing.'),
      );
    }
    return CloudResult.success(uid);
  }

  CloudFailure mapError(Object error) {
    if (error is CloudMappingException) return cloudMalformed(error.reason);
    if (error is CloudBackendException) {
      return CloudFailure(error.code, 'Cloud request failed.');
    }
    if (error is PostgrestException) {
      final code = error.code;
      if (code == '401' || code == 'PGRST301') {
        return const CloudFailure(
          CloudErrorCode.unauthenticated,
          'A signed-in user is required.',
        );
      }
      if (code == '403' || code == '42501') {
        return const CloudFailure(
          CloudErrorCode.permissionDenied,
          'Cloud access was denied.',
        );
      }
      if (code == '23505' || code == '23514' || code == '23503') {
        return const CloudFailure(
          CloudErrorCode.constraintViolation,
          'Cloud data violated a database constraint.',
        );
      }
      if (code == '429') {
        return const CloudFailure(
          CloudErrorCode.rateLimited,
          'Too many cloud requests.',
        );
      }
      return const CloudFailure(
        CloudErrorCode.unavailable,
        'Cloud storage is unavailable.',
      );
    }
    return const CloudFailure(
      CloudErrorCode.unknown,
      'Cloud storage failed unexpectedly.',
    );
  }
}

class SupabaseHabitCloudRepository extends _CloudRepositoryBase
    implements HabitCloudRepository {
  static const table = 'habits';

  SupabaseHabitCloudRepository({
    CloudAuthSessionProvider? sessionProvider,
    CloudBackend? backend,
  }) : super(
         sessionProvider: sessionProvider ?? SupabaseCloudAuthSessionProvider(),
         backend: backend ?? SupabaseCloudBackend(),
       );

  @override
  Future<CloudResult<List<CloudHabitRecord>>> fetchAll() async {
    final uid = activeUid();
    if (!uid.isSuccess) return CloudResult.failure(uid.failure!);
    try {
      final rows = await backend.fetchRows(table: table, userId: uid.value);
      return CloudResult.success(
        rows
            .map(
              (row) => CloudHabitRecord.fromRow(row, expectedUserId: uid.value),
            )
            .toList(),
      );
    } catch (error) {
      return CloudResult.failure(mapError(error));
    }
  }

  @override
  Future<CloudResult<List<CloudHabitRecord>>> fetchUpdatedSince(
    DateTime updatedSince,
  ) async {
    final uid = activeUid();
    if (!uid.isSuccess) return CloudResult.failure(uid.failure!);
    try {
      final rows = await backend.fetchRowsUpdatedSince(
        table: table,
        userId: uid.value,
        updatedSince: updatedSince,
      );
      return CloudResult.success(
        rows
            .map(
              (row) => CloudHabitRecord.fromRow(row, expectedUserId: uid.value),
            )
            .toList(),
      );
    } catch (error) {
      return CloudResult.failure(mapError(error));
    }
  }

  @override
  Future<CloudResult<void>> upsert(CloudHabitRecord record) =>
      upsertMany([record]);

  @override
  Future<CloudResult<void>> upsertMany(List<CloudHabitRecord> records) async {
    final uid = activeUid();
    if (!uid.isSuccess) return CloudResult.failure(uid.failure!);
    try {
      await backend.upsertRows(
        table: table,
        rows: records.map((r) => r.toRow(expectedUserId: uid.value)).toList(),
        onConflict: 'user_id,id',
      );
      return CloudResult.success(null);
    } catch (error) {
      return CloudResult.failure(mapError(error));
    }
  }

  @override
  Future<CloudResult<void>> hardDelete(String id) async {
    final uid = activeUid();
    if (!uid.isSuccess) return CloudResult.failure(uid.failure!);
    if (id.trim().isEmpty) {
      return CloudResult.failure(cloudMalformed('id missing'));
    }
    try {
      await backend.hardDeleteRow(table: table, userId: uid.value, id: id);
      return CloudResult.success(null);
    } catch (error) {
      return CloudResult.failure(mapError(error));
    }
  }
}

class SupabaseAdaptiveSuggestionCloudRepository extends _CloudRepositoryBase
    implements AdaptiveSuggestionCloudRepository {
  static const table = 'adaptive_suggestions';

  SupabaseAdaptiveSuggestionCloudRepository({
    CloudAuthSessionProvider? sessionProvider,
    CloudBackend? backend,
  }) : super(
         sessionProvider: sessionProvider ?? SupabaseCloudAuthSessionProvider(),
         backend: backend ?? SupabaseCloudBackend(),
       );

  @override
  Future<CloudResult<List<CloudAdaptiveSuggestionRecord>>> fetchAll() async {
    final uid = activeUid();
    if (!uid.isSuccess) return CloudResult.failure(uid.failure!);
    try {
      final rows = await backend.fetchRows(table: table, userId: uid.value);
      return CloudResult.success(
        rows
            .map(
              (row) => CloudAdaptiveSuggestionRecord.fromRow(
                row,
                expectedUserId: uid.value,
              ),
            )
            .toList(),
      );
    } catch (error) {
      return CloudResult.failure(mapError(error));
    }
  }

  @override
  Future<CloudResult<List<CloudAdaptiveSuggestionRecord>>> fetchUpdatedSince(
    DateTime updatedSince,
  ) async {
    final uid = activeUid();
    if (!uid.isSuccess) return CloudResult.failure(uid.failure!);
    try {
      final rows = await backend.fetchRowsUpdatedSince(
        table: table,
        userId: uid.value,
        updatedSince: updatedSince,
      );
      return CloudResult.success(
        rows
            .map(
              (row) => CloudAdaptiveSuggestionRecord.fromRow(
                row,
                expectedUserId: uid.value,
              ),
            )
            .toList(),
      );
    } catch (error) {
      return CloudResult.failure(mapError(error));
    }
  }

  @override
  Future<CloudResult<void>> upsert(CloudAdaptiveSuggestionRecord record) =>
      upsertMany([record]);

  @override
  Future<CloudResult<void>> upsertMany(
    List<CloudAdaptiveSuggestionRecord> records,
  ) async {
    final uid = activeUid();
    if (!uid.isSuccess) return CloudResult.failure(uid.failure!);
    try {
      await backend.upsertRows(
        table: table,
        rows: records.map((r) => r.toRow(expectedUserId: uid.value)).toList(),
        onConflict: 'user_id,id',
      );
      return CloudResult.success(null);
    } catch (error) {
      return CloudResult.failure(mapError(error));
    }
  }

  @override
  Future<CloudResult<void>> hardDelete(String id) async {
    final uid = activeUid();
    if (!uid.isSuccess) return CloudResult.failure(uid.failure!);
    if (id.trim().isEmpty) {
      return CloudResult.failure(cloudMalformed('id missing'));
    }
    try {
      await backend.hardDeleteRow(table: table, userId: uid.value, id: id);
      return CloudResult.success(null);
    } catch (error) {
      return CloudResult.failure(mapError(error));
    }
  }
}

class SupabaseSettingsCloudRepository extends _CloudRepositoryBase
    implements SettingsCloudRepository {
  static const table = 'user_preferences';

  SupabaseSettingsCloudRepository({
    CloudAuthSessionProvider? sessionProvider,
    CloudBackend? backend,
  }) : super(
         sessionProvider: sessionProvider ?? SupabaseCloudAuthSessionProvider(),
         backend: backend ?? SupabaseCloudBackend(),
       );

  @override
  Future<CloudResult<CloudSettingsRecord?>> fetch() async {
    final uid = activeUid();
    if (!uid.isSuccess) return CloudResult.failure(uid.failure!);
    try {
      final rows = await backend.fetchRows(table: table, userId: uid.value);
      if (rows.isEmpty) return CloudResult.success(null);
      if (rows.length > 1) {
        return CloudResult.failure(cloudMalformed('multiple settings rows'));
      }
      return CloudResult.success(
        CloudSettingsRecord.fromRow(rows.single, expectedUserId: uid.value),
      );
    } catch (error) {
      return CloudResult.failure(mapError(error));
    }
  }

  @override
  Future<CloudResult<void>> upsert(CloudSettingsRecord record) async {
    final uid = activeUid();
    if (!uid.isSuccess) return CloudResult.failure(uid.failure!);
    try {
      await backend.upsertRows(
        table: table,
        rows: [record.toRow(expectedUserId: uid.value)],
        onConflict: 'user_id',
      );
      return CloudResult.success(null);
    } catch (error) {
      return CloudResult.failure(mapError(error));
    }
  }
}
