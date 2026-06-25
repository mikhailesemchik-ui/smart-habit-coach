import 'ai_weekly_review.dart';
import 'ai_weekly_review_exception.dart';

const _genericParseError =
    "Couldn't understand the AI response. Please try again.";

/// Parses and validates the JSON payload returned by the
/// `generate-weekly-review` edge function into an [AiWeeklyReview].
///
/// Throws [AiWeeklyReviewException] if [rawResponse] doesn't match the
/// expected shape.
AiWeeklyReview parseAiWeeklyReviewResponse(Object? rawResponse) {
  if (rawResponse is! Map) {
    throw const AiWeeklyReviewException(_genericParseError);
  }

  final summary = rawResponse['summary'];
  final strongestInsight = rawResponse['strongestInsight'];
  final weakestInsight = rawResponse['weakestInsight'];
  final recommendation = rawResponse['recommendation'];

  if (summary is! String || summary.trim().isEmpty) {
    throw const AiWeeklyReviewException(_genericParseError);
  }
  if (strongestInsight is! String || strongestInsight.trim().isEmpty) {
    throw const AiWeeklyReviewException(_genericParseError);
  }
  if (weakestInsight is! String || weakestInsight.trim().isEmpty) {
    throw const AiWeeklyReviewException(_genericParseError);
  }
  if (recommendation is! String || recommendation.trim().isEmpty) {
    throw const AiWeeklyReviewException(_genericParseError);
  }

  return AiWeeklyReview(
    summary: summary.trim(),
    strongestInsight: strongestInsight.trim(),
    weakestInsight: weakestInsight.trim(),
    recommendation: recommendation.trim(),
  );
}
