import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_habit_coach/features/coach/domain/adaptive_suggestion.dart';
import 'package:smart_habit_coach/features/home/domain/habit.dart';
import 'package:smart_habit_coach/features/profile/domain/app_settings.dart';
import 'package:smart_habit_coach/features/sync/data/cloud_backend.dart';
import 'package:smart_habit_coach/features/sync/data/cloud_records.dart';
import 'package:smart_habit_coach/features/sync/data/cloud_repositories.dart';
import 'package:smart_habit_coach/features/sync/data/cloud_result.dart';

class _FakeSessionProvider implements CloudAuthSessionProvider {
  String? uid;

  _FakeSessionProvider(this.uid);

  @override
  String? currentUid() => uid;
}

class _FakeBackend implements CloudBackend {
  final _rowsByTable = <String, List<Map<String, dynamic>>>{};
  CloudBackendException? fetchFailure;
  CloudBackendException? upsertFailure;
  String? lastFetchUserId;
  String? lastUpsertTable;
  String? lastOnConflict;
  List<Map<String, dynamic>> lastUpsertRows = [];

  List<Map<String, dynamic>> rows(String table) =>
      _rowsByTable.putIfAbsent(table, () => []);

  @override
  Future<List<Map<String, dynamic>>> fetchRows({
    required String table,
    required String userId,
  }) async {
    if (fetchFailure != null) throw fetchFailure!;
    lastFetchUserId = userId;
    return rows(table)
        .where((row) => row['user_id'] == userId)
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  @override
  Future<List<Map<String, dynamic>>> fetchRowsUpdatedSince({
    required String table,
    required String userId,
    required DateTime updatedSince,
  }) async {
    final all = await fetchRows(table: table, userId: userId);
    return all.where((row) {
      final raw = row['updated_at'];
      final parsed = raw is String ? DateTime.tryParse(raw) : null;
      return parsed != null && !parsed.isBefore(updatedSince);
    }).toList();
  }

  @override
  Future<void> upsertRows({
    required String table,
    required List<Map<String, dynamic>> rows,
    required String onConflict,
  }) async {
    if (upsertFailure != null) throw upsertFailure!;
    lastUpsertTable = table;
    lastOnConflict = onConflict;
    lastUpsertRows = rows.map((row) => Map<String, dynamic>.from(row)).toList();
    final target = this.rows(table);
    for (final row in rows) {
      final id = row['id'];
      final userId = row['user_id'];
      final index = target.indexWhere(
        (existing) => existing['user_id'] == userId && existing['id'] == id,
      );
      if (index >= 0) {
        target[index] = Map<String, dynamic>.from(row);
      } else {
        target.add(Map<String, dynamic>.from(row));
      }
    }
  }

  @override
  Future<void> hardDeleteRow({
    required String table,
    required String userId,
    required String id,
  }) async {
    rows(
      table,
    ).removeWhere((row) => row['user_id'] == userId && row['id'] == id);
  }
}

Habit _habit(String id, {DateTime? deletedAt, DateTime? updatedAt}) => Habit(
  id: id,
  title: 'Habit $id',
  scheduledTime: '08:00 AM',
  icon: Icons.check,
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: updatedAt ?? DateTime.utc(2026, 1, 2),
  deletedAt: deletedAt,
);

void main() {
  group('HabitCloudRepository', () {
    test('unauthenticated and blank uid fail before backend calls', () async {
      final backend = _FakeBackend();
      final repo = SupabaseHabitCloudRepository(
        sessionProvider: _FakeSessionProvider(null),
        backend: backend,
      );

      final result = await repo.fetchAll();

      expect(result.failure!.code, CloudErrorCode.unauthenticated);
      expect(backend.lastFetchUserId, isNull);

      final blankRepo = SupabaseHabitCloudRepository(
        sessionProvider: _FakeSessionProvider('   '),
        backend: backend,
      );
      final blankResult = await blankRepo.fetchAll();
      expect(blankResult.failure!.code, CloudErrorCode.unauthenticated);
    });

    test('fetch includes tombstones and filters by active uid', () async {
      final backend = _FakeBackend();
      final active = _FakeSessionProvider('uid-a');
      final repo = SupabaseHabitCloudRepository(
        sessionProvider: active,
        backend: backend,
      );
      final tombstone = DateTime.utc(2026, 1, 5);
      backend.rows(SupabaseHabitCloudRepository.table).addAll([
        CloudHabitRecord.fromHabit(
          userId: 'uid-a',
          habit: _habit('same-id', deletedAt: tombstone),
        ).toRow(expectedUserId: 'uid-a'),
        CloudHabitRecord.fromHabit(
          userId: 'uid-b',
          habit: _habit('same-id'),
        ).toRow(expectedUserId: 'uid-b'),
      ]);

      final result = await repo.fetchAll();

      expect(result.isSuccess, isTrue);
      expect(result.value, hasLength(1));
      expect(result.value.single.userId, 'uid-a');
      expect(result.value.single.habit.id, 'same-id');
      expect(result.value.single.habit.deletedAt, tombstone);
    });

    test('upsert uses active uid and composite conflict target', () async {
      final backend = _FakeBackend();
      final repo = SupabaseHabitCloudRepository(
        sessionProvider: _FakeSessionProvider('uid-a'),
        backend: backend,
      );

      final result = await repo.upsert(
        CloudHabitRecord.fromHabit(userId: 'uid-a', habit: _habit('habit-1')),
      );

      expect(result.isSuccess, isTrue);
      expect(backend.lastUpsertTable, SupabaseHabitCloudRepository.table);
      expect(backend.lastOnConflict, 'user_id,id');
      expect(backend.lastUpsertRows.single['user_id'], 'uid-a');
    });

    test('upsert rejects caller-controlled cross-user row', () async {
      final backend = _FakeBackend();
      final repo = SupabaseHabitCloudRepository(
        sessionProvider: _FakeSessionProvider('uid-a'),
        backend: backend,
      );

      final result = await repo.upsert(
        CloudHabitRecord.fromHabit(userId: 'uid-b', habit: _habit('habit-1')),
      );

      expect(result.failure!.code, CloudErrorCode.malformedResponse);
      expect(backend.lastUpsertRows, isEmpty);
    });

    test(
      'upsert many preserves all rows and same ids remain isolated by uid',
      () async {
        final backend = _FakeBackend();
        final repoA = SupabaseHabitCloudRepository(
          sessionProvider: _FakeSessionProvider('uid-a'),
          backend: backend,
        );
        final repoB = SupabaseHabitCloudRepository(
          sessionProvider: _FakeSessionProvider('uid-b'),
          backend: backend,
        );

        await repoA.upsertMany([
          CloudHabitRecord.fromHabit(userId: 'uid-a', habit: _habit('same-id')),
          CloudHabitRecord.fromHabit(userId: 'uid-a', habit: _habit('habit-2')),
        ]);
        await repoB.upsert(
          CloudHabitRecord.fromHabit(userId: 'uid-b', habit: _habit('same-id')),
        );

        expect((await repoA.fetchAll()).value.map((r) => r.userId).toSet(), {
          'uid-a',
        });
        expect((await repoB.fetchAll()).value.map((r) => r.userId).toSet(), {
          'uid-b',
        });
        expect(backend.rows(SupabaseHabitCloudRepository.table), hasLength(3));
      },
    );

    test('malformed backend row returns typed failure', () async {
      final backend = _FakeBackend();
      backend.rows(SupabaseHabitCloudRepository.table).add({
        'user_id': 'uid-a',
        'id': 'habit-1',
        'created_at': 'bad',
        'updated_at': DateTime.utc(2026, 1, 2).toIso8601String(),
        'payload': {'id': 'habit-1'},
      });
      final repo = SupabaseHabitCloudRepository(
        sessionProvider: _FakeSessionProvider('uid-a'),
        backend: backend,
      );

      final result = await repo.fetchAll();

      expect(result.failure!.code, CloudErrorCode.malformedResponse);
    });

    test('backend errors map safely without raw technical messages', () async {
      final backend = _FakeBackend()
        ..fetchFailure = const CloudBackendException(
          CloudErrorCode.permissionDenied,
        );
      final repo = SupabaseHabitCloudRepository(
        sessionProvider: _FakeSessionProvider('uid-a'),
        backend: backend,
      );

      final result = await repo.fetchAll();

      expect(result.failure!.code, CloudErrorCode.permissionDenied);
      expect(result.failure!.message, isNot(contains('policy stack trace')));
    });
  });

  group('AdaptiveSuggestionCloudRepository', () {
    test('upsert uses active uid and fetch includes tombstones', () async {
      final backend = _FakeBackend();
      final repo = SupabaseAdaptiveSuggestionCloudRepository(
        sessionProvider: _FakeSessionProvider('uid-a'),
        backend: backend,
      );
      final deletedAt = DateTime.utc(2026, 2, 1);
      final suggestion = AdaptiveHabitSuggestion(
        id: 'suggestion-1',
        habitId: 'habit-1',
        type: AdaptiveSuggestionType.reviewSchedule,
        createdAt: DateTime.utc(2026, 1, 1),
        analysisStart: DateTime.utc(2026, 1, 1),
        analysisEnd: DateTime.utc(2026, 1, 7),
        evidenceCode: 'schedule_review',
        updatedAt: DateTime.utc(2026, 1, 2),
        deletedAt: deletedAt,
      );

      final upsertResult = await repo.upsert(
        CloudAdaptiveSuggestionRecord.fromSuggestion(
          userId: 'uid-a',
          suggestion: suggestion,
        ),
      );
      final fetchResult = await repo.fetchAll();

      expect(upsertResult.isSuccess, isTrue);
      expect(backend.lastOnConflict, 'user_id,id');
      expect(fetchResult.value.single.suggestion.deletedAt, deletedAt);
    });
  });

  group('SettingsCloudRepository', () {
    test('upsert uses one row per active uid', () async {
      final backend = _FakeBackend();
      final repo = SupabaseSettingsCloudRepository(
        sessionProvider: _FakeSessionProvider('uid-a'),
        backend: backend,
      );
      final settings = AppSettings(
        displayName: 'Jamie',
        updatedAt: DateTime.utc(2026, 1, 2),
      );

      final result = await repo.upsert(
        CloudSettingsRecord.fromSettings(userId: 'uid-a', settings: settings),
      );

      expect(result.isSuccess, isTrue);
      expect(backend.lastOnConflict, 'user_id');
      expect(backend.lastUpsertRows.single['user_id'], 'uid-a');
    });
  });
}
