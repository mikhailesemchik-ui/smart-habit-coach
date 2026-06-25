import 'package:flutter_test/flutter_test.dart';
import 'package:smart_habit_coach/features/progress/domain/ai_weekly_review_exception.dart';
import 'package:smart_habit_coach/features/progress/domain/ai_weekly_review_response.dart';

void main() {
  group('parseAiWeeklyReviewResponse with valid input', () {
    test('parses a well-formed response', () {
      final review = parseAiWeeklyReviewResponse({
        'summary': 'You completed 45% of your habits this week.',
        'strongestInsight': 'Wednesday was your most consistent day.',
        'weakestInsight': 'Sunday could use more attention.',
        'recommendation': 'Plan a lighter Sunday routine next week.',
      });

      expect(review.summary, 'You completed 45% of your habits this week.');
      expect(
        review.strongestInsight,
        'Wednesday was your most consistent day.',
      );
      expect(review.weakestInsight, 'Sunday could use more attention.');
      expect(review.recommendation, 'Plan a lighter Sunday routine next week.');
    });

    test('trims surrounding whitespace from every field', () {
      final review = parseAiWeeklyReviewResponse({
        'summary': '  Good week overall.  ',
        'strongestInsight': '  Wednesday stood out.  ',
        'weakestInsight': '  Sunday lagged behind.  ',
        'recommendation': '  Keep it up.  ',
      });

      expect(review.summary, 'Good week overall.');
      expect(review.strongestInsight, 'Wednesday stood out.');
      expect(review.weakestInsight, 'Sunday lagged behind.');
      expect(review.recommendation, 'Keep it up.');
    });
  });

  group('parseAiWeeklyReviewResponse rejects invalid input', () {
    test('rejects a non-map response', () {
      expect(
        () => parseAiWeeklyReviewResponse('not a map'),
        throwsA(isA<AiWeeklyReviewException>()),
      );
    });

    test('rejects a missing field', () {
      expect(
        () => parseAiWeeklyReviewResponse({
          'summary': 'Good week.',
          'strongestInsight': 'Wednesday stood out.',
          'recommendation': 'Keep it up.',
        }),
        throwsA(isA<AiWeeklyReviewException>()),
      );
    });

    test('rejects an empty field', () {
      expect(
        () => parseAiWeeklyReviewResponse({
          'summary': '   ',
          'strongestInsight': 'Wednesday stood out.',
          'weakestInsight': 'Sunday lagged behind.',
          'recommendation': 'Keep it up.',
        }),
        throwsA(isA<AiWeeklyReviewException>()),
      );
    });

    test('rejects a non-string field', () {
      expect(
        () => parseAiWeeklyReviewResponse({
          'summary': 42,
          'strongestInsight': 'Wednesday stood out.',
          'weakestInsight': 'Sunday lagged behind.',
          'recommendation': 'Keep it up.',
        }),
        throwsA(isA<AiWeeklyReviewException>()),
      );
    });
  });
}
