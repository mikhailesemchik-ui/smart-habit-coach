import 'package:flutter_test/flutter_test.dart';
import 'package:smart_habit_coach/core/sync/recovery_snapshot.dart';

void main() {
  group('RecoverySnapshot', () {
    test('toJson/fromJson round trip preserves all fields', () {
      final snapshot = RecoverySnapshot(
        createdAt: DateTime.utc(2026, 1, 1),
        reason: 'beforeHabitTombstone',
        habits: [
          {'id': 'h1', 'deletedAt': '2026-01-01T00:00:00.000Z'},
        ],
        suggestions: [
          {'id': 's1'},
        ],
        settings: {'displayName': 'Jamie'},
        syncMetadata: {'preferencesDirty': true},
      );

      final restored = RecoverySnapshot.fromJson(snapshot.toJson());

      expect(restored, isNotNull);
      expect(restored!.createdAt, DateTime.utc(2026, 1, 1));
      expect(restored.reason, 'beforeHabitTombstone');
      expect(restored.habits.single['id'], 'h1');
      expect(restored.habits.single['deletedAt'], isNotNull);
      expect(restored.suggestions.single['id'], 's1');
      expect(restored.settings?['displayName'], 'Jamie');
      expect(restored.syncMetadata?['preferencesDirty'], true);
    });

    test('fromJson returns null for malformed data', () {
      expect(RecoverySnapshot.fromJson({}), isNull);
      expect(
        RecoverySnapshot.fromJson({
          'createdAt': 'not-a-date',
          'reason': 'x',
          'habits': [],
          'suggestions': [],
        }),
        isNull,
      );
      expect(
        RecoverySnapshot.fromJson({
          'createdAt': '2026-01-01T00:00:00.000Z',
          'reason': 'x',
          'habits': 'not-a-list',
          'suggestions': [],
        }),
        isNull,
      );
    });
  });
}
