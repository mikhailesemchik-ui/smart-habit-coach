import 'ai_weekly_review.dart';
import 'weekly_review.dart';

/// Abstraction over anything that can turn locally calculated
/// [WeeklyReviewMetrics] into an [AiWeeklyReview]. Allows the real
/// Supabase-backed implementation to be swapped for a test double.
abstract class AiWeeklyReviewSource {
  Future<AiWeeklyReview> generateReview(WeeklyReviewMetrics metrics);
}
