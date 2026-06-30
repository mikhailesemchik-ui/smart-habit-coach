import 'package:supabase_flutter/supabase_flutter.dart';

import '../../home/domain/habit.dart';

import '../domain/ai_weekly_review.dart';
import '../domain/ai_weekly_review_exception.dart';
import '../domain/ai_weekly_review_response.dart';
import '../domain/ai_weekly_review_source.dart';
import '../domain/weekly_review.dart';

const _requestFailedMessage =
    "Couldn't generate an AI review right now. Please try again.";
const aiWeeklyReviewQuotaMessage =
    "Today's AI review limit has been reached. Showing your local review instead.";

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
              'minimumCompletedCount': metrics.minimumCompletedCount,
              'totalPossibleCount': metrics.totalPossibleCount,
              'skipReasons': {
                'noTime': metrics.skipReasonCounts[HabitSkipReason.noTime] ?? 0,
                'forgot': metrics.skipReasonCounts[HabitSkipReason.forgot] ?? 0,
                'tooTired':
                    metrics.skipReasonCounts[HabitSkipReason.tooTired] ?? 0,
                'tooDifficult':
                    metrics.skipReasonCounts[HabitSkipReason.tooDifficult] ?? 0,
                'other': metrics.skipReasonCounts[HabitSkipReason.other] ?? 0,
              },
              'missedWithoutReason': metrics.missedWithoutReason,
              'partialReasons': {
                'noTime':
                    metrics.partialReasonCounts[HabitPartialReason.noTime] ?? 0,
                'tooTired':
                    metrics.partialReasonCounts[HabitPartialReason.tooTired] ??
                    0,
                'targetTooDifficult':
                    metrics.partialReasonCounts[HabitPartialReason
                        .targetTooDifficult] ??
                    0,
                'forgotToContinue':
                    metrics.partialReasonCounts[HabitPartialReason
                        .forgotToContinue] ??
                    0,
                'other':
                    metrics.partialReasonCounts[HabitPartialReason.other] ?? 0,
              },
              'partialWithoutReason': metrics.partialWithoutReason,
              'quantitativeHabits': metrics.quantitativeHabits
                  .map(
                    (s) => {
                      'title': s.title,
                      'unit': s.unit,
                      'target': s.target,
                      'scheduledOccurrences': s.scheduledOccurrences,
                      'targetReached': s.targetReached,
                      'partialOccurrences': s.partialOccurrences,
                      'totalLogged': s.totalLogged,
                      'averageLogged': s.averageLogged,
                    },
                  )
                  .toList(),
            },
          )
          .timeout(const Duration(seconds: 20));
    } on FunctionException catch (e) {
      if (isAiWeeklyReviewQuotaExceeded(e.status, e.details)) {
        throw const AiWeeklyReviewException(
          aiWeeklyReviewQuotaMessage,
          isQuotaExceeded: true,
        );
      }
      throw const AiWeeklyReviewException(_requestFailedMessage);
    } catch (_) {
      throw const AiWeeklyReviewException(_requestFailedMessage);
    }

    return parseAiWeeklyReviewResponse(response.data);
  }
}

bool isAiWeeklyReviewQuotaExceeded(int status, Object? data) {
  if (status == 429) return true;
  if (data is! Map) return false;

  final error = data['error'];
  if (error is! Map) return false;

  return error['code'] == 'quota_exceeded';
}
