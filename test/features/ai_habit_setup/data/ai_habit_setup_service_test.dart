import 'package:flutter_test/flutter_test.dart';
import 'package:smart_habit_coach/features/ai_habit_setup/data/ai_habit_setup_service.dart';

void main() {
  group('isAiHabitSetupQuotaExceeded', () {
    test('detects HTTP 429 responses', () {
      expect(isAiHabitSetupQuotaExceeded(429, null), isTrue);
    });

    test('detects quota_exceeded backend error code', () {
      expect(
        isAiHabitSetupQuotaExceeded(500, {
          'error': {'code': 'quota_exceeded'},
        }),
        isTrue,
      );
    });

    test('ignores unrelated backend errors', () {
      expect(
        isAiHabitSetupQuotaExceeded(502, {
          'error': {'code': 'upstream_error'},
        }),
        isFalse,
      );
    });
  });
}
