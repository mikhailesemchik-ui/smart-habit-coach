import 'package:flutter_test/flutter_test.dart';
import 'package:smart_habit_coach/features/progress/data/ai_weekly_review_service.dart';

void main() {
  group('isAiWeeklyReviewQuotaExceeded', () {
    test('detects HTTP 429 responses', () {
      expect(isAiWeeklyReviewQuotaExceeded(429, null), isTrue);
    });

    test('detects quota_exceeded backend error code', () {
      expect(
        isAiWeeklyReviewQuotaExceeded(500, {
          'error': {'code': 'quota_exceeded'},
        }),
        isTrue,
      );
    });

    test('ignores unrelated backend errors', () {
      expect(
        isAiWeeklyReviewQuotaExceeded(502, {
          'error': {'code': 'upstream_error'},
        }),
        isFalse,
      );
    });
  });
}
