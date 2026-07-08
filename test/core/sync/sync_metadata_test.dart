import 'package:flutter_test/flutter_test.dart';
import 'package:smart_habit_coach/core/sync/sync_metadata.dart';

void main() {
  group('SyncMetadata', () {
    test('empty has deterministic, empty defaults', () {
      const m = SyncMetadata.empty;
      expect(m.dirtyHabitIds, isEmpty);
      expect(m.dirtySuggestionIds, isEmpty);
      expect(m.preferencesDirty, isFalse);
      expect(m.lastSuccessfulSyncAt, isNull);
      expect(m.lastSyncAttemptAt, isNull);
      expect(m.lastSyncErrorCode, isNull);
    });

    test('toJson/fromJson round trip preserves all fields', () {
      final m = SyncMetadata(
        dirtyHabitIds: {'h1', 'h2'},
        dirtySuggestionIds: {'s1'},
        preferencesDirty: true,
        lastSuccessfulSyncAt: DateTime.utc(2026, 1, 1),
        lastSyncAttemptAt: DateTime.utc(2026, 1, 2),
        lastSyncErrorCode: 'network_error',
      );

      final restored = SyncMetadata.fromJson(m.toJson());

      expect(restored.dirtyHabitIds, {'h1', 'h2'});
      expect(restored.dirtySuggestionIds, {'s1'});
      expect(restored.preferencesDirty, isTrue);
      expect(restored.lastSuccessfulSyncAt, DateTime.utc(2026, 1, 1));
      expect(restored.lastSyncAttemptAt, DateTime.utc(2026, 1, 2));
      expect(restored.lastSyncErrorCode, 'network_error');
    });

    test('fromJson falls back safely for malformed fields', () {
      final restored = SyncMetadata.fromJson({
        'dirtyHabitIds': 'not-a-list',
        'preferencesDirty': 'not-a-bool',
        'lastSuccessfulSyncAt': 12345,
        'lastSyncErrorCode': 42,
      });

      expect(restored.dirtyHabitIds, isEmpty);
      expect(restored.preferencesDirty, isFalse);
      expect(restored.lastSuccessfulSyncAt, isNull);
      expect(restored.lastSyncErrorCode, isNull);
    });

    test('copyWith preserves fields not explicitly changed', () {
      final m = SyncMetadata(dirtyHabitIds: {'h1'}, preferencesDirty: true);

      final updated = m.copyWith(dirtySuggestionIds: {'s1'});

      expect(updated.dirtyHabitIds, {'h1'});
      expect(updated.preferencesDirty, isTrue);
      expect(updated.dirtySuggestionIds, {'s1'});
    });
  });
}
