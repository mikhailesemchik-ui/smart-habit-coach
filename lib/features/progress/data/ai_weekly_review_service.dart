import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/ai_weekly_review.dart';
import '../domain/ai_weekly_review_exception.dart';
import '../domain/ai_weekly_review_response.dart';
import '../domain/ai_weekly_review_source.dart';
import '../domain/weekly_review.dart';

const _requestFailedMessage =
    "Couldn't generate an AI review right now. Please try again.";

/// Calls the `generate-weekly-review` Supabase Edge Function to turn
/// locally calculated [WeeklyReviewMetrics] into an [AiWeeklyReview].
class AiWeeklyReviewService implements AiWeeklyReviewSource {
  final SupabaseClient _client;

  AiWeeklyReviewService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  @override
  Future<AiWeeklyReview> generateReview(WeeklyReviewMetrics metrics) async {
    final FunctionResponse response;
    try {
      response = await _client.functions
          .invoke(
            'generate-weekly-review',
            body: {
              'completionRate': metrics.completionRate,
              'currentStreak': metrics.currentStreak,
              'bestStreak': metrics.bestStreak,
              'strongestDay': metrics.strongestDay,
              'weakestDay': metrics.weakestDay,
              'completedCount': metrics.completedCount,
              'totalPossibleCount': metrics.totalPossibleCount,
            },
          )
          .timeout(const Duration(seconds: 20));
    } catch (_) {
      throw const AiWeeklyReviewException(_requestFailedMessage);
    }

    return parseAiWeeklyReviewResponse(response.data);
  }
}
