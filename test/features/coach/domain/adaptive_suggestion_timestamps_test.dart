import 'package:flutter_test/flutter_test.dart';
import 'package:smart_habit_coach/features/coach/domain/adaptive_suggestion.dart';

AdaptiveHabitSuggestion _suggestion({
  DateTime? updatedAt,
  DateTime? deletedAt,
}) {
  return AdaptiveHabitSuggestion(
    id: 's1',
    habitId: 'h1',
    type: AdaptiveSuggestionType.addMinimumVersion,
    createdAt: DateTime.utc(2026, 1, 1),
    analysisStart: DateTime.utc(2025, 12, 1),
    analysisEnd: DateTime.utc(2025, 12, 31),
    evidenceCode: 'code',
    updatedAt: updatedAt,
    deletedAt: deletedAt,
  );
}

void main() {
  group('AdaptiveHabitSuggestion updatedAt / deletedAt (Phase 1A)', () {
    test(
      'old JSON without updatedAt/deletedAt falls back to the legacy sentinel',
      () {
        final json = {
          'id': 's1',
          'habitId': 'h1',
          'type': 'addMinimumVersion',
          'evidenceCode': 'code',
          'createdAt': '2026-01-01T00:00:00.000Z',
          'analysisStart': '2025-12-01T00:00:00.000Z',
          'analysisEnd': '2025-12-31T00:00:00.000Z',
        };

        final suggestion = AdaptiveHabitSuggestion.fromJson(json);

        expect(suggestion, isNotNull);
        expect(suggestion!.updatedAt, DateTime.utc(2000, 1, 1));
        expect(suggestion.deletedAt, isNull);
        // createdAt's existing required semantics are unchanged.
        expect(suggestion.createdAt, DateTime.utc(2026, 1, 1));
      },
    );

    test('new JSON round-trips updatedAt/deletedAt exactly', () {
      final suggestion = _suggestion(
        updatedAt: DateTime.utc(2026, 6, 1),
        deletedAt: DateTime.utc(2026, 6, 15),
      );

      final restored = AdaptiveHabitSuggestion.fromJson(suggestion.toJson());

      expect(restored, isNotNull);
      expect(restored!.updatedAt, suggestion.updatedAt);
      expect(restored.deletedAt, suggestion.deletedAt);
    });

    test('malformed timestamp values fall back safely without throwing', () {
      final json = {
        'id': 's1',
        'habitId': 'h1',
        'type': 'addMinimumVersion',
        'evidenceCode': 'code',
        'createdAt': '2026-01-01T00:00:00.000Z',
        'analysisStart': '2025-12-01T00:00:00.000Z',
        'analysisEnd': '2025-12-31T00:00:00.000Z',
        'updatedAt': 'not-a-date',
        'deletedAt': 12345,
      };

      final suggestion = AdaptiveHabitSuggestion.fromJson(json);

      expect(suggestion, isNotNull);
      expect(suggestion!.updatedAt, DateTime.utc(2000, 1, 1));
      expect(suggestion.deletedAt, isNull);
    });

    test('copyWith preserves updatedAt/deletedAt by default', () {
      final suggestion = _suggestion(
        updatedAt: DateTime.utc(2026, 6, 1),
        deletedAt: DateTime.utc(2026, 6, 15),
      );

      final updated = suggestion.copyWith(evidenceCode: 'new-code');

      expect(updated.updatedAt, suggestion.updatedAt);
      expect(updated.deletedAt, suggestion.deletedAt);
    });

    test('copyWith can explicitly clear deletedAt', () {
      final suggestion = _suggestion(deletedAt: DateTime.utc(2026, 6, 15));

      final restored = suggestion.copyWith(deletedAt: null);

      expect(restored.deletedAt, isNull);
    });
  });
}
